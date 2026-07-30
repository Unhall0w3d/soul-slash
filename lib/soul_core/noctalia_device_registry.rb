# frozen_string_literal: true

require "json"

module SoulCore
  class NoctaliaDeviceRegistry
    ACTIONS_SCHEMA = "soul.noctalia.device_actions.v1"
    FLEET_REGISTRY_SCHEMA = "soul.maintenance.fleet_registry.v1"
    MAX_REGISTRY_BYTES = 256 * 1024
    DEVICE_ID_PATTERN = /\A[a-zA-Z0-9][a-zA-Z0-9_.-]{0,127}\z/
    SSH_TARGET_PATTERN = /\A[a-zA-Z0-9][a-zA-Z0-9_.-]{0,127}\z/

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def connectable?(device_id)
      targets.key?(validated_device_id!(device_id))
    rescue ArgumentError
      false
    end

    def ssh_argv(device_id)
      id = validated_device_id!(device_id)
      target = targets[id]
      raise ArgumentError, "device is not enrolled for interactive SSH" unless target

      ["/usr/bin/ssh", target]
    end

    private

    def targets
      @targets ||= discovered_targets.merge(interactive_overrides)
    end

    def discovered_targets
      parsed = read_registry(
        File.join(@root, "Soul", "private", "host_maintenance", "discovered_devices.json"),
        FLEET_REGISTRY_SCHEMA
      )
      Array(parsed["devices"]).each_with_object({}) do |record, result|
        next unless record.is_a?(Hash) && record["connection_mode"] == "ssh"

        id = record["id"].to_s
        target = record["ssh_alias"].to_s
        next unless id.match?(DEVICE_ID_PATTERN) && target.match?(SSH_TARGET_PATTERN)

        result[id] = target
      end
    end

    def interactive_overrides
      parsed = read_registry(
        File.join(@root, "Soul", "private", "noctalia", "device_actions.json"),
        ACTIONS_SCHEMA,
        optional: true
      )
      Array(parsed["devices"]).each_with_object({}) do |record, result|
        next unless record.is_a?(Hash)

        id = record["id"].to_s
        target = record["interactive_ssh_alias"].to_s
        next unless id.match?(DEVICE_ID_PATTERN) && target.match?(SSH_TARGET_PATTERN)

        result[id] = target
      end
    end

    def read_registry(path, expected_schema, optional: false)
      return {} if optional && !File.exist?(path)
      return {} unless File.exist?(path)
      raise ArgumentError, "registry path is unsafe" if File.symlink?(path)

      stat = File.stat(path)
      raise ArgumentError, "registry must be a bounded regular file" unless stat.file? && stat.size.between?(1, MAX_REGISTRY_BYTES)

      parsed = JSON.parse(File.binread(path, MAX_REGISTRY_BYTES + 1))
      raise ArgumentError, "registry schema is unsupported" unless parsed["schema_version"] == expected_schema

      parsed
    rescue JSON::ParserError, SystemCallError
      {}
    end

    def validated_device_id!(value)
      id = value.to_s
      raise ArgumentError, "device id is invalid" unless id.match?(DEVICE_ID_PATTERN)

      id
    end
  end
end
