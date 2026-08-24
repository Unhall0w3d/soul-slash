# frozen_string_literal: true

require "digest"
require "json"
require "securerandom"
require "time"
require_relative "conversation_memory_store"
require_relative "memory_paths"

module SoulCore
  # Foreground, content-free audit and reconstruction operations for the
  # canonical conversation memory JSONL ledger.
  class MemoryAuditJournalService
    SCHEMA = ConversationMemoryStore::AUDIT_SCHEMA
    MAX_EVENTS = 10_000
    MAX_METADATA_FIELDS = 16
    HEX_DIGEST = /\A[0-9a-f]{64}\z/
    AUDIT_METADATA_KEYS = ConversationMemoryStore::AUDIT_METADATA_KEYS

    def initialize(root: Dir.pwd, memory_store: nil, path: nil, clock: -> { Time.now }, id_generator: -> { SecureRandom.hex(5) })
      @root = File.expand_path(root)
      default_path = path || (memory_store && memory_store.path) || MemoryPaths.new(root: @root).write_path("conversation_memory.jsonl")
      @path = File.expand_path(default_path, @root)
      @store = memory_store
      if @store.nil? && @path.start_with?("#{@root}#{File::SEPARATOR}")
        @store = ConversationMemoryStore.new(root: @root, path: @path, create: false)
      end
      @clock = clock
      @id_generator = id_generator
    end

    def baseline(audit_metadata: {}, **metadata)
      audit_metadata = audit_metadata.merge(metadata)
      ensure_safe_path!
      existing = strict_lines
      found = existing.select { |event| event["event"] == "audit_baseline" }
      if found.length > 1
        return failure("multiple audit baselines")
      end
      if found.one?
        integrity = verify
        return integrity unless integrity["ok"]
        return baseline_receipt(found.first, idempotent: true, event_count: existing.length)
      end

      event = @store.append_audit_baseline(audit_metadata: normalize_metadata(audit_metadata))
      baseline_receipt(event, idempotent: false, event_count: existing.length + 1)
    rescue JSON::ParserError
      failure("malformed JSON")
    rescue ArgumentError, Errno::EACCES, Errno::EISDIR, Errno::ENOENT => error
      failure(error.message)
    end

    alias ensure_baseline baseline
    alias establish_baseline baseline

    def verify
      ensure_safe_path!
      raw = File.file?(@path) ? File.binread(@path) : ""
      events = parse_strict(raw)
      baseline_index = events.index { |event| event["event"] == "audit_baseline" }
      return failure("audit baseline is missing", event_count: events.length) unless baseline_index
      return failure("multiple audit baselines", event_count: events.length) if events.drop(baseline_index + 1).any? { |event| event["event"] == "audit_baseline" }

      baseline = events.fetch(baseline_index)
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
      checks = {
        "baseline_schema" => baseline["schema"] == SCHEMA,
        "pre_baseline_byte_count" => baseline["pre_baseline_byte_count"] == prefix.bytesize,
        "pre_baseline_byte_sha256" => secure_equal?(baseline["pre_baseline_byte_sha256"].to_s, Digest::SHA256.hexdigest(prefix)),
        "pre_baseline_event_count" => baseline["pre_baseline_event_count"] == baseline_index,
        "event_ids_unique" => events.all? { |event| !event["event_id"].to_s.empty? } &&
          events.map { |event| event["event_id"].to_s }.uniq.length == events.length,
        "newline_terminated" => raw.empty? || raw.end_with?("\n"),
        "chain" => true
      }
      previous = nil
      events.drop(baseline_index).each do |event|
        valid = event.is_a?(Hash) && HEX_DIGEST.match?(event["event_sha256"].to_s) &&
          (event["previous_event_sha256"].nil? || HEX_DIGEST.match?(event["previous_event_sha256"].to_s)) &&
          event["previous_event_sha256"] == previous && audit_metadata_valid?(event["audit_metadata"]) &&
          event_digest(event) == event["event_sha256"]
        checks["chain"] = false unless valid
        previous = event["event_sha256"] if valid
        break unless valid
      end
      {
        "ok" => checks.values.all?,
        "schema" => SCHEMA,
        "event_count" => events.length,
        "baseline_event_id" => baseline["event_id"],
        "chain_head_sha256" => checks["chain"] ? previous : nil,
        "checks" => checks
      }
    rescue JSON::ParserError
      failure("malformed JSON")
    rescue ArgumentError, Errno::EACCES, Errno::EISDIR => error
      failure(error.message)
    end

    alias integrity verify
    alias status verify
    alias verify_integrity verify
    alias integrity_report verify

    def reconstruct(event_id: nil, occurred_at: nil, at_event_id: nil, at_occurred_at: nil)
      ensure_safe_path!
      selected_id = event_id || at_event_id
      selected_time = occurred_at || at_occurred_at
      raise ArgumentError, "provide event_id or occurred_at" if selected_id.to_s.empty? && selected_time.to_s.empty?
      events = parse_strict(File.file?(@path) ? File.binread(@path) : "")
      if events.any? { |event| event["event"] == "audit_baseline" }
        integrity = verify
        return integrity.merge("records" => []) unless integrity["ok"]
      end
      chosen = if selected_id
                 index = events.index { |event| event["event_id"].to_s == selected_id.to_s }
                 raise ArgumentError, "unknown reconstruction event" unless index
                 events.first(index + 1)
               else
                 timestamp = Time.iso8601(selected_time.to_s)
                 events.select { |event| Time.iso8601(event["occurred_at"].to_s) <= timestamp }
               end
      records = replay(chosen)
      {
        "ok" => true,
        "event_id" => chosen.last && chosen.last["event_id"],
        "occurred_at" => selected_time,
        "record_count" => records.length,
        "state_sha256" => state_digest(records),
        "records" => lifecycle_descriptors(records),
        "event_count" => chosen.length
      }
    rescue JSON::ParserError
      failure("malformed JSON")
    rescue ArgumentError => error
      failure(error.message)
    end

    alias point_in_time reconstruct
    alias reconstruct_at reconstruct
    alias reconstruct_state reconstruct

    def rollback(target_event_id:, audit_metadata: {}, reason: nil, **metadata)
      audit_metadata = audit_metadata.merge(metadata)
      ensure_safe_path!
      events = parse_strict(File.file?(@path) ? File.binread(@path) : "")
      if events.any? { |event| event["event"] == "audit_baseline" }
        integrity = verify
        return integrity.merge("rollback_of_event_id" => target_event_id.to_s) unless integrity["ok"]
      end
      target_index = events.index { |event| event["event_id"].to_s == target_event_id.to_s }
      raise ArgumentError, "invalid rollback target" unless target_index
      target = events.fetch(target_index)
      raise ArgumentError, "invalid rollback target" if target["event"] == "audit_baseline"

      later_events = events.drop(target_index + 1).select do |event|
        event["memory_id"].to_s == target["memory_id"].to_s && !compensation_event?(event)
      end
      raise ArgumentError, "stale rollback target" unless later_events.empty?

      prior_compensation = events.find { |event| event["rollback_of_event_id"].to_s == target_event_id.to_s }
      return rollback_receipt(prior_compensation, target, idempotent: true) if prior_compensation

      prior_records = replay(events.first(target_index))
      current = prior_records.find { |record| record["id"].to_s == target["memory_id"].to_s }
      raise ArgumentError, "protected rollback target" if protected_record?(current) || protected_event?(target)
      event = {
        "event_id" => "mev_#{@clock.call.utc.strftime('%Y%m%d%H%M%S%6N')}_#{@id_generator.call}",
        "event" => current ? "restored" : "deleted",
        "memory_id" => target["memory_id"].to_s,
        "occurred_at" => @clock.call.iso8601(6),
        "rollback_of_event_id" => target_event_id.to_s,
        "rollback_reason" => bounded_string(reason || "compensating rollback")
      }
      if current
        event["restored_snapshot"] = deep_copy(current)
      else
        event["status"] = "deleted"
        event["deleted_at"] = event["occurred_at"]
      end
      appended = @store.append_audit_event(event, audit_metadata: normalize_metadata(audit_metadata))
      rollback_receipt(appended, target, idempotent: false)
    rescue JSON::ParserError
      failure("malformed JSON")
    rescue ArgumentError => error
      failure(error.message)
    end

    alias compensate rollback
    alias compensating_rollback rollback
    alias rollback_event rollback

    def rollback_transaction(transaction_id:, audit_metadata: {}, reason: nil, **metadata)
      audit_metadata = audit_metadata.merge(metadata)
      ensure_safe_path!
      events = parse_strict(File.file?(@path) ? File.binread(@path) : "")
      baseline_index = events.index { |event| event["event"] == "audit_baseline" }
      raise ArgumentError, "invalid rollback transaction" unless baseline_index
      integrity = verify
      return integrity.merge("transaction_id" => transaction_id.to_s) if integrity && !integrity["ok"]
      matching = events.each_with_index.drop(baseline_index + 1).select do |event, _index|
        event.dig("audit_metadata", "transaction_id").to_s == transaction_id.to_s &&
          event["event"] != "audit_baseline" && event["rollback_of_event_id"].nil?
      end
      raise ArgumentError, "invalid rollback transaction" if transaction_id.to_s.empty? || matching.empty?
      existing = events.select { |event| event["rollback_transaction_id"].to_s == transaction_id.to_s }
      return transaction_rollback_receipt(existing, transaction_id, idempotent: true, event_count: existing.length) unless existing.empty?

      grouped = matching.group_by { |event, _index| event["memory_id"].to_s }
      raise ArgumentError, "invalid rollback transaction" if grouped.keys.any?(&:empty?)
      states = grouped.map do |memory_id, entries|
        earliest_index = entries.map(&:last).min
        current = replay(events.first(earliest_index)).find { |record| record["id"].to_s == memory_id }
        latest = entries.max_by(&:last).first
        later_events = events.drop(entries.map(&:last).max + 1).select do |event|
          event["memory_id"].to_s == memory_id &&
            !compensation_event?(event) && event.dig("audit_metadata", "transaction_id").to_s != transaction_id.to_s
        end
        raise ArgumentError, "stale rollback transaction" unless later_events.empty?
        raise ArgumentError, "protected rollback target" if protected_record?(current) || entries.any? { |event, _| protected_event?(event) }
        [memory_id, current, latest]
      end
      new_transaction_id = "rollback_#{@id_generator.call}"
      events_to_append = states.map do |memory_id, current, latest|
        event = {
          "event_id" => "mev_#{@clock.call.utc.strftime('%Y%m%d%H%M%S%6N')}_#{@id_generator.call}",
          "event" => current ? "restored" : "deleted",
          "memory_id" => memory_id,
          "occurred_at" => @clock.call.iso8601(6),
          "rollback_of_event_id" => latest["event_id"],
          "rollback_transaction_id" => transaction_id.to_s,
          "rollback_reason" => bounded_string(reason || "compensating transaction rollback")
        }
        if current
          event["restored_snapshot"] = deep_copy(current)
        else
          event["status"] = "deleted"
          event["deleted_at"] = event["occurred_at"]
        end
        event
      end
      metadata_for = normalize_metadata(audit_metadata.merge("transaction_id" => new_transaction_id))
      appended = @store.append_audit_events(events_to_append, audit_metadata: metadata_for)
      transaction_rollback_receipt(appended, transaction_id, idempotent: false, event_count: appended.length)
    rescue JSON::ParserError
      failure("malformed JSON")
    rescue ArgumentError => error
      failure(error.message)
    end

    alias compensate_transaction rollback_transaction

    private

    def ensure_safe_path!
      prefix = "#{@root}#{File::SEPARATOR}"
      raise ArgumentError, "memory ledger path escapes project" unless @path.start_with?(prefix)
      raise ArgumentError, "memory ledger must not be a symlink" if File.symlink?(@path)
      parent = File.dirname(@path)
      while parent.start_with?(prefix)
        raise ArgumentError, "memory ledger parent must not be a symlink" if File.symlink?(parent)
        parent = File.dirname(parent)
      end
    end

    def strict_lines(raw = (File.file?(@path) ? File.binread(@path) : ""))
      parse_strict(raw)
    end

    def parse_strict(raw)
      lines = raw.to_s.lines
      raise ArgumentError, "memory ledger exceeds event limit" if lines.length > MAX_EVENTS
      lines.each_with_index.filter_map do |line, index|
        next if line.strip.empty?
        parsed = JSON.parse(line)
        raise ArgumentError, "memory ledger event #{index} is not an object" unless parsed.is_a?(Hash)
        parsed
      rescue JSON::ParserError => error
        raise JSON::ParserError, "line #{index + 1}: #{error.message}"
      end
    end

    def replay(events)
      records = {}
      events.each do |event|
        id = event["memory_id"].to_s
        next if id.empty? || event["event"] == "audit_baseline"
        if event["event"] == "created"
          records[id] = {
            "id" => id, "status" => event["status"], "layer" => event["layer"], "content" => event["content"],
            "source" => event["source"], "confidence" => event["confidence"], "chat_id" => event["chat_id"],
            "tags" => event["tags"] || [], "metadata" => event["metadata"] || {}, "created_at" => event["occurred_at"],
            "updated_at" => event["occurred_at"], "last_event_id" => event["event_id"]
          }.reject { |_key, value| value.nil? }
        elsif event["event"] == "restored" && event["restored_snapshot"].is_a?(Hash)
          records[id] = deep_copy(event["restored_snapshot"])
          records[id]["id"] = id
          records[id]["updated_at"] = event["occurred_at"]
          records[id]["last_event_id"] = event["event_id"]
        elsif records[id]
          records[id].merge!(event.reject { |key, _value| ConversationMemoryStore::AUDIT_EVENT_FIELDS.include?(key) })
          records[id]["updated_at"] = event["occurred_at"]
          records[id]["last_event_id"] = event["event_id"]
        end
      end
      records.values.sort_by { |record| record["id"].to_s }
    end

    def event_digest(event)
      Digest::SHA256.hexdigest(JSON.generate(event.reject { |key, _value| key.to_s == "event_sha256" }) + "\n")
    end

    def lifecycle_descriptors(records)
      records.map do |record|
        {
          "record_id" => record["id"],
          "status" => record["status"],
          "layer" => record["layer"],
          "created_at" => record["created_at"],
          "updated_at" => record["updated_at"],
          "last_event_id" => record["last_event_id"]
        }
      end.sort_by { |record| record["record_id"].to_s }
    end

    def state_digest(records)
      Digest::SHA256.hexdigest(JSON.generate(records.sort_by { |record| record["id"].to_s }))
    end

    def deep_copy(value)
      JSON.parse(JSON.generate(value))
    end

    def protected_record?(record)
      metadata = record.is_a?(Hash) ? record["metadata"] : nil
      metadata.is_a?(Hash) && (metadata["protected"] == true || metadata["protection"].to_s == "protected")
    end

    def protected_event?(event)
      protected_record?("metadata" => event["metadata"]) || protected_record?(event["restored_snapshot"])
    end

    def compensation_event?(event)
      event["rollback_of_event_id"] || event["rollback_transaction_id"]
    end

    def normalize_metadata(metadata)
      value = metadata.is_a?(Hash) ? metadata.transform_keys(&:to_s) : {}
      raise ArgumentError, "audit metadata has too many fields" if value.length > MAX_METADATA_FIELDS
      value.each_with_object({}) do |(key, item), output|
        raise ArgumentError, "audit metadata keys must be simple" unless key.match?(/\A[a-z][a-z0-9_]{0,63}\z/)
        raise ArgumentError, "unknown audit metadata field" unless AUDIT_METADATA_KEYS.include?(key)
        raise ArgumentError, "audit metadata must be JSON-compatible" unless [String, Integer, Float, TrueClass, FalseClass, NilClass].any? { |type| item.is_a?(type) }
        if %w[model_runtime_identity before_state_sha256 after_state_sha256 evidence_digest rollback_reference].include?(key) && !item.is_a?(String)
          raise ArgumentError, "audit metadata field must be a string"
        end
        raise ArgumentError, "audit metadata digest is invalid" if %w[before_state_sha256 after_state_sha256 evidence_digest].include?(key) && !item.to_s.match?(HEX_DIGEST)
        output[key] = item.is_a?(String) ? bounded_string(item) : item
      end
    end

    def audit_metadata_valid?(metadata)
      return false unless metadata.is_a?(Hash)
      return false unless metadata.keys.all? { |key| AUDIT_METADATA_KEYS.include?(key.to_s) }
      required = %w[transaction_id actor trigger reason policy_version]
      return false unless required.all? { |key| metadata.key?(key) && metadata[key].is_a?(String) && metadata[key].bytesize <= 256 }
      optional = metadata["model_runtime_identity"]
      return false unless optional.nil? || (optional.is_a?(String) && optional.bytesize <= 256)
      return false unless %w[before_state_sha256 after_state_sha256 evidence_digest rollback_reference].all? do |key|
        metadata[key].nil? || (metadata[key].is_a?(String) && metadata[key].bytesize <= 256)
      end
      %w[before_state_sha256 after_state_sha256 evidence_digest].all? do |key|
        metadata[key].nil? || HEX_DIGEST.match?(metadata[key].to_s)
      end && %w[rollback_reference].all? do |key|
        metadata[key].nil? || (metadata[key].is_a?(String) && metadata[key].bytesize <= 256)
      end
    end

    def bounded_string(value)
      text = value.to_s
      raise ArgumentError, "audit metadata field is too long" if text.bytesize > 256
      text
    end

    def baseline_receipt(event, idempotent:, event_count:)
      { "ok" => true, "lifecycle_state" => "complete", "idempotent" => idempotent, "event_id" => event["event_id"], "event_count" => event_count, "pre_baseline_byte_count" => event["pre_baseline_byte_count"], "pre_baseline_byte_sha256" => event["pre_baseline_byte_sha256"] }
    end

    def rollback_receipt(event, target, idempotent:)
      { "ok" => true, "lifecycle_state" => "complete", "idempotent" => idempotent, "event_id" => event["event_id"], "event" => event["event"], "rollback_of_event_id" => target["event_id"], "memory_id" => target["memory_id"] }
    end

    def transaction_rollback_receipt(event, transaction_id, idempotent:, event_count: 1)
      events = event.is_a?(Array) ? event.compact : [event].compact
      {
        "ok" => true,
        "lifecycle_state" => "complete",
        "idempotent" => idempotent,
        "transaction_id" => transaction_id.to_s,
        "event_id" => events.first && events.first["event_id"],
        "event_ids" => events.map { |item| item["event_id"] },
        "memory_ids" => events.map { |item| item["memory_id"] }.uniq,
        "event_count" => event_count
      }
    end

    def failure(message, **extra)
      { "ok" => false, "lifecycle_state" => "failed", "error" => message.to_s, "event_count" => extra.fetch(:event_count, 0) }.merge(extra)
    end

    def secure_equal?(left, right)
      return false unless left.bytesize == right.bytesize
      left.bytes.zip(right.bytes).reduce(0) { |difference, pair| difference | (pair[0] ^ pair[1]) }.zero?
    end
  end
end
