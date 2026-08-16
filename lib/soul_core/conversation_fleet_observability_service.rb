# frozen_string_literal: true

module SoulCore
  class ConversationFleetObservabilityService
    def initialize(summary_service:)
      @summary_service = summary_service
    end

    def report
      outcome = @summary_service.summary
      raise outcome["message"].to_s unless outcome["ok"] == true

      report = outcome.fetch("data")
      {
        "ok" => true,
        "lifecycle_state" => "complete",
        "content" => render(report),
        "report" => report,
        "mutation" => "none"
      }
    rescue StandardError => error
      report = {"state" => "unavailable", "gaps" => [{"source_id" => "observatory", "reason" => error.message.to_s.byteslice(0, 160)}], "mutation_authority" => "none"}
      {"ok" => true, "lifecycle_state" => "complete", "content" => render(report), "report" => report, "mutation" => "none"}
    end

    private

    def render(report)
      endpoints = report.fetch("endpoints", {})
      network = report.fetch("network", {})
      alerts = Array(report["alerts"])
      gaps = Array(report["gaps"])
      lines = [
        "Fleet observability is #{report.fetch('state', 'unavailable')} within the current bounded Observatory check.",
        "Endpoints: #{endpoints.fetch('reporting', 0)} reporting and #{endpoints.fetch('stale', 0)} stale.",
        "Network: #{network.fetch('switches_reporting', 0)} switches reporting, #{network.fetch('switches_unavailable', 0)} unavailable, #{Array(network['host_errors']).length} hosts and #{Array(network['switch_interface_errors']).length} switch interfaces with current error evidence.",
        "Bounded alerts firing: #{alerts.length}."
      ]
      lines << "#{gaps.length} query gaps remain; absent evidence is not treated as healthy." if gaps.any?
      lines << "Grafana drill-down: #{report['grafana_url']}" if report["grafana_url"]
      lines << "This was a read-only foreground summary. No maintenance, reboot, switch change, alert mutation, or remediation was performed or authorized."
      lines.join("\n")
    end
  end
end
