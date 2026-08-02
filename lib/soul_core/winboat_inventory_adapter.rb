# frozen_string_literal: true

require "ipaddr"
require "json"
require "socket"
require "timeout"

require_relative "bounded_command_runner"

module SoulCore
  class WinboatInventoryAdapter
    DOCKER_PATH = "/usr/bin/docker"
    COMMAND_TIMEOUT_SECONDS = 8
    MAX_OUTPUT_BYTES = 16 * 1024
    CONTAINER_NAME_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9_.-]{0,127}\z/
    HOSTNAME_PATTERN = /\A(?=.{1,253}\z)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)*[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\z/
    EXPECTED_PORTS = {
      "3389/tcp" => {"id" => "windows_rdp", "label" => "Windows RDP", "range" => (47_300..47_309)},
      "7148/tcp" => {"id" => "winboat_guest_service", "label" => "WinBoat guest service", "range" => (47_280..47_289)}
    }.freeze

    def initialize(runner: BoundedCommandRunner.new, tcp_probe: nil, docker_path: DOCKER_PATH)
      @runner = runner
      @tcp_probe = tcp_probe || method(:probe_loopback_port)
      @docker_path = File.expand_path(docker_path)
    end

    def collect(container_name:, fqdn:, guest_address:)
      validate_configuration!(container_name, fqdn, guest_address)
      state = run_inspect(
        container_name,
        "{{.State.Status}}\t{{.State.Running}}\t{{.State.StartedAt}}\t{{.RestartCount}}\t{{.Config.Image}}"
      )
      return unavailable("container_state", state) unless state.success?

      status, running, started_at, restart_count, image = state.stdout.to_s.strip.split("\t", 5)
      network = run_inspect(
        container_name,
        '{{with index .NetworkSettings.Networks "winboat_default"}}{{.IPAddress}}{{end}}'
      )
      bindings = run_inspect(container_name, "{{json .HostConfig.PortBindings}}")
      return unavailable("container_network", network) unless network.success?
      return unavailable("port_bindings", bindings) unless bindings.success?

      parsed_bindings = parse_bindings(bindings.stdout)
      services, loopback_only, port_evidence = inspect_services(container_name, parsed_bindings, running == "true")
      running_ok = running == "true" && status == "running"
      healthy = running_ok && loopback_only && services.all? { |service| service.fetch("state") == "active" }
      {
        "available" => true,
        "reachable" => running_ok && loopback_only && services.any? { |service| service.fetch("state") == "active" },
        "healthy" => healthy,
        "status" => status.to_s.empty? ? "unknown" : status,
        "container_running" => running_ok,
        "container_address" => safe_ipv4(network.stdout.to_s.strip),
        "guest_address" => guest_address,
        "fqdn" => fqdn,
        "started_at" => started_at.to_s,
        "restart_count" => Integer(restart_count.to_s, exception: false) || 0,
        "image" => bounded_text(image, 256),
        "loopback_only" => loopback_only,
        "services" => [
          {"id" => "winboat_container", "label" => "WinBoat container", "state" => running_ok ? "active" : "unavailable"}
        ] + services,
        "evidence" => ([state, network, bindings] + port_evidence).map { |result| evidence(result) }
      }
    rescue ArgumentError, JSON::ParserError => error
      {
        "available" => false,
        "reachable" => false,
        "healthy" => false,
        "reason" => bounded_text(error.message, 256),
        "services" => [],
        "evidence" => []
      }
    end

    private

    def validate_configuration!(container_name, fqdn, guest_address)
      raise ArgumentError, "WinBoat container name is invalid" unless container_name.to_s.match?(CONTAINER_NAME_PATTERN)
      raise ArgumentError, "WinBoat FQDN is invalid" unless fqdn.to_s.match?(HOSTNAME_PATTERN)

      address = IPAddr.new(guest_address.to_s)
      raise ArgumentError, "WinBoat guest address must be private IPv4" unless address.ipv4? && address.private?
    rescue IPAddr::InvalidAddressError
      raise ArgumentError, "WinBoat guest address must be private IPv4"
    end

    def run_inspect(container_name, format)
      @runner.run(
        @docker_path, "inspect", "--type", "container", "--format", format, container_name,
        timeout_seconds: COMMAND_TIMEOUT_SECONDS,
        max_output_bytes: MAX_OUTPUT_BYTES,
        env: {"LC_ALL" => "C"}
      )
    end

    def parse_bindings(raw)
      parsed = JSON.parse(raw.to_s)
      raise ArgumentError, "WinBoat port bindings are unavailable" unless parsed.is_a?(Hash)

      parsed
    end

    def inspect_services(container_name, bindings, container_running)
      loopback_only = bindings.values.flatten.all? do |entry|
        entry.is_a?(Hash) && entry["HostIp"].to_s == "127.0.0.1"
      end
      port_evidence = []
      services = EXPECTED_PORTS.map do |guest_port, definition|
        entries = Array(bindings[guest_port])
        declared = entries.length == 1 && entries.all? do |entry|
          next false unless entry.is_a?(Hash)

          host = entry["HostIp"].to_s
          host_port = entry["HostPort"].to_s
          allowed = definition.fetch("range")
          host == "127.0.0.1" && (host_port == allowed.begin.to_s || host_port == "#{allowed.begin}-#{allowed.end}")
        end
        loopback_only &&= declared
        resolved = declared ? run_port(container_name, guest_port) : nil
        port_evidence << resolved if resolved
        host, port = resolved&.success? ? parse_resolved_port(resolved.stdout, definition.fetch("range")) : [nil, nil]
        valid = host == "127.0.0.1" && !port.nil?
        loopback_only &&= valid
        active = container_running && valid && @tcp_probe.call(host, port)
        {
          "id" => definition.fetch("id"),
          "label" => definition.fetch("label"),
          "state" => active ? "active" : "unavailable"
        }
      rescue StandardError
        loopback_only = false
        {"id" => definition.fetch("id"), "label" => definition.fetch("label"), "state" => "unavailable"}
      end
      [services, loopback_only, port_evidence]
    end

    def run_port(container_name, guest_port)
      @runner.run(
        @docker_path, "port", container_name, guest_port,
        timeout_seconds: COMMAND_TIMEOUT_SECONDS,
        max_output_bytes: MAX_OUTPUT_BYTES,
        env: {"LC_ALL" => "C"}
      )
    end

    def parse_resolved_port(raw, allowed_range)
      lines = raw.to_s.lines.map(&:strip).reject(&:empty?)
      return [nil, nil] unless lines.length == 1

      match = lines.first.match(/\A(127\.0\.0\.1):(\d{1,5})\z/)
      port = match && Integer(match[2], exception: false)
      return [nil, nil] unless port && allowed_range.cover?(port)

      [match[1], port]
    end

    def probe_loopback_port(host, port)
      Timeout.timeout(1.5) { Socket.tcp(host, port, connect_timeout: 1).close }
      true
    rescue SystemCallError, Timeout::Error
      false
    end

    def unavailable(reason, result)
      {
        "available" => false,
        "reachable" => false,
        "healthy" => false,
        "reason" => reason,
        "services" => [],
        "evidence" => [evidence(result)]
      }
    end

    def evidence(result)
      {
        "status" => result.status,
        "exit_status" => result.exit_status,
        "truncated" => result.truncated == true
      }
    end

    def safe_ipv4(value)
      address = IPAddr.new(value)
      address.ipv4? ? address.to_s : "unavailable"
    rescue IPAddr::InvalidAddressError
      "unavailable"
    end

    def bounded_text(value, maximum)
      value.to_s.byteslice(0, maximum).to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "�")
    end
  end
end
