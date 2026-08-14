# frozen_string_literal: true

require "etc"
require "time"

module SoulCore
  class HostStewardshipService
    def initialize(host_source:, security_source:, backup_source:, capability_registry:, file_steward:, clock: -> { Time.now.utc })
      @host_source = host_source
      @security_source = security_source
      @backup_source = backup_source
      @capability_registry = capability_registry
      @file_steward = file_steward
      @clock = clock
    end

    def snapshot
      host = safely("host") { @host_source.call }
      security = safely("security") { unwrap(@security_source.call) }
      backup = safely("backup") { unwrap(@backup_source.call) }
      capabilities = unwrap(@capability_registry.snapshot(file_steward_configured: @file_steward.configured?))
      signals = interpret(host: host, security: security, backup: backup)

      complete({
        "schema_version" => "soul.host-stewardship.presence.v1",
        "state" => overall_state(signals),
        "signals" => signals,
        "host" => host,
        "security" => security,
        "backup_automation" => backup,
        "capabilities" => capabilities,
        "sources" => {
          "host" => source_record(host, host["collected_at"]),
          "security" => source_record(security, security["collected_at"] || security["last_successful_at"]),
          "backup_automation" => source_record(backup, backup["checked_at"] || backup["generated_at"])
        },
        "automatic_refresh" => false,
        "background_polling" => false
      })
    rescue StandardError => error
      failed("Host Presence failed safely: #{error.class}")
    end

    private

    def safely(label)
      yield
    rescue StandardError => error
      { "available" => false, "source" => label, "reason" => "#{label} evidence unavailable: #{error.class}" }
    end

    def unwrap(result)
      return result.fetch("data", {}) if result.is_a?(Hash) && result.key?("data")
      result.is_a?(Hash) ? result : {}
    end

    def interpret(host:, security:, backup:)
      records = []
      memory = host.dig("collected", "memory") || {}
      memory_percent = memory["used_percent"].to_f
      records << signal("memory", threshold_state(memory_percent, attention: 80, critical: 92), "#{memory_percent.round(1)}% used", host["collected_at"]) if memory_percent.positive?

      load = host.dig("collected", "load", "one_minute")
      if load
        processors = [Etc.nprocessors, 1].max
        ratio = load.to_f / processors
        records << signal("cpu_load", threshold_state(ratio, attention: 0.8, critical: 1.25), "#{load} across #{processors} logical CPUs", host["collected_at"])
      end

      filesystems = Array(host.dig("collected", "filesystems"))
      highest = filesystems.map { |entry| entry["used_percent"].to_f }.max
      records << signal("storage", threshold_state(highest, attention: 80, critical: 92), "highest mounted filesystem use #{highest.round(1)}%", host["collected_at"]) if highest

      failed_units = host.dig("collected", "systemd", "failed_unit_count")
      unless failed_units.nil?
        records << signal("systemd", failed_units.to_i.zero? ? "healthy" : "attention", "#{failed_units.to_i} failed units", host["collected_at"])
      end

      core = host["core"] || {}
      core_state = core["runtime_status"].to_s == "complete" ? "healthy" : (core["runtime_status"].to_s.empty? ? "unavailable" : "attention")
      records << signal("core", core_state, core["label"] || core["mode"] || "Core evidence unavailable", host["collected_at"])

      security_state = security["available"] == true ? normalize_state(security["state"]) : "unavailable"
      records << signal("security", security_state, security["reason"] || security["state"] || "Wazuh snapshot unavailable", security["collected_at"] || security["last_successful_at"])

      backup_ready = backup["ready"] == true || backup["installed"] == true || backup["timer_enabled"] == true
      backup_state = backup.empty? ? "unavailable" : (backup_ready ? "healthy" : "attention")
      records << signal("backup_automation", backup_state, backup_summary(backup), backup["checked_at"] || backup["generated_at"])
      records
    end

    def backup_summary(backup)
      return "Backup automation evidence unavailable" if backup.empty?
      mode = backup["mode"] || backup["state"] || "configured"
      credential = backup["credential_ready"]
      [mode, credential.nil? ? nil : "credential #{credential ? 'ready' : 'not ready'}"].compact.join(" · ")
    end

    def threshold_state(value, attention:, critical:)
      return "critical" if value >= critical
      return "attention" if value >= attention
      "healthy"
    end

    def normalize_state(value)
      text = value.to_s.downcase
      return "critical" if %w[critical failed offline].include?(text)
      return "attention" if %w[attention degraded warning].include?(text)
      return "healthy" if %w[healthy ready online].include?(text)
      "unavailable"
    end

    def signal(id, state, summary, observed_at)
      { "id" => id, "state" => state, "summary" => summary.to_s, "observed_at" => observed_at }.compact
    end

    def overall_state(signals)
      states = signals.map { |record| record["state"] }
      return "critical" if states.include?("critical")
      return "attention" if states.include?("attention")
      return "healthy" if states.include?("healthy")
      "unavailable"
    end

    def source_record(data, observed_at)
      {
        "available" => data["available"] != false && !data.empty?,
        "observed_at" => observed_at,
        "reason" => data["reason"]
      }.compact
    end

    def complete(data)
      { "ok" => true, "lifecycle_state" => "complete", "message" => "Host Presence collected.", "data" => data, "mutation" => "none", "retrieved_at" => @clock.call.iso8601(6) }
    end

    def failed(message)
      { "ok" => false, "lifecycle_state" => "failed", "message" => message, "data" => {}, "mutation" => "none", "retrieved_at" => @clock.call.iso8601(6) }
    end
  end
end
