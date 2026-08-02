#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"

ROOT = File.expand_path("..", __dir__)
$LOAD_PATH.unshift(File.join(ROOT, "lib"))

require "soul_core/noctalia_device_registry"
require "soul_core/noctalia_core_control_service"
require "soul_core/noctalia_status_service"
require "soul_core/configuration_schema"

EnvelopeStub = Struct.new(:value) { def status = value }
FleetStub = Struct.new(:value) { def snapshot = value }

checks = 0
assert = lambda do |condition, message|
  raise message unless condition
  checks += 1
end

assert.call(
  SoulCore::ConfigurationSchema.definitions.length <= SoulCore::ConfigurationSchema::MAX_SETTINGS,
  "typed configuration growth exceeds the Noctalia companion's runtime schema bound"
)

Dir.mktmpdir("soul-noctalia-v2-") do |root|
  File.write(File.join(root, "VERSION"), "0.1.0-dev\n")
  fleet_dir = File.join(root, "Soul", "private", "host_maintenance")
  action_dir = File.join(root, "Soul", "private", "noctalia")
  FileUtils.mkdir_p(fleet_dir)
  FileUtils.mkdir_p(action_dir)
  File.write(File.join(fleet_dir, "discovered_devices.json"), JSON.generate({
    "schema_version" => "soul.maintenance.fleet_registry.v1",
    "devices" => [
      {"id" => "node_beta", "connection_mode" => "ssh", "ssh_alias" => "node-beta-automation"},
      {"id" => "speaker", "connection_mode" => "status_only", "ssh_alias" => ""}
    ]
  }))
  File.write(File.join(action_dir, "device_actions.json"), JSON.generate({
    "schema_version" => "soul.noctalia.device_actions.v1",
    "devices" => [
      {"id" => "node_alpha", "interactive_ssh_alias" => "node-alpha-interactive"},
      {"id" => "node_beta", "interactive_ssh_alias" => "node-beta-interactive"}
    ]
  }))

  core_data = {
    "active_core_id" => "daily", "active_core_label" => "Soul Core", "core_mode" => "daily",
    "cores" => [
      {"id" => "daily", "label" => "Soul Core", "purpose" => "Main chat", "active" => true, "can_activate" => false},
      {"id" => "amd-free", "label" => "Soul-Lite Core", "purpose" => "Release AMD", "active" => false, "can_activate" => true},
      {"id" => "music", "label" => "Creative Core", "purpose" => "Creative work", "active" => false, "can_activate" => true},
      {"id" => "free", "label" => "Free Core", "purpose" => "No model", "active" => false, "can_activate" => true},
      {"id" => "dev", "label" => "Dev Core", "purpose" => "Development", "active" => false, "can_activate" => true}
    ]
  }
  core = EnvelopeStub.new({
    "ok" => true, "lifecycle_state" => "complete",
    "data" => core_data
  })
  voice = EnvelopeStub.new({
    "ok" => true, "message" => "Voice Presence is closed",
    "data" => {"running" => false, "checked_at" => "2026-07-30T12:00:00Z"}
  })
  fleet = FleetStub.new({
    "ok" => true,
    "data" => {
      "collected_at" => "2026-07-30T11:59:00Z",
      "devices" => [
        {
          "id" => "node_alpha", "label" => "Node Alpha", "address" => "192.0.2.6",
          "status" => "healthy", "reachable" => true, "role" => "Hypervisor",
          "os" => "Proxmox VE", "version" => "9.2.5", "observed_at" => "2026-07-30T11:59:00Z",
          "updates" => {"total" => 0, "freshness" => "fresh", "channels" => [
            {"label" => "APT", "status" => "complete", "count" => 0}
          ]},
          "kernel" => {"running" => "7.0.14", "available" => "7.0.14", "update_required" => false},
          "reboot" => {"required" => false},
          "services" => [{"id" => "ssh", "label" => "SSH", "state" => "active"}],
          "facts" => {"hostname" => "node-alpha", "management_channel" => "ssh"}
        },
        {
          "id" => "node_beta", "label" => "Node Beta", "address" => "192.0.2.7",
          "status" => "healthy", "reachable" => true,
          "facts" => {"hostname" => "node-beta", "management_channel" => "ssh_inventory"}
        },
        {
          "id" => "speaker", "label" => "Speaker", "address" => "192.0.2.8",
          "status" => "reachable", "reachable" => true,
          "facts" => {"hostname" => "speaker", "management_channel" => "icmp_status"}
        }
      ]
    }
  })

  registry = SoulCore::NoctaliaDeviceRegistry.new(root:)
  result = SoulCore::NoctaliaStatusService.new(
    root:, clock: -> { Time.utc(2026, 7, 30, 12, 0, 0) },
    core_service: core, fleet_service: fleet, voice_presence_service: voice,
    device_registry: registry
  ).status

  devices = result.dig("fleet", "devices")
  serialized = JSON.generate(result)
  assert.call(result["schema_version"] == "soul.noctalia.status.v2", "schema differs")
  assert.call(result.dig("core", "label") == "Soul Core", "Core projection differs")
  assert.call(result.dig("core", "choices").map { |choice| choice["id"] } == %w[daily amd-free music free dev], "Core choices differ")
  assert.call(result.dig("core", "choices").find { |choice| choice["id"] == "free" } == {"id" => "free", "label" => "Free Core", "purpose" => "No model", "active" => false, "can_activate" => true}, "Free Core choice differs")
  assert.call(devices.map { |device| device["id"] } == %w[node_alpha node_beta], "SSH filtering differs")
  assert.call(devices.first["summary_rows"].any? { |row| row == {"label" => "Hostname", "value" => "node-alpha"} }, "generic summary is missing")
  assert.call(devices.first["detail_rows"].any? { |row| row["label"] == "Updates" && row["value"].include?("APT 0") }, "generic details are missing")
  assert.call(devices.all? { |device| device["actions"] == [{"id" => "connect", "label" => "Connect", "kind" => "terminal", "enabled" => true}] }, "connect action differs")
  assert.call(!serialized.include?("node-alpha-interactive") && !serialized.include?("node-beta-interactive"), "private SSH target leaked into status")
  assert.call(!serialized.include?("ssh_target"), "legacy target field leaked into status")
  assert.call(registry.ssh_argv("node_alpha") == ["/usr/bin/ssh", "node-alpha-interactive"], "private override was not resolved")
  assert.call(registry.ssh_argv("node_beta") == ["/usr/bin/ssh", "node-beta-interactive"], "enrolled override was not resolved")
  assert.call(!registry.connectable?("speaker"), "status-only device became connectable")
  assert.call(!registry.connectable?("../forge"), "unsafe device id was accepted")
  begin
    registry.ssh_argv("missing")
    raise "unknown device was accepted"
  rescue ArgumentError
    checks += 1
  end

  preview_data = {
    "action" => "switch",
    "source_core" => core_data["cores"][0],
    "target_core" => core_data["cores"][1],
    "target_profile" => {"id" => "nvidia-fallback"},
    "confirmation_phrase" => "SWITCH_MODEL_RUNTIME_TO_NVIDIA_FALLBACK",
    "expected_digest" => "a" * 64,
    "service_mutation_required" => true
  }
  control = Object.new
  control.define_singleton_method(:preview) do |core_id:|
    raise "unexpected Core" unless core_id == "amd-free"
    {"ok" => true, "lifecycle_state" => "complete", "data" => preview_data}
  end
  control.define_singleton_method(:execute) do |**attributes|
    raise "unexpected execution" unless attributes == {
      core_id: "amd-free", target_profile_id: "nvidia-fallback",
      confirmation: "SWITCH_MODEL_RUNTIME_TO_NVIDIA_FALLBACK", expected_digest: "a" * 64
    }
    {"ok" => true, "lifecycle_state" => "complete", "mutation" => "core_activated", "data" => {
      "active_core_id" => "amd-free", "active_core_label" => "Soul-Lite Core", "core_mode" => "amd-free"
    }}
  end
  control_service = SoulCore::NoctaliaCoreControlService.new(root:, core_service: control)
  control_preview = control_service.preview(core_id: "amd-free")
  assert.call(control_preview["schema_version"] == "soul.noctalia.core_control.v1" && control_preview.dig("data", "executable") == true, "Core preview projection differs")
  assert.call(control_preview.dig("data", "target_profile_id") == "nvidia-fallback" && control_preview.dig("data", "expected_digest") == "a" * 64, "Core gate was not preserved")
  assert.call(control_preview.dig("data", "service_mutation_required") == true, "runtime switch was not disclosed as service mutation")
  invalid = control_service.execute(core_id: "amd-free", target_profile_id: "nvidia-fallback", confirmation: "unsafe value; true", expected_digest: "a" * 64)
  assert.call(invalid["lifecycle_state"] == "awaiting_input", "unsafe confirmation was accepted")
  executed = control_service.execute(
    core_id: "amd-free", target_profile_id: control_preview.dig("data", "target_profile_id"),
    confirmation: control_preview.dig("data", "confirmation_phrase"), expected_digest: control_preview.dig("data", "expected_digest")
  )
  assert.call(executed["ok"] && executed.dig("data", "active_core_id") == "amd-free" && executed.dig("data", "mutation") == "core_activated", "Core execution projection differs")

  fleet.value["data"]["devices"][0]["reachable"] = false
  fleet.value["data"]["devices"][0]["status"] = "offline"
  degraded = SoulCore::NoctaliaStatusService.new(
    root:, clock: -> { Time.utc(2026, 7, 30, 12, 1, 0) },
    core_service: core, fleet_service: fleet, voice_presence_service: voice,
    device_registry: registry
  ).status
  assert.call(degraded.dig("soul", "health") == "degraded", "offline device did not degrade health")

  failing_core = Object.new
  failing_core.define_singleton_method(:status) { raise "fixture unavailable" }
  unavailable = SoulCore::NoctaliaStatusService.new(
    root:, core_service: failing_core, fleet_service: fleet, voice_presence_service: voice,
    device_registry: registry
  ).status
  assert.call(unavailable.dig("core", "available") == false && unavailable.dig("core", "choices") == [], "unavailable Core projection violates the status contract")
end

puts JSON.pretty_generate(
  "lifecycle_state" => "complete",
  "deterministic_tests" => checks,
  "schema_version" => SoulCore::NoctaliaStatusService::SCHEMA_VERSION,
  "resolved_targets_exposed" => false
)
