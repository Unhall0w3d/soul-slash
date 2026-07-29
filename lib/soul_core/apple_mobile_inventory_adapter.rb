# frozen_string_literal: true

module SoulCore
  class AppleMobileInventoryAdapter
    IDEVICE_ID_PATH = "/usr/bin/idevice_id"
    IDEVICEINFO_PATH = "/usr/bin/ideviceinfo"
    MAX_USB_DEVICES = 4
    COMMAND_TIMEOUT_SECONDS = 3
    MAX_OUTPUT_BYTES = 64 * 1024
    IDENTITY_KEYS = %w[DeviceName ProductType ProductVersion BuildVersion CPUArchitecture].freeze
    BATTERY_KEYS = %w[BatteryCurrentCapacity BatteryIsCharging ExternalConnected FullyCharged].freeze

    def initialize(
      runner:,
      idevice_id_path: IDEVICE_ID_PATH,
      ideviceinfo_path: IDEVICEINFO_PATH
    )
      @runner = runner
      @idevice_id_path = File.expand_path(idevice_id_path)
      @ideviceinfo_path = File.expand_path(ideviceinfo_path)
    end

    def discover(reviewed_macs:)
      expected = Array(reviewed_macs).filter_map { |value| normalize_mac(value) }.uniq.first(64)
      return result("not_applicable") if expected.empty?
      return result("dependency_unavailable") unless dependencies_available?

      listed = run(@idevice_id_path, "-l")
      return result("not_connected", inspected: 0) if disconnected_device_list?(listed)
      return result(listed.status == "timeout" ? "timeout" : "dependency_failed") unless listed.status == "ok"

      identifiers = listed.stdout.lines.filter_map do |line|
        value = line.strip
        value if value.match?(/\A[0-9A-Fa-f-]{20,64}\z/)
      end.uniq.first(MAX_USB_DEVICES)
      return result("not_connected", inspected: 0) if identifiers.empty?

      locked_or_untrusted = false
      matched = {}
      identifiers.each do |identifier|
        network_identity = query_key(
          identifier,
          "InstanceName",
          domain: "com.apple.mobile.wireless_lockdown"
        )
        unless network_identity[:ok]
          locked_or_untrusted = true
          next
        end

        mac = normalize_mac(network_identity[:value].to_s.split("@", 2).first)
        next unless mac && expected.include?(mac)

        projection = identity_projection(identifier)
        unless projection
          locked_or_untrusted = true
          next
        end

        matched[mac] = projection
      end

      state = if matched.any?
                "available"
              elsif locked_or_untrusted
                "locked_or_untrusted"
              else
                "no_reviewed_match"
              end
      result(state, inspected: identifiers.length, devices: matched)
    end

    private

    def dependencies_available?
      [@idevice_id_path, @ideviceinfo_path].all? { |path| File.file?(path) && File.executable?(path) }
    end

    def disconnected_device_list?(listed)
      listed.status == "failed" &&
        listed.exit_status == 255 &&
        listed.stdout.to_s.empty? &&
        listed.stderr.to_s.strip == "ERROR: Unable to retrieve device list!"
    end

    def identity_projection(identifier)
      identity = {}
      IDENTITY_KEYS.each do |key|
        queried = query_key(identifier, key)
        return nil unless queried[:ok]

        identity[underscore(key)] = safe_value(queried[:value], 160)
      end

      battery = run(@ideviceinfo_path, "-u", identifier, "-q", "com.apple.mobile.battery")
      battery_values = battery.status == "ok" ? parse_key_values(battery.stdout, BATTERY_KEYS) : {}
      {
        "state" => "available",
        "connection" => "trusted_usb",
        "device_name" => identity.fetch("device_name"),
        "product_type" => identity.fetch("product_type"),
        "product_version" => identity.fetch("product_version"),
        "build_version" => identity.fetch("build_version"),
        "cpu_architecture" => identity.fetch("cpu_architecture"),
        "battery_percent" => integer_between(battery_values["BatteryCurrentCapacity"], 0, 100),
        "battery_is_charging" => boolean_value(battery_values["BatteryIsCharging"]),
        "external_power_connected" => boolean_value(battery_values["ExternalConnected"]),
        "fully_charged" => boolean_value(battery_values["FullyCharged"])
      }
    end

    def query_key(identifier, key, domain: nil)
      argv = [@ideviceinfo_path, "-u", identifier]
      argv.concat(["-q", domain]) if domain
      argv.concat(["-k", key])
      result = run(*argv)
      value = result.stdout.to_s.strip
      {ok: result.status == "ok" && !value.empty?, value: value}
    end

    def run(*argv)
      @runner.run(
        *argv,
        timeout_seconds: COMMAND_TIMEOUT_SECONDS,
        max_output_bytes: MAX_OUTPUT_BYTES,
        env: {"LC_ALL" => "C"}
      )
    end

    def result(state, inspected: 0, devices: {})
      {
        "state" => state,
        "inspected_usb_device_count" => inspected,
        "devices" => devices,
        "background_process" => false,
        "mutation_authority" => false
      }
    end

    def normalize_mac(value)
      normalized = value.to_s.strip.downcase
      normalized if normalized.match?(/\A[0-9a-f]{2}(?::[0-9a-f]{2}){5}\z/)
    end

    def parse_key_values(output, allowed)
      output.to_s.lines.each_with_object({}) do |line, values|
        key, value = line.split(":", 2).map(&:strip)
        values[key] = value if allowed.include?(key) && !value.to_s.empty?
      end
    end

    def boolean_value(value)
      return true if value.to_s.casecmp("true").zero?
      return false if value.to_s.casecmp("false").zero?

      nil
    end

    def integer_between(value, minimum, maximum)
      parsed = Integer(value, 10)
      parsed if parsed.between?(minimum, maximum)
    rescue ArgumentError, TypeError
      nil
    end

    def underscore(value)
      value
        .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
        .gsub(/([a-z\d])([A-Z])/, '\1_\2')
        .downcase
    end

    def safe_value(value, maximum)
      value.to_s.byteslice(0, maximum).to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "�")
    end
  end
end
