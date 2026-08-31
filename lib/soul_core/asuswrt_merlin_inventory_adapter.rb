# frozen_string_literal: true

require "shellwords"

require_relative "bounded_command_runner"

module SoulCore
  # Read-only inventory for an ASUSWRT-Merlin router.  The remote script is a
  # fixed literal: no registry or UI value is interpolated into it.
  class AsuswrtMerlinInventoryAdapter
    SSH_PATH = "/usr/bin/ssh"
    SSH_ALIAS_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9_.-]{0,127}\z/
    COMMAND_TIMEOUT_SECONDS = 8
    MAX_OUTPUT_BYTES = 32 * 1024
    MARKER = "__SOUL_MERLIN__"

    REMOTE_SCRIPT = <<~'SH'.freeze
      printf '\n__SOUL_MERLIN__productid\n'; /usr/sbin/nvram get productid
      printf '\n__SOUL_MERLIN__firmver\n'; /usr/sbin/nvram get firmver
      printf '\n__SOUL_MERLIN__buildno\n'; /usr/sbin/nvram get buildno
      printf '\n__SOUL_MERLIN__extendno\n'; /usr/sbin/nvram get extendno
      printf '\n__SOUL_MERLIN__bl_version\n'; /usr/sbin/nvram get bl_version
      printf '\n__SOUL_MERLIN__hostname\n'; /bin/hostname
      printf '\n__SOUL_MERLIN__uname\n'; /bin/uname -r
      printf '\n__SOUL_MERLIN__uptime\n'; /bin/cat /proc/uptime
      printf '\n__SOUL_MERLIN__loadavg\n'; /bin/cat /proc/loadavg
      printf '\n__SOUL_MERLIN__meminfo\n'; /bin/cat /proc/meminfo
      printf '\n__SOUL_MERLIN__jffs_df\n'; /bin/df -k /jffs
      printf '\n__SOUL_MERLIN__temperatures\n'; /bin/cat /proc/dmu/temperature
      printf '\n__SOUL_MERLIN__qos_enable\n'; /usr/sbin/nvram get qos_enable
      printf '\n__SOUL_MERLIN__qos_type\n'; /usr/sbin/nvram get qos_type
      printf '\n__SOUL_MERLIN__qos_obw\n'; /usr/sbin/nvram get qos_obw
      printf '\n__SOUL_MERLIN__qos_ibw\n'; /usr/sbin/nvram get qos_ibw
      printf '\n__SOUL_MERLIN__ctf_disable\n'; /usr/sbin/nvram get ctf_disable
      printf '\n__SOUL_MERLIN__jffs2_scripts\n'; /usr/sbin/nvram get jffs2_scripts
      printf '\n__SOUL_MERLIN__lsmod\n'; /sbin/lsmod
      printf '\n__SOUL_MERLIN__jffs_script_count\n'; /usr/bin/find /jffs/scripts -mindepth 1 -maxdepth 1 -type f -print 2>/dev/null | /usr/bin/wc -l
      printf '\n__SOUL_MERLIN__jffs_config_count\n'; /usr/bin/find /jffs/configs -mindepth 1 -maxdepth 1 -type f -print 2>/dev/null | /usr/bin/wc -l
      printf '\n__SOUL_MERLIN__complete\n1\n'; exit 0
    SH
    REMOTE_COMMAND = "/bin/sh -c #{Shellwords.escape(REMOTE_SCRIPT)}".freeze

    def initialize(runner: BoundedCommandRunner.new, ssh_path: SSH_PATH, ssh_config: File.expand_path("~/.ssh/config"))
      @runner = runner
      @ssh_path = File.expand_path(ssh_path)
      @ssh_config = File.expand_path(ssh_config)
    end

    def collect(ssh_alias:)
      alias_name = ssh_alias.to_s
      return unavailable("invalid_ssh_alias") unless alias_name.match?(SSH_ALIAS_PATTERN)
      return unavailable("dependency_unavailable") unless File.file?(@ssh_path) && File.executable?(@ssh_path)

      result = @runner.run(
        @ssh_path,
        "-F", @ssh_config,
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=5",
        "-o", "ConnectionAttempts=1",
        "-o", "LogLevel=ERROR",
        alias_name,
        REMOTE_COMMAND,
        timeout_seconds: COMMAND_TIMEOUT_SECONDS,
        max_output_bytes: MAX_OUTPUT_BYTES,
        env: {"LC_ALL" => "C"}
      )
      return unavailable(result.status, result: result) unless result.status == "ok"

      fields = parse_fields(result.stdout)
      return unavailable("incomplete_inventory", result: result) unless complete_inventory?(fields)
      product = first_present(fields["productid"], fields["extendno"], "ASUS router")
      firmware = firmware_version(fields)
      memory = parse_memory(fields["meminfo"])
      jffs = parse_jffs(fields["jffs_df"])
      temperatures = parse_temperatures(fields["temperatures"])
      scripts = integer(fields["jffs_script_count"])
      configs = integer(fields["jffs_config_count"])
      qos = {
        "enabled" => fields["qos_enable"] == "1",
        "type" => safe_text(fields["qos_type"], 32),
        "configured_upload_kbps" => integer(fields["qos_obw"]),
        "configured_download_kbps" => integer(fields["qos_ibw"])
      }
      ctf_disabled = fields["ctf_disable"] == "1"
      ctf_loaded = fields["lsmod"].to_s.lines.any? { |line| line.match?(/\bctf\b/i) }

      {
        "available" => true,
        "state" => "available",
        "reachable" => true,
        "healthy" => true,
        "model" => safe_text(product, 80),
        "firmware_version" => firmware,
        "bootloader_version" => safe_text(fields["bl_version"], 40),
        "kernel" => safe_text(fields["uname"], 80),
        "hostname" => safe_text(fields["hostname"], 80),
        "uptime_seconds" => fields["uptime"].to_s.split.first.to_f.to_i,
        "load_average" => safe_text(fields["loadavg"].to_s.split.first(3).join(" "), 64),
        "memory" => memory,
        "jffs" => jffs.merge("custom_scripts" => scripts, "custom_configs" => configs),
        "temperatures" => temperatures,
        "qos" => qos,
        "ctf" => {"disabled" => ctf_disabled, "module_loaded" => ctf_loaded, "active" => !ctf_disabled && ctf_loaded},
        "custom_scripts_enabled" => fields["jffs2_scripts"] == "1",
        "custom_scripts_configured" => fields["jffs2_scripts"] == "1",
        "evidence" => {"status" => result.status, "exit_status" => result.exit_status, "truncated" => result.truncated == true}
      }
    rescue StandardError => error
      unavailable("collection_failed:#{error.class}")
    end

    private

    def parse_fields(raw)
      fields = Hash.new { |hash, field| hash[field] = String.new }
      key = nil
      raw.to_s.lines.first(4096).each do |line|
        line = line.chomp
        if line.start_with?(MARKER)
          key = line.delete_prefix(MARKER).strip
          fields[key] = String.new
        elsif key
          fields[key] << line << "\n"
        end
      end
      fields.transform_values { |value| safe_text(value.strip, 4096) }
    end

    def firmware_version(fields)
      values = [fields["firmver"], fields["buildno"], fields["extendno"]].map { |value| safe_text(value, 40) }.reject(&:empty?)
      values.empty? ? "unavailable" : values.join(" · ")
    end

    def complete_inventory?(fields)
      !fields["productid"].to_s.empty? &&
        [fields["firmver"], fields["buildno"], fields["extendno"]].any? { |value| !value.to_s.empty? } &&
        %w[hostname uname uptime meminfo jffs_df].all? { |key| !fields[key].to_s.empty? } &&
        fields["complete"] == "1"
    end

    def parse_memory(raw)
      values = raw.to_s.each_line.filter_map do |line|
        match = line.strip.match(/\A(MemTotal|MemFree|Buffers|Cached):\s+(\d+)\s+kB\z/)
        [match[1], match[2].to_i] if match
      end.to_h
      values.merge(
        "total_kb" => values["MemTotal"],
        "available_kb" => values["MemFree"].to_i + values["Buffers"].to_i + values["Cached"].to_i
      ).compact
    end

    def parse_jffs(raw)
      line = raw.to_s.lines.map(&:strip).find { |candidate| candidate.match?(/\A\S+\s+\d+\s+\d+\s+\d+\s+\d+%\s+\/jffs\z/) }
      return {"total_kb" => nil, "used_kb" => nil, "available_kb" => nil, "use_percent" => nil} unless line

      fields = line.split
      {"total_kb" => integer(fields[1]), "used_kb" => integer(fields[2]), "available_kb" => integer(fields[3]), "use_percent" => integer(fields[4].to_s.delete_suffix("%"))}
    end

    def parse_temperatures(raw)
      raw.to_s.lines.filter_map do |line|
        match = line.match(/\A\s*([^:]+):\s*(-?\d+(?:\.\d+)?)\s*[^0-9\r\n]*C/i)
        {"sensor" => safe_text(match[1], 40), "celsius" => match[2].to_f} if match
      end.first(8)
    end

    def integer(value)
      Integer(value.to_s.strip, exception: false) || 0
    end

    def first_present(*values)
      values.map { |value| value.to_s.strip }.find { |value| !value.empty? } || "unavailable"
    end

    def safe_text(value, limit)
      value.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "").delete("\x00").strip.slice(0, limit) || ""
    end

    def unavailable(reason, result: nil)
      {
        "available" => false,
        "state" => "unavailable",
        "reachable" => false,
        "healthy" => false,
        "reason" => safe_text(reason, 160),
        "evidence" => result ? {"status" => result.status, "exit_status" => result.exit_status, "truncated" => result.truncated == true} : {}
      }
    end
  end
end
