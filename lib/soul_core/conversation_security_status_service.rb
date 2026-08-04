# frozen_string_literal: true

require "time"

module SoulCore
  class ConversationSecurityStatusService
    SCHEMA_VERSION = "soul.conversation.security-status.v1"

    def initialize(wazuh_status_service:, alert_evidence_service:, posture_service: nil, clock: -> { Time.now.utc })
      @wazuh_status_service = wazuh_status_service
      @alert_evidence_service = alert_evidence_service
      @posture_service = posture_service
      @clock = clock
    end

    def report
      health = data_from(@wazuh_status_service.collect)
      alerts = data_from(@alert_evidence_service.collect)
      posture = @posture_service ? data_from(@posture_service.status) : unavailable_posture
      report = normalize(health, alerts, posture)

      {
        "ok" => true,
        "lifecycle_state" => "complete",
        "content" => render(report),
        "report" => report,
        "mutation" => "private_status_caches_only"
      }
    rescue StandardError => error
      report = unavailable_report("Security status unavailable: #{safe_reason(error)}")
      {
        "ok" => true,
        "lifecycle_state" => "complete",
        "content" => render(report),
        "report" => report,
        "mutation" => "none"
      }
    end

    private

    def data_from(outcome)
      data = outcome.is_a?(Hash) ? outcome["data"] : nil
      raise "security source returned no data" unless data.is_a?(Hash)

      data
    end

    def normalize(health, alerts, posture)
      health_available = health["available"] == true
      alerts_available = alerts["available"] == true
      normalized_health = normalize_health(health)
      normalized_alerts = normalize_alerts(alerts)
      normalized_posture = normalize_posture(posture)
      state = overall_state(normalized_health, normalized_alerts, normalized_posture)
      {
        "schema_version" => SCHEMA_VERSION,
        "available" => health_available || alerts_available,
        "state" => state,
        "checked_at" => @clock.call.utc.iso8601,
        "wazuh" => normalized_health,
        "alerts" => normalized_alerts,
        "posture" => normalized_posture,
        "clamav" => {
          "collected" => false,
          "reason" => "Current ClamAV signatures and latest scan receipts are not centralized by the accepted A3 lane."
        },
        "read_only" => true,
        "remote_mutation" => false,
        "raw_events_returned" => false,
        "remediation_authority" => false
      }
    end

    def normalize_health(data)
      summary = hash(data["summary"])
      manager = hash(data["manager"])
      {
        "available" => data["available"] == true,
        "state" => bounded(data["state"], 40),
        "collected_at" => bounded(data["collected_at"], 64),
        "last_successful_at" => bounded(data["last_successful_at"], 64),
        "reason" => bounded(data["reason"], 240),
        "manager" => {
          "state" => bounded(manager["state"], 40),
          "active_daemons" => integer(manager["active_daemons"]),
          "daemon_count" => integer(manager["daemon_count"])
        },
        "agents" => {
          "agent_count" => integer(summary["agent_count"]),
          "active" => integer(summary["active"]),
          "disconnected" => integer(summary["disconnected"]),
          "pending" => integer(summary["pending"]),
          "never_connected" => integer(summary["never_connected"]),
          "unknown" => integer(summary["unknown"])
        }
      }
    end

    def normalize_alerts(data)
      summary = hash(data["summary"])
      query = hash(data["query"])
      {
        "available" => data["available"] == true,
        "state" => bounded(data["state"], 40),
        "collected_at" => bounded(data["collected_at"], 64),
        "last_successful_at" => bounded(data["last_successful_at"], 64),
        "reason" => bounded(data["reason"], 240),
        "lookback_minutes" => integer(query["lookback_minutes"]),
        "minimum_level" => integer(query["minimum_level"]),
        "matching_alerts" => integer(query["matching_alerts"]),
        "returned_alerts" => integer(query["returned_alerts"]),
        "truncated" => query["truncated"] == true,
        "elevated" => integer(summary["elevated"]),
        "high" => integer(summary["high"]),
        "critical" => integer(summary["critical"]),
        "latest_at" => bounded(summary["latest_at"], 64)
      }
    end

    def normalize_posture(data)
      raw = hash(data["raw_wazuh_result"])
      review = hash(data["adapted_review"])
      summary = hash(data["summary"])
      posture_count = integer(summary["posture_count"])
      posture_count = 1 if posture_count.zero? && data["available"] == true && !raw.empty?
      {
        "available" => data["available"] == true,
        "state" => bounded(data["state"], 40),
        "loaded_at" => bounded(data["loaded_at"], 64),
        "reason" => bounded(data["reason"], 240),
        "posture_count" => posture_count,
        "raw_score" => posture_count == 1 ? integer(raw["score"]) : 0,
        "raw_passed" => integer(summary["raw_passed"] || raw["passed"]),
        "raw_failed" => integer(summary["raw_failed"] || raw["failed"]),
        "raw_not_applicable" => integer(summary["raw_not_applicable"] || raw["not_applicable"]),
        "genuine_remaining_decisions" => integer(summary["genuine_remaining_decision_count"] || review["genuine_remaining_decision_count"]),
        "raw_result_preserved" => data["raw_result_preserved"] == true
      }
    end

    def overall_state(health, alerts, posture)
      available = [health, alerts].count { |record| record["available"] == true }
      return "unavailable" if available.zero?
      return "partial" if available < 2
      return "attention" if health["state"] != "healthy" || alerts["state"] != "healthy"
      return "attention" if posture["available"] == true && posture["genuine_remaining_decisions"].to_i.positive?

      "healthy"
    end

    def render(report)
      lines = [headline(report.fetch("state"))]
      health = report.fetch("wazuh")
      alerts = report.fetch("alerts")
      posture = report.fetch("posture")

      if health["available"]
        manager = health.fetch("manager")
        agents = health.fetch("agents")
        lines << "Wazuh monitoring: #{health['state']}; manager #{manager['state']} with #{manager['active_daemons']}/#{manager['daemon_count']} required daemons; #{agents['active']}/#{agents['agent_count']} agents active."
      else
        lines << "Wazuh monitoring is unavailable#{reason_suffix(health['reason'])}."
      end

      if alerts["available"]
        scope = "#{duration_label(alerts['lookback_minutes'])}, level #{alerts['minimum_level']}+"
        lines << "Recent alerts (#{scope}): #{alerts['matching_alerts']} matched; the newest #{alerts['returned_alerts']} contain #{alerts['elevated']} elevated, #{alerts['high']} high, and #{alerts['critical']} critical#{alerts['truncated'] ? '; the result is truncated' : ''}."
      else
        lines << "Recent alert evidence is unavailable#{reason_suffix(alerts['reason'])}."
      end

      if posture["available"]
        if posture["posture_count"] == 1
          lines << "Adapted posture: raw Wazuh score #{posture['raw_score']}%, with #{posture['genuine_remaining_decisions']} genuine remaining decisions; the raw result remains unchanged."
        else
          lines << "Adapted posture: #{posture['posture_count']} endpoint reviews preserve their separate raw Wazuh results; #{posture['raw_failed']} raw failures are classified with #{posture['genuine_remaining_decisions']} genuine remaining decisions."
        end
      end

      lines << "ClamAV freshness and latest scan receipts were not collected by this status check."
      lines << "This was a read-only aggregate check. Raw events were not returned, and Wazuh remains the investigation console; no remediation was performed or authorized."
      lines.join("\n")
    end

    def headline(state)
      case state
      when "healthy" then "The current security projection is healthy within the checked Wazuh scope."
      when "attention" then "The current security projection needs attention within the checked Wazuh scope."
      when "partial" then "The security check completed with partial Wazuh evidence."
      else "The security projection is currently unavailable."
      end
    end

    def duration_label(minutes)
      return "#{minutes / 60}h" if minutes.positive? && (minutes % 60).zero?

      "#{minutes}m"
    end

    def reason_suffix(reason)
      text = bounded(reason, 180)
      text.empty? ? "" : ": #{text}"
    end

    def unavailable_report(reason)
      {
        "schema_version" => SCHEMA_VERSION,
        "available" => false,
        "state" => "unavailable",
        "checked_at" => @clock.call.utc.iso8601,
        "wazuh" => { "available" => false, "reason" => reason },
        "alerts" => { "available" => false, "reason" => reason },
        "posture" => unavailable_posture,
        "clamav" => { "collected" => false, "reason" => "not collected" },
        "read_only" => true,
        "remote_mutation" => false,
        "raw_events_returned" => false,
        "remediation_authority" => false
      }
    end

    def unavailable_posture
      { "available" => false, "state" => "unavailable", "reason" => "Adapted posture is not configured." }
    end

    def integer(value)
      value.to_i.clamp(0, 1_000_000)
    end

    def hash(value)
      value.is_a?(Hash) ? value : {}
    end

    def bounded(value, maximum)
      value.to_s.byteslice(0, maximum).to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "�")
    end

    def safe_reason(error)
      bounded(error.message.to_s.gsub(%r{/(?:home|run|etc)/[^\s]+}, "[private path]"), 240)
    end
  end
end
