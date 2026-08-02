# frozen_string_literal: true

require_relative "network_diagnostic_service"

module SoulCore
  class NetworkDiagnosticChatControls
    SNAPSHOT_PATTERN = /\A\s*(?:diagnose|inspect|check)\s+(?:the\s+)?(?:local\s+)?network(?:\s+status)?\s*[?.!]*\s*\z/i
    RESOLVE_PATTERN = /\A\s*(?:resolve|check\s+dns\s+for|look\s+up\s+dns\s+for)\s+([A-Za-z0-9:._-]+)\s*[?.!]*\s*\z/i
    REACHABILITY_PATTERN = /\A\s*(?:ping|(?:check|test)\s+(?:network\s+)?reachability\s+(?:to|for))\s+([A-Za-z0-9:._-]+)\s*[?.!]*\s*\z/i
    SOCKET_PATTERN = /\A\s*(?:check|test)\s+(?:tcp\s+)?(?:socket|port)\s+([A-Za-z0-9:._-]+)\s+(?:on\s+)?port\s+([0-9]{1,5})\s*[?.!]*\s*\z/i
    SOCKET_REVERSE_PATTERN = /\A\s*(?:check|test)\s+(?:tcp\s+)?port\s+([0-9]{1,5})\s+(?:on|at|for)\s+([A-Za-z0-9:._-]+)\s*[?.!]*\s*\z/i
    REQUEST_PATTERNS = [SNAPSHOT_PATTERN, RESOLVE_PATTERN, REACHABILITY_PATTERN, SOCKET_PATTERN, SOCKET_REVERSE_PATTERN].freeze

    def initialize(service: nil)
      @service = service || NetworkDiagnosticService.new
    end

    def match?(message)
      !parse(message).nil?
    end

    def respond(message, chat_id: nil)
      request = parse(message)
      return usage unless request

      outcome = case request.fetch("action")
                when "snapshot" then @service.snapshot
                when "resolve" then @service.resolve(target: request.fetch("target"))
                when "reachability" then @service.reachability(target: request.fetch("target"))
                when "socket" then @service.socket(target: request.fetch("target"), port: request.fetch("port"))
                end
      render(outcome, request)
    rescue StandardError => error
      "Network diagnosis failed safely: #{error.class}. Lifecycle: failed. Mutation: none."
    end

    private

    def parse(message)
      text = message.to_s.strip
      return { "action" => "snapshot" } if text.match?(SNAPSHOT_PATTERN)
      match = text.match(RESOLVE_PATTERN)
      return { "action" => "resolve", "target" => match[1] } if match
      match = text.match(REACHABILITY_PATTERN)
      return { "action" => "reachability", "target" => match[1] } if match
      match = text.match(SOCKET_PATTERN)
      return { "action" => "socket", "target" => match[1], "port" => match[2] } if match
      match = text.match(SOCKET_REVERSE_PATTERN)
      return { "action" => "socket", "target" => match[2], "port" => match[1] } if match

      nil
    end

    def render(outcome, request)
      return "#{outcome.fetch('message')}\nLifecycle: #{outcome.fetch('lifecycle_state')}. Mutation: none." unless outcome.fetch("lifecycle_state") == "complete"

      data = outcome.fetch("data")
      body = case request.fetch("action")
             when "snapshot" then render_snapshot(data)
             when "resolve" then render_resolution(data)
             when "reachability" then render_reachability(data)
             when "socket" then render_socket(data)
             end
      "#{body}\nThis is one point-in-time diagnostic, not a global availability claim. Lifecycle: complete. Mutation: none."
    end

    def render_snapshot(data)
      addresses = data.fetch("addresses")
      routes = data.fetch("routes")
      lines = ["Bounded local network snapshot.", "Addresses: #{addresses.fetch('available') ? addresses.fetch('count') : 'unavailable'}"]
      addresses.fetch("records").each do |record|
        lines << "- #{record.fetch('interface')} · #{record.fetch('family')} · #{record.fetch('address')} · #{record.fetch('scope')}"
      end
      lines << "Routes: #{routes.fetch('available') ? routes.fetch('count') : 'unavailable'}"
      routes.fetch("records").each do |record|
        gateway = record["gateway"] ? " via #{record['gateway']}" : ""
        lines << "- #{record.fetch('interface')} · #{record.fetch('destination')}#{gateway} · metric #{record.fetch('metric')}"
      end
      lines.join("\n")
    end

    def render_resolution(data)
      lines = ["DNS diagnosis for #{data.fetch('target')}.", "Resolved: #{data.fetch('resolved')}"]
      data.fetch("addresses").each { |address| lines << "- #{address}" }
      lines << "Observation: #{data['observation']}" if data["observation"]
      lines.join("\n")
    end

    def render_reachability(data)
      lines = [
        "Reachability diagnosis for #{data.fetch('target')}.",
        "Reply received: #{data.fetch('reachable')}",
        "Observation: #{data.fetch('observation')}"
      ]
      lines << "Latency: #{data['latency_ms']} ms" if data["latency_ms"]
      lines.join("\n")
    end

    def render_socket(data)
      [
        "TCP socket diagnosis for #{data.fetch('target')}:#{data.fetch('port')}.",
        "Connected: #{data.fetch('connected')}",
        ("Observation: #{data['observation']}" if data["observation"]),
        ("Connect latency: #{data['latency_ms']} ms" if data["latency_ms"]),
        "Application payload sent: 0 bytes"
      ].compact.join("\n")
    end

    def usage
      [
        "Use `diagnose local network`, `resolve example.com`, `check reachability to 192.0.2.10`, or `check socket example.com port 443`.",
        "One target and one port are allowed per bounded foreground request.",
        "Lifecycle: awaiting_input. Mutation: none."
      ].join("\n")
    end
  end
end
