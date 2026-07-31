#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require "time"

require_relative "../lib/soul_core/conversation_capability_action_store"
require_relative "../lib/soul_core/conversation_maintenance_workflow_service"

checks = {}
check = ->(name, value) { checks[name] = value == true }

class MaintenanceFleetFixture
  def snapshot
    {
      "ok" => true,
      "lifecycle_state" => "complete",
      "data" => {
        "devices" => [
          {
            "id" => "workstation", "label" => "Atelier", "address" => "local",
            "control" => "maintenance", "os" => "CachyOS", "facts" => {}
          },
          {
            "id" => "managed_crucible", "label" => "Crucible", "address" => "192.0.2.22",
            "control" => "maintenance", "os" => "Fedora",
            "facts" => {"control_target_id" => "crucible"}
          },
          {
            "id" => "forge", "label" => "Forge", "address" => "192.0.2.6",
            "control" => "maintenance", "os" => "Proxmox VE", "facts" => {}
          }
        ]
      }
    }
  end
end

class MaintenanceControlFixture
  attr_reader :executions

  def initialize
    @executions = []
  end

  def preview(device_id:, action:)
    digest = device_id == "crucible" ? "a" * 64 : "b" * 64
    {
      "ok" => true, "lifecycle_state" => "complete", "reason" => "preview ready",
      "data" => {
        "plan" => {
          "device_id" => device_id, "device_label" => device_id.capitalize,
          "address" => "192.0.2.22", "action" => action,
          "maintenance_adapter" => device_id == "crucible" ? "fedora_dnf5" : "proxmox_apt",
          "confirmation" => "MAINTAIN_#{device_id.upcase}",
          "expected_digest" => digest
        }
      }
    }
  end

  def execute(device_id:, action:, confirmation:, expected_digest:, progress:)
    @executions << {
      "device_id" => device_id, "action" => action,
      "confirmation" => confirmation, "expected_digest" => expected_digest
    }
    progress.call({"stage" => "maintaining", "message" => "Fixed maintenance step active."})
    {
      "ok" => true, "lifecycle_state" => "complete",
      "reason" => "Crucible maintenance completed.",
      "data" => {
        "receipt" => {
          "receipt_id" => "device_receipt_fixture",
          "summary" => "Crucible maintenance completed.",
          "evidence" => [{"adapter" => "maintenance.1", "status" => "ok"}]
        },
        "fleet" => {
          "devices" => [{
            "id" => "managed_crucible", "label" => "Crucible", "status" => "healthy",
            "facts" => {"control_target_id" => "crucible"},
            "updates" => {"total" => 0}, "reboot" => {"required" => false}
          }]
        }
      }
    }
  end
end

Dir.mktmpdir("soul-maintenance-conversation-") do |root|
  now = Time.utc(2026, 7, 30, 18, 0, 0)
  clock = -> { now }
  control = MaintenanceControlFixture.new
  service = SoulCore::ConversationMaintenanceWorkflowService.new(
    root: root,
    fleet_status_service: MaintenanceFleetFixture.new,
    device_control_service: control,
    clock: clock,
    id_generator: -> { "1" * 16 }
  )
  chat_id = "chat_maintenance_fixture"

  check.call("explicit exact maintenance request is a candidate",
             service.candidate_message?(chat_id: chat_id, message: "Run maintenance on Crucible"))
  check.call("ordinary maintenance discussion is not a candidate",
             !service.candidate_message?(chat_id: "chat_discussion", message: "I was reading about maintenance today"))
  check.call("status question is not mistaken for maintenance authority",
             !service.candidate_message?(chat_id: "chat_status", message: "Does Crucible need maintenance?"))

  prepared = service.plan(chat_id: chat_id, message: "Run maintenance on Crucible")
  check.call("exact target produces short-lived conversational confirmation",
             prepared["mode"] == "maintenance_confirmation_required" &&
               prepared["metadata"]["lifecycle_state"] == "awaiting_input" &&
               prepared["content"].include?("Crucible at 192.0.2.22") &&
               prepared["content"].include?("without rebooting") &&
               control.executions.empty?)

  progress = []
  completed = service.plan(chat_id: chat_id, message: "Yes", progress: ->(event) { progress << event })
  check.call("authenticated affirmative executes only the retained fixed plan",
             control.executions == [{
               "device_id" => "crucible", "action" => "maintenance",
               "confirmation" => "MAINTAIN_CRUCIBLE", "expected_digest" => "a" * 64
             }])
  check.call("terminal response reports receipt and refreshed state",
             completed["mode"] == "maintenance_complete" &&
               completed["content"].include?("device_receipt_fixture") &&
               completed["content"].include?("Updates remaining: 0") &&
               completed["content"].include?("Reboot required: no") &&
               completed["metadata"]["model_authorization"] == false &&
               progress.any? { |event| event["state"] == "maintaining" })

  canceled_chat = "chat_cancel_fixture"
  service.plan(chat_id: canceled_chat, message: "Maintain Forge")
  canceled = service.plan(chat_id: canceled_chat, message: "No")
  check.call("negative follow-up cancels without execution",
             canceled["mode"] == "maintenance_canceled" && control.executions.length == 1)

  protected = service.plan(chat_id: "chat_reboot_fixture", message: "Reboot Atelier")
  check.call("reboot remains an Operator-gesture protected action",
             protected["mode"] == "maintenance_protected_handoff" &&
               protected["metadata"]["lifecycle_state"] == "blocked_for_human_review" &&
               protected["content"].include?("will not treat a chat or voice reply as execution authority") &&
               control.executions.length == 1)

  local_maintenance = service.plan(chat_id: "chat_local_fixture", message: "Run maintenance on Atelier")
  check.call("workstation maintenance remains in its protected owning workflow",
             local_maintenance["mode"] == "maintenance_protected_handoff" &&
               local_maintenance["content"].include?("protected workstation workflow") &&
               control.executions.length == 1)

  expired_chat = "chat_expired_fixture"
  service.plan(chat_id: expired_chat, message: "Run maintenance on Crucible")
  now += SoulCore::ConversationMaintenanceWorkflowService::CONFIRMATION_TTL_SECONDS + 1
  expired = service.plan(chat_id: expired_chat, message: "Yes")
  check.call("expired confirmation executes nothing",
             expired["mode"] == "maintenance_expired" && control.executions.length == 1)
end

runtime_source = File.read(File.expand_path("../lib/soul_core/conversation_runtime.rb", __dir__))
facade_source = File.read(File.expand_path("../lib/soul_core/application_facade.rb", __dir__))
voice_bridge = File.read(File.expand_path("../scripts/soul-voice-presence-bridge", __dir__))
registry = File.read(File.expand_path("../Soul/skills/registry.yaml", __dir__))
skill = File.read(File.expand_path("../Soul/skills/maintenance/maintain-device/SKILL.md", __dir__))
check.call("ordinary chat and voice share the maintenance workflow injection",
           runtime_source.include?("maintenance_workflow_service") &&
             facade_source.include?("conversation_maintenance_workflow") &&
             voice_bridge.include?('request("chats.send"') &&
             registry.include?("maintenance.device:"))
check.call("skill metadata defines positive and negative trigger boundaries",
           skill.include?("explicitly asks to maintain") &&
             skill.include?("Do not trigger for casual maintenance discussion"))

failed = checks.reject { |_name, passed| passed }
puts "Conversation maintenance workflow A1 verification:"
checks.each { |name, passed| puts "- #{name}: #{passed ? 'ok' : 'missing'}" }
abort("#{failed.length} conversation maintenance workflow checks failed") unless failed.empty?
puts "Conversation maintenance workflow A1 verification passed."
