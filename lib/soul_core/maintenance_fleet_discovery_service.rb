# frozen_string_literal: true

require "digest"
require "fileutils"
require "ipaddr"
require "json"
require "time"

require_relative "bounded_command_runner"

module SoulCore
  class MaintenanceFleetDiscoveryService
    SCHEMA_VERSION = "soul.maintenance.fleet_discovery.v1"
    REGISTRY_SCHEMA = "soul.maintenance.fleet_registry.v1"
    NMAP_PATH = "/usr/bin/nmap"
    SSH_PATH = "/usr/bin/ssh"
    PING_PATH = "/usr/bin/ping"
    MAX_HOSTS = 256
    MAX_DEVICES = 64
    MAX_FILE_BYTES = 256 * 1024
    DISCOVERY_TIMEOUT_SECONDS = 30
    SSH_TIMEOUT_SECONDS = 5
    ENROLL_CONFIRMATION = "ENROLL_FLEET_DEVICE"
    REMOVE_CONFIRMATION = "REMOVE_FLEET_DEVICE"
    PACKAGE_PATHS = {
      "pacman" => %w[/usr/bin/pacman],
      "yay" => %w[/usr/bin/yay],
      "paru" => %w[/usr/bin/paru],
      "apt" => %w[/usr/bin/apt],
      "apt-get" => %w[/usr/bin/apt-get],
      "dnf" => %w[/usr/bin/dnf /usr/bin/dnf5],
      "zypper" => %w[/usr/bin/zypper],
      "apk" => %w[/sbin/apk /usr/sbin/apk],
      "flatpak" => %w[/usr/bin/flatpak],
      "snap" => %w[/usr/bin/snap],
      "nix" => %w[/usr/bin/nix /run/current-system/sw/bin/nix /nix/var/nix/profiles/default/bin/nix]
    }.freeze

    def initialize(
      root: Dir.pwd,
      process_env: ENV,
      runner: BoundedCommandRunner.new,
      clock: -> { Time.now.utc },
      ssh_config: File.expand_path("~/.ssh/config"),
      nmap_path: NMAP_PATH,
      ssh_path: SSH_PATH,
      ping_path: PING_PATH
    )
      @root = File.expand_path(root)
      @process_env = process_env.to_h.transform_keys(&:to_s)
      @runner = runner
      @clock = clock
      @ssh_config = File.expand_path(ssh_config)
      @nmap_path = File.expand_path(nmap_path)
      @ssh_path = File.expand_path(ssh_path)
      @ping_path = File.expand_path(ping_path)
      @state_root = File.join(@root, "Soul", "private", "host_maintenance")
      @registry_path = File.join(@state_root, "discovered_devices.json")
    end

    def status
      success(
        "schema_version" => SCHEMA_VERSION,
        "available" => File.file?(@nmap_path) && File.executable?(@nmap_path),
        "nmap_path" => @nmap_path,
        "maximum_hosts" => MAX_HOSTS,
        "subnet_bounds" => "/24../32 private IPv4 only",
        "registered_devices" => registry_records.length,
        "registry_private" => true,
        "background_scanning" => false,
        "mutation_authority" => false
      )
    end

    def discover(subnet:)
      network_info = private_network!(subnet)
      network = network_info.fetch("network")
      canonical_subnet = network_info.fetch("cidr")
      return failed("fleet discovery dependency is unavailable: install nmap") unless File.file?(@nmap_path) && File.executable?(@nmap_path)

      result = @runner.run(
        @nmap_path,
        "-sn",
        "-n",
        "--max-retries", "1",
        "--host-timeout", "2s",
        canonical_subnet,
        timeout_seconds: DISCOVERY_TIMEOUT_SECONDS,
        max_output_bytes: MAX_FILE_BYTES,
        env: {"LC_ALL" => "C"}
      )
      return failed("fleet discovery #{result.status}; no candidate state was written") unless result.status == "ok"

      known = known_addresses
      addresses = parse_nmap_addresses(result.stdout).select { |address| network.include?(IPAddr.new(address)) }
      candidates = addresses.first(MAX_HOSTS).map do |address|
        existing = known[address]
        {
          "candidate_id" => "candidate_#{Digest::SHA256.hexdigest(address)[0, 16]}",
          "address" => address,
          "state" => existing ? "already_configured" : "available",
          "known_device" => existing,
          "supported_enrollment_modes" => %w[status_only ssh],
          "trusted" => false,
          "mutation_authority" => false
        }
      end
      success(
        "schema_version" => SCHEMA_VERSION,
        "subnet" => canonical_subnet,
        "candidate_count" => candidates.length,
        "candidates" => candidates,
        "command" => {
          "adapter" => "nmap_ping_discovery",
          "status" => result.status,
          "exit_status" => result.exit_status,
          "truncated" => result.truncated == true,
          "timeout_seconds" => DISCOVERY_TIMEOUT_SECONDS
        },
        "persisted" => false,
        "background_scanning" => false,
        "mutation_authority" => false
      )
    rescue ArgumentError => error
      failed(error.message)
    end

    def registry
      success(
        "schema_version" => REGISTRY_SCHEMA,
        "devices" => registry_records,
        "device_count" => registry_records.length,
        "private" => true,
        "mutation_authority" => false
      )
    end

    def enrollment_preview(address:, label:, mode:, ssh_alias: nil)
      scope = enrollment_scope(address: address, label: label, mode: mode, ssh_alias: ssh_alias)
      success(
        "schema_version" => SCHEMA_VERSION,
        "device" => scope,
        "expected_digest" => digest(scope),
        "confirmation_phrase" => ENROLL_CONFIRMATION,
        "prospective_registry_mutation" => "one_private_record",
        "device_mutation" => "none"
      )
    rescue ArgumentError => error
      failed(error.message)
    end

    def enroll(address:, label:, mode:, ssh_alias: nil, confirmation:, expected_digest:)
      return awaiting("confirmation and preview digest are required") if confirmation.to_s.empty? || expected_digest.to_s.empty?
      return blocked("exact fleet enrollment confirmation is required") unless confirmation.to_s == ENROLL_CONFIRMATION

      preview = enrollment_preview(address: address, label: label, mode: mode, ssh_alias: ssh_alias)
      return preview unless preview["lifecycle_state"] == "complete"

      scope = preview.dig("data", "device")
      return blocked("fleet enrollment evidence changed; preview again") unless secure_compare(expected_digest.to_s, digest(scope))

      records = registry_records
      return blocked("fleet device is already enrolled") if records.any? { |record| record["id"] == scope["id"] || record["address"] == scope["address"] }
      return blocked("fleet registry reached its #{MAX_DEVICES}-device bound") if records.length >= MAX_DEVICES

      record = scope.merge("enrolled_at" => @clock.call.iso8601)
      persist_registry(records + [record])
      success(
        "schema_version" => REGISTRY_SCHEMA,
        "device" => record,
        "device_count" => records.length + 1,
        "registry_mutation" => "one_private_record",
        "device_mutation" => "none"
      )
    rescue ArgumentError => error
      failed(error.message)
    end

    def removal_preview(device_id:)
      record = registry_records.find { |candidate| candidate["id"] == device_id.to_s }
      return failed("enrolled fleet device was not found") unless record

      scope = {"device_id" => record.fetch("id"), "address" => record.fetch("address"), "label" => record.fetch("label")}
      success(
        "schema_version" => SCHEMA_VERSION,
        "device" => scope,
        "expected_digest" => digest(scope),
        "confirmation_phrase" => REMOVE_CONFIRMATION,
        "prospective_registry_mutation" => "remove_one_private_record",
        "device_mutation" => "none"
      )
    end

    def remove(device_id:, confirmation:, expected_digest:)
      return awaiting("confirmation and preview digest are required") if confirmation.to_s.empty? || expected_digest.to_s.empty?
      return blocked("exact fleet removal confirmation is required") unless confirmation.to_s == REMOVE_CONFIRMATION

      preview = removal_preview(device_id: device_id)
      return preview unless preview["lifecycle_state"] == "complete"

      scope = preview.dig("data", "device")
      return blocked("fleet removal evidence changed; preview again") unless secure_compare(expected_digest.to_s, digest(scope))

      records = registry_records
      retained = records.reject { |record| record["id"] == device_id.to_s }
      return failed("enrolled fleet device was not found") if retained.length == records.length

      persist_registry(retained)
      success(
        "schema_version" => REGISTRY_SCHEMA,
        "removed_device" => scope,
        "device_count" => retained.length,
        "registry_mutation" => "remove_one_private_record",
        "device_mutation" => "none"
      )
    end

    private

    def enrollment_scope(address:, label:, mode:, ssh_alias:)
      normalized_address = private_address!(address)
      normalized_label = label.to_s.strip
      raise ArgumentError, "fleet device label must be 1..80 characters" unless normalized_label.length.between?(1, 80)
      raise ArgumentError, "fleet device label contains unsupported control characters" if normalized_label.match?(/[[:cntrl:]]/)

      normalized_mode = mode.to_s
      raise ArgumentError, "fleet enrollment mode must be status_only or ssh" unless %w[status_only ssh].include?(normalized_mode)

      facts = if normalized_mode == "ssh"
                fingerprint_ssh(normalized_address, ssh_alias)
              else
                fingerprint_status_only(normalized_address)
              end
      normalized_alias = normalized_mode == "ssh" ? ssh_alias.to_s.strip : ""
      identity = [normalized_address, normalized_mode, normalized_alias].join("\0")
      {
        "id" => "managed_#{Digest::SHA256.hexdigest(identity)[0, 16]}",
        "label" => safe_text(normalized_label, 80),
        "address" => normalized_address,
        "connection_mode" => normalized_mode,
        "ssh_alias" => normalized_alias,
        "control" => "inventory_only",
        "role" => normalized_mode == "ssh" ? "Discovered Linux device · inventory only" : "Discovered local appliance · status only",
        "facts" => facts,
        "mutation_authority" => false
      }
    end

    def fingerprint_status_only(address)
      result = @runner.run(
        @ping_path, "-c", "1", "-W", "2", address,
        timeout_seconds: 5,
        max_output_bytes: 16 * 1024,
        env: {"LC_ALL" => "C"}
      )
      raise ArgumentError, "device did not answer the bounded enrollment reachability probe" unless result.status == "ok"

      {
        "platform" => "network_appliance",
        "os_id" => "unknown",
        "os_pretty_name" => "not queried",
        "kernel" => "not queried",
        "hostname" => "not queried",
        "package_managers" => [],
        "capability_probe" => "status_only",
        "reachability" => "reachable"
      }
    end

    def fingerprint_ssh(address, ssh_alias)
      alias_name = validated_ssh_alias!(ssh_alias)
      raise ArgumentError, "SSH alias must be one exact literal Host entry in #{@ssh_config}" unless literal_ssh_alias?(alias_name)
      resolved_address = resolved_ssh_hostname(alias_name)
      raise ArgumentError, "SSH alias must resolve to the selected candidate address" unless resolved_address == address

      hostname = first_ssh_output(alias_name, [%w[/usr/bin/hostname], %w[/bin/hostname]])
      kernel = first_ssh_output(alias_name, [%w[/usr/bin/uname -r], %w[/bin/uname -r]])
      os_release = first_ssh_output(alias_name, [%w[/usr/bin/cat /etc/os-release], %w[/bin/cat /etc/os-release]])
      raise ArgumentError, "SSH fingerprint could not collect fixed hostname, kernel, and OS evidence" if hostname.empty? || kernel.empty? || os_release.empty?

      values = parse_os_release(os_release)
      test_path = remote_test_path(alias_name)
      raise ArgumentError, "SSH fingerprint could not locate a fixed test executable" if test_path.empty?

      managers = PACKAGE_PATHS.filter_map do |manager, paths|
        manager if paths.any? { |path| ssh_success?(alias_name, test_path, "-x", path) }
      end
      {
        "platform" => "linux",
        "os_id" => safe_text(values["ID"], 80),
        "os_pretty_name" => safe_text(values["PRETTY_NAME"].to_s.empty? ? values["NAME"] : values["PRETTY_NAME"], 160),
        "kernel" => safe_text(kernel, 160),
        "hostname" => safe_text(hostname, 160),
        "package_managers" => managers,
        "capability_probe" => "fixed_ssh_inventory",
        "reachability" => "reachable",
        "address_assertion" => address,
        "ssh_target_verified" => true
      }
    end

    def resolved_ssh_hostname(alias_name)
      result = @runner.run(
        @ssh_path,
        "-G",
        "-F", @ssh_config,
        alias_name,
        timeout_seconds: SSH_TIMEOUT_SECONDS,
        max_output_bytes: 64 * 1024,
        env: {"LC_ALL" => "C"}
      )
      return "" unless result.status == "ok"

      value = result.stdout.to_s.lines.find { |line| line.match?(/\Ahostname\s+/i) }.to_s.split(/\s+/, 2).last.to_s.strip
      private_address!(value)
    rescue ArgumentError
      ""
    end

    def first_ssh_output(alias_name, command_options)
      command_options.each do |argv|
        result = ssh_run(alias_name, *argv)
        return result.stdout.to_s.strip if result.status == "ok" && !result.stdout.to_s.strip.empty?
      end
      ""
    end

    def remote_test_path(alias_name)
      %w[/usr/bin/test /bin/test].find { |path| ssh_success?(alias_name, path, "-x", path) }.to_s
    end

    def ssh_success?(alias_name, *argv)
      ssh_run(alias_name, *argv).status == "ok"
    end

    def ssh_run(alias_name, *argv)
      @runner.run(
        @ssh_path,
        "-F", @ssh_config,
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=5",
        "-o", "ConnectionAttempts=1",
        "-o", "LogLevel=ERROR",
        alias_name,
        *argv,
        timeout_seconds: SSH_TIMEOUT_SECONDS,
        max_output_bytes: 64 * 1024,
        env: {"LC_ALL" => "C"}
      )
    end

    def literal_ssh_alias?(alias_name)
      return false unless File.file?(@ssh_config) && File.size(@ssh_config) <= MAX_FILE_BYTES

      File.foreach(@ssh_config, encoding: "UTF-8").any? do |line|
        content = line.sub(/#.*/, "").strip
        next false unless content.match?(/\AHost\s+/i)

        content.split(/\s+/).drop(1).any? { |token| token == alias_name && !token.match?(/[*?!]/) }
      end
    rescue SystemCallError, EncodingError
      false
    end

    def validated_ssh_alias!(value)
      alias_name = value.to_s.strip
      raise ArgumentError, "SSH alias is required for ssh enrollment" if alias_name.empty?
      raise ArgumentError, "SSH alias is invalid" unless alias_name.match?(/\A[A-Za-z0-9][A-Za-z0-9_.-]{0,127}\z/)

      alias_name
    end

    def private_network!(value)
      text = value.to_s.strip
      raise ArgumentError, "fleet discovery subnet must use IPv4 CIDR notation" unless text.match?(%r{\A\d{1,3}(?:\.\d{1,3}){3}/\d{1,2}\z})

      network = IPAddr.new(text)
      prefix = Integer(text.split("/", 2).last)
      raise ArgumentError, "fleet discovery accepts private IPv4 only" unless network.ipv4? && private_ipv4?(network.to_range.first)
      raise ArgumentError, "fleet discovery subnet must be /24../32 (maximum #{MAX_HOSTS} addresses)" unless prefix.between?(24, 32)

      {
        "network" => network,
        "prefix" => prefix,
        "cidr" => "#{network.to_s}/#{prefix}"
      }
    rescue IPAddr::InvalidAddressError
      raise ArgumentError, "fleet discovery subnet is invalid"
    end

    def private_address!(value)
      text = value.to_s.strip
      address = IPAddr.new(text)
      raise ArgumentError, "fleet device address must be one private IPv4 address" unless address.ipv4? && private_ipv4?(address) && !text.include?("/")

      address.to_s
    rescue IPAddr::InvalidAddressError
      raise ArgumentError, "fleet device address is invalid"
    end

    def private_ipv4?(address)
      [
        IPAddr.new("10.0.0.0/8"),
        IPAddr.new("172.16.0.0/12"),
        IPAddr.new("192.168.0.0/16")
      ].any? { |network| network.include?(address) }
    end

    def parse_nmap_addresses(value)
      value.to_s.lines.filter_map do |line|
        match = line.strip.match(/\ANmap scan report for (\d{1,3}(?:\.\d{1,3}){3})\z/)
        next unless match

        IPAddr.new(match[1]).to_s
      rescue IPAddr::InvalidAddressError
        nil
      end.uniq.sort_by { |address| IPAddr.new(address).to_i }
    end

    def known_addresses
      configured = {
        @process_env["SOUL_FLEET_MAVEN_ADDRESS"] => "Maven",
        @process_env["SOUL_FLEET_FORGE_ADDRESS"] => "Forge",
        @process_env["SOUL_FLEET_PIHOLE_ADDRESS"] => "Pi-hole",
        @process_env["SOUL_FLEET_CISCO_PHONE_ADDRESS"] => @process_env.fetch("SOUL_FLEET_CISCO_PHONE_LABEL", "Cisco 8851")
      }
      configured.each_with_object({}) do |(address, label), memo|
        next unless address.to_s.match?(/\A\d{1,3}(?:\.\d{1,3}){3}\z/)

        memo[address.to_s] = safe_text(label, 80)
      end.merge(registry_records.to_h { |record| [record.fetch("address"), record.fetch("label")] })
    end

    def parse_os_release(value)
      value.to_s.lines.each_with_object({}) do |line, memo|
        key, raw = line.strip.split("=", 2)
        next unless key.to_s.match?(/\A[A-Z_]+\z/) && raw

        memo[key] = raw.sub(/\A["']/, "").sub(/["']\z/, "")
      end
    end

    def registry_records
      return [] unless File.exist?(@registry_path)
      return [] if File.symlink?(@registry_path)

      stat = File.stat(@registry_path)
      return [] unless stat.file? && (stat.mode & 0o077).zero? && stat.size <= MAX_FILE_BYTES

      parsed = JSON.parse(File.binread(@registry_path, MAX_FILE_BYTES + 1))
      return [] unless parsed["schema_version"] == REGISTRY_SCHEMA && parsed["devices"].is_a?(Array)

      parsed["devices"].first(MAX_DEVICES).filter_map { |record| normalized_registry_record(record) }
    rescue JSON::ParserError, SystemCallError
      []
    end

    def normalized_registry_record(record)
      return nil unless record.is_a?(Hash)
      return nil unless record["id"].to_s.match?(/\Amanaged_[a-f0-9]{16}\z/)
      return nil unless %w[status_only ssh].include?(record["connection_mode"])
      return nil unless record["label"].to_s.length.between?(1, 80) && !record["label"].to_s.match?(/[[:cntrl:]]/)
      return nil unless record["role"].to_s.length.between?(1, 160)
      return nil unless record["control"] == "inventory_only"
      return nil unless record["facts"].is_a?(Hash)
      return nil if record["connection_mode"] == "ssh" && !record["ssh_alias"].to_s.match?(/\A[A-Za-z0-9][A-Za-z0-9_.-]{0,127}\z/)

      private_address!(record["address"])
      record.slice(
        "id", "label", "address", "connection_mode", "ssh_alias", "control",
        "role", "facts", "mutation_authority", "enrolled_at"
      )
    rescue ArgumentError
      nil
    end

    def persist_registry(records)
      FileUtils.mkdir_p(@state_root, mode: 0o700)
      raise "fleet registry directory is unsafe" if File.symlink?(@state_root)

      File.chmod(0o700, @state_root)
      payload = JSON.pretty_generate(
        "schema_version" => REGISTRY_SCHEMA,
        "updated_at" => @clock.call.iso8601,
        "devices" => records
      )
      raise "fleet registry exceeds its size bound" if payload.bytesize > MAX_FILE_BYTES

      temporary = "#{@registry_path}.tmp-#{Process.pid}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(payload)
        file.flush
        file.fsync
      end
      File.rename(temporary, @registry_path)
      File.chmod(0o600, @registry_path)
    ensure
      File.delete(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
    end

    def digest(value)
      Digest::SHA256.hexdigest(JSON.generate(deep_sort(value)))
    end

    def deep_sort(value)
      case value
      when Hash then value.keys.sort.to_h { |key| [key, deep_sort(value.fetch(key))] }
      when Array then value.map { |item| deep_sort(item) }
      else value
      end
    end

    def secure_compare(left, right)
      return false unless left.bytesize == right.bytesize

      accumulator = 0
      left.bytes.zip(right.bytes) { |a, b| accumulator |= a ^ b }
      accumulator.zero?
    end

    def safe_text(value, limit)
      value.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "�").byteslice(0, limit).to_s
    end

    def success(data)
      {"ok" => true, "lifecycle_state" => "complete", "data" => data, "mutation" => data["registry_mutation"] || "none"}
    end

    def awaiting(reason)
      {"ok" => false, "lifecycle_state" => "awaiting_input", "reason" => reason, "data" => {}, "mutation" => "none"}
    end

    def blocked(reason)
      {"ok" => false, "lifecycle_state" => "blocked_for_human_review", "reason" => reason, "data" => {}, "mutation" => "none"}
    end

    def failed(reason)
      {"ok" => false, "lifecycle_state" => "failed", "reason" => safe_text(reason, 512), "data" => {}, "mutation" => "none"}
    end
  end
end
