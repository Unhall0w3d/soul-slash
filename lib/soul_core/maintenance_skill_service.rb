# frozen_string_literal: true

module SoulCore
  # Skill entry points narrow the shared controller; they never execute a fleet
  # plan or infer reboot authority from a completed package transaction.
  class MaintenanceSkillService
    def initialize(fleet_status_service:, device_control_service:)
      @fleet = fleet_status_service
      @control = device_control_service
    end

    def preview(device_id:, action:)
      validate_action!(action)
      device = refresh_target!(device_id)
      require_reboot!(device) if action == "reboot"
      @control.preview(device_id: device_id, action: action)
    rescue ArgumentError => error
      blocked(error.message)
    end

    def execute(device_id:, action:, confirmation:, expected_digest:, progress: nil)
      validate_action!(action)
      device = refresh_target!(device_id)
      require_reboot!(device) if action == "reboot"
      result = @control.execute(device_id: device_id, action: action,
        confirmation: confirmation, expected_digest: expected_digest, progress: progress)
      return result unless action == "maintenance" && result["ok"] == true && result["lifecycle_state"] == "complete"

      # A failed recollection is not evidence that reboot is unnecessary.
      refreshed = refresh_target!(device_id)
      result.merge("data" => (result["data"] || {}).merge(
        "reboot_followup" => reboot_followup(refreshed)))
    rescue ArgumentError => error
      return result.merge("data" => (result["data"] || {}).merge(
        "reboot_followup" => {"state" => "unknown", "reason" => error.message, "automatic_execution" => false})) if result
      blocked(error.message)
    end

    private

    def validate_action!(action)
      raise ArgumentError, "one separate maintenance or reboot action is required" unless %w[maintenance reboot].include?(action)
    end

    def target!(device_id, snapshot)
      raise ArgumentError, "fleet evidence unavailable" unless snapshot["ok"] == true && snapshot["lifecycle_state"] == "complete"
      raise ArgumentError, "Atelier is excluded from these skills" if %w[workstation atelier].include?(device_id.to_s.downcase)
      matches = Array(snapshot.dig("data", "devices")).select do |device|
        target_id(device) == device_id
      end
      raise ArgumentError, "one enrolled remote maintenance target is required" unless matches.length == 1
      device = matches.first
      unless device["id"] != "workstation" && device["label"].to_s.downcase != "atelier" && device["control"] == "maintenance"
        raise ArgumentError, "target is excluded or inventory-only"
      end
      device
    end

    def target_id(device)
      id = device.dig("facts", "control_target_id")
      id = device["id"] if id.to_s.empty? && %w[forge pihole].include?(device["id"])
      id
    end

    def refresh_target!(device_id)
      device = target!(device_id, @fleet.snapshot)
      refreshed = @fleet.refresh(device_id: device.fetch("id"), schedule_recovery: false)
      unless refreshed["ok"] == true && refreshed.dig("data", "refreshed_device_id") == device["id"]
        raise ArgumentError, "exact target refresh failed; no operation authorized"
      end
      device = target!(device_id, refreshed)
      raise ArgumentError, "target is offline or unavailable" if %w[offline unavailable failed].include?(device["status"])
      device
    end

    def require_reboot!(device)
      raise ArgumentError, "fresh evidence does not report reboot required; no reboot proposed" unless device.dig("reboot", "required") == true
    end

    def reboot_followup(device)
      value = device.dig("reboot", "required")
      {"state" => value == true ? "required" : value == false ? "not_required" : "unknown",
       "suggested_skill" => value == true ? "maintenance.reboot" : nil,
       "reason" => device.dig("reboot", "reason"), "automatic_execution" => false}
    end

    def blocked(reason)
      {"ok" => false, "lifecycle_state" => "blocked_for_human_review", "reason" => reason, "mutation" => "none"}
    end
  end
end
