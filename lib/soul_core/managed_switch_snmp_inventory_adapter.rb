# frozen_string_literal: true

require "fileutils"
require "ipaddr"
require "tmpdir"

module SoulCore
  class ManagedSwitchSnmpInventoryAdapter
    SNMPGET_PATH = "/usr/bin/snmpget"
    SNMPBULKWALK_PATH = "/usr/bin/snmpbulkwalk"
    COMMAND_TIMEOUT_SECONDS = 6
    MAX_OUTPUT_BYTES = 128 * 1024
    MAX_PORTS = 64

    SYSTEM_OIDS = %w[
      .1.3.6.1.2.1.1.1.0
      .1.3.6.1.2.1.1.2.0
      .1.3.6.1.2.1.1.3.0
      .1.3.6.1.2.1.1.5.0
    ].freeze
    INTERFACE_TABLE_OID = ".1.3.6.1.2.1.2.2.1"
    IF_HIGH_SPEED_OID = ".1.3.6.1.2.1.31.1.1.1.15"
    ENTITY_TABLE_OID = ".1.3.6.1.2.1.47.1.1.1.1"
    INTERFACE_COLUMNS = {
      1 => "index", 2 => "name", 3 => "type", 5 => "speed_bps",
      7 => "admin_status", 8 => "oper_status", 10 => "in_octets",
      14 => "in_errors", 16 => "out_octets", 20 => "out_errors"
    }.freeze

    def initialize(runner:, snmpget_path: SNMPGET_PATH, snmpbulkwalk_path: SNMPBULKWALK_PATH)
      @runner = runner
      @snmpget_path = File.expand_path(snmpget_path)
      @snmpbulkwalk_path = File.expand_path(snmpbulkwalk_path)
    end

    def collect(address:, community:)
      target = validated_address(address)
      secret = community.to_s
      return unavailable("invalid_target") unless target
      return unavailable("credential_not_configured") unless valid_community?(secret)
      return unavailable("dependency_unavailable") unless dependencies_available?

      with_private_configuration(secret) do |environment|
        system = run(environment, @snmpget_path, "-v2c", "-t", "2", "-r", "0", "-On", "-Oqv", target, *SYSTEM_OIDS)
        return unavailable(command_state(system), probe_status: system.status) unless system.status == "ok"

        interface_table = run(environment, @snmpbulkwalk_path, "-v2c", "-t", "2", "-r", "0", "-On", target, INTERFACE_TABLE_OID)
        high_speed = run(environment, @snmpbulkwalk_path, "-v2c", "-t", "2", "-r", "0", "-On", target, IF_HIGH_SPEED_OID)
        entity_table = run(environment, @snmpbulkwalk_path, "-v2c", "-t", "2", "-r", "0", "-On", target, ENTITY_TABLE_OID)
        return unavailable(command_state(interface_table), probe_status: interface_table.status) unless interface_table.status == "ok"

        system_values = system.stdout.to_s.lines.map { |line| clean_value(line) }
        description, object_id, uptime, system_name = system_values.first(4)
        ports = parse_interfaces(interface_table.stdout, high_speed.status == "ok" ? high_speed.stdout : "")
        chassis = entity_table.status == "ok" ? parse_chassis(entity_table.stdout) : {}
        {
          "available" => true,
          "state" => "available",
          "system_name" => safe_text(system_name, 80),
          "system_description" => safe_text(description, 240),
          "object_id" => safe_oid(object_id),
          "vendor" => extract_vendor(description, object_id),
          "model" => first_present(extract_model(description), chassis["model"], chassis["name"]),
          "product_id" => chassis["model"],
          "firmware_version" => first_present(chassis["software_version"], extract_firmware(description)),
          "boot_version" => chassis["firmware_version"],
          "hardware_version" => chassis["hardware_version"],
          "uptime_seconds" => parse_uptime_seconds(uptime),
          "ports" => ports,
          "port_count" => ports.length,
          "active_port_count" => ports.count { |port| port["oper_status"] == "up" },
          "error_port_count" => ports.count { |port| port["in_errors"].to_i.positive? || port["out_errors"].to_i.positive? },
          "background_process" => false,
          "mutation_authority" => false,
          "snmp_set_authority" => false
        }
      end
    rescue SystemCallError
      unavailable("private_configuration_failed")
    end

    private

    def dependencies_available?
      [@snmpget_path, @snmpbulkwalk_path].all? { |path| File.file?(path) && File.executable?(path) }
    end

    def validated_address(value)
      address = value.to_s.strip
      parsed = IPAddr.new(address)
      address if parsed.ipv4? && parsed.private?
    rescue IPAddr::InvalidAddressError
      nil
    end

    def with_private_configuration(secret)
      directory = Dir.mktmpdir("soul-snmp-")
      File.chmod(0o700, directory)
      config = File.join(directory, "snmp.conf")
      escaped = secret.gsub("\\", "\\\\").gsub('"', '\\"')
      File.open(config, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write("defCommunity \"#{escaped}\"\n") }
      yield({"LC_ALL" => "C", "MIBS" => "", "SNMPCONFPATH" => directory, "HOME" => directory})
    ensure
      FileUtils.remove_entry_secure(directory) if directory && File.directory?(directory)
    end

    def run(environment, *argv)
      @runner.run(
        *argv,
        timeout_seconds: COMMAND_TIMEOUT_SECONDS,
        max_output_bytes: MAX_OUTPUT_BYTES,
        env: environment
      )
    end

    def valid_community?(value)
      bytes = value.to_s.bytes
      bytes.length.between?(8, 128) && bytes.all? { |byte| byte.between?(33, 126) }
    end

    def parse_interfaces(table_output, high_speed_output)
      rows = Hash.new { |hash, key| hash[key] = {} }
      table_output.to_s.lines.first(4096).each do |line|
        line = line.strip
        next unless (match = line.match(/\A\.1\.3\.6\.1\.2\.1\.2\.2\.1\.(\d+)\.(\d+)\s+=\s+\S+:\s*(.*)\z/))

        column = INTERFACE_COLUMNS[match[1].to_i]
        next unless column

        index = match[2].to_i
        rows[index][column] = clean_value(match[3])
      end
      high_speed_output.to_s.lines.first(512).each do |line|
        line = line.strip
        next unless (match = line.match(/\A\.1\.3\.6\.1\.2\.1\.31\.1\.1\.1\.15\.(\d+)\s+=\s+\S+:\s*(\d+)\z/))

        rows[match[1].to_i]["high_speed_mbps"] = match[2].to_i
      end

      rows.keys.sort.first(MAX_PORTS).filter_map do |index|
        row = rows[index]
        next unless row["type"].to_i == 6

        {
          "index" => index,
          "name" => safe_text(row["name"], 40),
          "admin_status" => status_name(row["admin_status"]),
          "oper_status" => status_name(row["oper_status"]),
          "speed_mbps" => interface_speed_mbps(row),
          "in_octets" => integer(row["in_octets"]),
          "out_octets" => integer(row["out_octets"]),
          "in_errors" => integer(row["in_errors"]),
          "out_errors" => integer(row["out_errors"])
        }
      end
    end

    def parse_chassis(output)
      rows = Hash.new { |hash, key| hash[key] = {} }
      columns = {
        5 => "class", 7 => "name", 8 => "hardware_version",
        9 => "firmware_version", 10 => "software_version", 13 => "model"
      }
      output.to_s.lines.first(4096).each do |line|
        match = line.strip.match(/\A\.1\.3\.6\.1\.2\.1\.47\.1\.1\.1\.1\.(\d+)\.(\d+)\s+=\s+(?:\S+:\s*)?(.*)\z/)
        next unless match && columns.key?(match[1].to_i)

        rows[match[2].to_i][columns.fetch(match[1].to_i)] = clean_value(match[3])
      end
      selected = rows.values.find { |row| integer(row["class"]) == 3 } || {}
      selected.transform_values { |value| safe_text(value, 80) }
    end

    def interface_speed_mbps(row)
      high_speed = integer(row["high_speed_mbps"])
      return high_speed if high_speed.positive?

      integer(row["speed_bps"]) / 1_000_000
    end

    def status_name(value)
      {1 => "up", 2 => "down", 3 => "testing"}.fetch(integer(value), "unknown")
    end

    def extract_model(description)
      candidate = description.to_s[/\b(?:SG\d{3}(?:-\d+)?|GS\d{3}[A-Z0-9-]*(?:v\d+)?)\b/i]
      safe_text(candidate || description.to_s.split(",", 2).first || "Managed switch", 80)
    end

    def extract_firmware(description)
      match = description.to_s.match(/(?:software\s+version|firmware\s+version|version)\s*[:=]?\s*(\d+(?:\.\d+){2,})/i)
      safe_text(match ? match[1] : "unavailable", 40)
    end

    def extract_vendor(description, object_id)
      value = "#{description} #{object_id}"
      return "Cisco" if value.match?(/Cisco|\.1\.3\.6\.1\.4\.1\.9\./i)
      return "Netgear" if value.match?(/Netgear|\.1\.3\.6\.1\.4\.1\.4526\./i)

      "Managed switch"
    end

    def parse_uptime_seconds(value)
      text = value.to_s
      return Regexp.last_match(1).to_i / 100 if text.match(/\((\d+)\)/)

      days = text[/\A(\d+)\s+days?,/i, 1].to_i
      clock = text.match(/(\d+):(\d+):(\d+)(?:\.\d+)?\z/)
      clock ? (days * 86_400) + (clock[1].to_i * 3600) + (clock[2].to_i * 60) + clock[3].to_i : 0
    end

    def clean_value(value)
      value.to_s.strip.sub(/\A(?:STRING|OID|Timeticks|INTEGER|Counter32|Gauge32):\s*/i, "").sub(/\A"(.*)"\z/m, '\\1')
    end

    def safe_oid(value)
      candidate = clean_value(value)
      candidate.match?(/\A\.?\d+(?:\.\d+)+\z/) ? candidate : "unavailable"
    end

    def integer(value)
      Integer(value.to_s[/\d+/].to_s, 10)
    rescue ArgumentError
      0
    end

    def command_state(result)
      result.status == "timeout" ? "timeout" : "probe_failed"
    end

    def unavailable(reason, probe_status: nil)
      {
        "available" => false,
        "state" => reason,
        "reason" => reason,
        "probe_status" => probe_status,
        "ports" => [],
        "background_process" => false,
        "mutation_authority" => false,
        "snmp_set_authority" => false
      }
    end

    def safe_text(value, maximum)
      value.to_s.byteslice(0, maximum).to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "�")
    end

    def first_present(*values)
      values.find { |value| !value.to_s.empty? && value != "unavailable" } || "unavailable"
    end
  end
end
