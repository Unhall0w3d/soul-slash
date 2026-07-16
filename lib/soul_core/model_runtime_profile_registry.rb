# frozen_string_literal: true

require "yaml"

module SoulCore
  class ModelRuntimeProfileRegistry
    SCHEMA_VERSION = "soul.model_runtime_profiles.v1"
    MAX_BYTES = 32 * 1024
    MAX_PROFILES = 4
    PROFILE_ID = /\A[a-z][a-z0-9-]{0,39}\z/
    UNIT_PATTERN = /\A(?:llama-server|soul-[A-Za-z0-9@_.-]+)\.service\z/
    ROOT_KEYS = %w[schema_version default_profile profiles].freeze
    PROFILE_KEYS = %w[id label service].freeze

    class ConfigurationError < StandardError; end

    attr_reader :multi_profile

    def initialize(root: Dir.pwd, env: ENV)
      @root = File.expand_path(root)
      @env = env.to_h
      @multi_profile = false
    end

    def configuration
      file = @env["SOUL_MODEL_RUNTIME_PROFILES_FILE"].to_s.strip
      return legacy_configuration if file.empty?

      @multi_profile = true
      parse_file(resolve_file(file))
    end

    private

    def legacy_configuration
      profile_id = @env["SOUL_MODEL_RUNTIME_PROFILE"].to_s.strip
      profile_id = "local-model" unless profile_id.match?(PROFILE_ID)
      service = @env["SOUL_MODEL_RUNTIME_SERVICE"].to_s
      raise ConfigurationError, "model runtime service is not allowlisted" unless service.match?(UNIT_PATTERN)
      {
        "default_profile" => profile_id,
        "profiles" => [{
          "id" => profile_id,
          "label" => profile_id.tr("-", " ").split.map(&:capitalize).join(" "),
          "service" => service
        }],
        "multi_profile" => false
      }
    end

    def resolve_file(value)
      candidate = File.expand_path(value, @root)
      prefix = @root.end_with?(File::SEPARATOR) ? @root : "#{@root}#{File::SEPARATOR}"
      raise ConfigurationError, "model runtime profiles file must remain inside the project root" unless candidate.start_with?(prefix)

      stat = File.lstat(candidate)
      raise ConfigurationError, "model runtime profiles file must be a regular non-symlink file" unless stat.file? && !stat.symlink?
      raise ConfigurationError, "model runtime profiles file exceeds #{MAX_BYTES} bytes" if stat.size > MAX_BYTES

      candidate
    rescue Errno::ENOENT
      raise ConfigurationError, "model runtime profiles file does not exist"
    end

    def parse_file(path)
      data = YAML.safe_load(File.binread(path, MAX_BYTES), permitted_classes: [], permitted_symbols: [], aliases: false)
      raise ConfigurationError, "model runtime profiles document must be an object" unless data.is_a?(Hash)
      raise ConfigurationError, "model runtime profiles keys must be strings" unless data.keys.all? { |key| key.is_a?(String) }
      raise ConfigurationError, "model runtime profiles document contains unknown keys" unless (data.keys - ROOT_KEYS).empty?
      raise ConfigurationError, "unsupported model runtime profiles schema" unless data["schema_version"] == SCHEMA_VERSION

      rows = data["profiles"]
      raise ConfigurationError, "model runtime profiles must contain one to #{MAX_PROFILES} records" unless rows.is_a?(Array) && rows.length.between?(1, MAX_PROFILES)
      profiles = rows.map { |row| normalize_profile(row) }
      raise ConfigurationError, "model runtime profile IDs must be unique" unless profiles.map { |profile| profile.fetch("id") }.uniq.length == profiles.length
      raise ConfigurationError, "model runtime profile services must be unique" unless profiles.map { |profile| profile.fetch("service") }.uniq.length == profiles.length

      default = data["default_profile"].to_s
      raise ConfigurationError, "default model runtime profile is invalid" unless profiles.any? { |profile| profile.fetch("id") == default }

      { "default_profile" => default, "profiles" => profiles, "multi_profile" => true }
    rescue Psych::Exception => error
      raise ConfigurationError, "invalid model runtime profiles YAML: #{error.class}"
    end

    def normalize_profile(row)
      raise ConfigurationError, "model runtime profile must be an object" unless row.is_a?(Hash)
      raise ConfigurationError, "model runtime profile keys must be strings" unless row.keys.all? { |key| key.is_a?(String) }
      raise ConfigurationError, "model runtime profile contains unknown keys" unless (row.keys - PROFILE_KEYS).empty?
      raise ConfigurationError, "model runtime profile is missing required keys" unless (PROFILE_KEYS - row.keys).empty?

      id = row["id"].to_s
      label = row["label"].to_s.strip
      service = row["service"].to_s
      raise ConfigurationError, "model runtime profile ID is invalid" unless id.match?(PROFILE_ID)
      raise ConfigurationError, "model runtime profile label is invalid" unless label.length.between?(1, 80)
      raise ConfigurationError, "model runtime profile service is not allowlisted" unless service.match?(UNIT_PATTERN)

      { "id" => id, "label" => label, "service" => service }
    end
  end
end
