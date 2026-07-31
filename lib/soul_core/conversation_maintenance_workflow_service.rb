# frozen_string_literal: true

require "securerandom"
require "time"
require_relative "conversation_capability_action_store"

module SoulCore
  class ConversationMaintenanceWorkflowService
    CAPABILITY_ID = "maintenance.device"
    CONFIRMATION_TTL_SECONDS = 10 * 60
    EXPLICIT_MAINTENANCE = /
      (?:
        \b(?:run|perform|start|begin|do)\s+(?:package\s+|system\s+)?maintenance\s+(?:on|for)\b |
        \bmaintain\s+(?:the\s+)?(?:device|host|server|vm|container)?\s*
      )
    /ix
    EXPLICIT_REBOOT = /\b(?:reboot|restart)\s+(?:the\s+)?(?:device|host|server|vm|container)?\s*/i
    AFFIRMATIVE = /\A\s*(?:yes|yes please|correct|confirmed|confirm|proceed|go ahead|do it)\s*[.!]*\s*\z/i
    NEGATIVE = /\A\s*(?:no|no thanks|cancel|stop|never mind|nevermind)\s*[.!]*\s*\z/i

    def initialize(
      root: Dir.pwd,
      fleet_status_service:,
      device_control_service:,
      store: nil,
      clock: -> { Time.now.utc },
      id_generator: -> { SecureRandom.hex(8) }
    )
      @fleet_status_service = fleet_status_service
      @device_control_service = device_control_service
      @clock = clock
      @id_generator = id_generator
      @store = store || ConversationCapabilityActionStore.new(root: root, clock: clock)
    end

    def candidate_message?(chat_id:, message:)
      text = message.to_s.strip
      return true if explicit_request?(text)

      pending = @store.active(chat_id)
      pending && (text.match?(AFFIRMATIVE) || text.match?(NEGATIVE))
    end

    def plan(chat_id:, message:, progress: nil)
      text = message.to_s.strip
      pending = @store.active(chat_id)

      if pending && text.match?(NEGATIVE)
        @store.cancel(chat_id)
        return result(
          "Canceled. No maintenance or reboot request was sent.",
          "maintenance_canceled",
          lifecycle: "canceled",
          action: pending
        )
      end

      return confirm_pending(pending, progress) if pending && text.match?(AFFIRMATIVE)
      return protected_reboot(chat_id, text) if text.match?(EXPLICIT_REBOOT)
      return nil unless text.match?(EXPLICIT_MAINTENANCE)

      prepare_maintenance(chat_id, text)
    rescue ArgumentError => error
      result(
        "The maintenance request is waiting for clarification: #{error.message}.",
        "maintenance_awaiting_input",
        lifecycle: "awaiting_input"
      )
    rescue StandardError => error
      result(
        "The maintenance workflow stopped safely before execution: #{error.class}.",
        "maintenance_failed",
        lifecycle: "failed"
      )
    end

    private

    def explicit_request?(text)
      text.match?(EXPLICIT_MAINTENANCE) || text.match?(EXPLICIT_REBOOT)
    end

    def prepare_maintenance(chat_id, text)
      fleet = fleet_snapshot
      target = resolve_target(fleet, text)
      raise ArgumentError, available_target_prompt(fleet) unless target
      if target.fetch("protected", false)
        return protected_handoff(
          "Maintenance for #{target.fetch('label')} uses its protected workstation workflow.",
          target
        )
      end

      preview = @device_control_service.preview(device_id: target.fetch("control_target_id"), action: "maintenance")
      unless preview["ok"] && preview["lifecycle_state"] == "complete"
        return result(
          "I could not prepare maintenance for #{target.fetch('label')}: #{preview['reason']}. No command was run.",
          "maintenance_blocked",
          lifecycle: preview["lifecycle_state"] || "blocked_for_human_review"
        )
      end

      plan = preview.dig("data", "plan")
      now = @clock.call
      action = @store.write(
        "schema_version" => ConversationCapabilityActionStore::SCHEMA,
        "action_id" => "capability_#{@id_generator.call}",
        "chat_id" => chat_id,
        "capability_id" => CAPABILITY_ID,
        "lifecycle_state" => "awaiting_input",
        "stage" => "confirmation",
        "authority_class" => "routine_mutation",
        "target" => target,
        "operation" => "maintenance",
        "confirmation" => plan.fetch("confirmation"),
        "expected_digest" => plan.fetch("expected_digest"),
        "created_at" => now.iso8601,
        "expires_at" => (now + CONFIRMATION_TTL_SECONDS).iso8601
      )

      result(
        [
          "I found #{target.fetch('label')} at #{target.fetch('address')}.",
          "Run its fixed #{plan.fetch('maintenance_adapter')} maintenance workflow, without rebooting—correct?",
          "This can change installed packages. Reply yes to authorize this exact reviewed plan, or no to cancel. The confirmation expires in 10 minutes."
        ].join("\n"),
        "maintenance_confirmation_required",
        lifecycle: "awaiting_input",
        action: public_action(action)
      )
    end

    def confirm_pending(action, progress)
      return expired(action) if expired?(action)
      return protected_handoff("This action requires an Operator-controlled interface.", action.fetch("target")) unless action["authority_class"] == "routine_mutation"

      progress&.call({"state" => "maintaining", "summary" => "Running the fixed maintenance workflow on #{action.dig('target', 'label')}."})
      outcome = @device_control_service.execute(
        device_id: action.dig("target", "control_target_id"),
        action: "maintenance",
        confirmation: action.fetch("confirmation"),
        expected_digest: action.fetch("expected_digest"),
        progress: lambda do |event|
          progress&.call({
            "state" => event["stage"] || "maintaining",
            "summary" => event["message"] || "Device maintenance is active."
          })
        end
      )
      lifecycle = outcome["lifecycle_state"] || "failed"
      updated = @store.write(action.merge(
        "lifecycle_state" => lifecycle,
        "stage" => lifecycle == "complete" ? "complete" : "failed",
        "confirmation" => nil,
        "expected_digest" => nil
      ))
      render_outcome(outcome, updated)
    end

    def protected_reboot(chat_id, text)
      fleet = fleet_snapshot
      target = resolve_target(fleet, text)
      raise ArgumentError, available_target_prompt(fleet) unless target

      @store.cancel(chat_id) if @store.active(chat_id)
      protected_handoff(
        "Rebooting #{target.fetch('label')} is an availability-impacting protected action.",
        target
      )
    end

    def protected_handoff(prefix, target)
      result(
        [
          prefix,
          "I can inspect and prepare the target, but I will not treat a chat or voice reply as execution authority.",
          "Use Administration → Guided Maintenance, a reviewed terminal command, or Noctalia for the final Operator-controlled action.",
          "No action was executed."
        ].join("\n"),
        "maintenance_protected_handoff",
        lifecycle: "blocked_for_human_review",
        action: {
          "capability_id" => CAPABILITY_ID,
          "authority_class" => "protected_action",
          "target" => target,
          "dashboard_anchor" => "#maintenance-panel"
        }
      )
    end

    def render_outcome(outcome, action)
      data = outcome["data"] || {}
      receipt = data["receipt"] || {}
      target = action.fetch("target")
      fleet_device = Array(data.dig("fleet", "devices")).find do |device|
        device["id"] == target["fleet_device_id"] ||
          device.dig("facts", "control_target_id") == target["control_target_id"]
      end
      lines = [
        outcome["reason"].to_s.empty? ? receipt["summary"] : outcome["reason"],
        "Target: #{target.fetch('label')} · #{target.fetch('address')}",
        "Lifecycle: #{outcome['lifecycle_state']}",
        "Receipt: #{receipt['receipt_id'] || 'unavailable'}"
      ]
      if fleet_device
        lines << "Current status: #{fleet_device['status']}"
        lines << "Updates remaining: #{fleet_device.dig('updates', 'total')}" unless fleet_device.dig("updates", "total").nil?
        lines << "Reboot required: #{fleet_device.dig('reboot', 'required') == true ? 'yes' : 'no'}"
      end
      evidence = Array(receipt["evidence"])
      failed = evidence.count { |entry| entry["status"] != "ok" }
      lines << "Issues: #{failed.zero? ? 'none reported by the fixed workflow' : "#{failed} fixed step(s) require review"}"
      result(
        lines.join("\n"),
        outcome["lifecycle_state"] == "complete" ? "maintenance_complete" : "maintenance_failed",
        lifecycle: outcome["lifecycle_state"] || "failed",
        action: public_action(action).merge("receipt_id" => receipt["receipt_id"])
      )
    end

    def expired(action)
      @store.write(action.merge("lifecycle_state" => "canceled", "stage" => "expired", "confirmation" => nil, "expected_digest" => nil))
      result(
        "That maintenance confirmation expired. No command was run; ask me to prepare a fresh plan.",
        "maintenance_expired",
        lifecycle: "canceled",
        action: public_action(action)
      )
    end

    def expired?(action)
      Time.iso8601(action.fetch("expires_at")) <= @clock.call
    rescue ArgumentError
      true
    end

    def fleet_snapshot
      snapshot = @fleet_status_service.snapshot
      raise ArgumentError, "fleet evidence is unavailable" unless snapshot["ok"] && snapshot["lifecycle_state"] == "complete"

      snapshot.dig("data", "devices") || []
    end

    def resolve_target(devices, text)
      candidates = devices.filter_map { |device| target_record(device) }
      matches = candidates.select do |target|
        [target["label"], target["address"], target["control_target_id"]].compact.any? do |value|
          text.match?(/(?:\A|[^a-zA-Z0-9])#{Regexp.escape(value.to_s)}(?:\z|[^a-zA-Z0-9])/i)
        end
      end
      raise ArgumentError, "the target is ambiguous; name one exact device" if matches.length > 1

      matches.first
    end

    def target_record(device)
      control_target_id = device.dig("facts", "control_target_id").to_s
      control_target_id = builtin_control_target(device) if control_target_id.empty?
      return nil if control_target_id.empty? && device["id"] != "workstation"

      {
        "fleet_device_id" => device.fetch("id"),
        "control_target_id" => control_target_id.empty? ? "workstation" : control_target_id,
        "label" => device.fetch("label"),
        "address" => device.fetch("address"),
        "platform" => device["os"],
        "protected" => device["id"] == "workstation" || control_target_id == "workstation",
        "control" => device["control"]
      }
    end

    def builtin_control_target(device)
      case device["id"].to_s
      when "forge", "proxmox" then "forge"
      when "pihole" then "pihole"
      else ""
      end
    end

    def available_target_prompt(devices)
      labels = devices.filter_map { |device| target_record(device) }
        .select { |target| target["control"] == "maintenance" || target["protected"] }
        .map { |target| target["label"] }
        .uniq
        .first(8)
      return "name the exact device" if labels.empty?

      "name one exact device: #{labels.join(', ')}"
    end

    def public_action(action)
      action.slice("action_id", "capability_id", "lifecycle_state", "stage", "authority_class", "target", "operation", "created_at", "expires_at")
    end

    def result(content, mode, lifecycle:, action: nil)
      metadata = {
        "capability_id" => CAPABILITY_ID,
        "lifecycle_state" => lifecycle,
        "authority_source" => "authenticated_operator_message",
        "model_authorization" => false
      }
      metadata["action"] = action if action
      {"content" => content, "mode" => mode, "metadata" => metadata}
    end
  end
end
