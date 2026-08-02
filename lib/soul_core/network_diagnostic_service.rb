# frozen_string_literal: true

require "ipaddr"
require "open3"
require "resolv"
require "socket"
require "time"
require "timeout"

module SoulCore
  class NetworkDiagnosticService
    MAX_TARGET_BYTES = 253
    MAX_ADDRESSES = 64
    MAX_ADDRESS_SCAN = 256
    MAX_ROUTES = 64
    MAX_ROUTE_SCAN = 256
    MAX_ROUTE_BYTES = 64 * 1024
    MAX_DNS_RESULTS = 8
    DNS_TIMEOUT_SECONDS = 3
    PING_WAIT_SECONDS = 2
    PING_TIMEOUT_SECONDS = 4
    SOCKET_TIMEOUT_SECONDS = 3
    PING_PATHS = %w[/usr/bin/ping /bin/ping].freeze
    HOST_LABEL = /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/i

    class AwaitingInput < StandardError; end
    class BoundaryViolation < StandardError; end

    def initialize(
      clock: -> { Time.now.utc },
      address_source: -> { Socket.getifaddrs },
      route_reader: -> { File.binread("/proc/net/route", MAX_ROUTE_BYTES + 1) },
      resolver: nil,
      ping_path: nil,
      ping_runner: nil,
      socket_connector: nil
    )
      @clock = clock
      @address_source = address_source
      @route_reader = route_reader
      @resolver = resolver || method(:system_resolve)
      @ping_path = ping_path
      @ping_runner = ping_runner || method(:system_ping)
      @socket_connector = socket_connector || method(:system_socket_connect)
    end

    def snapshot
      addresses = address_snapshot
      routes = route_snapshot
      complete({
        "addresses" => addresses,
        "routes" => routes,
        "limits" => { "addresses" => MAX_ADDRESSES, "routes" => MAX_ROUTES }
      }, "bounded local network evidence inspected")
    rescue BoundaryViolation => error
      blocked(error.message)
    rescue StandardError => error
      failed("local network inspection failed safely: #{error.class}")
    end

    def resolve(target:)
      normalized = normalize_target(target)
      literal = ip_literal(normalized)
      records = literal ? [literal.to_s] : Timeout.timeout(DNS_TIMEOUT_SECONDS) { Array(@resolver.call(normalized)) }
      addresses = records.filter_map do |record|
        ip_literal(record.to_s.strip)&.to_s
      end.uniq.first(MAX_DNS_RESULTS)

      complete({
        "target" => normalized,
        "target_kind" => literal ? "ip_literal" : "hostname",
        "addresses" => addresses,
        "count" => addresses.length,
        "resolved" => !addresses.empty?,
        "truncated" => records.length > MAX_DNS_RESULTS,
        "timeout_seconds" => DNS_TIMEOUT_SECONDS
      }, addresses.empty? ? "target returned no address records" : "target resolution completed")
    rescue Timeout::Error
      complete({ "target" => safe_target_label(target), "addresses" => [], "count" => 0, "resolved" => false, "observation" => "timeout", "timeout_seconds" => DNS_TIMEOUT_SECONDS }, "target resolution timed out")
    rescue AwaitingInput => error
      awaiting(error.message)
    rescue BoundaryViolation => error
      blocked(error.message)
    rescue Resolv::ResolvError, SocketError
      complete({ "target" => safe_target_label(target), "addresses" => [], "count" => 0, "resolved" => false, "observation" => "resolver_error", "timeout_seconds" => DNS_TIMEOUT_SECONDS }, "target resolution returned no usable evidence")
    rescue StandardError => error
      failed("target resolution failed safely: #{error.class}")
    end

    def reachability(target:)
      normalized = normalize_target(target)
      command = selected_ping_path
      raise AwaitingInput, "the reviewed ping binary is unavailable on this host" unless command

      argv = [command, "-n", "-c", "1", "-W", PING_WAIT_SECONDS.to_s, "--", normalized]
      stdout, _stderr, status = Timeout.timeout(PING_TIMEOUT_SECONDS) { @ping_runner.call(argv) }
      exit_status = status.respond_to?(:exitstatus) ? status.exitstatus : Integer(status)
      raise "ping runner returned an invalid exit status" unless exit_status.between?(0, 255)

      reachable = exit_status.zero?
      complete({
        "target" => normalized,
        "reachable" => reachable,
        "observation" => reachable ? "reply_received" : (exit_status == 1 ? "no_reply" : "probe_error"),
        "latency_ms" => parse_latency(stdout),
        "attempts" => 1,
        "timeout_seconds" => PING_TIMEOUT_SECONDS
      }, reachable ? "bounded reachability probe received one reply" : "bounded reachability probe received no reply")
    rescue Timeout::Error
      complete({ "target" => safe_target_label(target), "reachable" => false, "observation" => "timeout", "attempts" => 1, "timeout_seconds" => PING_TIMEOUT_SECONDS }, "bounded reachability probe timed out")
    rescue AwaitingInput => error
      awaiting(error.message)
    rescue BoundaryViolation => error
      blocked(error.message)
    rescue StandardError => error
      failed("reachability probe failed safely: #{error.class}")
    end

    def socket(target:, port:)
      normalized = normalize_target(target)
      normalized_port = normalize_port(port)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      Timeout.timeout(SOCKET_TIMEOUT_SECONDS + 1) do
        @socket_connector.call(normalized, normalized_port, SOCKET_TIMEOUT_SECONDS)
      end
      elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1_000).round(2)
      complete({
        "target" => normalized,
        "port" => normalized_port,
        "protocol" => "tcp",
        "connected" => true,
        "latency_ms" => elapsed,
        "payload_bytes_sent" => 0,
        "attempts" => 1,
        "timeout_seconds" => SOCKET_TIMEOUT_SECONDS
      }, "bounded TCP connection succeeded and closed without sending data")
    rescue Timeout::Error
      complete(socket_failure_data(target, port, "timeout"), "bounded TCP connection timed out")
    rescue Errno::ECONNREFUSED
      complete(socket_failure_data(target, port, "connection_refused"), "bounded TCP connection was refused")
    rescue Errno::EHOSTUNREACH, Errno::ENETUNREACH
      complete(socket_failure_data(target, port, "unreachable"), "bounded TCP connection found no route to the target")
    rescue SocketError
      complete(socket_failure_data(target, port, "resolver_error"), "bounded TCP connection could not resolve the target")
    rescue AwaitingInput => error
      awaiting(error.message)
    rescue BoundaryViolation => error
      blocked(error.message)
    rescue StandardError => error
      failed("TCP connection check failed safely: #{error.class}")
    end

    private

    def address_snapshot
      source = Array(@address_source.call)
      records = source.first(MAX_ADDRESS_SCAN).filter_map do |interface|
        address = interface.respond_to?(:addr) ? interface.addr : nil
        next unless address&.respond_to?(:ip?) && address.ip?

        literal = ip_literal(address.ip_address.to_s)
        interface_name = safe_interface_name(interface.respond_to?(:name) ? interface.name : nil)
        next unless literal
        next unless interface_name

        {
          "interface" => interface_name,
          "family" => literal.ipv4? ? "ipv4" : "ipv6",
          "address" => literal.to_s,
          "scope" => literal.loopback? ? "loopback" : (literal.link_local? ? "link_local" : (literal.private? ? "private" : "public"))
        }
      end
      records.uniq { |record| [record.fetch("interface"), record.fetch("address")] }
             .sort_by { |record| [record.fetch("interface"), record.fetch("family"), record.fetch("address")] }
             .first(MAX_ADDRESSES)
             .then { |bounded| { "available" => true, "records" => bounded, "count" => bounded.length, "truncated" => source.length > MAX_ADDRESS_SCAN || records.length > MAX_ADDRESSES } }
    rescue StandardError => error
      { "available" => false, "records" => [], "count" => 0, "truncated" => false, "reason" => error.class.name }
    end

    def route_snapshot
      bytes = @route_reader.call.to_s
      raise BoundaryViolation, "route evidence exceeds the #{MAX_ROUTE_BYTES}-byte limit" if bytes.bytesize > MAX_ROUTE_BYTES

      lines = bytes.lines.drop(1).first(MAX_ROUTE_SCAN)
      records = lines.filter_map do |line|
        fields = line.split
        next unless fields.length >= 8
        next unless fields[1].match?(/\A[0-9A-Fa-f]{8}\z/) && fields[2].match?(/\A[0-9A-Fa-f]{8}\z/) && fields[7].match?(/\A[0-9A-Fa-f]{8}\z/)

        destination = little_endian_ipv4(fields[1])
        gateway = little_endian_ipv4(fields[2])
        mask = little_endian_ipv4(fields[7])
        prefix = ipv4_prefix(mask)
        interface_name = safe_interface_name(fields[0])
        next unless prefix
        next unless interface_name

        {
          "interface" => interface_name,
          "destination" => "#{destination}/#{prefix}",
          "gateway" => gateway == "0.0.0.0" ? nil : gateway,
          "metric" => Integer(fields[6], 10),
          "default" => destination == "0.0.0.0" && prefix.zero?
        }.compact
      rescue ArgumentError
        nil
      end
      bounded = records.first(MAX_ROUTES)
      { "available" => true, "records" => bounded, "count" => bounded.length, "truncated" => lines.length >= MAX_ROUTE_SCAN || records.length > MAX_ROUTES }
    rescue Errno::ENOENT, Errno::EACCES, NotImplementedError => error
      { "available" => false, "records" => [], "count" => 0, "truncated" => false, "reason" => error.class.name }
    end

    def normalize_target(target)
      text = target.to_s.strip
      raise AwaitingInput, "one exact network target is required" if text.empty?
      raise BoundaryViolation, "network target exceeds #{MAX_TARGET_BYTES} bytes" if text.bytesize > MAX_TARGET_BYTES
      raise BoundaryViolation, "network target must be valid UTF-8" unless text.valid_encoding?
      raise BoundaryViolation, "network target contains prohibited whitespace or control characters" if text.match?(/[\s\x00-\x1f\x7f]/)
      prohibited_shape = text.start_with?("-") || text.include?("/") || text.include?("*") || text.include?("..") || text.match?(/\A[a-z][a-z0-9+.-]*:\/\//i) || text.match?(/\A[0-9.]+-[0-9.]+\z/)
      raise BoundaryViolation, "URL, CIDR, range, wildcard, and option targets are outside the reviewed boundary" if prohibited_shape

      literal = ip_literal(text)
      return literal.to_s if literal
      raise BoundaryViolation, "numeric dotted target is not a valid IP literal" if text.match?(/\A[0-9.]+\z/) && text.include?(".")

      hostname = text.downcase.sub(/\.\z/, "")
      labels = hostname.split(".", -1)
      raise BoundaryViolation, "network target must be one hostname or IP literal" unless !labels.empty? && labels.all? { |label| label.match?(HOST_LABEL) }
      hostname
    end

    def normalize_port(port)
      text = port.to_s.strip
      raise AwaitingInput, "one TCP port is required" if text.empty?
      raise BoundaryViolation, "TCP port must be one integer from 1 through 65535" unless text.match?(/\A[0-9]{1,5}\z/)
      value = Integer(text, 10)
      raise BoundaryViolation, "TCP port must be one integer from 1 through 65535" unless value.between?(1, 65_535)
      value
    end

    def selected_ping_path
      return @ping_path if @ping_path && PING_PATHS.include?(@ping_path)
      PING_PATHS.find { |path| File.file?(path) && File.executable?(path) }
    end

    def system_resolve(target)
      Resolv.getaddresses(target)
    end

    def system_ping(argv)
      Open3.capture3(*argv)
    end

    def system_socket_connect(target, port, timeout)
      Socket.tcp(target, port, connect_timeout: timeout) { |_socket| true }
    end

    def ip_literal(value)
      IPAddr.new(value)
    rescue IPAddr::InvalidAddressError
      nil
    end

    def safe_interface_name(value)
      name = value.to_s
      name.match?(/\A[A-Za-z0-9_.:@-]{1,64}\z/) ? name : nil
    end

    def little_endian_ipv4(hex)
      [Integer(hex, 16)].pack("V").unpack("C4").join(".")
    end

    def ipv4_prefix(mask)
      bits = IPAddr.new(mask).to_i.to_s(2).rjust(32, "0")
      bits.match?(/\A1*0*\z/) ? bits.count("1") : nil
    end

    def parse_latency(stdout)
      match = stdout.to_s.match(/\btime[=<]([0-9]+(?:\.[0-9]+)?)\s*ms\b/i)
      match ? Float(match[1]).round(3) : nil
    rescue ArgumentError
      nil
    end

    def socket_failure_data(target, port, observation)
      {
        "target" => safe_target_label(target),
        "port" => safe_port_label(port),
        "protocol" => "tcp",
        "connected" => false,
        "observation" => observation,
        "payload_bytes_sent" => 0,
        "attempts" => 1,
        "timeout_seconds" => SOCKET_TIMEOUT_SECONDS
      }
    end

    def safe_target_label(target)
      normalize_target(target)
    rescue StandardError
      "invalid_target"
    end

    def safe_port_label(port)
      normalize_port(port)
    rescue StandardError
      0
    end

    def complete(data, message)
      outcome(true, "complete", message, data)
    end

    def awaiting(message)
      outcome(false, "awaiting_input", message, {})
    end

    def blocked(message)
      outcome(false, "blocked_for_human_review", message, {})
    end

    def failed(message)
      outcome(false, "failed", message, {})
    end

    def outcome(ok, lifecycle, message, data)
      {
        "ok" => ok,
        "lifecycle_state" => lifecycle,
        "message" => message,
        "data" => data,
        "mutation" => "none",
        "retrieved_at" => @clock.call.iso8601(6)
      }
    end
  end
end
