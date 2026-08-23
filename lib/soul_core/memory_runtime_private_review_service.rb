# frozen_string_literal: true

require "digest"
require "json"
require "net/http"
require "pathname"
require "time"
require "uri"

module SoulCore
  # Bounded, read-only evidence for the configured embedding runtime and one
  # owner-private retrieval case file. The service never rebuilds an index or
  # exposes the private query or memory text it reads.
  class MemoryRuntimePrivateReviewService
    CASE_SCHEMA = "soul.memory_retrieval.private_review.v1"
    CASE_RELATIVE_PATH = File.join("Soul", "private", "memory", "retrieval_review_cases.json")
    MAX_CASE_FILE_BYTES = 64 * 1024
    MAX_CASES = 32
    MAX_QUERY_CHARACTERS = 500
    MAX_IDENTIFIER_CHARACTERS = 200
    MAX_EXPECTED_IDS = 8
    MAX_FORBIDDEN_IDS = 8
    MAX_RESULT_LIMIT = 8
    MAX_RESPONSE_BYTES = 4 * 1024 * 1024
    MAX_APPROVED_RECORDS = 10_000
    LOOPBACK_HOSTS = %w[localhost 127.0.0.1 ::1].freeze
    CASE_DOCUMENT_KEYS = %w[cases schema_version].freeze
    CASE_KEYS = %w[id query expected_approved_memory_ids forbidden_approved_memory_ids result_limit].freeze

    CORE_IDS = %w[daily amd-free music free dev].freeze

    attr_reader :root, :case_path

    def initialize(root: Dir.pwd, memory_store:, retrieval_service:, embedding_endpoint: "",
                   embedding_profile: "", embedding_dimensions: 0, embedding_protocol: "ollama",
                   selected_core: nil, core_identity: nil, case_path: nil, http_get: nil,
                   clock: -> { Time.now.utc }, open_timeout: 2, read_timeout: 10,
                   max_response_bytes: MAX_RESPONSE_BYTES)
      @root = File.expand_path(root)
      @memory_store = memory_store
      @retrieval_service = retrieval_service
      @embedding_endpoint = embedding_endpoint.to_s.strip
      @embedding_profile = embedding_profile.to_s.strip
      @embedding_dimensions = embedding_dimensions
      @embedding_protocol = embedding_protocol.to_s.strip
      @selected_core = core_identity.nil? ? selected_core : core_identity
      @case_path = File.expand_path(case_path || CASE_RELATIVE_PATH, @root)
      @http_get = http_get
      @clock = clock
      @open_timeout = bounded_timeout(open_timeout)
      @read_timeout = bounded_timeout(read_timeout)
      @max_response_bytes = Integer(max_response_bytes)
      raise ArgumentError, "runtime response limit is invalid" unless @max_response_bytes.between?(1, MAX_RESPONSE_BYTES)
    end

    # One observation of the configured local endpoint. Only GET /api/tags and
    # GET /api/ps are permitted; neither endpoint can load or evict a model.
    def runtime
      endpoint = validated_embedding_endpoint
      profile = validated_runtime_profile
      core = normalized_core_identity
      return failed("memory runtime configuration is invalid", data: runtime_data(endpoint, profile, core)) unless endpoint && profile

      tags = get_json(endpoint, "/api/tags")
      ps = get_json(endpoint, "/api/ps")
      installed = tags && model_list(tags)
      resident = ps && model_list(ps)
      exact_name = profile.fetch("name")
      installed_exact = installed&.any? { |model| model_matches?(model, exact_name) }
      loaded_exact = resident&.any? { |model| model_matches?(model, exact_name) }
      reachability = if tags && ps
                       "reachable"
                     else
                       "unreachable_or_invalid_response"
                     end
      disposition = compatibility_disposition(core, reachability: reachability, loaded: loaded_exact)

      complete(
        runtime_data(endpoint, profile, core).merge(
          "endpoint_reachability" => reachability,
          "endpoint_reachable" => reachability == "reachable",
          "model_installed" => installed_exact,
          "model_loaded" => loaded_exact,
          "compatibility_disposition" => disposition,
          "compatibility" => disposition,
          "installed_model_count" => installed&.length,
          "loaded_model_count" => resident&.length,
          "mutation" => "none"
        )
      )
    rescue StandardError => error
      failed("memory runtime observation failed safely: #{error.class}: #{error.message}")
    end

    alias runtime_observation runtime
    alias observe_runtime runtime
    alias runtime_evidence runtime

    # Evaluate the fixed owner-private case set against the injected retrieval
    # collaborator. Returned data contains identifiers and digests only.
    def private_review
      case_document = load_case_file
      cases = case_document.fetch("cases")
      source_digest = approved_memory_source_digest
      results = cases.map { |review_case| evaluate_case(review_case) }
      aggregate = aggregate_results(results)
      profile = results.map { |result| result["retrieval_profile"] }.compact.uniq
      index_states = results.map { |result| result["index_available"] }.compact.uniq

      complete(
        "case_file_digest" => case_document.fetch("digest"),
        "approved_memory_source_digest" => source_digest,
        "case_count" => results.length,
        "cases" => results,
        "aggregate" => aggregate,
        "retrieval_profile" => profile.length == 1 ? profile.first : (profile.empty? ? nil : "mixed"),
        "index_available" => index_states.length == 1 ? index_states.first : (index_states.empty? ? nil : "mixed"),
        "authority" => "evaluation_only",
        "content_trusted" => false,
        "mutation" => "none"
      )
    rescue StandardError => error
      failed("private memory review failed safely: #{error.class}: #{error.message}")
    end

    alias review_private private_review
    alias evaluate_private_review private_review
    alias run_private_review private_review

    private

    def validated_embedding_endpoint
      return nil if @embedding_endpoint.empty?

      uri = URI.parse(@embedding_endpoint)
      return nil unless uri.is_a?(URI::HTTP) && LOOPBACK_HOSTS.include?(uri.host)
      return nil if uri.user || uri.password || uri.query || uri.fragment

      uri.path = "/"
      uri
    rescue URI::InvalidURIError
      nil
    end

    def validated_runtime_profile
      return nil unless @embedding_protocol == "ollama"
      return nil if @embedding_profile.empty? || @embedding_profile.length > MAX_IDENTIFIER_CHARACTERS

      dimensions = Integer(@embedding_dimensions)
      return nil unless dimensions.between?(1, 1_024)

      { "name" => @embedding_profile, "protocol" => @embedding_protocol, "dimensions" => dimensions }
    rescue ArgumentError, TypeError
      nil
    end

    def runtime_data(endpoint, profile, core)
      {
        "configured_endpoint" => endpoint&.then { |uri| "#{uri.scheme}://#{uri.host}:#{uri.port}" },
        "endpoint" => endpoint&.then { |uri| "#{uri.scheme}://#{uri.host}:#{uri.port}" },
        "configured_profile" => profile,
        "embedding_profile" => profile,
        "selected_core" => core,
        "core_identity" => core,
        "protocol" => profile && profile["protocol"],
        "embedding_protocol" => profile && profile["protocol"],
        "dimensions" => profile && profile["dimensions"],
        "embedding_dimensions" => profile && profile["dimensions"]
      }
    end

    def normalized_core_identity
      value = @selected_core.respond_to?(:call) ? @selected_core.call : @selected_core
      if value.is_a?(Hash)
        id = value["id"] || value[:id] || value["active_core_id"] || value[:active_core_id]
        label = value["label"] || value[:label] || value["active_core_label"] || value[:active_core_label]
        { "id" => id.to_s, "label" => label.to_s }.reject { |_key, item| item.empty? }
      else
        id = value.to_s
        id.empty? ? {} : { "id" => id, "label" => id }
      end
    rescue StandardError
      {}
    end

    def compatibility_disposition(core, reachability:, loaded:)
      return "unavailable" unless reachability == "reachable"
      return loaded ? "incompatible_free_core" : "free_core_unloaded" if core["id"] == "free"
      return "qualification_required" unless CORE_IDS.include?(core["id"])

      # Core residency is not approved by this observation, even when Ollama
      # reports the exact model. A separate live coexistence review owns that decision.
      "qualification_required"
    end

    def get_json(base_uri, path)
      uri = base_uri.dup
      uri.path = path
      raw = if @http_get
              @http_get.call(uri.to_s)
            else
              request_get(uri)
            end
      return raw if raw.is_a?(Hash) || raw.is_a?(Array)
      body = raw.respond_to?(:body) ? raw.body.to_s : raw.to_s
      raise "runtime response exceeds #{@max_response_bytes} bytes" if body.bytesize > @max_response_bytes
      if raw.respond_to?(:is_a?) && raw.respond_to?(:code) && !raw.is_a?(String)
        raise "runtime endpoint returned HTTP #{raw.code}" unless raw.is_a?(Net::HTTPSuccess)
      end
      JSON.parse(body)
    rescue JSON::ParserError => error
      raise "runtime response is not valid JSON: #{error.message}"
    end

    def request_get(uri)
      request = Net::HTTP::Get.new(uri.request_uri)
      connection = Net::HTTP.new(uri.host, uri.port)
      connection.use_ssl = uri.scheme == "https"
      connection.open_timeout = @open_timeout
      connection.read_timeout = @read_timeout
      connection.start { |client| client.request(request) }
    end

    def model_list(payload)
      Array(payload.fetch("models")).filter_map do |model|
        next unless model.is_a?(Hash)

        model.transform_keys(&:to_s)
      end
    end

    def model_matches?(model, target)
      [model["name"], model["model"]].compact.map(&:to_s).include?(target.to_s)
    end

    def load_case_file
      validate_case_path!
      stat = File.lstat(@case_path)
      raise "private review case file must be a regular non-symlink file" unless stat.file? && !stat.symlink?
      raise "private review case file exceeds #{MAX_CASE_FILE_BYTES} bytes" if stat.size > MAX_CASE_FILE_BYTES

      bytes = File.binread(@case_path)
      document = JSON.parse(bytes)
      raise "private review case document must be an object" unless document.is_a?(Hash)
      raise "private review case document contains unsupported fields" unless document.keys.sort == CASE_DOCUMENT_KEYS
      raise "private review case schema mismatch" unless document["schema_version"] == CASE_SCHEMA

      cases = document["cases"]
      raise "private review cases must contain 1..#{MAX_CASES} cases" unless cases.is_a?(Array) && cases.length.between?(1, MAX_CASES)
      validated = cases.map { |item| validate_case(item) }
      ids = validated.map { |item| item.fetch("id") }
      raise "private review case IDs must be unique" unless ids.uniq.length == ids.length
      { "cases" => validated, "digest" => Digest::SHA256.hexdigest(bytes) }
    rescue JSON::ParserError => error
      raise "private review case JSON is malformed: #{error.message}"
    end

    def validate_case(item)
      raise "private review case must be an object" unless item.is_a?(Hash)
      required_keys = %w[id query expected_approved_memory_ids result_limit]
      raise "private review case contains unsupported fields" unless (item.keys - CASE_KEYS).empty?
      raise "private review case is missing required fields" unless (required_keys - item.keys).empty?
      id = bounded_id(item["id"], "case ID")
      query = item["query"].to_s
      raise "private review query is required" if query.empty?
      raise "private review query exceeds #{MAX_QUERY_CHARACTERS} characters" if query.length > MAX_QUERY_CHARACTERS
      expected = validate_ids(item["expected_approved_memory_ids"], "expected memory IDs", 1..MAX_EXPECTED_IDS)
      forbidden = validate_ids(item.fetch("forbidden_approved_memory_ids", []), "forbidden memory IDs", 0..MAX_FORBIDDEN_IDS)
      limit = Integer(item.fetch("result_limit"))
      raise "private review result limit must be 1..#{MAX_RESULT_LIMIT}" unless (1..MAX_RESULT_LIMIT).cover?(limit)
      raise "private review expected and forbidden IDs must not overlap" unless (expected & forbidden).empty?

      { "id" => id, "query" => query, "expected_approved_memory_ids" => expected,
        "forbidden_approved_memory_ids" => forbidden, "limit" => limit }
    rescue KeyError, ArgumentError, TypeError
      raise "private review case is malformed"
    end

    def validate_ids(value, label, range)
      ids = Array(value)
      raise "#{label} must contain #{range} identifiers" unless range.cover?(ids.length)
      ids.map { |id| bounded_id(id, label) }.tap do |validated|
        raise "#{label} must be unique" unless validated.uniq.length == validated.length
      end
    end

    def bounded_id(value, label)
      text = value.to_s
      raise "#{label} is required" if text.empty?
      raise "#{label} exceeds #{MAX_IDENTIFIER_CHARACTERS} characters" if text.length > MAX_IDENTIFIER_CHARACTERS
      raise "#{label} contains invalid characters" unless text.match?(/\A[A-Za-z0-9][A-Za-z0-9_.:-]*\z/)

      text
    end

    def validate_case_path!
      prefix = "#{@root}#{File::SEPARATOR}"
      raise "private review case path escapes project root" unless @case_path.start_with?(prefix)
      relative = Pathname.new(@case_path).relative_path_from(Pathname.new(@root))
      current = Pathname.new(@root)
      relative.each_filename do |component|
        current = current.join(component)
        next unless File.exist?(current.to_s) || File.symlink?(current.to_s)
        raise "private review case path contains a symlink component" if File.symlink?(current.to_s)
      end
      true
    rescue ArgumentError
      raise "private review case path escapes project root"
    end

    def approved_memory_source_digest
      records = Array(@memory_store.records(status: "approved"))
      raise "approved-memory source exceeds #{MAX_APPROVED_RECORDS} records" if records.length > MAX_APPROVED_RECORDS
      canonical = records.sort_by { |record| record.fetch("id").to_s }
      Digest::SHA256.hexdigest(JSON.generate(canonical))
    end

    def evaluate_case(review_case)
      output = @retrieval_service.query(query: review_case.fetch("query"), limit: review_case.fetch("limit"))
      raise "retrieval collaborator returned a non-object" unless output.is_a?(Hash)
      data = output["data"] || output
      returned = Array(data.fetch("results")).filter_map do |result|
        next unless result.is_a?(Hash)

        result["memory_id"] || result[:memory_id]
      end.map(&:to_s).reject(&:empty?).first(review_case.fetch("limit"))
      expected = review_case.fetch("expected_approved_memory_ids")
      forbidden = review_case.fetch("forbidden_approved_memory_ids")
      positions = returned.each_with_index.select { |id, _index| expected.include?(id) }.map { |_id, index| index }
      recall = (returned & expected).length.to_f / expected.length
      reciprocal_rank = positions.empty? ? 0.0 : (1.0 / (positions.first + 1))
      {
        "case_id" => review_case.fetch("id"),
        "query_sha256" => Digest::SHA256.hexdigest(review_case.fetch("query")),
        "expected_memory_ids" => expected,
        "forbidden_memory_ids" => forbidden,
        "returned_memory_ids" => returned,
        "hit" => positions.any?,
        "recall" => recall.round(6),
        "reciprocal_rank" => reciprocal_rank.round(6),
        "forbidden_hit" => !(returned & forbidden).empty?,
        "abstained" => returned.empty?,
        "retrieval_profile" => data["ranking_profile"] || data["retrieval_profile"],
        "index_available" => data["index_available"]
      }
    end

    def aggregate_results(results)
      {
        "recall" => mean(results.map { |item| item.fetch("recall") }),
        "reciprocal_rank" => mean(results.map { |item| item.fetch("reciprocal_rank") }),
        "forbidden_hit_count" => results.count { |item| item.fetch("forbidden_hit") },
        "abstention_count" => results.count { |item| item.fetch("abstained") },
        "case_count" => results.length
      }
    end

    def mean(values)
      return 0.0 if values.empty?

      (values.sum.to_f / values.length).round(6)
    end

    def complete(data)
      { "lifecycle_state" => "complete", "data" => data }
    end

    def failed(message, data: nil)
      envelope = { "lifecycle_state" => "failed", "message" => message, "mutation" => "none" }
      envelope["data"] = data if data
      envelope
    end

    def bounded_timeout(value)
      timeout = Float(value)
      raise ArgumentError, "runtime timeout must be between 0.1 and 60 seconds" unless timeout.between?(0.1, 60.0)

      timeout
    rescue ArgumentError, TypeError
      raise ArgumentError, "runtime timeout must be between 0.1 and 60 seconds"
    end
  end
end
