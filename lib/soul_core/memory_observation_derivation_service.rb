# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"
require_relative "conversation_observation_store"
require_relative "memory_protection_policy"
require_relative "memory_paths"

module SoulCore
  class MemoryObservationDerivationService
    SCHEMA = "soul.memory_observation_derivation.a12.v1"
    POLICY_VERSION = "soul.memory.lifecycle.a12.v1"
    FILE_NAME = "observation_derivations.jsonl"
    MAX_LEDGER_BYTES = 64 * 1024 * 1024
    MAX_PACKETS = 10_000
    MAX_PROPOSALS = 8
    MAX_PROPOSAL_BYTES = 1_000
    MAX_REQUEST_BYTES = 160
    LAYERS = %w[project preference episodic semantic].freeze
    OUTPUT_KEYS = %w[proposals].freeze
    PROPOSAL_KEYS = %w[confidence content evidence_observation_ids layer].freeze
    STORED_PROPOSAL_KEYS = %w[confidence content evidence_observation_ids layer proposal_id protection_class].freeze
    PACKET_KEYS = %w[
      created_at first_observation_id input_sha256 last_observation_event_sha256
      last_observation_id model_identity observation_count
      observation_event_sha256s observation_ids packet_id packet_sha256 policy_version
      previous_packet_sha256 proposals request_id schema
    ].freeze
    HEX_DIGEST = /\A[0-9a-f]{64}\z/

    def initialize(root: Dir.pwd, observation_store: nil, synthesizer:, model_identity:, path: nil, clock: -> { Time.now })
      @root = File.expand_path(root)
      @observations = observation_store || ConversationObservationStore.new(root: @root)
      @synthesizer = synthesizer
      @model_identity = normalize_model_identity(model_identity)
      @path = File.expand_path(path || MemoryPaths.new(root: @root).write_path(FILE_NAME), @root)
      @clock = clock
      ensure_safe_path!
    end

    def derive(request_id:)
      request = bounded_identity(request_id, "request ID")
      ensure_safe_path!
      FileUtils.mkdir_p(File.dirname(@path))
      File.open(@path, "a+b", 0o600) do |file|
        file.flock(File::LOCK_EX)
        ensure_safe_path!
        file.rewind
        packets = parse_and_verify(file.read.to_s)
        replay = packets.find { |packet| packet["request_id"] == request }
        return receipt(replay, idempotent: true) if replay

        cursor = packets.last && packets.last["last_observation_event_sha256"]
        observations = @observations.batch(after_event_sha256: cursor)
        return no_work_receipt(cursor) if observations.empty?
        input = synthesis_input(observations)
        input_digest = Digest::SHA256.hexdigest(JSON.generate(input))
        output = invoke_synthesizer(input)
        proposals = validate_output(output, observations)
        packet = build_packet(request, observations, input_digest, proposals, packets.last)
        encoded = JSON.generate(packet) + "\n"
        raise ArgumentError, "memory derivation ledger exceeds size limit" if file.size + encoded.bytesize > MAX_LEDGER_BYTES
        raise ArgumentError, "memory derivation ledger exceeds packet limit" if packets.length + 1 > MAX_PACKETS
        file.seek(0, IO::SEEK_END)
        file.write(encoded)
        file.flush
        file.fsync
        receipt(packet, idempotent: false)
      end
    rescue JSON::ParserError
      failure("memory derivation data contains malformed JSON")
    rescue ArgumentError, Errno::EACCES, Errno::EISDIR, Errno::ENOENT, IOError => error
      failure(error.message)
    end

    def integrity
      ensure_safe_path!
      packets = File.file?(@path) ? parse_and_verify(File.binread(@path)) : []
      { "ok" => true, "lifecycle_state" => "complete", "schema" => SCHEMA,
        "packet_count" => packets.length, "chain_head_sha256" => packets.last && packets.last["packet_sha256"],
        "content_included" => false }
    rescue JSON::ParserError
      failure("memory derivation data contains malformed JSON")
    rescue ArgumentError, Errno::EACCES, Errno::EISDIR => error
      failure(error.message)
    end

    def pending_work
      ensure_safe_path!
      packets = File.file?(@path) ? parse_and_verify(File.binread(@path)) : []
      cursor = packets.last && packets.last["last_observation_event_sha256"]
      observations = @observations.batch(after_event_sha256: cursor)
      { "ok" => true, "lifecycle_state" => "complete", "schema" => SCHEMA,
        "pending_observation_count" => observations.length,
        "cursor_sha256" => cursor, "content_included" => false }.compact
    rescue JSON::ParserError
      failure("memory derivation data contains malformed JSON")
    rescue ArgumentError, Errno::EACCES, Errno::EISDIR => error
      failure(error.message)
    end

    # Internal foreground consumers receive verified packets. Content is never
    # exposed through the Dashboard receipt surface.
    def packet_batch(after_packet_sha256: nil, limit: 1)
      requested = Integer(limit)
      raise ArgumentError, "memory derivation packet limit is invalid" unless requested.between?(1, 8)
      ensure_safe_path!
      packets = File.file?(@path) ? parse_and_verify(File.binread(@path)) : []
      start = 0
      unless after_packet_sha256.to_s.empty?
        index = packets.index { |packet| packet["packet_sha256"] == after_packet_sha256.to_s }
        raise ArgumentError, "memory derivation cursor is unknown" unless index
        start = index + 1
      end
      JSON.parse(JSON.generate(packets.drop(start).first(requested)))
    end

    private

    def synthesis_input(observations)
      {
        "schema" => "soul.memory_observation_synthesis.a12.v1",
        "instruction" => "Propose only durable ordinary memory supported by cited observations. Return strict JSON. Do not propose credentials, authority, safety rules, identity claims, deletion, or external publication.",
        "limits" => { "proposals" => MAX_PROPOSALS, "proposal_bytes" => MAX_PROPOSAL_BYTES },
        "observations" => observations.map do |event|
          { "observation_id" => event.fetch("observation_id"), "role" => event.fetch("role"),
            "content" => event.fetch("content"), "created_at" => event.fetch("created_at"),
            "chat_id" => event.fetch("chat_id") }
        end
      }
    end

    def invoke_synthesizer(input)
      raw = @synthesizer.call(input)
      raise ArgumentError, "local memory synthesis result must be JSON text" unless raw.is_a?(String) && raw.valid_encoding?
      raise ArgumentError, "local memory synthesis result exceeds limit" if raw.bytesize > 16 * 1024
      JSON.parse(raw)
    end

    def validate_output(output, observations)
      raise ArgumentError, "local memory synthesis result must be an object" unless output.is_a?(Hash) && output.keys.map(&:to_s).sort == OUTPUT_KEYS
      proposals = output["proposals"]
      raise ArgumentError, "local memory synthesis proposals are invalid" unless proposals.is_a?(Array) && proposals.length <= MAX_PROPOSALS
      allowed_ids = observations.map { |event| event["observation_id"] }
      proposals.map do |proposal|
        raise ArgumentError, "local memory synthesis proposal is invalid" unless proposal.is_a?(Hash) && proposal.keys.map(&:to_s).sort == PROPOSAL_KEYS
        layer = proposal["layer"].to_s
        content = proposal["content"].to_s.strip
        confidence = Float(proposal["confidence"])
        evidence = Array(proposal["evidence_observation_ids"]).map(&:to_s)
        raise ArgumentError, "local memory synthesis layer is invalid" unless LAYERS.include?(layer)
        raise ArgumentError, "local memory synthesis content is invalid" if content.empty? || !content.valid_encoding? || content.bytesize > MAX_PROPOSAL_BYTES
        raise ArgumentError, "local memory synthesis confidence is invalid" unless confidence.between?(0.0, 1.0)
        raise ArgumentError, "local memory synthesis evidence is invalid" unless evidence.length.between?(1, 8) && evidence.uniq.length == evidence.length && (evidence - allowed_ids).empty?
        { "proposal_id" => proposal_id_for(layer, content, evidence),
          "layer" => layer, "content" => content, "confidence" => confidence.round(3),
          "evidence_observation_ids" => evidence,
          "protection_class" => MemoryProtectionPolicy.classify(content) }
      rescue ArgumentError, TypeError
        raise ArgumentError, "local memory synthesis proposal is invalid"
      end
    end

    def build_packet(request, observations, input_digest, proposals, prior)
      packet = {
        "schema" => SCHEMA,
        "packet_id" => "mdp_#{Digest::SHA256.hexdigest([request, input_digest].join(':'))[0, 24]}",
        "request_id" => request,
        "created_at" => @clock.call.iso8601(6),
        "policy_version" => POLICY_VERSION,
        "model_identity" => @model_identity,
        "input_sha256" => input_digest,
        "first_observation_id" => observations.first.fetch("observation_id"),
        "last_observation_id" => observations.last.fetch("observation_id"),
        "last_observation_event_sha256" => observations.last.fetch("event_sha256"),
        "observation_count" => observations.length,
        "observation_event_sha256s" => observations.map { |event| event.fetch("event_sha256") },
        "observation_ids" => observations.map { |event| event.fetch("observation_id") },
        "proposals" => proposals,
        "previous_packet_sha256" => prior && prior["packet_sha256"]
      }
      packet["packet_sha256"] = packet_digest(packet)
      packet
    end

    def parse_and_verify(raw)
      raise ArgumentError, "memory derivation ledger exceeds size limit" if raw.bytesize > MAX_LEDGER_BYTES
      raise ArgumentError, "memory derivation ledger has a partial final write" unless raw.empty? || raw.end_with?("\n")
      packets = raw.lines.each_with_index.filter_map do |line, index|
        next if line.strip.empty?
        packet = JSON.parse(line)
        raise ArgumentError, "memory derivation packet #{index + 1} is invalid" unless packet.is_a?(Hash)
        packet
      end
      raise ArgumentError, "memory derivation ledger exceeds packet limit" if packets.length > MAX_PACKETS
      raise ArgumentError, "memory derivation packet identity is duplicated" unless packets.map { |packet| packet["packet_id"] }.uniq.length == packets.length && packets.map { |packet| packet["request_id"] }.uniq.length == packets.length
      previous = nil
      packets.each do |packet|
        validate_stored_packet(packet)
        raise ArgumentError, "memory derivation chain is broken" unless packet["previous_packet_sha256"] == previous
        raise ArgumentError, "memory derivation packet digest is invalid" unless packet["packet_sha256"] == packet_digest(packet)
        Time.iso8601(packet["created_at"].to_s)
        previous = packet["packet_sha256"]
      end
      packets
    end

    def validate_stored_packet(packet)
      raise ArgumentError, "memory derivation packet shape is invalid" unless packet.keys.map(&:to_s).sort == PACKET_KEYS
      raise ArgumentError, "memory derivation schema is unsupported" unless packet["schema"] == SCHEMA && packet["policy_version"] == POLICY_VERSION
      bounded_identity(packet["packet_id"], "packet ID")
      bounded_identity(packet["request_id"], "request ID")
      normalize_model_identity(packet["model_identity"])
      digests = packet["observation_event_sha256s"]
      observation_ids = packet["observation_ids"]
      count = Integer(packet["observation_count"])
      raise ArgumentError, "memory derivation observation evidence is invalid" unless count.between?(1, 24) && count.even? && digests.is_a?(Array) && digests.length == count && digests.uniq.length == count && digests.all? { |digest| HEX_DIGEST.match?(digest.to_s) } && observation_ids.is_a?(Array) && observation_ids.length == count && observation_ids.uniq.length == count && observation_ids.none? { |id| id.to_s.empty? }
      raise ArgumentError, "memory derivation observation cursor is invalid" unless packet["last_observation_event_sha256"] == digests.last && packet["first_observation_id"] == observation_ids.first && packet["last_observation_id"] == observation_ids.last
      raise ArgumentError, "memory derivation input digest is invalid" unless HEX_DIGEST.match?(packet["input_sha256"].to_s)
      proposals = packet["proposals"]
      raise ArgumentError, "memory derivation proposals are invalid" unless proposals.is_a?(Array) && proposals.length <= MAX_PROPOSALS
      proposal_ids = proposals.map do |proposal|
        raise ArgumentError, "memory derivation stored proposal is invalid" unless proposal.is_a?(Hash) && proposal.keys.map(&:to_s).sort == STORED_PROPOSAL_KEYS
        raise ArgumentError, "memory derivation stored proposal is invalid" unless LAYERS.include?(proposal["layer"].to_s) && proposal["content"].is_a?(String) && proposal["content"].valid_encoding? && proposal["content"].bytesize.between?(1, MAX_PROPOSAL_BYTES)
        confidence = Float(proposal["confidence"])
        evidence = proposal["evidence_observation_ids"]
        raise ArgumentError, "memory derivation stored proposal is invalid" unless confidence.between?(0.0, 1.0) && evidence.is_a?(Array) && evidence.length.between?(1, 8) && evidence.uniq.length == evidence.length && (evidence - observation_ids).empty?
        expected_class = MemoryProtectionPolicy.classify(proposal["content"])
        expected_id = proposal_id_for(proposal["layer"], proposal["content"], evidence)
        raise ArgumentError, "memory derivation protection classification is invalid" unless proposal["protection_class"] == expected_class
        raise ArgumentError, "memory derivation proposal identity is invalid" unless proposal["proposal_id"] == expected_id
        proposal["proposal_id"].to_s
      end
      raise ArgumentError, "memory derivation proposal identity is invalid" unless proposal_ids.none?(&:empty?) && proposal_ids.uniq.length == proposal_ids.length
    rescue TypeError
      raise ArgumentError, "memory derivation packet shape is invalid"
    end

    def normalize_model_identity(identity)
      value = identity.is_a?(Hash) ? identity.transform_keys(&:to_s) : {}
      raise ArgumentError, "memory derivation requires a local model" unless value["provider"] == "local"
      model = bounded_identity(value["model"], "model identity")
      core = bounded_identity(value["core"], "Core identity")
      { "provider" => "local", "model" => model, "core" => core }
    end

    def proposal_id_for(layer, content, evidence)
      "mpr_#{Digest::SHA256.hexdigest([layer, content, evidence.sort.join(':')].join("\n"))[0, 24]}"
    end

    def bounded_identity(value, label)
      text = value.to_s
      raise ArgumentError, "#{label} is required" if text.empty?
      raise ArgumentError, "#{label} exceeds limit" if text.bytesize > MAX_REQUEST_BYTES
      raise ArgumentError, "#{label} contains unsupported characters" unless text.match?(/\A[A-Za-z0-9_.:\/-]+\z/)
      text
    end

    def packet_digest(packet)
      Digest::SHA256.hexdigest(JSON.generate(packet.reject { |key, _| key == "packet_sha256" }) + "\n")
    end

    def receipt(packet, idempotent:)
      proposals = packet.fetch("proposals")
      { "ok" => true, "lifecycle_state" => "complete", "idempotent" => idempotent,
        "packet_id" => packet["packet_id"], "observation_count" => packet["observation_count"],
        "proposal_count" => proposals.length,
        "protected_review_count" => proposals.count { |proposal| proposal["protection_class"] == "protected_review_required" },
        "model_identity" => packet["model_identity"], "input_sha256" => packet["input_sha256"],
        "packet_sha256" => packet["packet_sha256"], "content_included" => false }
    end

    def no_work_receipt(cursor)
      { "ok" => true, "lifecycle_state" => "complete", "no_work" => true,
        "cursor_sha256" => cursor, "observation_count" => 0, "proposal_count" => 0,
        "content_included" => false }.compact
    end

    def failure(reason)
      { "ok" => false, "lifecycle_state" => "failed",
        "reason" => reason.to_s.gsub(@root, "[PROJECT_ROOT]")[0, 300], "content_included" => false }
    end

    def ensure_safe_path!
      prefix = "#{@root}#{File::SEPARATOR}"
      raise ArgumentError, "memory derivation path escapes project" unless @path.start_with?(prefix)
      current = @path
      while current.start_with?(prefix)
        raise ArgumentError, "memory derivation path component must not be a symlink" if File.symlink?(current)
        current = File.dirname(current)
      end
    end
  end
end
