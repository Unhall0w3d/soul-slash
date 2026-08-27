# frozen_string_literal: true

require "digest"
require "json"

module SoulCore
  class MemoryLifecycleProjectionCoordinator
    SCHEMA = "soul.memory_lifecycle_projection_coordinator.a33.v1"

    def initialize(maintenance_service:, reconciliation_service: nil, reconciliation_factory: nil)
      @maintenance = maintenance_service
      @reconciliation = reconciliation_service
      @reconciliation_factory = reconciliation_factory
      raise ArgumentError, "reconciliation service or factory is required" unless @reconciliation || @reconciliation_factory
    end

    def work_status
      canonical = @maintenance.work_status
      return canonical unless canonical["ok"]
      return canonical.merge("work_kind" => "canonical_memory") if canonical["work_available"]

      projection = reconciliation.work_status
      return projection unless projection["ok"]
      projection.merge("schema" => SCHEMA)
    end

    def run(request_id:)
      status = work_status
      return status unless status["ok"]
      return failure("memory coordinator has no verified work") unless status["work_available"]
      if status["work_kind"] == "canonical_memory"
        cycle = @maintenance.run(request_id: request_id)
        if cycle["ok"] && cycle["projection_reconciliation_required"]
          cycle["projection_request_persisted"] = begin
            reconciliation.capture_required(trigger: cycle["mode"])
          rescue StandardError
            false
          end
        end
        return cycle
      end

      result = reconciliation.run(request_id: status.fetch("request_id"))
      return result unless result["ok"]
      {
        "ok" => true, "lifecycle_state" => "complete", "schema" => SCHEMA,
        "cycle_id" => "mprc_#{result.fetch('source_digest')[0, 24]}",
        "cycle_sha256" => Digest::SHA256.hexdigest(JSON.generate(result)),
        "mode" => "projection_reconciliation", "decision_counts" => { "projection_generations_activated" => 1 },
        "rollback_references" => [], "idempotent" => false,
        "projection_reconciliation_required" => false,
        "generation_id" => result["generation_id"], "content_included" => false
      }
    end

    private

    def reconciliation
      @reconciliation ||= @reconciliation_factory.call
    end

    def failure(reason)
      { "ok" => false, "lifecycle_state" => "failed", "schema" => SCHEMA,
        "reason" => reason.to_s[0, 300], "content_included" => false }
    end
  end
end
