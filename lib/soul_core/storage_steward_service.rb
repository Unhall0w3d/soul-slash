# frozen_string_literal: true

require "json"
require "time"
require_relative "software_steward_service"

module SoulCore
  class StorageStewardService
    ROOTS_ENV = "SOUL_STORAGE_STEWARD_PATHS"
    ROOT_ID = /\A[a-z][a-z0-9_-]{0,31}\z/
    MAX_DEVICES = 64
    MAX_FILESYSTEMS = 64
    MAX_ROOTS = 8
    MAX_IO_ROWS = 25
    COMMAND_TIMEOUT_SECONDS = 8
    COMPRESSION_TIMEOUT_SECONDS = 12
    IO_TIMEOUT_SECONDS = 8
    OUTPUT_LIMIT_BYTES = 512 * 1024

    COMMANDS = {
      "lsblk" => %w[lsblk --json --bytes -o NAME,KNAME,TYPE,SIZE,MODEL,TRAN,ROTA],
      "findmnt" => %w[findmnt --json --bytes -o TARGET,FSTYPE,SIZE,USED,AVAIL,USE%],
      "nvme" => %w[nvme list --output-format=json],
      "iotop" => %w[iotop --batch --only --processes --no-color --hide-command --iter=2 --delay=2]
    }.freeze

    def initialize(runner: ReadOnlyCommandRunner.new, process_env: ENV, clock: -> { Time.now.utc })
      @runner = runner
      @process_env = process_env.to_h.transform_keys(&:to_s)
      @clock = clock
    end

    def refresh
      devices = json_source("lsblk") { |parsed| parse_devices(parsed) }
      filesystems = json_source("findmnt") { |parsed| parse_filesystems(parsed) }
      nvme = nvme_source
      compression = configured_roots.map { |root_id, path| compression_source(root_id, path) }
      complete({
        "schema_version" => "soul.storage-steward.a1.v1",
        "block_devices" => devices,
        "filesystems" => filesystems,
        "nvme" => nvme,
        "compression_roots" => compression,
        "sources" => {
          "block_devices" => source_metadata(devices),
          "filesystems" => source_metadata(filesystems),
          "nvme" => source_metadata(nvme),
          "compression" => { "available" => compression.all? { |root| root["available"] }, "configured_root_count" => compression.length }
        },
        "limits" => { "devices" => MAX_DEVICES, "filesystems" => MAX_FILESYSTEMS, "compression_roots" => MAX_ROOTS, "command_output_bytes" => OUTPUT_LIMIT_BYTES, "command_timeout_seconds" => COMMAND_TIMEOUT_SECONDS, "compression_timeout_seconds" => COMPRESSION_TIMEOUT_SECONDS },
        "automatic_refresh" => false,
        "background_polling" => false,
        "mutation_authority" => "none"
      }, "Storage Steward evidence collected.")
    rescue StandardError => error
      failed("Storage Steward refresh failed safely: #{error.class}")
    end

    def io_diagnostic
      result = run(COMMANDS.fetch("iotop"), timeout: IO_TIMEOUT_SECONDS)
      return complete(io_unavailable(result), "Storage I/O diagnostic is unavailable.") unless result["status"] == "ok"

      rows = parse_iotop(result["stdout"])
      return complete({ "schema_version" => "soul.storage-steward.io-a1.v1", "available" => false, "reason" => "I/O diagnostic output was malformed and is unavailable", "source" => command_metadata(COMMANDS.fetch("iotop"), result), "rows" => [], "truncated" => false, "maximum_rows" => MAX_IO_ROWS, "automatic_refresh" => false, "background_polling" => false, "mutation_authority" => "none" }, "Storage I/O diagnostic is unavailable.") unless rows

      complete({ "schema_version" => "soul.storage-steward.io-a1.v1", "available" => true, "rows" => rows.first(MAX_IO_ROWS), "truncated" => rows.length > MAX_IO_ROWS, "source" => command_metadata(COMMANDS.fetch("iotop"), result), "maximum_rows" => MAX_IO_ROWS, "sample_count" => 2, "sample_interval_seconds" => 2, "automatic_refresh" => false, "background_polling" => false, "mutation_authority" => "none" }, "Storage I/O diagnostic collected.")
    rescue StandardError => error
      failed("Storage I/O diagnostic failed safely: #{error.class}")
    end

    def configured?
      !configured_roots.empty?
    rescue StandardError
      false
    end

    private

    def json_source(name)
      result = run(COMMANDS.fetch(name))
      return unavailable(result, COMMANDS.fetch(name)) unless result["status"] == "ok"

      value = yield(JSON.parse(result["stdout"]))
      return malformed(result, COMMANDS.fetch(name), "source JSON did not have the expected shape") unless value

      { "available" => true, "entries" => value.fetch("entries"), "count" => value.fetch("count"), "truncated" => value.fetch("truncated"), "command" => command_metadata(COMMANDS.fetch(name), result) }
    rescue JSON::ParserError
      malformed(result, COMMANDS.fetch(name), "source JSON was malformed")
    end

    def parse_devices(parsed)
      entries = parsed["blockdevices"]
      return nil unless entries.is_a?(Array)

      devices = entries.filter_map do |entry|
        next unless entry.is_a?(Hash) && entry["type"].to_s == "disk" && valid_name?(entry["name"])

        { "name" => entry["name"].to_s, "kernel_name" => entry["kname"].to_s, "size_bytes" => integer_or_nil(entry["size"]), "model" => clean(entry["model"]), "transport" => clean(entry["tran"]), "rotational" => boolean_or_nil(entry["rota"]) }.reject { |_key, value| value.nil? || value == "" }
      end
      { "entries" => devices.first(MAX_DEVICES), "count" => devices.length, "truncated" => devices.length > MAX_DEVICES }
    end

    def parse_filesystems(parsed)
      roots = parsed["filesystems"]
      return nil unless roots.is_a?(Array)

      entries = flatten_filesystems(roots).filter_map do |entry|
        target = entry["target"]
        next unless target.is_a?(String) && target.start_with?("/")

        { "mount_id" => mount_id(target), "filesystem_type" => clean(entry["fstype"]), "size_bytes" => integer_or_nil(entry["size"]), "used_bytes" => integer_or_nil(entry["used"]), "available_bytes" => integer_or_nil(entry["avail"]), "used_percent" => percentage(entry["use%"]) }.reject { |_key, value| value.nil? || value == "" }
      end
      { "entries" => entries.first(MAX_FILESYSTEMS), "count" => entries.length, "truncated" => entries.length > MAX_FILESYSTEMS }
    end

    def flatten_filesystems(entries)
      entries.flat_map { |entry| [entry] + flatten_filesystems(Array(entry["children"])) }
    end

    def nvme_source
      result = run(COMMANDS.fetch("nvme"))
      return unavailable(result, COMMANDS.fetch("nvme")) unless result["status"] == "ok"

      parsed = JSON.parse(result["stdout"])
      entries = parsed["Devices"] || parsed["devices"]
      return malformed(result, COMMANDS.fetch("nvme"), "NVMe JSON did not contain a device list") unless entries.is_a?(Array)

      devices = entries.filter_map do |entry|
        next unless entry.is_a?(Hash)
        name = entry["DevicePath"] || entry["device"] || entry["NameSpace"]
        next unless name.to_s.match?(%r{\A/dev/nvme\d+(?:n\d+)?\z})

        [name.to_s, { "device_id" => File.basename(name.to_s), "model" => clean(entry["ModelNumber"] || entry["model"]), "firmware" => clean(entry["Firmware"] || entry["firmware"]), "namespace_capacity_bytes" => integer_or_nil(entry["PhysicalSize"] || entry["namespace_capacity"]), "used_capacity_bytes" => integer_or_nil(entry["UsedBytes"] || entry["used_capacity"]) }.reject { |_key, value| value.nil? || value == "" }]
      end
      smart = devices.map { |device, _display| smart_source(device) }
      { "available" => true, "devices" => devices.map(&:last).first(MAX_DEVICES), "count" => devices.length, "truncated" => devices.length > MAX_DEVICES, "smart" => smart.first(MAX_DEVICES), "command" => command_metadata(COMMANDS.fetch("nvme"), result) }
    rescue JSON::ParserError
      malformed(result, COMMANDS.fetch("nvme"), "NVMe JSON was malformed")
    end

    def smart_source(device)
      argv = ["nvme", "smart-log", "--output-format=json", device]
      result = run(argv)
      return { "device_id" => File.basename(device), "available" => false, "reason" => authority_reason(result, "NVMe SMART evidence"), "command" => command_metadata(argv, result) } unless result["status"] == "ok"

      parsed = JSON.parse(result["stdout"])
      health = parsed.slice("critical_warning", "temperature", "available_spare", "percentage_used", "media_errors", "num_err_log_entries")
      return { "device_id" => File.basename(device), "available" => false, "reason" => "NVMe SMART JSON was malformed", "command" => command_metadata(argv, result) } if health.empty?

      { "device_id" => File.basename(device), "available" => true, "health" => health, "command" => command_metadata(argv, result) }
    rescue JSON::ParserError
      { "device_id" => File.basename(device), "available" => false, "reason" => "NVMe SMART JSON was malformed", "command" => command_metadata(argv, result) }
    end

    def compression_source(root_id, path)
      argv = ["compsize", "-b", path]
      result = run(argv, timeout: COMPRESSION_TIMEOUT_SECONDS)
      return { "root_id" => root_id, "available" => false, "reason" => source_reason(result), "command" => command_metadata(["compsize", "-b", "<configured-root>"], result) } unless result["status"] == "ok"

      output = result["stdout"].to_s.gsub(path, "<configured-root>")
      return { "root_id" => root_id, "available" => false, "reason" => "compression output exposed a configured path", "command" => command_metadata(["compsize", "-b", "<configured-root>"], result) } if output.include?(path)

      summary = output.gsub(%r{/[^\s]+}, "<path>").lines.map(&:strip).reject(&:empty?).first(12)
      { "root_id" => root_id, "available" => true, "summary" => summary, "command" => command_metadata(["compsize", "-b", "<configured-root>"], result) }
    end

    def configured_roots
      raw = @process_env.fetch(ROOTS_ENV, "").to_s
      return [] if raw.empty?

      entries = raw.split(";", -1)
      raise ArgumentError, "at most #{MAX_ROOTS} compression roots are allowed" if entries.length > MAX_ROOTS
      parsed = entries.map do |entry|
        root_id, path = entry.split("=", 2)
        raise ArgumentError, "storage root must use root_id=absolute_path" unless root_id.to_s.match?(ROOT_ID) && path.to_s.start_with?("/") && !path.include?("\0")

        [root_id, path]
      end
      raise ArgumentError, "storage root IDs must be unique" unless parsed.map(&:first).uniq.length == parsed.length

      parsed
    end

    def parse_iotop(output)
      rows = output.lines.filter_map do |line|
        match = line.match(/^\s*(\d+)\s+(\S+)\s+(\S+)\s+([0-9.]+\s+\S+\/s)\s+([0-9.]+\s+\S+\/s)\s+([0-9.]+\s*%)\s+([0-9.]+\s*%)(?:\s+.*)?$/)
        next unless match

        { "process_id" => match[1].to_i, "priority" => safe_token(match[2]), "user" => safe_token(match[3]), "disk_read" => match[4], "disk_write" => match[5], "swapin" => match[6], "io" => match[7] }
      end
      return nil if output.to_s.strip != "" && rows.empty?

      rows
    end

    def io_unavailable(result)
      { "schema_version" => "soul.storage-steward.io-a1.v1", "available" => false, "reason" => authority_reason(result, "I/O diagnostic"), "source" => command_metadata(COMMANDS.fetch("iotop"), result), "rows" => [], "truncated" => false, "maximum_rows" => MAX_IO_ROWS, "automatic_refresh" => false, "background_polling" => false, "mutation_authority" => "none" }
    end

    def run(argv, timeout: COMMAND_TIMEOUT_SECONDS)
      @runner.call(argv, timeout_seconds: timeout, output_limit_bytes: OUTPUT_LIMIT_BYTES)
    end

    def unavailable(result, argv)
      { "available" => false, "reason" => source_reason(result), "entries" => [], "count" => 0, "truncated" => false, "command" => command_metadata(argv, result) }
    end

    def malformed(result, argv, reason)
      { "available" => false, "reason" => reason, "entries" => [], "count" => 0, "truncated" => false, "command" => command_metadata(argv, result) }
    end

    def source_metadata(source)
      { "available" => source["available"], "reason" => source["reason"] }.compact
    end

    def command_metadata(argv, result)
      { "source_id" => Array(argv).first, "status" => result["status"], "exit_status" => result["exit_status"], "elapsed_ms" => result["elapsed_ms"] }.compact
    end

    def source_reason(result)
      case result["status"]
      when "unavailable" then "required local command is unavailable"
      when "timeout" then "source timed out and is unavailable"
      when "truncated" then "source output exceeded its bound and is unavailable"
      else "source command failed and is unavailable"
      end
    end

    def authority_reason(result, label)
      diagnostic = "#{result['stdout']}\n#{result['stderr']}"
      return "#{label} requires existing unprivileged read authority; no elevation was requested" if diagnostic.match?(/permission|not permitted|root|privileges|cap_net_admin|net_admin/i)

      source_reason(result)
    end

    def valid_name?(value)
      value.to_s.match?(/\A[a-zA-Z0-9._-]+\z/)
    end

    def integer_or_nil(value)
      Integer(value)
    rescue ArgumentError, TypeError
      nil
    end

    def boolean_or_nil(value)
      return true if value == true || value.to_s == "1"
      return false if value == false || value.to_s == "0"

      nil
    end

    def percentage(value)
      text = value.to_s.delete("%")
      number = Float(text)
      number.between?(0, 100) ? number : nil
    rescue ArgumentError
      nil
    end

    def clean(value)
      text = value.to_s.strip[0, 256]
      text.start_with?("/") ? nil : text
    end

    def safe_token(value)
      text = value.to_s[0, 128]
      text.start_with?("/") ? "<redacted>" : text
    end

    def mount_id(path)
      return "root" if path == "/"

      "mount_#{path.delete_prefix("/").gsub(/[^A-Za-z0-9_-]+/, "_")[0, 80]}"
    end

    def complete(data, message)
      { "ok" => true, "lifecycle_state" => "complete", "message" => message, "data" => data, "mutation" => "none", "retrieved_at" => @clock.call.iso8601(6) }
    end

    def failed(message)
      { "ok" => false, "lifecycle_state" => "failed", "message" => message, "data" => {}, "mutation" => "none", "retrieved_at" => @clock.call.iso8601(6) }
    end
  end
end
