# frozen_string_literal: true

require "fileutils"
require "digest"
require "json"
require "securerandom"
require "time"
require_relative "memory_paths"

module SoulCore
  class ConversationMemoryStore
    DEFAULT_PATH = "Soul/memory/conversation_memory.jsonl"
    LAYERS = %w[project preference episodic semantic].freeze
    STATUSES = %w[candidate approved superseded deleted].freeze
    EVENTS = %w[created approved superseded deleted restored audit_baseline].freeze
    AUDIT_SCHEMA = "soul.conversation_memory.audit.v1"
    MAX_AUDIT_BATCH = 256
    AUDIT_METADATA_KEYS = %w[
      transaction_id actor trigger reason policy_version model_runtime_identity
      before_state_sha256 after_state_sha256 evidence_digest rollback_reference
    ].freeze
    AUDIT_EVENT_FIELDS = %w[
      event_id event memory_id occurred_at previous_event_sha256 event_sha256
      audit_metadata rollback_of_event_id rollback_transaction_id rollback_reason
      restored_snapshot
    ].freeze

    attr_reader :path

    def initialize(
      root: Dir.pwd,
      path: nil,
      create: true,
      clock: -> { Time.now },
      id_generator: -> { SecureRandom.hex(5) }
    )
      @root = File.expand_path(root)
      resolved_path = path || MemoryPaths.new(root: @root).write_path("conversation_memory.jsonl")
      @path = File.expand_path(resolved_path, @root)
      prefix = "#{@root}#{File::SEPARATOR}"
      raise ArgumentError, "memory ledger path must remain inside the project" unless @path.start_with?(prefix)
      @clock = clock
      @id_generator = id_generator
      if create
        FileUtils.mkdir_p(File.dirname(@path))
        FileUtils.touch(@path)
      end
    end

    def propose(layer:, content:, source:, confidence:, chat_id: nil, tags: [], metadata: {}, audit_metadata: nil)
      normalized_layer = normalize_layer(layer)
      normalized_content = content.to_s.strip
      raise ArgumentError, "Memory content must not be empty" if normalized_content.empty?

      event = {
        "event_id" => event_id,
        "event" => "created",
        "memory_id" => memory_id,
        "occurred_at" => now,
        "status" => "candidate",
        "layer" => normalized_layer,
        "content" => normalized_content,
        "source" => normalize_source(source),
        "confidence" => normalize_confidence(confidence),
        "chat_id" => optional_string(chat_id),
        "tags" => normalize_tags(tags),
        "metadata" => normalize_metadata(metadata),
        "promote_automatically" => false
      }
      event["audit_metadata"] = normalize_audit_metadata(audit_metadata, fallback_event_id: event["event_id"]) if audit_metadata

      append_event(event)
      materialize_event(event)
    end

    def approve(memory_id, note: nil, audit_metadata: nil)
      current = fetch!(memory_id)
      raise ArgumentError, "Only candidate memory may be approved" unless current["status"] == "candidate"

      append_transition(
        event: "approved",
        memory_id: current.fetch("id"),
        fields: {
          "status" => "approved",
          "approved_at" => now,
          "approval_note" => optional_string(note)
        },
        audit_metadata: audit_metadata
      )
      fetch!(memory_id)
    end

    def supersede(memory_id, by:, reason: nil, audit_metadata: nil)
      current = fetch!(memory_id)
      replacement = fetch!(by)
      raise ArgumentError, "Deleted memory cannot supersede another record" if replacement["status"] == "deleted"
      raise ArgumentError, "A memory record cannot supersede itself" if current["id"] == replacement["id"]

      append_transition(
        event: "superseded",
        memory_id: current.fetch("id"),
        fields: {
          "status" => "superseded",
          "superseded_at" => now,
          "superseded_by" => replacement.fetch("id"),
          "supersession_reason" => optional_string(reason)
        },
        audit_metadata: audit_metadata
      )
      fetch!(memory_id)
    end

    def delete(memory_id, reason: nil, audit_metadata: nil)
      current = fetch!(memory_id)
      return current if current["status"] == "deleted"

      append_transition(
        event: "deleted",
        memory_id: current.fetch("id"),
        fields: {
          "status" => "deleted",
          "deleted_at" => now,
          "deletion_reason" => optional_string(reason)
        },
        audit_metadata: audit_metadata
      )
      fetch!(memory_id)
    end

    def find(memory_id)
      materialized.fetch(memory_id.to_s, nil)
    end

    def records(layer: nil, status: nil, include_deleted: false)
      selected = materialized.values
      selected = selected.select { |record| record["layer"] == normalize_layer(layer) } if layer
      selected = selected.select { |record| record["status"] == normalize_status(status) } if status
      selected = selected.reject { |record| record["status"] == "deleted" } unless include_deleted
      selected.sort_by { |record| [record["updated_at"].to_s, record["id"].to_s] }.reverse
    end

    def events(memory_id: nil)
      parsed_events.select do |event|
        memory_id.nil? || event["memory_id"].to_s == memory_id.to_s
      end
    end

    # Creates the sole audit anchor without changing any historical bytes.
    # The audit service performs strict validation before calling this method.
    def append_audit_baseline(audit_metadata: {})
      ensure_safe_ledger_path!
      FileUtils.mkdir_p(File.dirname(@path))
      File.open(@path, "a+b") do |file|
        file.flock(File::LOCK_EX)
        ensure_safe_ledger_path!
        file.rewind
        bytes = file.read.to_s
        parsed_before_baseline = bytes.lines.each_with_object([]) do |line, entries|
          next if line.strip.empty?
          item = JSON.parse(line)
          raise ArgumentError, "memory ledger contains malformed JSON" unless item.is_a?(Hash)
          entries << item
        rescue JSON::ParserError
          raise ArgumentError, "memory ledger contains malformed JSON"
        end
        raise ArgumentError, "audit baseline already exists" if parsed_before_baseline.any? { |item| item["event"] == "audit_baseline" }

        baseline_event_id = event_id
        event = {
          "event_id" => baseline_event_id,
          "event" => "audit_baseline",
          "occurred_at" => now,
          "schema" => AUDIT_SCHEMA,
          "pre_baseline_byte_count" => bytes.bytesize,
          "pre_baseline_byte_sha256" => Digest::SHA256.hexdigest(bytes),
          "pre_baseline_event_count" => parsed_before_baseline.length,
          "audit_metadata" => normalize_audit_metadata(audit_metadata, fallback_event_id: baseline_event_id)
        }
        event["previous_event_sha256"] = nil
        event["event_sha256"] = event_digest(event)
        file.seek(0, IO::SEEK_END)
        file.puts(JSON.generate(event))
        file.flush
        file.fsync
        event
      end
    end

    # Appends a lifecycle event used by the audit service for compensation.
    def append_audit_event(event, audit_metadata: {})
      append_audit_events([event], audit_metadata: audit_metadata).first
    end

    # Appends a validated batch under one lock so validation failure cannot
    # leave only part of a compensating transaction in the ledger.
    def append_audit_events(events, audit_metadata: {})
      candidates = Array(events)
      raise ArgumentError, "audit event batch must not be empty" if candidates.empty?
      raise ArgumentError, "audit event batch exceeds limit" if candidates.length > MAX_AUDIT_BATCH
      candidates = candidates.map do |event|
        raise ArgumentError, "audit event must be an object" unless event.is_a?(Hash)
        raise ArgumentError, "Unknown memory event" unless EVENTS.include?(event["event"].to_s)
        raise ArgumentError, "audit baseline requires dedicated adoption" if event["event"] == "audit_baseline"
        raise ArgumentError, "audit event id is required" if event["event_id"].to_s.empty?
        raise ArgumentError, "audit memory id is required" if event["memory_id"].to_s.empty?
        Time.iso8601(event["occurred_at"].to_s)
        event.dup
      end
      candidate_ids = candidates.map { |event| event.fetch("event_id").to_s }
      raise ArgumentError, "audit event ids must be unique" unless candidate_ids.uniq.length == candidate_ids.length
      ensure_safe_ledger_path!
      FileUtils.mkdir_p(File.dirname(@path))
      File.open(@path, "a") do |file|
        file.flock(File::LOCK_EX)
        ensure_safe_ledger_path!
        adopted = audit_baseline_present?
        previous = nil
        if adopted
          chain = strict_audit_chain
          previous = chain.last.fetch("event_sha256")
          existing_ids = parsed_events.map { |event| event["event_id"].to_s }
          raise ArgumentError, "audit event id already exists" unless (candidate_ids & existing_ids).empty?
        end
        staged = candidates.map do |candidate|
          if adopted
            candidate["previous_event_sha256"] = previous
            supplied = candidate["audit_metadata"] || audit_metadata
            candidate["audit_metadata"] = normalize_audit_metadata(supplied, fallback_event_id: candidate["event_id"])
            candidate["event_sha256"] = event_digest(candidate)
            previous = candidate["event_sha256"]
          elsif candidate.key?("audit_metadata")
            candidate["audit_metadata"] = normalize_audit_metadata(candidate["audit_metadata"], fallback_event_id: candidate["event_id"])
          end
          candidate
        end
        file.seek(0, IO::SEEK_END)
        file.write(staged.map { |candidate| JSON.generate(candidate) + "\n" }.join)
        file.flush
        file.fsync
        staged
      end
    end

    def context_for(query:, chat_id: nil, limit: 8)
      query_tokens = tokens(query)
      selected = records(status: "approved").filter_map do |record|
        score = relevance_score(record, query_tokens, chat_id)
        next unless score.positive?

        [score, record]
      end
      selected.sort_by! { |score, record| [-score, record["id"].to_s] }
      chosen = selected.first(normalize_limit(limit)).map(&:last)

      {
        "records" => chosen,
        "record_ids" => chosen.map { |record| record["id"] },
        "layers" => chosen.map { |record| record["layer"] }.uniq,
        "count" => chosen.length,
        "rendered" => render_context(chosen)
      }
    end

    def render_context(memory_records)
      Array(memory_records).map do |record|
        source = record.fetch("source", {})
        source_label = [source["kind"], source["reference"]].compact.reject(&:empty?).join(":")
        source_label = "unspecified" if source_label.empty?
        confidence = format("%.2f", record.fetch("confidence", 0.0).to_f)
        "- [#{record['layer']}; confidence #{confidence}; source #{source_label}; id #{record['id']}] #{record['content']}"
      end.join("\n")
    end

    private

    def ensure_safe_ledger_path!
      prefix = "#{@root}#{File::SEPARATOR}"
      raise ArgumentError, "memory ledger path must remain inside the project" unless @path.start_with?(prefix)
      raise ArgumentError, "memory ledger must not be a symlink" if File.symlink?(@path)
      parent = File.dirname(@path)
      while parent.start_with?(prefix)
        raise ArgumentError, "memory ledger parent must not be a symlink" if File.symlink?(parent)
        parent = File.dirname(parent)
      end
    end

    def append_transition(event:, memory_id:, fields:, audit_metadata: nil)
      transition = {
          "event_id" => event_id,
          "event" => event,
          "memory_id" => memory_id.to_s,
          "occurred_at" => now
        }.merge(fields).reject { |_key, value| value.nil? }
      transition["audit_metadata"] = normalize_audit_metadata(audit_metadata, fallback_event_id: transition["event_id"]) if audit_metadata
      append_event(transition)
    end

    def append_event(event)
      append_audit_events([event]).first
    end

    def audit_baseline_present?
      return false unless File.file?(@path) && !File.symlink?(@path)

      found = false
      File.foreach(@path) do |line|
        next if line.strip.empty?
        parsed = JSON.parse(line)
        raise ArgumentError, "memory ledger event must be an object" unless parsed.is_a?(Hash)
        found ||= parsed["event"] == "audit_baseline"
      rescue JSON::ParserError
        raise ArgumentError, "memory ledger contains malformed JSON"
      end
      found
    end

    def strict_audit_chain
      events = []
      raw = File.binread(@path)
      raw.lines.each do |line|
        next if line.strip.empty?

        parsed = JSON.parse(line)
        raise ArgumentError, "memory ledger event must be an object" unless parsed.is_a?(Hash)
        events << parsed
      rescue JSON::ParserError => error
        raise ArgumentError, "memory ledger contains malformed JSON: #{error.message}"
      end
      baseline_index = events.index { |item| item["event"] == "audit_baseline" }
      raise ArgumentError, "audit baseline is missing" unless baseline_index
      event_ids = events.map { |event| event["event_id"].to_s }
      raise ArgumentError, "audit event ids are invalid" if event_ids.any?(&:empty?) || event_ids.uniq.length != event_ids.length
      validate_baseline_prefix!(events, raw, baseline_index)
      chain = events.drop(baseline_index)
      previous = nil
      chain.each do |event|
        raise ArgumentError, "audit chain fields are invalid" unless event.is_a?(Hash) && event["event_sha256"].to_s.match?(/\A[0-9a-f]{64}\z/) && (event["previous_event_sha256"].nil? || event["previous_event_sha256"].to_s.match?(/\A[0-9a-f]{64}\z/))
        raise ArgumentError, "audit chain is broken" unless event["previous_event_sha256"] == previous
        raise ArgumentError, "audit chain digest is invalid" unless event_digest(event) == event["event_sha256"]

        previous = event["event_sha256"]
      end
      chain
    end

    def validate_baseline_prefix!(events, raw, baseline_index)
      prefix = String.new
      seen = 0
      raw.lines.each do |line|
        if line.strip.empty?
          prefix << line
          next
        end
        break if seen == baseline_index
        prefix << line
        seen += 1
      end
      baseline = events.fetch(baseline_index)
      unless baseline["schema"] == AUDIT_SCHEMA && baseline["pre_baseline_byte_count"] == prefix.bytesize &&
             baseline["pre_baseline_byte_sha256"] == Digest::SHA256.hexdigest(prefix) && baseline["pre_baseline_event_count"] == baseline_index
        raise ArgumentError, "audit baseline prefix is invalid"
      end
    end

    def event_digest(event)
      unsigned = event.reject { |key, _value| key.to_s == "event_sha256" }
      Digest::SHA256.hexdigest(JSON.generate(unsigned) + "\n")
    end

    def normalize_audit_metadata(metadata, fallback_event_id:)
      value = metadata.is_a?(Hash) ? metadata.transform_keys(&:to_s) : {}
      value.each_key do |key|
        raise ArgumentError, "unknown audit metadata field" unless AUDIT_METADATA_KEYS.include?(key)
      end
      normalized = {
        "transaction_id" => value["transaction_id"].to_s,
        "actor" => value["actor"].to_s,
        "trigger" => value["trigger"].to_s,
        "reason" => value["reason"].to_s,
        "policy_version" => value["policy_version"].to_s
      }
      normalized["transaction_id"] = fallback_event_id.to_s if normalized["transaction_id"].empty? && fallback_event_id
      normalized["actor"] = "soul" if normalized["actor"].empty?
      normalized["trigger"] = "memory_write" if normalized["trigger"].empty?
      normalized["reason"] = "unspecified" if normalized["reason"].empty?
      normalized["policy_version"] = "soul.memory.audit.v1" if normalized["policy_version"].empty?
      runtime = value["model_runtime_identity"]
      normalized["model_runtime_identity"] = runtime.to_s unless runtime.nil? || runtime.to_s.empty?
      %w[before_state_sha256 after_state_sha256 evidence_digest rollback_reference].each do |key|
        normalized[key] = value[key].to_s if value.key?(key)
      end
      normalized.each do |key, item|
        raise ArgumentError, "audit metadata field is too long" if item.to_s.bytesize > 256
        if %w[before_state_sha256 after_state_sha256 evidence_digest].include?(key) && !item.to_s.match?(/\A[0-9a-f]{64}\z/)
          raise ArgumentError, "audit metadata digest is invalid"
        end
      end
      normalized
    end

    def parsed_events
      return [] unless File.exist?(@path)

      baseline_seen = false
      File.readlines(@path, chomp: true).filter_map do |line|
        next if line.strip.empty?

        event = JSON.parse(line)
        baseline_seen ||= event.is_a?(Hash) && event["event"] == "audit_baseline"
        event
      rescue JSON::ParserError
        raise ArgumentError, "memory ledger contains malformed JSON" if baseline_seen
        nil
      end
    end

    def materialized
      parsed_events.each_with_object({}) do |event, records|
        id = event["memory_id"].to_s
        next if id.empty?

        if event["event"] == "created"
          records[id] = materialize_event(event)
        elsif event["event"] == "restored" && event["restored_snapshot"].is_a?(Hash)
          records[id] = materialize_snapshot(event["restored_snapshot"], event)
        elsif records[id]
          records[id] = records[id].merge(transition_fields(event))
          records[id]["updated_at"] = event["occurred_at"]
          records[id]["last_event_id"] = event["event_id"]
        end
      end
    end

    def materialize_event(event)
      {
        "id" => event.fetch("memory_id"),
        "status" => event.fetch("status"),
        "layer" => event.fetch("layer"),
        "content" => event.fetch("content"),
        "source" => event.fetch("source"),
        "confidence" => event.fetch("confidence"),
        "chat_id" => event["chat_id"],
        "tags" => Array(event["tags"]),
        "metadata" => event.fetch("metadata", {}),
        "promote_automatically" => false,
        "created_at" => event.fetch("occurred_at"),
        "updated_at" => event.fetch("occurred_at"),
        "last_event_id" => event.fetch("event_id")
      }.reject { |_key, value| value.nil? }
    end

    def materialize_snapshot(snapshot, event)
      snapshot.merge(
        "id" => snapshot.fetch("id", event.fetch("memory_id")),
        "updated_at" => event.fetch("occurred_at"),
        "last_event_id" => event.fetch("event_id")
      ).reject { |_key, value| value.nil? }
    end

    def transition_fields(event)
      event.reject do |key, _value|
        AUDIT_EVENT_FIELDS.include?(key)
      end
    end

    def fetch!(memory_id)
      record = find(memory_id)
      raise ArgumentError, "Unknown memory id: #{memory_id}" unless record

      record
    end

    def normalize_layer(layer)
      value = layer.to_s
      raise ArgumentError, "Unknown memory layer: #{layer}" unless LAYERS.include?(value)

      value
    end

    def normalize_status(status)
      value = status.to_s
      raise ArgumentError, "Unknown memory status: #{status}" unless STATUSES.include?(value)

      value
    end

    def normalize_confidence(confidence)
      value = Float(confidence)
      raise ArgumentError, "Memory confidence must be between 0.0 and 1.0" unless value.between?(0.0, 1.0)

      value.round(3)
    rescue ArgumentError, TypeError
      raise ArgumentError, "Memory confidence must be between 0.0 and 1.0"
    end

    def normalize_source(source)
      value = case source
              when Hash
                source.transform_keys(&:to_s)
              else
                { "kind" => source.to_s }
              end
      value["kind"] = value["kind"].to_s.strip
      raise ArgumentError, "Memory source kind must not be empty" if value["kind"].empty?

      value.reject { |_key, item| item.nil? || item.to_s.empty? }
    end

    def normalize_tags(tags)
      Array(tags).map { |tag| tag.to_s.downcase.strip }.reject(&:empty?).uniq.first(20)
    end

    def normalize_metadata(metadata)
      value = metadata.is_a?(Hash) ? metadata.transform_keys(&:to_s) : {}
      JSON.parse(JSON.generate(value))
    rescue JSON::GeneratorError
      raise ArgumentError, "Memory metadata must be JSON-compatible"
    end

    def relevance_score(record, query_tokens, chat_id)
      content_tokens = tokens([record["content"], Array(record["tags"]).join(" ")].join(" "))
      overlap = (query_tokens & content_tokens).length
      always_include = record.fetch("metadata", {})["always_include"] == true
      same_chat = !chat_id.to_s.empty? && record["chat_id"].to_s == chat_id.to_s
      return 0 unless overlap.positive? || always_include || same_chat

      layer_weight = {
        "preference" => 4,
        "project" => 3,
        "semantic" => 2,
        "episodic" => 1
      }.fetch(record["layer"], 0)

      (overlap * 10) + layer_weight + (same_chat ? 5 : 0) +
        (always_include ? 3 : 0) + record.fetch("confidence", 0.0).to_f
    end

    def tokens(value)
      value.to_s.downcase.scan(/[a-z0-9][a-z0-9_.-]{2,}/).uniq
    end

    def normalize_limit(value)
      limit = value.to_i
      limit = 8 unless limit.positive?
      [limit, 20].min
    end

    def optional_string(value)
      text = value.to_s.strip
      text.empty? ? nil : text
    end

    def event_id
      "mev_#{@clock.call.utc.strftime('%Y%m%d%H%M%S%6N')}_#{@id_generator.call}"
    end

    def memory_id
      "mem_#{@clock.call.utc.strftime('%Y%m%d%H%M%S%6N')}_#{@id_generator.call}"
    end

    def now
      @clock.call.iso8601(6)
    end
  end

  class NullConversationMemoryStore
    def context_for(query:, chat_id: nil, limit: 8)
      _unused = [query, chat_id, limit]
      {
        "records" => [],
        "record_ids" => [],
        "layers" => [],
        "count" => 0,
        "rendered" => ""
      }
    end
  end
end
