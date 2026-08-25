# frozen_string_literal: true

require "digest"
require "json"
require "time"

module SoulCore
  class MemoryExactDuplicateConsolidationService
    SCHEMA = "soul.memory_exact_duplicate_consolidation.a30.v1"
    POLICY_VERSION = "soul.memory.consolidation.a30.v1"
    MAX_RECORDS = 10_000

    def initialize(memory_store:, audit_service:, clock: -> { Time.now })
      @memories = memory_store
      @audit = audit_service
      @clock = clock
    end

    def run(request_id:)
      request = bounded_id(request_id)
      verified = @audit.verify
      raise ArgumentError, "canonical memory audit is unavailable" unless verified["ok"]

      records = @memories.records(status: "approved")
      raise ArgumentError, "approved memory count exceeds consolidation bound" if records.length > MAX_RECORDS
      replay = replay_for(request)
      if replay
        survivor = @memories.find(replay.fetch("superseded_by"))
        redundant = @memories.find(replay.fetch("memory_id"))
        raise ArgumentError, "consolidation replay evidence is stale" unless survivor && redundant
        return receipt(request, survivor, redundant,
          replay.dig("audit_metadata", "transaction_id"), idempotent: true)
      end
      duplicate = next_duplicate(records)
      return complete("request_id" => request, "no_work" => true, "content_included" => false) unless duplicate

      survivor, redundant = duplicate
      transaction = "memory-consolidate:#{request}:#{redundant.fetch('id')}"
      before = state_digest
      evidence = Digest::SHA256.hexdigest(JSON.generate(
        "survivor_id" => survivor.fetch("id"),
        "redundant_id" => redundant.fetch("id"),
        "survivor_event_id" => survivor.fetch("last_event_id"),
        "redundant_event_id" => redundant.fetch("last_event_id"),
        "normalized_content_sha256" => Digest::SHA256.hexdigest(normalized_content(survivor.fetch("content")))
      ) + "\n")
      @memories.supersede(
        redundant.fetch("id"),
        by: survivor.fetch("id"),
        reason: "deterministic exact-duplicate consolidation",
        audit_metadata: {
          "transaction_id" => transaction,
          "actor" => "soul.memory.consolidation",
          "trigger" => "bounded_exact_duplicate_cycle",
          "reason" => "supersede one ordinary exact duplicate",
          "policy_version" => POLICY_VERSION,
          "before_state_sha256" => before,
          "evidence_digest" => evidence,
          "rollback_reference" => transaction
        }
      )
      after = @audit.verify
      raise ArgumentError, "canonical memory audit failed after consolidation" unless after["ok"]
      receipt(request, survivor, redundant, transaction, idempotent: false,
        before_state_sha256: before, after_state_sha256: state_digest,
        evidence_sha256: evidence)
    rescue ArgumentError, IOError, SystemCallError => error
      failure(error.message)
    end

    def preview
      verified = @audit.verify
      raise ArgumentError, "canonical memory audit is unavailable" unless verified["ok"]
      records = @memories.records(status: "approved")
      raise ArgumentError, "approved memory count exceeds consolidation bound" if records.length > MAX_RECORDS
      duplicate = next_duplicate(records)
      complete(
        "work_available" => !duplicate.nil?,
        "survivor_id" => duplicate && duplicate.first.fetch("id"),
        "superseded_id" => duplicate && duplicate.last.fetch("id"),
        "approved_record_count" => records.length,
        "content_included" => false,
        "no_work" => duplicate.nil?
      )
    rescue ArgumentError, IOError, SystemCallError => error
      failure(error.message)
    end

    private

    def next_duplicate(records)
      groups = records.group_by do |record|
        [record.fetch("layer"), normalized_content(record.fetch("content"))]
      end
      groups.keys.sort.each do |key|
        group = groups.fetch(key)
        next unless group.length > 1 && group.none? { |record| protected?(record) }

        ordered = group.sort_by do |record|
          [-record.fetch("confidence", 0).to_f, record.fetch("created_at").to_s, record.fetch("id").to_s]
        end
        return [ordered.first, ordered.drop(1).sort_by { |record| record.fetch("id") }.first]
      end
      nil
    end

    def replay_for(request)
      prefix = "memory-consolidate:#{request}:"
      @memories.events.reverse.find do |event|
        event["event"] == "superseded" &&
          event.dig("audit_metadata", "policy_version") == POLICY_VERSION &&
          event.dig("audit_metadata", "transaction_id").to_s.start_with?(prefix)
      end
    end

    def protected?(record)
      metadata = record.fetch("metadata", {})
      metadata["protected"] == true || metadata["protection"].to_s == "protected"
    end

    def normalized_content(value)
      value.to_s.strip.gsub(/\s+/, " ")
    end

    def state_digest
      rows = @memories.records(include_deleted: true).sort_by { |record| record.fetch("id") }
      Digest::SHA256.hexdigest(JSON.generate(rows) + "\n")
    end

    def receipt(request, survivor, redundant, transaction, idempotent:, **digests)
      complete({
        "request_id" => request,
        "no_work" => false,
        "idempotent" => idempotent,
        "survivor_id" => survivor.fetch("id"),
        "superseded_id" => redundant.fetch("id"),
        "transaction_id" => transaction,
        "rollback_reference" => transaction,
        "content_included" => false
      }.merge(digests.transform_keys(&:to_s)))
    end

    def complete(data)
      { "ok" => true, "lifecycle_state" => "complete", "schema" => SCHEMA,
        "data" => data,
        "mutation" => (data["no_work"] || data["idempotent"] || data.key?("work_available") ? "none" : "canonical_memory_lifecycle") }
    end

    def failure(reason)
      { "ok" => false, "lifecycle_state" => "failed", "schema" => SCHEMA,
        "reason" => reason.to_s[0, 300], "content_included" => false, "mutation" => "none" }
    end

    def bounded_id(value)
      text = value.to_s
      raise ArgumentError, "consolidation request ID is invalid" unless text.bytesize.between?(1, 128) && text.match?(/\A[A-Za-z0-9_.:\/-]+\z/)
      text
    end
  end
end
