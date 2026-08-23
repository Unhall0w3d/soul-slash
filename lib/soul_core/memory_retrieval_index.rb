# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "net/http"
require "pathname"
require "tempfile"
require "time"
require "timeout"
require "uri"

module SoulCore
  # Bounded client for an explicitly configured local embedding endpoint.
  class LocalLoopbackEmbeddingClient
    MAX_INPUT_CHARACTERS = 8_000
    MAX_BATCH_SIZE = 64
    MAX_DIMENSIONS = 1_024
    DEFAULT_RESPONSE_BYTES = 4 * 1024 * 1024

    attr_reader :endpoint, :profile, :dimensions

    def initialize(endpoint:, profile:, protocol: "ollama", open_timeout: 2, read_timeout: 10,
                   max_response_bytes: DEFAULT_RESPONSE_BYTES, http: Net::HTTP)
      @endpoint = URI.parse(endpoint.to_s)
      unless @endpoint.is_a?(URI::HTTP) && @endpoint.host && loopback_host?(@endpoint.host)
        raise ArgumentError, "embedding endpoint must be an HTTP loopback URL"
      end
      raise ArgumentError, "embedding endpoint must not include credentials" if @endpoint.user || @endpoint.password
      raise ArgumentError, "embedding endpoint must not include a query" if @endpoint.query
      raise ArgumentError, "embedding endpoint must not include a fragment" if @endpoint.fragment

      @profile = normalize_profile(profile)
      @protocol = protocol.to_s
      raise ArgumentError, "embedding protocol must be ollama or soul" unless %w[ollama soul].include?(@protocol)
      @dimensions = Integer(@profile.fetch("dimensions"))
      raise ArgumentError, "embedding dimensions must be 1..#{MAX_DIMENSIONS}" unless (1..MAX_DIMENSIONS).cover?(@dimensions)

      @open_timeout = bounded_timeout(open_timeout)
      @read_timeout = bounded_timeout(read_timeout)
      @max_response_bytes = Integer(max_response_bytes)
      raise ArgumentError, "embedding response limit is invalid" unless @max_response_bytes.between?(1, 16 * 1024 * 1024)
      @http = http
    rescue URI::InvalidURIError
      raise ArgumentError, "embedding endpoint must be an HTTP loopback URL"
    end

    def embed(texts)
      values = Array(texts).map(&:to_s)
      raise ArgumentError, "embedding batch must contain 1..#{MAX_BATCH_SIZE} inputs" unless values.length.between?(1, MAX_BATCH_SIZE)
      raise ArgumentError, "embedding input exceeds #{MAX_INPUT_CHARACTERS} characters" if values.any? { |value| value.length > MAX_INPUT_CHARACTERS }

      request = Net::HTTP::Post.new(request_path)
      request["content-type"] = "application/json"
      request.body = JSON.generate(request_payload(values))
      response = perform(request)
      body = response.body.to_s
      raise "embedding response exceeds #{@max_response_bytes} bytes" if body.bytesize > @max_response_bytes
      raise "embedding endpoint returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      raw = JSON.parse(body)
      vectors = raw.is_a?(Hash) ? raw.fetch("embeddings") : raw
      validate_vectors(vectors, values.length)
    rescue JSON::ParserError, KeyError, TypeError => error
      raise "invalid embedding response: #{error.message}"
    end

    private

    def perform(request)
      connection = @http.new(@endpoint.host, @endpoint.port)
      connection.use_ssl = @endpoint.scheme == "https"
      connection.open_timeout = @open_timeout
      connection.read_timeout = @read_timeout
      attempts = 0
      begin
        attempts += 1
        connection.start { |client| return client.request(request) }
      rescue Timeout::Error, Errno::ECONNRESET, Errno::EPIPE, IOError, SocketError
        raise if attempts > 1

        retry
      end
    end

    def request_path
      path = @endpoint.path.to_s
      path.empty? ? "/" : path
    end

    def request_payload(values)
      return { "texts" => values, "profile" => @profile.fetch("name") } if @protocol == "soul"

      { "model" => @profile.fetch("name"), "input" => values, "truncate" => false }
    end

    def validate_vectors(vectors, expected_count)
      raise "embedding response count does not match request" unless vectors.is_a?(Array) && vectors.length == expected_count
      vectors.map do |vector|
        values = Array(vector).map { |item| Float(item) }
        raise "embedding dimension mismatch" unless values.length == @dimensions
        raise "embedding contains a non-finite value" unless values.all?(&:finite?)

        values
      end
    rescue ArgumentError, TypeError
      raise "embedding response contains invalid vectors"
    end

    def normalize_profile(profile)
      value = profile.is_a?(Hash) ? profile.transform_keys(&:to_s) : { "name" => profile.to_s }
      name = value.fetch("name").to_s.strip
      raise ArgumentError, "embedding profile name is required" if name.empty? || name.length > 200

      value.merge("name" => name)
    rescue KeyError
      raise ArgumentError, "embedding profile name is required"
    end

    def bounded_timeout(value)
      timeout = Float(value)
      raise ArgumentError, "embedding timeout must be between 0.1 and 60 seconds" unless timeout.between?(0.1, 60.0)

      timeout
    rescue ArgumentError, TypeError
      raise ArgumentError, "embedding timeout must be between 0.1 and 60 seconds"
    end

    def loopback_host?(host)
      host == "localhost" || host == "127.0.0.1" || host == "::1"
    end
  end

  class ApprovedMemoryIndexService
    SCHEMA = "soul.approved_memory_index.v1"
    MAX_LEDGER_RECORDS = 10_000
    MAX_INDEXED_RECORDS = 5_000
    MAX_CONTENT_CHARACTERS = 8_000
    MAX_BATCH_SIZE = 64
    MAX_DIMENSIONS = 1_024
    MAX_RESULTS = 20
    DEFAULT_MAX_AGE_SECONDS = 86_400
    MAX_INDEX_BYTES = 128 * 1024 * 1024
    LAYERS = %w[project preference episodic semantic].freeze

    attr_reader :index_path, :embedding_profile, :dimensions

    def initialize(memory_store:, index_path:, allowed_root: nil, embedding_client: nil, embedding_profile: nil,
                   dimensions: nil, clock: -> { Time.now.utc }, max_age_seconds: DEFAULT_MAX_AGE_SECONDS)
      @memory_store = memory_store
      @index_path = File.expand_path(index_path.to_s)
      @allowed_root = allowed_root && File.expand_path(allowed_root.to_s)
      validate_index_path!
      @clock = clock
      @max_age_seconds = Integer(max_age_seconds)
      raise ArgumentError, "index freshness bound must be non-negative" if @max_age_seconds.negative?
      @embedding_client = embedding_client
      @embedding_profile = normalize_profile(embedding_profile || embedding_client&.profile || { "name" => "lexical-only" })
      @dimensions = Integer(dimensions || embedding_client&.dimensions || @embedding_profile["dimensions"] || 0)
      allowed_dimensions = @embedding_client ? (1..MAX_DIMENSIONS) : (0..MAX_DIMENSIONS)
      raise ArgumentError, "embedding dimensions must be 1..#{MAX_DIMENSIONS}" unless allowed_dimensions.cover?(@dimensions)
      if @embedding_client && @embedding_client.respond_to?(:dimensions) && @embedding_client.dimensions != @dimensions
        raise ArgumentError, "embedding client dimensions do not match profile"
      end
    end

    def rebuild(cancel: nil, canceled: false)
      return canceled_result("index rebuild canceled before inspection") if canceled || (cancel && cancel.call)
      records = approved_records
      return canceled_result("index rebuild canceled") if cancel && cancel.call

      entries = build_entries(records, cancel: cancel)
      return canceled_result("index rebuild canceled") if entries == :canceled

      payload = entries.sort_by { |entry| entry.fetch("memory_id") }
      envelope = build_envelope(payload, source_digest(records))
      verify_envelope!(envelope, expected_source_digest: source_digest(records), allow_stale: false)
      atomic_replace(envelope)
      complete(
        "message" => "approved-memory index rebuilt",
        "entry_count" => payload.length,
        "source_digest" => envelope.fetch("source_digest"),
        "payload_digest" => envelope.fetch("payload_digest"),
        "embedding_profile" => @embedding_profile,
        "dimensions" => @dimensions,
        "mutation" => "derived_index_replaced"
      )
    rescue StandardError => error
      failed("approved-memory index rebuild failed safely: #{error.class}: #{error.message}")
    end

    alias rebuild! rebuild

    def availability
      envelope, reason = load_valid_index
      {
        "available" => !envelope.nil?,
        "reason" => reason,
        "source_digest" => envelope && envelope["source_digest"],
        "payload_digest" => envelope && envelope["payload_digest"],
        "generated_at" => envelope && envelope["generated_at"],
        "embedding_profile" => envelope && envelope["embedding_profile"],
        "dimensions" => envelope && envelope["dimensions"],
        "entry_count" => envelope && envelope["entry_count"]
      }
    end

    def load_valid_index
      validate_index_path!
      return [nil, "index is absent"] unless File.exist?(@index_path)
      return [nil, "index path is a symlink"] if File.symlink?(@index_path)
      return [nil, "index path is not a regular file"] unless File.file?(@index_path)

      return [nil, "index exceeds byte bound"] if File.size(@index_path) > MAX_INDEX_BYTES
      envelope = JSON.parse(File.binread(@index_path))
      verify_envelope!(envelope, expected_source_digest: source_digest(approved_records))
      [envelope, "index is valid and fresh"]
    rescue JSON::ParserError
      [nil, "index JSON is malformed"]
    rescue StandardError => error
      [nil, "index is invalid or stale: #{error.message}"]
    end

    private

    def approved_records
      records = Array(@memory_store.records(status: "approved"))
      raise "ledger inspection exceeds #{MAX_LEDGER_RECORDS} records" if records.length > MAX_LEDGER_RECORDS
      raise "approved-memory index exceeds #{MAX_INDEXED_RECORDS} records" if records.length > MAX_INDEXED_RECORDS

      records.sort_by { |record| record.fetch("id").to_s }
    end

    def build_entries(records, cancel: nil)
      records.each { |record| validate_record!(record) }
      embeddings = []
      if @embedding_client
        texts = records.map { |record| retrieval_text(record) }
        texts.each_slice(MAX_BATCH_SIZE) do |batch|
          return :canceled if cancel && cancel.call
          embeddings.concat(@embedding_client.embed(batch))
        end
        raise "embedding response count does not match records" unless embeddings.length == records.length
      end

      records.each_with_index.map do |record, index|
        entry = {
          "memory_id" => record.fetch("id").to_s,
          "layer" => record.fetch("layer").to_s,
          "content" => record.fetch("content").to_s,
          "source" => deep_copy(record.fetch("source")),
          "confidence" => Float(record.fetch("confidence")),
          "approved_at" => record.fetch("approved_at").to_s,
          "lexical_terms" => tokens(retrieval_text(record))
        }
        entry["embedding"] = embeddings.fetch(index) if @embedding_client
        entry
      end
    end

    def validate_record!(record)
      raise "approved record status is not approved" unless record["status"] == "approved"
      raise "approved record has no id" if record["id"].to_s.empty?
      raise "approved record layer is invalid" unless LAYERS.include?(record["layer"].to_s)
      raise "approved record content is empty or too long" unless record["content"].to_s.length.between?(1, MAX_CONTENT_CHARACTERS)
      raise "approved record source is invalid" unless record["source"].is_a?(Hash)
      confidence = Float(record.fetch("confidence"))
      raise "approved record confidence is invalid" unless confidence.between?(0.0, 1.0)
      raise "approved record approved_at is required" if record["approved_at"].to_s.empty?
    rescue KeyError, ArgumentError, TypeError
      raise "approved record is malformed"
    end

    def build_envelope(entries, digest)
      generated_at = @clock.call.utc.iso8601(6)
      {
        "schema" => SCHEMA,
        "source_digest" => digest,
        "embedding_profile" => deep_copy(@embedding_profile),
        "dimensions" => @dimensions,
        "entry_count" => entries.length,
        "generated_at" => generated_at,
        "payload_digest" => Digest::SHA256.hexdigest(canonical_json(entries)),
        "entries" => entries
      }
    end

    def verify_envelope!(envelope, expected_source_digest:, allow_stale: true)
      raise "index envelope must be an object" unless envelope.is_a?(Hash)
      raise "index schema mismatch" unless envelope["schema"] == SCHEMA
      raise "index source digest mismatch" unless secure_compare(envelope["source_digest"].to_s, expected_source_digest.to_s)
      raise "index profile mismatch" unless canonical_json(envelope["embedding_profile"]) == canonical_json(@embedding_profile)
      raise "index dimensions mismatch" unless Integer(envelope["dimensions"]) == @dimensions
      entries = envelope.fetch("entries")
      raise "index entries must be an array" unless entries.is_a?(Array)
      raise "index entry count mismatch" unless Integer(envelope["entry_count"]) == entries.length
      raise "index exceeds entry bound" if entries.length > MAX_INDEXED_RECORDS
      raise "index payload digest mismatch" unless secure_compare(envelope["payload_digest"].to_s, Digest::SHA256.hexdigest(canonical_json(entries)))
      validate_entries!(entries)
      generated = Time.iso8601(envelope.fetch("generated_at").to_s)
      age = @clock.call.utc - generated
      raise "index generated_at is in the future" if age.negative?
      raise "index is stale" if allow_stale && age > @max_age_seconds
      true
    rescue KeyError, ArgumentError, TypeError
      raise "index envelope is malformed"
    end

    def validate_entries!(entries)
      entries.each do |entry|
        raise "index entry is malformed" unless entry.is_a?(Hash)
        raise "index entry content is invalid" unless entry["content"].to_s.length.between?(1, MAX_CONTENT_CHARACTERS)
        raise "index entry layer is invalid" unless LAYERS.include?(entry["layer"].to_s)
        terms = entry["lexical_terms"]
        raise "index lexical terms are invalid" unless terms.is_a?(Array) && terms.all? { |term| term.is_a?(String) }
        next unless @embedding_client || entry.key?("embedding")

        vector = entry["embedding"]
        raise "index embedding dimension mismatch" unless vector.is_a?(Array) && vector.length == @dimensions
        raise "index embedding contains a non-finite value" unless vector.all? { |value| Float(value).finite? }
      end
    end

    def atomic_replace(envelope)
      validate_index_path!
      parent = File.dirname(@index_path)
      FileUtils.mkdir_p(parent, mode: 0o700)
      validate_index_path!
      raise "index destination is a symlink" if File.symlink?(@index_path)
      temporary = Tempfile.new([File.basename(@index_path), ".tmp"], parent, mode: 0o600)
      begin
        temporary.write(JSON.generate(envelope))
        temporary.flush
        temporary.fsync
        temporary.close
        File.rename(temporary.path, @index_path)
        File.open(parent, File::RDONLY) { |directory| directory.fsync }
      ensure
        temporary.close unless temporary.closed?
        File.delete(temporary.path) if File.exist?(temporary.path)
      end
    end

    def source_digest(records)
      Digest::SHA256.hexdigest(canonical_json(records.sort_by { |record| record.fetch("id").to_s }))
    end

    def validate_index_path!
      return true unless @allowed_root

      prefix = "#{@allowed_root}#{File::SEPARATOR}"
      raise "index destination escapes its private root" unless @index_path.start_with?(prefix)

      current = Pathname.new(@allowed_root)
      relative_parent = Pathname.new(File.dirname(@index_path)).relative_path_from(current)
      [current, *relative_parent.each_filename.map { |name| current = current.join(name) }].each do |component|
        next unless File.exist?(component.to_s) || File.symlink?(component.to_s)
        raise "index destination contains a symlink component" if File.symlink?(component.to_s)
      end
      true
    rescue ArgumentError
      raise "index destination escapes its private root"
    end

    def retrieval_text(record)
      [record.fetch("content"), Array(record["tags"]).join(" ")].join(" ")[0, MAX_CONTENT_CHARACTERS]
    end

    def tokens(value)
      value.to_s.downcase.scan(/[a-z0-9][a-z0-9_.-]{2,}/).uniq.sort
    end

    def normalize_profile(profile)
      value = profile.is_a?(Hash) ? profile.transform_keys(&:to_s) : { "name" => profile.to_s }
      name = value["name"].to_s.strip
      raise ArgumentError, "embedding profile name is required" if name.empty?

      value.merge("name" => name)
    end

    def canonical_json(value)
      JSON.generate(canonicalize(value))
    end

    def canonicalize(value)
      case value
      when Hash
        value.keys.map(&:to_s).sort.each_with_object({}) do |key, output|
          original_key = value.key?(key) ? key : key.to_sym
          output[key] = canonicalize(value[original_key])
        end
      when Array then value.map { |item| canonicalize(item) }
      else value
      end
    end

    def deep_copy(value)
      JSON.parse(JSON.generate(value))
    end

    def secure_compare(left, right)
      return false unless left.bytesize == right.bytesize
      left.bytes.zip(right.bytes).reduce(0) { |memo, (a, b)| memo | (a ^ b) }.zero?
    end

    def complete(data)
      { "lifecycle_state" => "complete", "data" => data }
    end

    def failed(message)
      { "lifecycle_state" => "failed", "message" => message, "mutation" => "none" }
    end

    def canceled_result(message)
      { "lifecycle_state" => "canceled", "message" => message, "mutation" => "none" }
    end
  end

  MemoryRetrievalIndexService = ApprovedMemoryIndexService
  ApprovedMemoryIndex = ApprovedMemoryIndexService
end
