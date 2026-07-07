# frozen_string_literal: true

require "yaml"

module SoulCore
  class CloudProviderConfig
    DEFAULT_PATH = "Soul/config/cloud_providers.yaml"
    EXAMPLE_PATH = "Soul/config/cloud_providers.example.yaml"

    ALLOWED_AUTH_MODES = %w[
      none
      manual_api_key
      official_oauth_device_flow
      unsupported
    ].freeze

    ALLOWED_TRUST_LEVELS = %w[
      serious_manual_key_provider
      experimental_no_key_probe
      optional_manual_key_provider
      unsupported
    ].freeze

    REQUIRED_PROVIDER_KEYS = %w[
      enabled
      auth_mode
      requires_credit_card
      programmatic_key_acquisition
      trust_level
      roles
    ].freeze

    Provider = Struct.new(
      :name,
      :enabled,
      :auth_mode,
      :api_key_env,
      :base_url,
      :default_model,
      :requires_credit_card,
      :credit_card_policy,
      :programmatic_key_acquisition,
      :trust_level,
      :roles,
      :notes,
      keyword_init: true
    ) do
      def api_key_present?
        return false if api_key_env.to_s.strip.empty?

        ENV.key?(api_key_env.to_s) && !ENV.fetch(api_key_env.to_s, "").to_s.empty?
      end

      def manual_key_required?
        auth_mode == "manual_api_key"
      end

      def no_key?
        auth_mode == "none"
      end

      def to_h
        {
          "name" => name,
          "enabled" => enabled,
          "auth_mode" => auth_mode,
          "api_key_env" => api_key_env,
          "api_key_present" => api_key_present?,
          "base_url" => base_url,
          "default_model" => default_model,
          "requires_credit_card" => requires_credit_card,
          "credit_card_policy" => credit_card_policy,
          "programmatic_key_acquisition" => programmatic_key_acquisition,
          "trust_level" => trust_level,
          "roles" => roles,
          "notes" => notes
        }
      end
    end

    attr_reader :path, :raw, :errors, :warnings

    def initialize(path: nil)
      @path = resolve_path(path)
      @raw = {}
      @errors = []
      @warnings = []
      load
      validate
    end

    def self.load(path: nil)
      new(path: path)
    end

    def valid?
      errors.empty?
    end

    def enabled?
      !!raw.dig("cloud_llm", "enabled")
    end

    def default_policy
      raw.dig("cloud_llm", "default_policy") || {}
    end

    def providers
      provider_hash.map do |name, config|
        provider_from_hash(name, config || {})
      end
    end

    def enabled_providers
      providers.select(&:enabled)
    end

    def provider(name)
      providers.find { |item| item.name == name.to_s }
    end

    def providers_for_role(role)
      providers.select { |item| item.enabled && item.roles.include?(role.to_s) }
    end

    def summary
      {
        "path" => path,
        "configured" => File.exist?(path),
        "cloud_llm_enabled" => enabled?,
        "provider_count" => providers.length,
        "enabled_provider_count" => enabled_providers.length,
        "errors" => errors,
        "warnings" => warnings,
        "providers" => providers.map(&:to_h)
      }
    end

    private

    def resolve_path(path)
      explicit = path.to_s.strip
      return explicit unless explicit.empty?

      File.exist?(DEFAULT_PATH) ? DEFAULT_PATH : EXAMPLE_PATH
    end

    def load
      unless File.exist?(path)
        @errors << "Provider config not found: #{path}"
        @raw = {}
        return
      end

      parsed = YAML.safe_load(File.read(path), aliases: true)
      @raw = parsed.is_a?(Hash) ? parsed : {}
    rescue Psych::SyntaxError => e
      @errors << "YAML syntax error in #{path}: #{e.message}"
      @raw = {}
    rescue StandardError => e
      @errors << "Failed to load #{path}: #{e.class}: #{e.message}"
      @raw = {}
    end

    def validate
      validate_root
      validate_policy
      validate_providers
    end

    def validate_root
      unless raw.key?("cloud_llm")
        @errors << "Missing root key: cloud_llm"
        return
      end

      unless raw["cloud_llm"].is_a?(Hash)
        @errors << "cloud_llm must be a mapping"
      end
    end

    def validate_policy
      policy = default_policy
      return if policy.empty?

      boolean_keys = %w[
        output_mode
        send_secrets
        send_private_repo_content
        send_user_memory
        allow_direct_repo_mutation
        prefer_no_key_for_experiments
        allow_manual_no_credit_card_keys
        forbid_unofficial_key_acquisition
      ]

      boolean_keys.each do |key|
        next unless policy.key?(key)
        next if key == "output_mode"
        next if [true, false].include?(policy[key])

        @warnings << "default_policy.#{key} should be true or false"
      end

      if policy["allow_direct_repo_mutation"] == true
        @errors << "default_policy.allow_direct_repo_mutation must not be true"
      end

      if policy["send_secrets"] == true
        @errors << "default_policy.send_secrets must not be true"
      end
    end

    def validate_providers
      unless provider_hash.is_a?(Hash)
        @errors << "cloud_llm.providers must be a mapping"
        return
      end

      provider_hash.each do |name, config|
        validate_provider(name, config || {})
      end
    end

    def validate_provider(name, config)
      unless config.is_a?(Hash)
        @errors << "Provider #{name} must be a mapping"
        return
      end

      REQUIRED_PROVIDER_KEYS.each do |key|
        @errors << "Provider #{name} missing required key: #{key}" unless config.key?(key)
      end

      auth_mode = config["auth_mode"].to_s
      unless ALLOWED_AUTH_MODES.include?(auth_mode)
        @errors << "Provider #{name} has invalid auth_mode: #{auth_mode.inspect}"
      end

      trust_level = config["trust_level"].to_s
      unless ALLOWED_TRUST_LEVELS.include?(trust_level)
        @warnings << "Provider #{name} has unrecognized trust_level: #{trust_level.inspect}"
      end

      unless [true, false].include?(config["enabled"])
        @errors << "Provider #{name} enabled must be true or false"
      end

      roles = config["roles"]
      if !roles.is_a?(Array) || roles.empty?
        @errors << "Provider #{name} roles must be a non-empty list"
      elsif roles.any? { |role| role.to_s.strip.empty? }
        @errors << "Provider #{name} roles must not contain blank values"
      end

      if auth_mode == "manual_api_key" && config["api_key_env"].to_s.strip.empty?
        @errors << "Provider #{name} uses manual_api_key but api_key_env is blank"
      end

      if auth_mode == "none" && !config["api_key_env"].to_s.strip.empty?
        @warnings << "Provider #{name} auth_mode is none but api_key_env is set"
      end

      if config["programmatic_key_acquisition"].to_s !~ /\A(unsupported|not_applicable|official_oauth_device_flow|official_cli_flow|manual_only)\z/
        @warnings << "Provider #{name} has unusual programmatic_key_acquisition value: #{config['programmatic_key_acquisition']}"
      end

      if config["requires_credit_card"] == true
        @errors << "Provider #{name} requires a credit card and is not eligible by default"
      end

      if config["enabled"] == true && config["requires_credit_card"].to_s =~ /unknown/i
        @warnings << "Provider #{name} is enabled with unknown credit-card policy"
      end
    end

    def provider_hash
      raw.dig("cloud_llm", "providers") || {}
    end

    def provider_from_hash(name, config)
      Provider.new(
        name: name.to_s,
        enabled: !!config["enabled"],
        auth_mode: config["auth_mode"].to_s,
        api_key_env: blank_to_nil(config["api_key_env"]),
        base_url: blank_to_nil(config["base_url"]),
        default_model: blank_to_nil(config["default_model"]),
        requires_credit_card: config["requires_credit_card"],
        credit_card_policy: blank_to_nil(config["credit_card_policy"]),
        programmatic_key_acquisition: blank_to_nil(config["programmatic_key_acquisition"]),
        trust_level: blank_to_nil(config["trust_level"]),
        roles: Array(config["roles"]).map(&:to_s),
        notes: Array(config["notes"]).map(&:to_s)
      )
    end

    def blank_to_nil(value)
      text = value.to_s.strip
      text.empty? ? nil : text
    end
  end
end
