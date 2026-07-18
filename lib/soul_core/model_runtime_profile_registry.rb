# frozen_string_literal: true

require "json"
require "uri"
require "yaml"

module SoulCore
  class ModelRuntimeProfileRegistry
    SCHEMA_VERSION = "soul.model_runtime_profiles.v3"
    V2_SCHEMA_VERSION = "soul.model_runtime_profiles.v2"
    LEGACY_SCHEMA_VERSION = "soul.model_runtime_profiles.v1"
    MAX_BYTES = 32 * 1024
    MAX_PROFILES = 4
    PROFILE_ID = /\A[a-z][a-z0-9-]{0,39}\z/
    UNIT_PATTERN = /\A(?:llama-server|soul-[A-Za-z0-9@_.-]+)\.service\z/
    ROOT_KEYS = %w[schema_version default_profile profiles].freeze
    PROFILE_KEYS = %w[id label model_name api_model runtime accelerator service endpoint core_role].freeze
    V2_PROFILE_KEYS = %w[id label model_name accelerator service].freeze
    LEGACY_PROFILE_KEYS = %w[id label service].freeze
    RUNTIMES = %w[llamacpp_openai ollama_openai].freeze
    CORE_ROLES = %w[daily-chat reserve-chat music-chat specialist].freeze

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

    def selected_profile
      config = configuration
      id = config.fetch("default_profile")
      path = File.join(@root, "Soul/runtime/model_runtime/selected_profile.json")
      if File.exist?(path)
        stat = File.lstat(path)
        raise ConfigurationError, "model runtime selection must be a regular non-symlink file" unless stat.file? && !stat.symlink?
        raise ConfigurationError, "model runtime selection exceeds size limit" if stat.size > 1024

        record = JSON.parse(File.binread(path, 1024))
        id = record["profile_id"].to_s
        raise ConfigurationError, "model runtime selection is invalid" unless record.keys == ["profile_id"]
      end
      config.fetch("profiles").find { |profile| profile.fetch("id") == id } ||
        raise(ConfigurationError, "model runtime selection is invalid")
    rescue JSON::ParserError
      raise ConfigurationError, "model runtime selection is invalid"
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
          "model_name" => configured_model_name,
          "api_model" => configured_model_name,
          "runtime" => "llamacpp_openai",
          "accelerator" => "Configured local runtime",
          "service" => service,
          "endpoint" => configured_endpoint,
          "core_role" => "daily-chat"
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
      schema = data["schema_version"]
      raise ConfigurationError, "unsupported model runtime profiles schema" unless [LEGACY_SCHEMA_VERSION, V2_SCHEMA_VERSION, SCHEMA_VERSION].include?(schema)

      rows = data["profiles"]
      raise ConfigurationError, "model runtime profiles must contain one to #{MAX_PROFILES} records" unless rows.is_a?(Array) && rows.length.between?(1, MAX_PROFILES)
      profiles = rows.map { |row| normalize_profile(row, schema: schema) }
      raise ConfigurationError, "model runtime profile IDs must be unique" unless profiles.map { |profile| profile.fetch("id") }.uniq.length == profiles.length
      raise ConfigurationError, "model runtime profile services must be unique" unless profiles.map { |profile| profile.fetch("service") }.uniq.length == profiles.length

      default = data["default_profile"].to_s
      raise ConfigurationError, "default model runtime profile is invalid" unless profiles.any? { |profile| profile.fetch("id") == default }

      { "default_profile" => default, "profiles" => profiles, "multi_profile" => true }
    rescue Psych::Exception => error
      raise ConfigurationError, "invalid model runtime profiles YAML: #{error.class}"
    end

    def normalize_profile(row, schema:)
      raise ConfigurationError, "model runtime profile must be an object" unless row.is_a?(Hash)
      raise ConfigurationError, "model runtime profile keys must be strings" unless row.keys.all? { |key| key.is_a?(String) }
      keys = if schema == LEGACY_SCHEMA_VERSION
               LEGACY_PROFILE_KEYS
             elsif schema == V2_SCHEMA_VERSION
               V2_PROFILE_KEYS
             else
               PROFILE_KEYS
             end
      raise ConfigurationError, "model runtime profile contains unknown keys" unless (row.keys - keys).empty?
      raise ConfigurationError, "model runtime profile is missing required keys" unless (keys - row.keys).empty?

      id = row["id"].to_s
      label = row["label"].to_s.strip
      model_name = schema == LEGACY_SCHEMA_VERSION ? configured_model_name : row["model_name"].to_s.strip
      api_model = schema == SCHEMA_VERSION ? row["api_model"].to_s.strip : configured_model_name
      runtime = schema == SCHEMA_VERSION ? row["runtime"].to_s : "llamacpp_openai"
      accelerator = schema == LEGACY_SCHEMA_VERSION ? "Legacy profile" : row["accelerator"].to_s.strip
      service = row["service"].to_s
      endpoint = schema == SCHEMA_VERSION ? row["endpoint"].to_s.strip : configured_endpoint
      core_role = schema == SCHEMA_VERSION ? row["core_role"].to_s : "daily-chat"
      raise ConfigurationError, "model runtime profile ID is invalid" unless id.match?(PROFILE_ID)
      raise ConfigurationError, "model runtime profile label is invalid" unless label.length.between?(1, 80)
      raise ConfigurationError, "model runtime profile model_name is invalid" unless model_name.length.between?(1, 120)
      raise ConfigurationError, "model runtime profile api_model is invalid" unless api_model.length.between?(1, 120)
      raise ConfigurationError, "model runtime profile runtime is invalid" unless RUNTIMES.include?(runtime)
      raise ConfigurationError, "model runtime profile accelerator is invalid" unless accelerator.length.between?(1, 80)
      raise ConfigurationError, "model runtime profile service is not allowlisted" unless service.match?(UNIT_PATTERN)
      raise ConfigurationError, "model runtime profile endpoint must be loopback OpenAI v1" unless loopback_openai_endpoint?(endpoint)
      raise ConfigurationError, "model runtime profile core_role is invalid" unless CORE_ROLES.include?(core_role)

      { "id" => id, "label" => label, "model_name" => model_name, "api_model" => api_model,
        "runtime" => runtime, "accelerator" => accelerator, "service" => service,
        "endpoint" => endpoint, "core_role" => core_role }
    end

    def configured_model_name
      value = (@env["SOUL_LOCAL_OPENAI_MODEL"] || @env["SOUL_MODEL_ALIAS"]).to_s.strip
      value.empty? ? "Configured local model" : value
    end

    def configured_endpoint
      value = (@env["SOUL_LOCAL_OPENAI_BASE_URL"] || @env["SOUL_OPENAI_BASE_URL"]).to_s.strip
      value.empty? ? "http://127.0.0.1:8082/v1" : value
    end

    def loopback_openai_endpoint?(value)
      uri = URI.parse(value)
      uri.is_a?(URI::HTTP) && uri.scheme == "http" && %w[127.0.0.1 localhost ::1].include?(uri.host) &&
        uri.path == "/v1" && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil?
    rescue URI::InvalidURIError
      false
    end
  end
end
