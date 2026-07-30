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
    PREFERENCES_SCHEMA = "soul.maintenance.fleet_discovery_preferences.v1"
    IGNORED_SCHEMA = "soul.maintenance.fleet_ignored_devices.v1"
    NMAP_PATH = "/usr/bin/nmap"
    SSH_PATH = "/usr/bin/ssh"
    PING_PATH = "/usr/bin/ping"
    ARP_PATH = "/proc/net/arp"
    MAC_PREFIX_PATH = "/usr/share/nmap/nmap-mac-prefixes"
    MAX_HOSTS = 256
    MAX_DEVICES = 64
    MAX_FILE_BYTES = 256 * 1024
    MAX_MAC_PREFIX_BYTES = 2 * 1024 * 1024
    DISCOVERY_TIMEOUT_SECONDS = 30
    SSH_TIMEOUT_SECONDS = 5
    ENROLL_CONFIRMATION = "ENROLL_FLEET_DEVICE"
    REMOVE_CONFIRMATION = "REMOVE_FLEET_DEVICE"
    IGNORE_CONFIRMATION = "IGNORE_FLEET_CANDIDATE"
    RESTORE_CONFIRMATION = "RESTORE_FLEET_CANDIDATE"
    SSH_ALIAS_CONFIRMATION = "ADD_FLEET_SSH_ALIAS"
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
      ping_path: PING_PATH,
      arp_path: ARP_PATH,
      mac_prefix_path: MAC_PREFIX_PATH
    )
      @root = File.expand_path(root)
      @process_env = process_env.to_h.transform_keys(&:to_s)
      @runner = runner
      @clock = clock
      @ssh_config = File.expand_path(ssh_config)
      @nmap_path = File.expand_path(nmap_path)
      @ssh_path = File.expand_path(ssh_path)
      @ping_path = File.expand_path(ping_path)
      @arp_path = File.expand_path(arp_path)
      @mac_prefix_path = File.expand_path(mac_prefix_path)
      @state_root = File.join(@root, "Soul", "private", "host_maintenance")
      @registry_path = File.join(@state_root, "discovered_devices.json")
      @preferences_path = File.join(@state_root, "fleet_discovery_preferences.json")
      @ignored_path = File.join(@state_root, "ignored_devices.json")
    end

    def status
      success(
        "schema_version" => SCHEMA_VERSION,
        "available" => File.file?(@nmap_path) && File.executable?(@nmap_path),
        "nmap_path" => @nmap_path,
        "maximum_hosts" => MAX_HOSTS,
        "subnet_bounds" => "/24../32 private IPv4 only",
        "registered_devices" => registry_records.length,
        "ignored_devices" => ignored_records.length,
        "last_subnet" => discovery_preferences["last_subnet"],
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
      bounded_addresses = addresses.first(MAX_HOSTS)
      identity_hints = neighbor_identity_hints(bounded_addresses)
      ignored = ignored_records
      represented = bounded_addresses.filter_map do |address|
        label = known[address]
        {"address" => address, "known_device" => label} if label
      end
      ignored_detected = bounded_addresses.select do |address|
        ignored_match?(ignored, address, identity_hints.dig(address, "mac_address"))
      end
      candidates = bounded_addresses.reject do |address|
        known.key?(address) || ignored_detected.include?(address)
      end.map do |address|
        {
          "candidate_id" => "candidate_#{Digest::SHA256.hexdigest(address)[0, 16]}",
          "address" => address,
          "state" => "available",
          "known_device" => nil,
          "subnet" => canonical_subnet,
          "identity_hints" => identity_hints.fetch(address, {}),
          "supported_enrollment_modes" => %w[status_only ssh],
          "trusted" => false,
          "mutation_authority" => false
        }
      end
      persist_last_subnet(canonical_subnet)
      success(
        "schema_version" => SCHEMA_VERSION,
        "subnet" => canonical_subnet,
        "detected_count" => bounded_addresses.length,
        "candidate_count" => candidates.length,
        "candidates" => candidates,
        "represented_count" => represented.length,
        "represented" => represented,
        "ignored_count" => ignored_detected.length,
        "preference_persisted" => true,
        "preference_mutation" => "last_subnet",
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

    def ignored
      success(
        "schema_version" => IGNORED_SCHEMA,
        "devices" => ignored_records,
        "device_count" => ignored_records.length,
        "private" => true,
        "mutation_authority" => false
      )
    end

    def ignore_preview(address:, label:, subnet:, mac_address: nil, vendor: nil)
      scope = ignored_scope(
        address: address,
        label: label,
        subnet: subnet,
        mac_address: mac_address,
        vendor: vendor
      )
      success(
        "schema_version" => SCHEMA_VERSION,
        "device" => scope,
        "expected_digest" => digest(scope),
        "confirmation_phrase" => IGNORE_CONFIRMATION,
        "prospective_registry_mutation" => "ignore_one_candidate",
        "device_mutation" => "none"
      )
    rescue ArgumentError => error
      failed(error.message)
    end

    def ignore(address:, label:, subnet:, mac_address: nil, vendor: nil, confirmation:, expected_digest:)
      return awaiting("confirmation and preview digest are required") if confirmation.to_s.empty? || expected_digest.to_s.empty?
      return blocked("exact candidate ignore confirmation is required") unless confirmation.to_s == IGNORE_CONFIRMATION

      preview = ignore_preview(address: address, label: label, subnet: subnet, mac_address: mac_address, vendor: vendor)
      return preview unless preview["lifecycle_state"] == "complete"

      scope = preview.dig("data", "device")
      return blocked("ignored candidate evidence changed; preview again") unless secure_compare(expected_digest.to_s, digest(scope))

      records = ignored_records
      return blocked("candidate identity is already ignored") if records.any? { |record| record["identity_key"] == scope["identity_key"] }
      return blocked("ignored device list reached its #{MAX_DEVICES}-record bound") if records.length >= MAX_DEVICES

      record = scope.merge("ignored_at" => @clock.call.iso8601)
      persist_ignored(records + [record])
      success(
        "schema_version" => IGNORED_SCHEMA,
        "device" => record,
        "device_count" => records.length + 1,
        "registry_mutation" => "ignore_one_candidate",
        "device_mutation" => "none"
      )
    rescue ArgumentError => error
      failed(error.message)
    end

    def restore_preview(identity_key:)
      record = ignored_records.find { |candidate| candidate["identity_key"] == identity_key.to_s }
      return failed("ignored fleet candidate was not found") unless record

      scope = record.slice("identity_key", "label", "address", "mac_address", "subnet")
      success(
        "schema_version" => SCHEMA_VERSION,
        "device" => scope,
        "expected_digest" => digest(scope),
        "confirmation_phrase" => RESTORE_CONFIRMATION,
        "prospective_registry_mutation" => "restore_one_candidate",
        "device_mutation" => "none"
      )
    end

    def restore(identity_key:, confirmation:, expected_digest:)
      return awaiting("confirmation and preview digest are required") if confirmation.to_s.empty? || expected_digest.to_s.empty?
      return blocked("exact candidate restore confirmation is required") unless confirmation.to_s == RESTORE_CONFIRMATION

      preview = restore_preview(identity_key: identity_key)
      return preview unless preview["lifecycle_state"] == "complete"

      scope = preview.dig("data", "device")
      return blocked("ignored candidate evidence changed; preview again") unless secure_compare(expected_digest.to_s, digest(scope))

      records = ignored_records
      retained = records.reject { |record| record["identity_key"] == identity_key.to_s }
      return failed("ignored fleet candidate was not found") if retained.length == records.length

      persist_ignored(retained)
      success(
        "schema_version" => IGNORED_SCHEMA,
        "restored_device" => scope,
        "device_count" => retained.length,
        "registry_mutation" => "restore_one_candidate",
        "device_mutation" => "none"
      )
    end

    def enrollment_preview(address:, label:, mode:, ssh_alias: nil, address_policy: "fixed", subnet: nil, mac_address: nil)
      scope = enrollment_scope(
        address: address,
        label: label,
        mode: mode,
        ssh_alias: ssh_alias,
        address_policy: address_policy,
        subnet: subnet,
        mac_address: mac_address
      )
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

    def ssh_alias_preview(address:, ssh_alias:, ssh_user:, identity_file:)
      scope = ssh_alias_scope(
        address: address,
        ssh_alias: ssh_alias,
        ssh_user: ssh_user,
        identity_file: identity_file
      )
      success(
        "schema_version" => SCHEMA_VERSION,
        "ssh_alias" => scope,
        "expected_digest" => digest(scope),
        "confirmation_phrase" => SSH_ALIAS_CONFIRMATION,
        "prospective_ssh_config_mutation" => "append_one_literal_host",
        "device_mutation" => "none",
        "credentials_stored" => false
      )
    rescue ArgumentError => error
      failed(error.message)
    end

    def add_ssh_alias(address:, ssh_alias:, ssh_user:, identity_file:, confirmation:, expected_digest:)
      return awaiting("confirmation and preview digest are required") if confirmation.to_s.empty? || expected_digest.to_s.empty?
      return blocked("exact SSH alias confirmation is required") unless confirmation.to_s == SSH_ALIAS_CONFIRMATION

      preview = ssh_alias_preview(
        address: address,
        ssh_alias: ssh_alias,
        ssh_user: ssh_user,
        identity_file: identity_file
      )
      return preview unless preview["lifecycle_state"] == "complete"

      scope = preview.dig("data", "ssh_alias")
      return blocked("SSH config evidence changed; preview the alias again") unless secure_compare(expected_digest.to_s, digest(scope))

      append_ssh_alias(scope)
      success(
        "schema_version" => SCHEMA_VERSION,
        "ssh_alias" => scope.reject { |key, _value| key == "config_digest" },
        "ssh_config_mutation" => "append_one_literal_host",
        "device_mutation" => "none",
        "credentials_stored" => false
      )
    rescue ArgumentError => error
      failed(error.message)
    rescue SystemCallError => error
      failed("SSH alias could not be written safely: #{error.class}")
    end

    def enroll(address:, label:, mode:, ssh_alias: nil, address_policy: "fixed", subnet: nil, mac_address: nil, confirmation:, expected_digest:)
      return awaiting("confirmation and preview digest are required") if confirmation.to_s.empty? || expected_digest.to_s.empty?
      return blocked("exact fleet enrollment confirmation is required") unless confirmation.to_s == ENROLL_CONFIRMATION

      preview = enrollment_preview(
        address: address,
        label: label,
        mode: mode,
        ssh_alias: ssh_alias,
        address_policy: address_policy,
        subnet: subnet,
        mac_address: mac_address
      )
      return preview unless preview["lifecycle_state"] == "complete"

      scope = preview.dig("data", "device")
      return blocked("fleet enrollment evidence changed; preview again") unless secure_compare(expected_digest.to_s, digest(scope))

      records = registry_records
      return blocked("fleet device is already enrolled") if records.any? do |record|
        record["id"] == scope["id"] ||
          record["address"] == scope["address"] ||
          (!scope["mac_address"].to_s.empty? && record["mac_address"] == scope["mac_address"])
      end
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

    def ssh_alias_scope(address:, ssh_alias:, ssh_user:, identity_file:)
      normalized_address = private_address!(address)
      alias_name = validated_ssh_alias!(ssh_alias)
      raise ArgumentError, "SSH alias already exists as a literal Host entry" if literal_ssh_alias?(alias_name)

      user = ssh_user.to_s.strip
      raise ArgumentError, "SSH user must be one portable account name" unless user.match?(/\A[a-z_][a-z0-9_-]{0,31}\z/i)

      identity = validated_identity_file!(identity_file)
      config_digest = current_ssh_config_digest
      block = [
        "Host #{alias_name}",
        "    HostName #{normalized_address}",
        "    User #{user}",
        "    IdentityFile #{identity.fetch("display")}",
        "    IdentitiesOnly yes",
        "    BatchMode yes",
        "    PasswordAuthentication no",
        "    StrictHostKeyChecking yes",
        "    ServerAliveInterval 30",
        "    ServerAliveCountMax 3"
      ].join("\n")
      {
        "alias" => alias_name,
        "hostname" => normalized_address,
        "user" => user,
        "identity_file" => identity.fetch("display"),
        "config_digest" => config_digest,
        "stanza" => block
      }
    end

    def validated_identity_file!(value)
      display = value.to_s.strip
      raise ArgumentError, "SSH identity file is required" if display.empty?
      raise ArgumentError, "SSH identity file contains unsupported characters" unless display.match?(%r{\A(?:~/\.ssh/|/)[A-Za-z0-9_./-]+\z})

      expanded = File.expand_path(display)
      ssh_root = File.realpath(File.dirname(@ssh_config))
      resolved = File.realpath(expanded)
      raise ArgumentError, "SSH identity file must remain under the owner SSH directory" unless resolved.start_with?("#{ssh_root}/")
      raise ArgumentError, "SSH identity file must be a regular non-symlink file" unless File.file?(expanded) && !File.symlink?(expanded)
      raise ArgumentError, "SSH identity file must be owned by the current user" unless File.stat(expanded).uid == Process.uid
      raise ArgumentError, "SSH identity file permissions must exclude group and other access" unless (File.stat(expanded).mode & 0o077).zero?

      {"display" => display, "resolved" => resolved}
    rescue Errno::ENOENT, Errno::EACCES
      raise ArgumentError, "SSH identity file must already exist under the owner SSH directory"
    end

    def current_ssh_config_digest
      raise ArgumentError, "owner SSH config is unavailable" unless File.file?(@ssh_config) && !File.symlink?(@ssh_config)
      raise ArgumentError, "owner SSH config exceeds the bounded size" if File.size(@ssh_config) > MAX_FILE_BYTES
      raise ArgumentError, "owner SSH config must be owned by the current user" unless File.stat(@ssh_config).uid == Process.uid
      raise ArgumentError, "owner SSH config permissions must exclude group and other access" unless (File.stat(@ssh_config).mode & 0o077).zero?

      Digest::SHA256.hexdigest(File.binread(@ssh_config))
    end

    def append_ssh_alias(scope)
      raise ArgumentError, "SSH alias already exists as a literal Host entry" if literal_ssh_alias?(scope.fetch("alias"))
      raise ArgumentError, "SSH config evidence changed; preview the alias again" unless secure_compare(scope.fetch("config_digest"), current_ssh_config_digest)

      directory = File.dirname(@ssh_config)
      temporary = File.join(directory, ".#{File.basename(@ssh_config)}.soul-#{Process.pid}-#{Thread.current.object_id}")
      content = File.binread(@ssh_config)
      content = "#{content}\n" unless content.empty? || content.end_with?("\n")
      content = "#{content}\n#{scope.fetch("stanza")}\n"
      raise ArgumentError, "resulting SSH config exceeds the bounded size" if content.bytesize > MAX_FILE_BYTES

      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(content)
        file.flush
        file.fsync
      end
      File.rename(temporary, @ssh_config)
      File.chmod(0o600, @ssh_config)
    ensure
      File.delete(temporary) if temporary && File.exist?(temporary)
    end

    def ignored_scope(address:, label:, subnet:, mac_address:, vendor:)
      normalized_address = private_address!(address)
      network = private_network!(subnet)
      raise ArgumentError, "ignored candidate address is outside the reviewed subnet" unless network.fetch("network").include?(IPAddr.new(normalized_address))

      normalized_label = label.to_s.strip
      raise ArgumentError, "ignored candidate label must be 1..80 characters" unless normalized_label.length.between?(1, 80)
      raise ArgumentError, "ignored candidate label contains unsupported control characters" if normalized_label.match?(/[[:cntrl:]]/)

      normalized_mac = normalize_mac(mac_address)
      identity_key = normalized_mac.empty? ? "ip:#{normalized_address}" : "mac:#{normalized_mac}"
      {
        "identity_key" => identity_key,
        "label" => safe_text(normalized_label, 80),
        "address" => normalized_address,
        "mac_address" => normalized_mac,
        "vendor" => safe_text(vendor, 120),
        "subnet" => network.fetch("cidr")
      }
    end

    def enrollment_scope(address:, label:, mode:, ssh_alias:, address_policy:, subnet:, mac_address:)
      normalized_address = private_address!(address)
      normalized_label = label.to_s.strip
      raise ArgumentError, "fleet device label must be 1..80 characters" unless normalized_label.length.between?(1, 80)
      raise ArgumentError, "fleet device label contains unsupported control characters" if normalized_label.match?(/[[:cntrl:]]/)

      normalized_mode = mode.to_s
      raise ArgumentError, "fleet enrollment mode must be status_only or ssh" unless %w[status_only ssh].include?(normalized_mode)
      normalized_policy = address_policy.to_s
      raise ArgumentError, "address policy must be fixed or dhcp_tracked" unless %w[fixed dhcp_tracked].include?(normalized_policy)
      raise ArgumentError, "DHCP tracking is available only for status-only devices" if normalized_policy == "dhcp_tracked" && normalized_mode != "status_only"

      normalized_mac = normalized_policy == "dhcp_tracked" ? normalize_mac(mac_address) : ""
      raise ArgumentError, "DHCP tracking requires reviewed MAC evidence" if normalized_policy == "dhcp_tracked" && normalized_mac.empty?
      normalized_subnet = if normalized_policy == "dhcp_tracked"
                            network = private_network!(subnet)
                            raise ArgumentError, "device address is outside the reviewed DHCP subnet" unless network.fetch("network").include?(IPAddr.new(normalized_address))

                            network.fetch("cidr")
                          else
                            ""
                          end

      facts = if normalized_mode == "ssh"
                fingerprint_ssh(normalized_address, ssh_alias)
              else
                fingerprint_status_only(normalized_address)
              end
      normalized_alias = normalized_mode == "ssh" ? ssh_alias.to_s.strip : ""
      identity = if normalized_policy == "dhcp_tracked"
                   [normalized_mac, normalized_mode, normalized_policy].join("\0")
                 else
                   [normalized_address, normalized_mode, normalized_alias].join("\0")
                 end
      {
        "id" => "managed_#{Digest::SHA256.hexdigest(identity)[0, 16]}",
        "label" => safe_text(normalized_label, 80),
        "address" => normalized_address,
        "connection_mode" => normalized_mode,
        "address_policy" => normalized_policy,
        "mac_address" => normalized_mac,
        "subnet" => normalized_subnet,
        "address_history" => [],
        "ssh_alias" => normalized_alias,
        "inventory_adapter" => "",
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

    def neighbor_identity_hints(addresses)
      return {} unless File.file?(@arp_path) && !File.symlink?(@arp_path)
      wanted = addresses.to_h { |address| [address, true] }
      selected = File.foreach(@arp_path, encoding: "UTF-8").first(MAX_HOSTS * 4 + 1).drop(1).filter_map do |line|
        address, _hardware_type, flags, raw_mac, _mask, interface = line.split(/\s+/, 6)
        next unless wanted[address]

        mac = raw_mac.to_s.downcase
        next unless mac.match?(/\A[0-9a-f]{2}(?::[0-9a-f]{2}){5}\z/)

        [{"dst" => address, "dev" => interface.to_s.strip, "flags" => flags}, mac]
      end
      vendors = mac_vendors(selected.map(&:last))
      selected.to_h do |row, mac|
        locally_administered = (mac[0, 2].to_i(16) & 0x02).positive?
        hint = {
          "mac_address" => mac,
          "vendor" => locally_administered ? "Locally administered address" : vendors[mac.delete(":")[0, 6].upcase],
          "interface" => safe_text(row["dev"], 32),
          "neighbor_state" => [row["flags"] == "0x2" ? "ARP cached" : "ARP incomplete"]
        }.compact
        [row.fetch("dst"), hint]
      end
    rescue SystemCallError
      {}
    end

    def mac_vendors(addresses)
      prefixes = addresses.filter_map do |mac|
        next if (mac[0, 2].to_i(16) & 0x02).positive?

        mac.delete(":")[0, 6].upcase
      end.uniq
      return {} if prefixes.empty?
      return {} unless File.file?(@mac_prefix_path) && !File.symlink?(@mac_prefix_path)
      return {} if File.size(@mac_prefix_path) > MAX_MAC_PREFIX_BYTES

      wanted = prefixes.to_h { |prefix| [prefix, true] }
      File.foreach(@mac_prefix_path, encoding: "UTF-8").each_with_object({}) do |line, vendors|
        match = line.match(/\A([0-9A-F]{6})\s+(.+?)\s*\z/)
        next unless match && wanted[match[1]]

        vendors[match[1]] = safe_text(match[2], 120)
        break vendors if vendors.length == wanted.length
      end
    rescue SystemCallError
      {}
    end

    def known_addresses
      workstation_address = configured_value("SOUL_FLEET_WORKSTATION_ADDRESS", "SOUL_FLEET_MAVEN_ADDRESS")
      workstation_label = configured_value("SOUL_FLEET_WORKSTATION_LABEL", "SOUL_FLEET_MAVEN_LABEL", fallback: "Workstation")
      configured = {
        workstation_address => workstation_label,
        @process_env["SOUL_FLEET_FORGE_ADDRESS"] => "Forge",
        @process_env["SOUL_FLEET_PIHOLE_ADDRESS"] => @process_env.fetch("SOUL_FLEET_PIHOLE_LABEL", "Pi-hole"),
        @process_env["SOUL_FLEET_CISCO_PHONE_ADDRESS"] => @process_env.fetch("SOUL_FLEET_CISCO_PHONE_LABEL", "Cisco 8851")
      }
      configured.each_with_object({}) do |(address, label), memo|
        next unless address.to_s.match?(/\A\d{1,3}(?:\.\d{1,3}){3}\z/)

        memo[address.to_s] = safe_text(label, 80)
      end.merge(registry_records.to_h { |record| [record.fetch("address"), record.fetch("label")] })
    end

    def configured_value(key, legacy_key, fallback: "")
      value = @process_env[key].to_s.strip
      value = @process_env[legacy_key].to_s.strip if value.empty?
      value.empty? ? fallback : value
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

    def ignored_records
      return [] unless File.exist?(@ignored_path)
      return [] if File.symlink?(@ignored_path)

      stat = File.stat(@ignored_path)
      return [] unless stat.file? && (stat.mode & 0o077).zero? && stat.size <= MAX_FILE_BYTES

      parsed = JSON.parse(File.binread(@ignored_path, MAX_FILE_BYTES + 1))
      return [] unless parsed["schema_version"] == IGNORED_SCHEMA && parsed["devices"].is_a?(Array)

      parsed["devices"].first(MAX_DEVICES).filter_map do |record|
        next unless record.is_a?(Hash)
        next unless record["identity_key"].to_s.match?(/\A(?:mac:[0-9a-f]{2}(?::[0-9a-f]{2}){5}|ip:\d{1,3}(?:\.\d{1,3}){3})\z/)
        next unless record["label"].to_s.length.between?(1, 80)
        next unless record["subnet"].to_s.length.between?(9, 18)

        private_address!(record["address"])
        private_network!(record["subnet"])
        mac = normalize_mac(record["mac_address"])
        next if record["identity_key"].start_with?("mac:") && "mac:#{mac}" != record["identity_key"]

        record.slice("identity_key", "label", "address", "mac_address", "vendor", "subnet", "ignored_at")
      end
    rescue JSON::ParserError, SystemCallError, ArgumentError
      []
    end

    def ignored_match?(records, address, mac_address)
      normalized_mac = normalize_mac(mac_address)
      records.any? do |record|
        if record["identity_key"].start_with?("mac:")
          !normalized_mac.empty? && record["mac_address"] == normalized_mac
        else
          record["address"] == address
        end
      end
    end

    def persist_ignored(records)
      FileUtils.mkdir_p(@state_root, mode: 0o700)
      raise "ignored device directory is unsafe" if File.symlink?(@state_root)

      File.chmod(0o700, @state_root)
      payload = JSON.pretty_generate(
        "schema_version" => IGNORED_SCHEMA,
        "updated_at" => @clock.call.iso8601,
        "devices" => records
      )
      raise "ignored device list exceeds its size bound" if payload.bytesize > MAX_FILE_BYTES

      temporary = "#{@ignored_path}.tmp-#{Process.pid}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(payload)
        file.flush
        file.fsync
      end
      File.rename(temporary, @ignored_path)
      File.chmod(0o600, @ignored_path)
    ensure
      File.delete(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
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
      policy = record["address_policy"].to_s.empty? ? "fixed" : record["address_policy"].to_s
      return nil unless %w[fixed dhcp_tracked].include?(policy)
      return nil if policy == "dhcp_tracked" && record["connection_mode"] != "status_only"
      mac = policy == "dhcp_tracked" ? normalize_mac(record["mac_address"]) : ""
      return nil if policy == "dhcp_tracked" && mac.empty?
      subnet = policy == "dhcp_tracked" ? private_network!(record["subnet"]).fetch("cidr") : ""
      history = Array(record["address_history"]).first(8).filter_map do |event|
        next unless event.is_a?(Hash)
        next unless event["from"].to_s.match?(/\A\d{1,3}(?:\.\d{1,3}){3}\z/) && event["to"].to_s.match?(/\A\d{1,3}(?:\.\d{1,3}){3}\z/)

        event.slice("from", "to", "changed_at", "reason")
      end
      normalized = record.slice(
        "id", "label", "address", "connection_mode", "ssh_alias", "control",
        "role", "facts", "mutation_authority", "enrolled_at", "inventory_adapter"
      )
      normalized.merge(
        "address_policy" => policy,
        "mac_address" => mac,
        "subnet" => subnet,
        "address_history" => history,
        "inventory_adapter" => record["inventory_adapter"] == "apple_mobile" ? "apple_mobile" : ""
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

    def discovery_preferences
      return {} unless File.file?(@preferences_path) && !File.symlink?(@preferences_path)
      return {} if File.size(@preferences_path) > 16 * 1024

      parsed = JSON.parse(File.binread(@preferences_path, 16 * 1024 + 1))
      return {} unless parsed["schema_version"] == PREFERENCES_SCHEMA

      subnet = parsed["last_subnet"].to_s
      return {} unless private_network!(subnet).fetch("cidr") == subnet

      {"last_subnet" => subnet}
    rescue JSON::ParserError, SystemCallError, ArgumentError
      {}
    end

    def persist_last_subnet(subnet)
      FileUtils.mkdir_p(@state_root, mode: 0o700)
      raise "fleet discovery preference directory is unsafe" if File.symlink?(@state_root)

      File.chmod(0o700, @state_root)
      payload = JSON.pretty_generate(
        "schema_version" => PREFERENCES_SCHEMA,
        "updated_at" => @clock.call.iso8601,
        "last_subnet" => subnet
      )
      temporary = "#{@preferences_path}.tmp-#{Process.pid}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(payload)
        file.flush
        file.fsync
      end
      File.rename(temporary, @preferences_path)
      File.chmod(0o600, @preferences_path)
    ensure
      File.delete(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
    end

    def digest(value)
      Digest::SHA256.hexdigest(JSON.generate(deep_sort(value)))
    end

    def normalize_mac(value)
      mac = value.to_s.strip.downcase
      return "" if mac.empty?
      raise ArgumentError, "MAC address is invalid" unless mac.match?(/\A[0-9a-f]{2}(?::[0-9a-f]{2}){5}\z/)

      mac
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
      mutation = data["registry_mutation"] || data["preference_mutation"] || data["ssh_config_mutation"] || "none"
      {"ok" => true, "lifecycle_state" => "complete", "data" => data, "mutation" => mutation}
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
