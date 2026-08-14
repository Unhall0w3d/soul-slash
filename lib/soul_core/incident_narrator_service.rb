# frozen_string_literal: true

require "time"

module SoulCore
  # Bounded, deterministic, and read-only composition over injected retained
  # evidence. This service deliberately cannot collect, mutate, or persist.
  class IncidentNarratorService
    SCHEMA_VERSION = "soul.incident-narrator.a0.v1"
    MAX_EVENTS = 64
    MAX_FINDINGS = 32
    MAX_RECEIPTS_PER_SOURCE = 32
    MAX_TEXT_BYTES = 240
    SOURCE_IDS = %w[
      wazuh_alerts
      security_snapshot
      maintenance_device_receipts
      maintenance_host_receipts
      backup_drs
    ].freeze
    FAILURE_STATES = %w[failed blocked blocked_for_human_review unavailable invalid].freeze
    SEVERITY_ORDER = {"critical" => 4, "high" => 3, "elevated" => 2, "informational" => 1}.freeze
    FRESHNESS_SECONDS = {
      "wazuh_alerts" => 24 * 60 * 60,
      "security_snapshot" => 24 * 60 * 60,
      "backup_drs" => 36 * 60 * 60
    }.freeze

    def initialize(
      alert_source:,
      security_source:,
      maintenance_device_receipt_source:,
      maintenance_host_receipt_source:,
      backup_source:,
      clock: -> { Time.now.utc }
    )
      @sources = {
        "wazuh_alerts" => alert_source,
        "security_snapshot" => security_source,
        "maintenance_device_receipts" => maintenance_device_receipt_source,
        "maintenance_host_receipts" => maintenance_host_receipt_source,
        "backup_drs" => backup_source
      }
      @clock = clock
    end

    def compose
      source_results = SOURCE_IDS.to_h { |source_id| [source_id, read_source(source_id)] }
      events = []
      findings = []

      append_alerts(events, findings, source_results.fetch("wazuh_alerts"))
      append_security(events, findings, source_results.fetch("security_snapshot"))
      append_maintenance(events, findings, source_results.fetch("maintenance_device_receipts"), "maintenance_device_receipts")
      append_maintenance(events, findings, source_results.fetch("maintenance_host_receipts"), "maintenance_host_receipts")
      append_backup(events, findings, source_results.fetch("backup_drs"))

      source_results.each_value { |result| findings << gap_finding(result) if !result.fetch("available") || result.dig("source", "stale") == true }
      events = sort_events(events).first(MAX_EVENTS)
      findings = align_findings(findings, events)
      append_cross_source_inference(findings, events)
      findings = prioritize_findings(findings).first(MAX_FINDINGS)
      state = incident_state(source_results, events)
      complete(
        "schema_version" => SCHEMA_VERSION,
        "generated_at" => iso8601(@clock.call),
        "state" => state,
        "headline" => headline_for(state, source_results),
        "summary" => summary_for(events, findings),
        "events" => events,
        "findings" => findings,
        "sources" => SOURCE_IDS.map { |source_id| source_results.fetch(source_id).fetch("source") },
        "automatic_refresh" => false,
        "background_polling" => false,
        "mutation_authority" => "none",
        "model_used" => false
      )
    rescue StandardError => error
      failed("incident narrative failed safely: #{safe_text(error.message, 160)}")
    end

    private

    def read_source(source_id)
      callable = @sources.fetch(source_id)
      return unavailable_source(source_id, "source callable is unavailable") unless callable.respond_to?(:call)

      raw = callable.call
      return unavailable_source(source_id, unavailable_reason(raw)) if unavailable_payload?(raw)

      payload = unwrap(raw)
      return unavailable_source(source_id, unavailable_reason(payload)) if unavailable_payload?(payload)

      source = {
        "source_id" => source_id,
        "available" => true,
        "state" => safe_state(payload["state"] || payload["lifecycle_state"] || "available"),
        "observed_at" => source_observed_at(payload),
        "event_count" => 0
      }.compact
      if stale_source?(source_id, source["observed_at"])
        source["stale"] = true
        source["state"] = "stale"
      else
        source["stale"] = false
      end
      {
        "available" => true,
        "payload" => payload,
        "source" => source
      }
    rescue StandardError => error
      unavailable_source(source_id, "source could not be read: #{safe_text(error.message, 120)}")
    end

    def unwrap(value)
      return {} unless value.is_a?(Hash)
      return value.fetch("data") if value["data"].is_a?(Hash)

      value
    end

    def unavailable_payload?(payload)
      return true unless payload.is_a?(Hash)
      return true if payload["available"] == false || payload["ok"] == false

      FAILURE_STATES.include?(payload["state"].to_s) || FAILURE_STATES.include?(payload["lifecycle_state"].to_s)
    end

    def unavailable_reason(payload)
      safe_text(payload["reason"] || payload["message"] || "retained source is unavailable", 160)
    end

    def unavailable_source(source_id, reason)
      {
        "available" => false,
        "payload" => {},
        "source" => {
          "source_id" => source_id,
          "available" => false,
          "state" => "unavailable",
          "event_count" => 0,
          "reason" => safe_text(reason, 160)
        }
      }
    end

    def append_alerts(events, findings, result)
      return unless result.fetch("available")

      alerts = Array(result.fetch("payload")["alerts"]).first(MAX_EVENTS)
      result.fetch("source")["event_count"] = alerts.length
      critical = 0
      high = 0
      normalized = alerts.each_with_index.filter_map do |alert, index|
        next unless alert.is_a?(Hash)
        severity = normalize_severity(alert["severity"] || alert["level"])
        critical += 1 if severity == "critical"
        high += 1 if severity == "high"
        evidence_id = "wazuh:#{safe_identifier(alert["event_id"] || alert["id"], "alert-#{index + 1}")}"
        {
          "evidence_id" => evidence_id,
          "observed_at" => normalized_time(alert["occurred_at"] || alert["timestamp"]),
          "severity" => severity,
          "agent" => safe_identifier(alert["agent_name"], "unassigned"),
          "rule" => safe_identifier(alert["rule_id"], "unknown-rule")
        }
      end
      rendered_ids = []
      normalized.group_by { |alert| [alert.fetch("severity"), alert.fetch("agent"), alert.fetch("rule")] }.each_value do |group|
        latest = group.max_by { |alert| [alert.fetch("observed_at") || "", alert.fetch("evidence_id")] }
        rendered_ids << latest.fetch("evidence_id")
        count = group.length
        events << event(
          evidence_id: latest.fetch("evidence_id"),
          occurred_at: latest.fetch("observed_at"),
          category: "security_alert",
          severity: latest.fetch("severity"),
          statement: "Wazuh retained #{count} #{latest.fetch("severity")} alert#{count == 1 ? "" : "s"} for agent #{latest.fetch("agent")} under rule #{latest.fetch("rule")}; this is the latest retained occurrence.",
          occurrence_count: count,
          supporting_evidence_ids: group.sort_by { |alert| alert.fetch("observed_at") || "" }.reverse.first(8).map { |alert| alert.fetch("evidence_id") }
        )
      end
      result.fetch("source")["rendered_event_count"] = rendered_ids.length
      return if normalized.empty?

      findings << observation(
        "wazuh-alert-summary",
        "Wazuh retained #{normalized.length} alert#{normalized.length == 1 ? "" : "s"}, including #{critical} critical and #{high} high severity alert#{high == 1 ? "" : "s"}.",
        rendered_ids.first(8)
      )
    end

    def append_security(events, findings, result)
      return unless result.fetch("available")

      payload = result.fetch("payload")
      manager_state = safe_state(payload.dig("manager", "state") || payload.dig("manager", "status") || payload["manager_state"] || payload["state"] || "unknown")
      agent_summary = payload["summary"].is_a?(Hash) ? payload.fetch("summary") : {}
      active_agents = safe_integer(agent_summary["active"] || agent_summary["active_agents"] || agent_summary["connected"], 0)
      total_agents = safe_integer(agent_summary["total"] || agent_summary["agent_count"], 0)
      disconnected_agents = safe_integer(agent_summary["disconnected"], 0)
      statement = "Security snapshot reports manager state #{manager_state} and #{active_agents} active agent#{active_agents == 1 ? "" : "s"}#{total_agents.positive? ? " of #{total_agents}" : ""}#{disconnected_agents.positive? ? ", with #{disconnected_agents} disconnected" : ""}."
      security_attention = payload["state"].to_s == "attention" || manager_state != "healthy" || disconnected_agents.positive?
      events << event(
        evidence_id: "security:snapshot",
        occurred_at: payload["collected_at"] || payload["last_successful_at"],
        category: "security_snapshot",
        severity: security_attention ? "elevated" : "informational",
        statement: statement
      )
      result.fetch("source")["event_count"] = 1
      findings << observation("security-snapshot", statement, ["security:snapshot"])
    end

    def append_maintenance(events, findings, result, source_id)
      return unless result.fetch("available")

      payload = result.fetch("payload")
      receipts = Array(payload["receipts"] || payload["receipt"] || payload["transactions"]).first(MAX_RECEIPTS_PER_SOURCE)
      result.fetch("source")["event_count"] = receipts.length
      issue_ids = []
      receipts.each_with_index do |receipt, index|
        next unless receipt.is_a?(Hash)

        lifecycle = safe_state(receipt["lifecycle_state"] || receipt["state"] || "unknown")
        evidence_id = "#{source_id}:#{safe_identifier(receipt["receipt_id"] || receipt["transaction_id"] || receipt["id"], "receipt-#{index + 1}")}"
        suffix = safe_text(receipt["summary"] || receipt["reason"], 160)
        events << event(
          evidence_id: evidence_id,
          occurred_at: receipt["finished_at"] || receipt["completed_at"] || receipt["executed_at"] || receipt["created_at"],
          category: source_id,
          severity: FAILURE_STATES.include?(lifecycle) ? "high" : "informational",
          statement: "Retained #{safe_identifier(receipt["action"] || receipt["operation"], "maintenance")} receipt in #{safe_identifier(receipt["mode"], "unspecified")} mode ended #{lifecycle}.#{suffix.empty? ? "" : " #{suffix}"}"
        )
        issue_ids << evidence_id if FAILURE_STATES.include?(lifecycle)
      end
      return if issue_ids.empty?

      findings << observation(
        "#{source_id}-failure-summary",
        "#{source_id.tr("_", " ")} retained #{issue_ids.length} failed, blocked, unavailable, or invalid receipt#{issue_ids.length == 1 ? "" : "s"}.",
        issue_ids.first(8)
      )
    end

    def append_backup(events, findings, result)
      return unless result.fetch("available")

      payload = result.fetch("payload")
      drs = payload["drs"].is_a?(Hash) ? payload.fetch("drs") : payload
      state = safe_state(drs["state"] || "unknown")
      evidence_id = "backup:#{safe_identifier(drs["receipt_id"], "drs-latest")}"
      statement = "Latest DRS backup status is #{state}."
      events << event(
        evidence_id: evidence_id,
        occurred_at: drs["completed_at"] || drs["checked_at"] || payload["collected_at"],
        category: "backup_drs",
        severity: FAILURE_STATES.include?(state) ? "high" : "informational",
        statement: statement
      )
      result.fetch("source")["event_count"] = 1
      findings << observation("backup-drs", statement, [evidence_id]) if FAILURE_STATES.include?(state)
    end

    def append_cross_source_inference(findings, events)
      security = events.select { |record| record["category"] == "security_alert" && %w[critical high].include?(record["severity"]) }
      maintenance = events.select { |record| record["category"].start_with?("maintenance_") && record["severity"] == "high" }
      return if security.empty? || maintenance.empty?

      proximate = security.product(maintenance).select do |alert, receipt|
        alert_time = parsed_time(alert["observed_at"])
        receipt_time = parsed_time(receipt["observed_at"])
        alert_time && receipt_time && (alert_time - receipt_time).abs <= (6 * 60 * 60)
      end
      return if proximate.empty?

      findings << {
        "kind" => "inference",
        "finding_id" => "security-maintenance-correlation",
        "statement" => "Retained evidence places a high-priority security alert within six hours of a failed or blocked maintenance receipt; a causal relationship is unconfirmed.",
        "supporting_evidence_ids" => proximate.first(4).flat_map { |alert, receipt| [alert["evidence_id"], receipt["evidence_id"]] }.uniq,
        "confidence" => "low"
      }
    end

    def gap_finding(result)
      source = result.fetch("source")
      if source["stale"] == true
        return {
          "kind" => "gap",
          "finding_id" => "#{source.fetch("source_id")}-stale",
          "statement" => "#{source.fetch("source_id").tr("_", " ")} evidence is stale; the last retained observation is #{source["observed_at"] || "unknown"}.",
          "supporting_evidence_ids" => [],
          "confidence" => "low"
        }
      end
      {
        "kind" => "gap",
        "finding_id" => "#{source.fetch("source_id")}-unavailable",
        "statement" => "#{source.fetch("source_id").tr("_", " ")} evidence is unavailable: #{source.fetch("reason")}.",
        "supporting_evidence_ids" => [],
        "confidence" => "low"
      }
    end

    def event(evidence_id:, occurred_at:, category:, severity:, statement:, occurrence_count: nil, supporting_evidence_ids: nil)
      record = {
        "evidence_id" => evidence_id,
        "observed_at" => normalized_time(occurred_at),
        "category" => category,
        "severity" => severity,
        "statement" => safe_text(statement, MAX_TEXT_BYTES)
      }
      record["occurrence_count"] = occurrence_count if occurrence_count
      record["supporting_evidence_ids"] = supporting_evidence_ids if supporting_evidence_ids
      record
    end

    def observation(finding_id, statement, evidence_ids)
      {
        "kind" => "observation",
        "finding_id" => finding_id,
        "statement" => safe_text(statement, MAX_TEXT_BYTES),
        "supporting_evidence_ids" => evidence_ids,
        "confidence" => "medium"
      }
    end

    def sort_events(events)
      events.sort_by { |record| [record.fetch("observed_at") || "", record.fetch("evidence_id")] }.reverse
    end

    def prioritize_findings(findings)
      order = {"gap" => 0, "observation" => 1, "inference" => 2}
      findings.sort_by { |record| [order.fetch(record.fetch("kind"), 3), record.fetch("finding_id")] }
    end

    def align_findings(findings, events)
      visible = events.map { |event| event.fetch("evidence_id") }
      findings.filter_map do |finding|
        next finding if finding["kind"] == "gap"
        supported = Array(finding["supporting_evidence_ids"]) & visible
        next if supported.empty?

        finding.merge("supporting_evidence_ids" => supported)
      end
    end

    def incident_state(source_results, events)
      return "critical" if events.any? { |record| record["category"] == "security_alert" && record["severity"] == "critical" }
      return "attention" if source_results.values.any? { |result| !result.fetch("available") }
      return "attention" if source_results.values.any? { |result| result.dig("source", "stale") == true }
      return "attention" if events.any? { |record| %w[high elevated].include?(record["severity"]) }

      "quiet"
    end

    def headline_for(state, source_results)
      case state
      when "critical" then "Critical retained security evidence requires operator review."
      when "attention"
        source_results.values.any? { |result| !result.fetch("available") || result.dig("source", "stale") == true } ?
          "Retained evidence is incomplete; review stale or unavailable sources." :
          "Retained evidence requires operator attention."
      else "No critical retained incident evidence in this bounded snapshot."
      end
    end

    def summary_for(events, findings)
      observations = findings.count { |record| record["kind"] == "observation" }
      inferences = findings.count { |record| record["kind"] == "inference" }
      gaps = findings.count { |record| record["kind"] == "gap" }
      "#{events.length} retained event#{events.length == 1 ? "" : "s"}; #{observations} observation#{observations == 1 ? "" : "s"}; #{inferences} bounded inference#{inferences == 1 ? "" : "s"}; #{gaps} evidence gap#{gaps == 1 ? "" : "s"}."
    end

    def normalize_severity(value)
      text = value.to_s.downcase
      return text if SEVERITY_ORDER.key?(text)
      return "critical" if safe_integer(value, 0) >= 13
      return "high" if safe_integer(value, 0) >= 10
      return "elevated" if safe_integer(value, 0) >= 7

      "informational"
    end

    def safe_state(value)
      safe_identifier(value, "unknown").downcase
    end

    def safe_identifier(value, fallback)
      text = value.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?").strip
      return fallback unless text.match?(%r{\A[A-Za-z0-9][A-Za-z0-9_.:-]{0,95}\z})

      text
    end

    def safe_integer(value, fallback)
      Integer(value)
    rescue ArgumentError, TypeError
      fallback
    end

    def normalized_time(value)
      return nil if value.nil? || value.to_s.empty?

      Time.iso8601(value.to_s).utc.iso8601
    rescue ArgumentError
      nil
    end

    def parsed_time(value)
      Time.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end

    def source_observed_at(payload)
      direct = payload["collected_at"] || payload["last_successful_at"] || payload["checked_at"] || payload["generated_at"]
      direct ||= payload.dig("drs", "completed_at") if payload["drs"].is_a?(Hash)
      direct ||= Array(payload["receipts"]).filter_map { |receipt| receipt.is_a?(Hash) ? (receipt["finished_at"] || receipt["completed_at"]) : nil }.max
      normalized_time(direct)
    end

    def stale_source?(source_id, observed_at)
      maximum_age = FRESHNESS_SECONDS[source_id]
      return false unless maximum_age
      observed = parsed_time(observed_at)
      current = @clock.call
      return true unless observed && current.respond_to?(:to_time)

      (current.to_time.utc - observed.utc) > maximum_age
    rescue StandardError
      true
    end

    def iso8601(value)
      value.respond_to?(:utc) ? value.utc.iso8601 : Time.parse(value.to_s).utc.iso8601
    end

    def safe_text(value, maximum)
      text = value.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
      text = text.gsub(/\`[^\`]*\`/, "[command redacted]")
      text = text.gsub(/\b(?:sudo|yay|paru|apt(?:-get)?|dnf|zypper|apk|flatpak|nix|restic|systemctl|ssh|bash|sh)\b(?:\s+[^\n]*)?/i, "[command redacted]")
      text = text.gsub(/\b(password|passphrase|token|api[_-]?key|secret|credential)\s*(?:=|:|\s)\s*[^\s,;]+/i, '\\1=[redacted]')
      text = text.gsub(%r{(?<![A-Za-z0-9_.-])/(?:[^\s'"()]+)}, "[private path]")
      text.gsub(/\s+/, " ").strip.byteslice(0, maximum).to_s
    end

    def complete(data)
      {"ok" => true, "lifecycle_state" => "complete", "reason" => "bounded read-only incident narrative composed", "data" => data, "mutation" => "none"}
    end

    def failed(reason)
      {
        "ok" => false,
        "lifecycle_state" => "failed",
        "reason" => reason,
        "data" => {
          "schema_version" => SCHEMA_VERSION,
          "state" => "attention",
          "automatic_refresh" => false,
          "background_polling" => false,
          "mutation_authority" => "none",
          "model_used" => false
        },
        "mutation" => "none"
      }
    end
  end
end
