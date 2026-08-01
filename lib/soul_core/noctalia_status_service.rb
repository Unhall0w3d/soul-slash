# frozen_string_literal: true

require "time"

require "soul_core/configuration_resolver"
require "soul_core/core_orchestration_service"
require "soul_core/maintenance_fleet_status_service"
require "soul_core/noctalia_device_registry"
require "soul_core/voice_presence_launch_service"

module SoulCore
  class NoctaliaStatusService
    SCHEMA_VERSION = "soul.noctalia.status.v2"
    MAX_VERSION_BYTES = 128
    MAX_TEXT_BYTES = 240
    SSH_CHANNELS = %w[ssh ssh_inventory].freeze

    def initialize(
      root: Dir.pwd,
      process_env: ENV,
      clock: -> { Time.now.utc },
      core_service: nil,
      fleet_service: nil,
      voice_presence_service: nil,
      device_registry: nil
    )
      @root = File.expand_path(root)
      @process_env = process_env.to_h
      @clock = clock
      @core_service = core_service
      @fleet_service = fleet_service || MaintenanceFleetStatusService.new(root: @root, process_env: @process_env)
      @voice_presence_service = voice_presence_service || VoicePresenceLaunchService.new(root: @root, process_env: @process_env)
      @device_registry = device_registry || NoctaliaDeviceRegistry.new(root: @root)
    end

    def status
      core = project_core(core_service.status)
      voice = project_voice(@voice_presence_service.status)
      fleet = project_fleet(@fleet_service.snapshot)
      available = core.fetch("available") && fleet.fetch("available")

      {
        "schema_version" => SCHEMA_VERSION,
        "collected_at" => @clock.call.utc.iso8601,
        "ok" => available,
        "soul" => {"version" => version, "health" => overall_health(core:, fleet:)},
        "core" => core,
        "voice_presence" => voice,
        "fleet" => fleet
      }
    rescue StandardError => error
      {
        "schema_version" => SCHEMA_VERSION,
        "collected_at" => @clock.call.utc.iso8601,
        "ok" => false,
        "soul" => {"version" => safe_version, "health" => "unavailable"},
        "core" => {"available" => false, "choices" => []},
        "voice_presence" => {"available" => false, "running" => false},
        "fleet" => {"available" => false, "devices" => [], "device_count" => 0, "healthy_count" => 0},
        "error" => error.class.name
      }
    end

    private

    def core_service
      return @core_service if @core_service

      resolver = ConfigurationResolver.new(root: @root, process_env: @process_env)
      report = resolver.resolve
      raise "Soul configuration is unavailable" unless report.fetch("ok")

      @core_service = CoreOrchestrationService.new(root: @root, env: resolver.effective_environment)
    end

    def project_core(envelope)
      data = envelope.fetch("data", {})
      {
        "available" => envelope.fetch("ok", false),
        "id" => safe_text(data["active_core_id"]),
        "label" => safe_text(data["active_core_label"]),
        "mode" => safe_text(data["core_mode"] || "unavailable"),
        "runtime_status" => safe_text(envelope.fetch("lifecycle_state", "unknown")),
        "reason" => safe_text(envelope["reason"] || envelope["message"]),
        "choices" => Array(data["cores"]).first(8).filter_map { |core| project_core_choice(core) }
      }.reject { |_key, value| value == "" }
    end

    def project_core_choice(core)
      return nil unless core.is_a?(Hash)

      id = safe_text(core["id"], 40)
      return nil unless id.match?(CoreOrchestrationService::CORE_ID)

      {
        "id" => id,
        "label" => safe_text(core["label"], 80),
        "purpose" => safe_text(core["purpose"]),
        "active" => core["active"] == true,
        "can_activate" => core["can_activate"] == true
      }
    end

    def project_voice(envelope)
      data = envelope.fetch("data", {})
      {
        "available" => envelope.fetch("ok", false),
        "running" => data.fetch("running", false) == true,
        "state" => safe_text(data["presence_state"]),
        "checked_at" => safe_text(data["checked_at"]),
        "message" => safe_text(envelope["message"])
      }.reject { |_key, value| value == "" }
    end

    def project_fleet(envelope)
      data = envelope.fetch("data", {})
      devices = Array(data["devices"]).first(128).filter_map { |device| project_device(device) }
      {
        "available" => envelope.fetch("ok", false),
        "source_collected_at" => safe_text(data["collected_at"]),
        "device_count" => devices.length,
        "healthy_count" => devices.count { |device| device["health"] == "healthy" },
        "devices" => devices
      }.reject { |_key, value| value == "" }
    end

    def project_device(device)
      return nil unless device.is_a?(Hash)

      facts = device["facts"].is_a?(Hash) ? device["facts"] : {}
      return nil unless SSH_CHANNELS.include?(facts["management_channel"])

      id = safe_text(device["id"], 128)
      return nil unless id.match?(NoctaliaDeviceRegistry::DEVICE_ID_PATTERN)

      reachable = device["reachable"] == true
      health = device_health(device, reachable)
      {
        "id" => id,
        "display_name" => safe_text(device["label"].to_s.empty? ? id : device["label"]),
        "subtitle" => safe_text(device["role"].to_s.empty? ? "SSH-integrated device" : device["role"]),
        "health" => health,
        "reachable" => reachable,
        "summary_rows" => compact_rows([
          row("Hostname", facts["hostname"]),
          row("Address", device["address"])
        ]),
        "detail_rows" => detail_rows(device, facts),
        "actions" => device_actions(id)
      }
    end

    def detail_rows(device, facts)
      compact_rows([
        row("Role", device["role"]),
        row("Platform", device["os"]),
        row("Version", device["version"]),
        row("Updates", format_updates(device["updates"])),
        row("Kernel", format_kernel(device["kernel"])),
        row("Reboot", format_reboot(device["reboot"])),
        row("Services", format_services(device["services"], facts)),
        row("Checked", device["observed_at"])
      ])
    end

    def device_actions(id)
      return [] unless @device_registry.connectable?(id)

      [{"id" => "connect", "label" => "Connect", "kind" => "terminal", "enabled" => true}]
    end

    def row(label, value)
      {"label" => safe_text(label, 48), "value" => safe_text(value)}
    end

    def compact_rows(rows)
      rows.reject { |item| item["value"].empty? }
    end

    def format_updates(value)
      updates = value.is_a?(Hash) ? value : {}
      channels = Array(updates["channels"]).first(12).filter_map do |channel|
        next unless channel.is_a?(Hash)

        label = safe_text(channel["label"] || channel["manager"] || "Packages", 48)
        channel["status"] == "complete" ? "#{label} #{channel["count"].to_i}" : "#{label} unavailable"
      end
      channels << "#{updates["total"].to_i} available" if channels.empty?
      freshness = safe_text(updates["freshness"]).tr("_", " ")
      channels << freshness unless freshness.empty?
      safe_text(channels.join(" · "))
    end

    def format_kernel(value)
      kernel = value.is_a?(Hash) ? value : {}
      running = safe_text(kernel["running"])
      return "" if running.empty?
      return "#{running} · current" unless kernel["update_required"] == true

      "#{running} → #{safe_text(kernel["available"].to_s.empty? ? "newer available" : kernel["available"])}"
    end

    def format_reboot(value)
      reboot = value.is_a?(Hash) ? value : {}
      return "not indicated" unless reboot["required"] == true

      safe_text(reboot["reason"].to_s.empty? ? "required" : reboot["reason"])
    end

    def format_services(value, facts)
      services = Array(value).first(16).filter_map do |service|
        next unless service.is_a?(Hash)

        "#{safe_text(service["label"] || service["id"] || "Service", 48)} #{safe_text(service["state"], 48)}"
      end
      container = facts["pihole_container"]
      if container.is_a?(Hash)
        services << "LXC #{safe_text(container["id"], 24)} #{safe_text(container["status"], 48)}"
      end
      Array(facts["guests"]).first(16).each do |guest|
        next unless guest.is_a?(Hash)

        services << "#{safe_text(guest["type"], 24).upcase} #{safe_text(guest["id"], 24)} #{safe_text(guest["status"], 48)}"
      end
      safe_text(services.empty? ? "none reported" : services.join(" · "))
    end

    def device_health(device, reachable)
      status = safe_text(device["status"], 48).downcase
      return "unavailable" if status.empty?
      return "unhealthy" unless reachable
      return "unhealthy" if %w[offline failed unavailable error].include?(status)
      return "healthy" if status == "healthy"

      "degraded"
    end

    def overall_health(core:, fleet:)
      return "unavailable" unless core.fetch("available") && fleet.fetch("available")
      return "degraded" if fleet.fetch("devices").any? { |device| device["health"] != "healthy" }

      "healthy"
    end

    def version
      path = File.join(@root, "VERSION")
      raise "Soul version path is unsafe" if File.symlink?(path)

      stat = File.stat(path)
      raise "Soul version is not a bounded regular file" unless stat.file? && stat.size.between?(1, MAX_VERSION_BYTES)

      value = File.binread(path, MAX_VERSION_BYTES).strip
      raise "Soul version is empty" if value.empty?

      safe_text(value, MAX_VERSION_BYTES)
    end

    def safe_version
      version
    rescue StandardError
      "unknown"
    end

    def safe_text(value, bytes = MAX_TEXT_BYTES)
      value.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
        .gsub(/[[:cntrl:]]+/, " ").strip.byteslice(0, bytes).to_s
    end
  end
end
