# frozen_string_literal: true

require "digest"
require "json"

module SoulCore
  class MemoryAutomaticProjectionReconciliationService
    SCHEMA = "soul.memory_automatic_projection_reconciliation.a33.v1"

    def initialize(memory_store:, audit_service:, index_service:, reconciler:, selector_store:, request_store:)
      @memories = memory_store
      @audit = audit_service
      @index = index_service
      @reconciler = reconciler
      @selector = selector_store
      @requests = request_store
    end

    def capture_required(trigger:)
      snapshot = canonical_snapshot
      @requests.pending(source_digest: snapshot.fetch("source_digest"),
        canonical_state_digest: snapshot.fetch("canonical_state_digest"),
        audit_head_sha256: snapshot.fetch("audit_head_sha256"), trigger: trigger)
      true
    rescue StandardError
      false
    end

    def work_status
      snapshot = canonical_snapshot
      request = @requests.current
      aligned = aligned?(snapshot)
      if aligned
        return complete("work_available" => false, "work_kind" => "none",
          "work_digest" => digest("aligned" => snapshot), "content_included" => false)
      end
      request = @requests.pending(source_digest: snapshot.fetch("source_digest"),
        canonical_state_digest: snapshot.fetch("canonical_state_digest"),
        audit_head_sha256: snapshot.fetch("audit_head_sha256")) if request.nil? ||
          request["source_digest"] != snapshot["source_digest"] ||
          request["canonical_state_digest"] != snapshot["canonical_state_digest"]
      blocked = %w[blocked_for_human_review canceled].include?(request["state"])
      complete("work_available" => !blocked, "work_kind" => blocked ? "blocked_for_human_review" : "projection_reconciliation",
        "work_digest" => digest("request_id" => request.fetch("request_id"), "source_digest" => snapshot.fetch("source_digest"),
          "audit_head_sha256" => snapshot.fetch("audit_head_sha256")),
        "request_id" => request.fetch("request_id"), "attempts" => request.fetch("attempts"),
        "blocked_for_human_review" => request["state"] == "blocked_for_human_review",
        "canceled" => request["state"] == "canceled", "content_included" => false)
    rescue StandardError => error
      failure(error.message)
    end

    def run(request_id:)
      status = work_status
      return status unless status["ok"]
      return failure("projection reconciliation has no verified work") unless status["work_available"]
      request = @requests.current
      return failure("projection reconciliation request identity drifted") unless request && request["request_id"] == request_id
      before = canonical_snapshot
      return failure("projection reconciliation request is stale") unless request["source_digest"] == before["source_digest"] &&
        request["canonical_state_digest"] == before["canonical_state_digest"] &&
        request["audit_head_sha256"] == before["audit_head_sha256"]

      rebuilt = @index.rebuild
      raise rebuilt.fetch("message", "local index rebuild failed") unless rebuilt["lifecycle_state"] == "complete"
      after_index = canonical_snapshot
      raise "canonical memory changed during local index rebuild" unless after_index == before

      preview = @reconciler.preview
      raise preview.fetch("reason", "projection preview failed") unless preview["lifecycle_state"] == "blocked_for_human_review"
      plan = preview.fetch("data")
      raise "projection preview source digest drifted" unless plan.dig("source_digests", "approved_index") == before["source_digest"]
      previous_selector = @selector.active
      executed = @reconciler.execute(confirmation: plan.fetch("confirmation_phrase"), expected_digest: plan.fetch("expected_digest"))
      raise executed.fetch("reason", "projection activation failed") unless executed["ok"]
      final = canonical_snapshot
      unless final == before
        previous_selector ? @selector.activate(previous_selector) : @selector.deactivate
        raise "canonical memory changed during projection activation"
      end
      generation = executed.dig("data", "generation_id").to_s
      @requests.complete(generation_id: generation)
      complete("work_available" => false, "request_id" => request_id,
        "generation_id" => generation, "source_digest" => before["source_digest"],
        "audit_head_sha256" => before["audit_head_sha256"], "attempts" => request["attempts"],
        "mutation" => "derived_projection_reconciled", "content_included" => false)
    rescue StandardError => error
      state = @requests.failed(error.message) rescue nil
      failure(error.message, "attempts" => state && state["attempts"],
        "blocked_for_human_review" => state && state["state"] == "blocked_for_human_review")
    end

    private

    def canonical_snapshot
      verified = @audit.verify
      raise "canonical memory audit is unavailable" unless verified["ok"]
      approved = Array(@memories.records(status: "approved")).sort_by { |record| record.fetch("id").to_s }
      canonical = Array(@memories.records(include_deleted: true)).sort_by { |record| record.fetch("id").to_s }
      { "source_digest" => digest(approved), "canonical_state_digest" => digest(canonical),
        "audit_head_sha256" => verified.fetch("chain_head_sha256") }
    end

    def aligned?(snapshot)
      availability = @index.availability
      active = @selector.active
      availability["available"] == true && availability["source_digest"] == snapshot["source_digest"] &&
        active.is_a?(Hash) && active.dig("source_digests", "approved_index") == snapshot["source_digest"]
        && active.dig("source_digests", "canonical_state") == snapshot["canonical_state_digest"]
    rescue StandardError
      false
    end

    def complete(data)
      { "ok" => true, "lifecycle_state" => "complete", "schema" => SCHEMA,
        "mutation" => data.delete("mutation") || "none", "content_included" => false }.merge(data)
    end

    def failure(reason, details = {})
      { "ok" => false, "lifecycle_state" => "failed", "schema" => SCHEMA,
        "reason" => reason.to_s[0, 300], "mutation" => "none", "content_included" => false }.merge(details.compact)
    end

    def digest(value)
      Digest::SHA256.hexdigest(JSON.generate(canonicalize(value)))
    end

    def canonicalize(value)
      case value
      when Hash then value.keys.sort.to_h { |key| [key, canonicalize(value.fetch(key))] }
      when Array then value.map { |item| canonicalize(item) }
      else value
      end
    end
  end
end
