# frozen_string_literal: true

require "json"
require "open3"
require "socket"
require "time"
require "timeout"

module SoulCore
  class HostSystemStatusCollector
    SCOPE = "Bounded read-only Linux host environment assessment"

    DEFAULT_NOT_COLLECTED = [
      "SMART device health",
      "storage-device temperatures",
      "hardware RAID controller state",
      "ZFS pool health",
      "firewall policy",
      "authentication logs",
      "scheduled jobs",
      "package update state",
      "external network reachability",
      "application process health beyond systemd summary"
    ].freeze

    PSEUDO_FILESYSTEMS = %w[
      autofs
      bpf
      cgroup
      cgroup2
      configfs
      debugfs
      devpts
      devtmpfs
      efivarfs
      fusectl
      hugetlbfs
      mqueue
      overlay
      proc
      pstore
      securityfs
      sysfs
      tmpfs
      tracefs
    ].freeze

    CommandResult = Struct.new(
      :argv,
      :stdout,
      :stderr,
      :exit_status,
      :status,
      :elapsed_ms,
      keyword_init: true
    ) do
      def ok?
        status == "ok"
      end

      def to_h
        {
          "argv" => argv,
          "status" => status,
          "exit_status" => exit_status,
          "elapsed_ms" => elapsed_ms,
          "stderr" => stderr.to_s.strip.empty? ? nil : stderr.to_s.strip
        }.reject { |_key, value| value.nil? }
      end
    end

    class CommandRunner
      def run(argv, timeout_seconds: 3.0)
        command = Array(argv).map(&:to_s)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        stdout = ""
        stderr = ""
        process_status = nil

        Timeout.timeout(timeout_seconds.to_f) do
          stdout, stderr, process_status = Open3.capture3(*command)
        end

        status = process_status.success? ? "ok" : "failed"
        CommandResult.new(
          argv: command,
          stdout: stdout,
          stderr: stderr,
          exit_status: process_status.exitstatus,
          status: status,
          elapsed_ms: elapsed_ms(started)
        )
      rescue Timeout::Error => error
        CommandResult.new(
          argv: command,
          stdout: "",
          stderr: error.message,
          exit_status: nil,
          status: "timeout",
          elapsed_ms: elapsed_ms(started)
        )
      rescue Errno::ENOENT => error
        CommandResult.new(
          argv: command,
          stdout: "",
          stderr: error.message,
          exit_status: nil,
          status: "unavailable",
          elapsed_ms: elapsed_ms(started)
        )
      rescue StandardError => error
        CommandResult.new(
          argv: command,
          stdout: "",
          stderr: "#{error.class}: #{error.message}",
          exit_status: nil,
          status: "failed",
          elapsed_ms: elapsed_ms(started)
        )
      end

      private

      def elapsed_ms(started)
        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2)
      end
    end

    def initialize(
      runner: CommandRunner.new,
      file_reader: nil,
      hostname_reader: nil,
      clock: -> { Time.now }
    )
      @runner = runner
      @file_reader = file_reader || method(:safe_file_read)
      @hostname_reader = hostname_reader || -> { Socket.gethostname }
      @clock = clock
      @command_results = []
      @dynamic_not_collected = []
    end

    def collect
      @command_results = []
      @dynamic_not_collected = []

      os = collect_operating_system
      kernel = collect_kernel
      uptime = collect_uptime
      load = collect_load
      memory = collect_memory
      filesystems = collect_filesystems
      block_devices = collect_block_devices
      network_interfaces = collect_network_interfaces
      systemd = collect_systemd
      mdraid = collect_mdraid

      collected = {
        "host" => {
          "hostname" => safe_hostname
        },
        "operating_system" => os,
        "kernel" => kernel,
        "uptime" => uptime,
        "load" => load,
        "memory" => memory,
        "filesystems" => filesystems,
        "block_devices" => block_devices,
        "network_interfaces" => network_interfaces,
        "systemd" => systemd,
        "linux_mdraid" => mdraid
      }.reject { |_key, value| blank_collection?(value) }

      claims = build_claims(collected)
      not_collected = (DEFAULT_NOT_COLLECTED + @dynamic_not_collected).uniq

      {
        "ok" => !claims.empty?,
        "assessment" => "host_system_status",
        "scope" => SCOPE,
        "collected_at" => @clock.call.iso8601,
        "collected" => collected,
        "claims" => claims,
        "not_collected" => not_collected,
        "commands" => @command_results.map(&:to_h),
        "verification" => {
          "read_only" => true,
          "shell_interpolation_used" => false,
          "bounded_commands" => true,
          "secrets_collected" => false,
          "mac_addresses_collected" => false,
          "ip_addresses_collected" => false,
          "smart_collected" => false,
          "firewall_collected" => false,
          "auth_logs_collected" => false,
          "scheduled_jobs_collected" => false
        }
      }
    end

    private

    def collect_operating_system
      content = @file_reader.call("/etc/os-release").to_s
      return {} if content.empty?

      values = {}
      content.each_line do |line|
        key, value = line.strip.split("=", 2)
        next if key.to_s.empty? || value.nil?

        values[key] = value.sub(/\A["']/, "").sub(/["']\z/, "")
      end

      {
        "name" => values["NAME"],
        "pretty_name" => values["PRETTY_NAME"],
        "id" => values["ID"],
        "version_id" => values["VERSION_ID"]
      }.reject { |_key, value| value.to_s.empty? }
    end

    def collect_kernel
      result = run(%w[uname -srmo])
      return {} unless result.ok?

      {
        "summary" => result.stdout.to_s.strip
      }
    end

    def collect_uptime
      content = @file_reader.call("/proc/uptime").to_s
      seconds = content.split.first.to_f
      return {} unless seconds.positive?

      {
        "seconds" => seconds.round(2),
        "human" => format_duration(seconds)
      }
    end

    def collect_load
      content = @file_reader.call("/proc/loadavg").to_s
      values = content.split.first(3).map { |value| Float(value) rescue nil }
      return {} if values.compact.empty?

      {
        "one_minute" => values[0],
        "five_minutes" => values[1],
        "fifteen_minutes" => values[2]
      }.reject { |_key, value| value.nil? }
    end

    def collect_memory
      content = @file_reader.call("/proc/meminfo").to_s
      return {} if content.empty?

      values = {}
      content.each_line do |line|
        key, rest = line.split(":", 2)
        next if key.to_s.empty? || rest.nil?

        kilobytes = rest.to_s.scan(/\d+/).first.to_i
        values[key] = kilobytes * 1024
      end

      total = values["MemTotal"]
      available = values["MemAvailable"]
      used = total && available ? total - available : nil

      {
        "total_bytes" => total,
        "available_bytes" => available,
        "used_bytes" => used,
        "used_percent" => total.to_i.positive? && used ? ((used.to_f / total) * 100).round(1) : nil
      }.reject { |_key, value| value.nil? }
    end

    def collect_filesystems
      result = run(%w[findmnt --json --bytes -o TARGET,SOURCE,FSTYPE,SIZE,USED,AVAIL,USE%])
      if result.ok?
        parsed = parse_json(result.stdout)
        entries = flatten_findmnt(parsed.fetch("filesystems", []))
        return normalize_filesystems(entries)
      end

      @dynamic_not_collected << "mounted filesystem inventory through findmnt"
      fallback = run(%w[df -B1 -T -x tmpfs -x devtmpfs])
      return [] unless fallback.ok?

      parse_df(fallback.stdout)
    end

    def collect_block_devices
      result = run(
        %w[
          lsblk
          --json
          --bytes
          -o
          NAME,KNAME,TYPE,SIZE,FSTYPE,MOUNTPOINTS,MODEL,ROTA,TRAN
        ]
      )

      unless result.ok?
        result = run(%w[lsblk --json --bytes -o NAME,KNAME,TYPE,SIZE,FSTYPE,MOUNTPOINTS])
      end

      unless result.ok?
        @dynamic_not_collected << "block-device inventory through lsblk"
        return []
      end

      parsed = parse_json(result.stdout)
      flatten_lsblk(parsed.fetch("blockdevices", [])).map do |entry|
        {
          "name" => entry["name"],
          "kernel_name" => entry["kname"],
          "type" => entry["type"],
          "size_bytes" => integer_or_nil(entry["size"]),
          "filesystem_type" => entry["fstype"],
          "mountpoints" => Array(entry["mountpoints"]).compact,
          "model" => clean_string(entry["model"]),
          "rotational" => boolean_from_number(entry["rota"]),
          "transport" => entry["tran"]
        }.reject { |_key, value| value.nil? || value == [] || value == "" }
      end
    end

    def collect_network_interfaces
      result = run(%w[ip -j link show])
      unless result.ok?
        @dynamic_not_collected << "network-interface link state through iproute2"
        return []
      end

      parse_json(result.stdout).map do |entry|
        {
          "name" => entry["ifname"],
          "state" => entry["operstate"],
          "mtu" => integer_or_nil(entry["mtu"]),
          "link_type" => entry["link_type"]
        }.reject { |_key, value| value.nil? || value == "" }
      end
    end

    def collect_systemd
      state_result = run(%w[systemctl is-system-running])
      failed_result = run(%w[systemctl --failed --no-legend --plain])

      if !state_result.ok? && state_result.status == "unavailable"
        @dynamic_not_collected << "systemd runtime state"
        return {}
      end

      failed_units =
        if failed_result.ok?
          failed_result.stdout.lines.map do |line|
            line.strip.split(/\s+/, 2).first
          end.reject(&:empty?)
        else
          []
        end

      {
        "state" => state_result.stdout.to_s.strip.empty? ? nil : state_result.stdout.to_s.strip,
        "failed_unit_count" => failed_units.length,
        "failed_units" => failed_units.first(25)
      }.reject { |_key, value| value.nil? || value == [] }
    end

    def collect_mdraid
      content = @file_reader.call("/proc/mdstat").to_s
      if content.empty?
        @dynamic_not_collected << "Linux MD RAID state from /proc/mdstat"
        return {}
      end

      arrays = content.each_line.filter_map do |line|
        match = line.match(/\A(md\S+)\s*:\s*(\S+)\s*(.*)\z/)
        next unless match

        {
          "name" => match[1],
          "state" => match[2],
          "members" => match[3].split.select { |token| token.include?("[") }
        }
      end

      {
        "source" => "/proc/mdstat",
        "active_array_count" => arrays.length,
        "arrays" => arrays
      }
    end

    def build_claims(collected)
      claims = []

      hostname = collected.dig("host", "hostname")
      claims << "Hostname: #{hostname}." unless hostname.to_s.empty?

      os_name = collected.dig("operating_system", "pretty_name") ||
                collected.dig("operating_system", "name")
      claims << "Operating system: #{os_name}." unless os_name.to_s.empty?

      kernel = collected.dig("kernel", "summary")
      claims << "Kernel: #{kernel}." unless kernel.to_s.empty?

      uptime = collected.dig("uptime", "human")
      claims << "Uptime: #{uptime}." unless uptime.to_s.empty?

      load = collected["load"]
      if load
        claims << format(
          "Load averages: %.2f, %.2f, %.2f.",
          load["one_minute"],
          load["five_minutes"],
          load["fifteen_minutes"]
        )
      end

      memory = collected["memory"]
      if memory
        claims << "Memory: #{format_bytes(memory['used_bytes'])} used of #{format_bytes(memory['total_bytes'])} (#{memory['used_percent']}% used), #{format_bytes(memory['available_bytes'])} available."
      end

      Array(collected["filesystems"]).each do |filesystem|
        claim = [
          "Filesystem #{filesystem['target']}:",
          filesystem["filesystem_type"],
          "on #{filesystem['source']},",
          "#{format_bytes(filesystem['size_bytes'])} total,",
          "#{filesystem['used_percent']}% used."
        ].compact.join(" ")
        claims << claim
      end

      Array(collected["block_devices"]).each do |device|
        next unless %w[disk raid rom].include?(device["type"].to_s)

        details = [
          "Block device #{device['name']}:",
          device["type"],
          format_bytes(device["size_bytes"]),
          device["model"],
          device["transport"]
        ].compact.reject(&:empty?)
        claims << "#{details.join(', ')}."
      end

      Array(collected["network_interfaces"]).each do |interface|
        next if interface["name"] == "lo"

        claims << "Network interface #{interface['name']}: state #{interface['state']}, MTU #{interface['mtu']}."
      end

      systemd = collected["systemd"]
      if systemd
        claims << "systemd state: #{systemd['state']}; failed units: #{systemd['failed_unit_count']}."
      end

      mdraid = collected["linux_mdraid"]
      if mdraid
        if mdraid["active_array_count"].to_i.zero?
          claims << "No active Linux MD RAID arrays are listed in /proc/mdstat."
        else
          names = Array(mdraid["arrays"]).map { |array| array["name"] }.join(", ")
          claims << "Linux MD RAID arrays listed in /proc/mdstat: #{names}."
        end
      end

      claims
    end

    def normalize_filesystems(entries)
      entries.filter_map do |entry|
        filesystem_type = entry["fstype"].to_s
        next if filesystem_type.empty? || PSEUDO_FILESYSTEMS.include?(filesystem_type)

        size = integer_or_nil(entry["size"])
        used = integer_or_nil(entry["used"])
        available = integer_or_nil(entry["avail"])
        used_percent = numeric_percent(entry["use%"])
        used_percent ||= size.to_i.positive? && used ? ((used.to_f / size) * 100).round(1) : nil

        {
          "target" => entry["target"],
          "source" => entry["source"],
          "filesystem_type" => filesystem_type,
          "size_bytes" => size,
          "used_bytes" => used,
          "available_bytes" => available,
          "used_percent" => used_percent
        }.reject { |_key, value| value.nil? || value == "" }
      end
    end

    def parse_df(text)
      lines = text.lines.map(&:strip).reject(&:empty?)
      lines.drop(1).filter_map do |line|
        fields = line.split(/\s+/)
        next if fields.length < 7

        source, filesystem_type, size, used, available, percent = fields.first(6)
        target = fields[6..].join(" ")

        {
          "target" => target,
          "source" => source,
          "filesystem_type" => filesystem_type,
          "size_bytes" => integer_or_nil(size),
          "used_bytes" => integer_or_nil(used),
          "available_bytes" => integer_or_nil(available),
          "used_percent" => numeric_percent(percent)
        }
      end
    end

    def flatten_findmnt(entries)
      Array(entries).flat_map do |entry|
        [entry] + flatten_findmnt(entry["children"])
      end
    end

    def flatten_lsblk(entries)
      Array(entries).flat_map do |entry|
        [entry] + flatten_lsblk(entry["children"])
      end
    end

    def run(argv)
      result = @runner.run(argv, timeout_seconds: 3.0)
      @command_results << result
      result
    end

    def safe_file_read(path)
      File.exist?(path) ? File.read(path) : ""
    rescue StandardError
      ""
    end

    def safe_hostname
      @hostname_reader.call.to_s
    rescue StandardError
      ""
    end

    def parse_json(text)
      JSON.parse(text)
    rescue JSON::ParserError
      {}
    end

    def integer_or_nil(value)
      return value if value.is_a?(Integer)
      return nil if value.nil? || value.to_s.empty?

      Integer(value)
    rescue ArgumentError, TypeError
      nil
    end

    def numeric_percent(value)
      return nil if value.nil?

      Float(value.to_s.delete("%")).round(1)
    rescue ArgumentError, TypeError
      nil
    end

    def boolean_from_number(value)
      return nil if value.nil?
      return value if value == true || value == false

      value.to_i == 1
    end

    def clean_string(value)
      value.to_s.strip
    end

    def blank_collection?(value)
      value.nil? || value == {} || value == []
    end

    def format_duration(seconds)
      total = seconds.to_i
      days, remainder = total.divmod(86_400)
      hours, remainder = remainder.divmod(3_600)
      minutes, = remainder.divmod(60)

      parts = []
      parts << "#{days}d" if days.positive?
      parts << "#{hours}h" if hours.positive? || days.positive?
      parts << "#{minutes}m"
      parts.join(" ")
    end

    def format_bytes(value)
      bytes = value.to_f
      return "unknown" unless bytes.positive?

      units = %w[B KiB MiB GiB TiB PiB]
      index = 0
      while bytes >= 1024 && index < units.length - 1
        bytes /= 1024.0
        index += 1
      end

      precision = index.zero? ? 0 : 2
      "#{format("%.#{precision}f", bytes)} #{units[index]}"
    end
  end
end
