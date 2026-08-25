# frozen_string_literal: true

require "digest"
require "json"

module SoulCore
  class MemoryLifecycleMaintenanceService
    SCHEMA = "soul.memory_lifecycle_maintenance.a31.v1"

    def initialize(lifecycle_service:, consolidation_service:)
      @lifecycle = lifecycle_service
      @consolidation = consolidation_service
    end

    def work_status
      lifecycle = @lifecycle.work_status
      return failure(lifecycle["reason"]) unless lifecycle["ok"]

      consolidation = @consolidation.preview
      return failure(consolidation["reason"]) unless consolidation["ok"]

      lifecycle_work = lifecycle["work_available"] == true
      consolidation_work = consolidation.dig("data", "work_available") == true
      {
        "ok" => true,
        "lifecycle_state" => "complete",
        "schema" => SCHEMA,
        "work_available" => lifecycle_work || consolidation_work,
        "work_kind" => lifecycle_work ? "observation_lifecycle" : (consolidation_work ? "exact_duplicate_consolidation" : "none"),
        "work_digest" => Digest::SHA256.hexdigest(JSON.generate(
          "lifecycle_work" => lifecycle_work,
          "lifecycle_digest" => lifecycle["work_digest"],
          "consolidation_work" => consolidation_work,
          "consolidation_survivor_id" => consolidation.dig("data", "survivor_id"),
          "consolidation_superseded_id" => consolidation.dig("data", "superseded_id")
        ) + "\n"),
        "content_included" => false
      }
    rescue ArgumentError, IOError, SystemCallError => error
      failure(error.message)
    end

    def run(request_id:)
      status = work_status
      return status unless status["ok"]
      return failure("memory maintenance run has no verified work") unless status["work_available"]

      if status["work_kind"] == "observation_lifecycle"
        return @lifecycle.run(request_id: "#{request_id}:lifecycle")
      end

      result = @consolidation.run(request_id: "#{request_id}:consolidate")
      return failure(result["reason"]) unless result["ok"]

      data = result.fetch("data")
      {
        "ok" => true,
        "lifecycle_state" => "complete",
        "schema" => SCHEMA,
        "cycle_id" => "mlm_#{Digest::SHA256.hexdigest(request_id.to_s)[0, 24]}",
        "cycle_sha256" => Digest::SHA256.hexdigest(JSON.generate(data) + "\n"),
        "mode" => "exact_duplicate_consolidation",
        "decision_counts" => { "superseded_exact_duplicates" => data["no_work"] ? 0 : 1 },
        "rollback_references" => Array(data["rollback_reference"]).compact,
        "idempotent" => data["idempotent"] == true,
        "projection_reconciliation_required" => !data["no_work"] && data["idempotent"] != true,
        "content_included" => false
      }
    rescue ArgumentError, IOError, SystemCallError => error
      failure(error.message)
    end

    private

    def failure(reason)
      {
        "ok" => false,
        "lifecycle_state" => "failed",
        "schema" => SCHEMA,
        "reason" => reason.to_s[0, 400],
        "content_included" => false
      }
    end
  end
end
