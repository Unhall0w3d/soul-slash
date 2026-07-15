# frozen_string_literal: true

require "ipaddr"
require "uri"
require_relative "configuration_schema"
require_relative "dotenv_reader"

module SoulCore
  class ConfigurationResolver
    MAX_OVERRIDES = 32
    MAX_ERRORS = 100

    attr_reader :effective_environment

    def initialize(root:, process_env: {}, dotenv_path: nil, overrides: [])
      @root = File.expand_path(root)
      @process_env = stringify_hash(process_env)
      @dotenv_path = dotenv_path
      @override_inputs = Array(overrides)
      @effective_environment = @process_env.dup
    end

    def resolve
      dotenv = DotenvReader.new(root: @root, path: @dotenv_path).read
      unless dotenv.ok?
        return failure_report(
          lifecycle: dotenv.lifecycle_state,
          errors: dotenv.errors,
          dotenv: dotenv
        )
      end

      overrides, override_errors = parse_overrides
      return failure_report(lifecycle: "failed", errors: override_errors, dotenv: dotenv) unless override_errors.empty?

      resolved = {}
      errors = []
      ConfigurationSchema.definitions.each do |definition|
        raw, source, source_key = raw_value(definition, overrides, dotenv.values, resolved)
        begin
          value = coerce(definition, raw)
          resolved[definition.fetch("key")] = {
            "definition" => definition,
            "value" => value,
            "raw" => raw,
            "source" => source,
            "source_key" => source_key,
            "valid" => true
          }
        rescue ArgumentError => error
          errors << { "key" => definition.fetch("key"), "reason" => error.message }
          resolved[definition.fetch("key")] = {
            "definition" => definition,
            "value" => nil,
            "raw" => nil,
            "source" => source,
            "source_key" => source_key,
            "valid" => false
          }
        end
      end

      build_effective_environment(resolved, dotenv.values)
      public_settings = resolved.values.map { |entry| public_entry(entry) }
      lifecycle = errors.empty? ? "complete" : "failed"
      {
        "ok" => errors.empty?,
        "lifecycle_state" => lifecycle,
        "settings" => public_settings,
        "setting_count" => public_settings.length,
        "error_count" => errors.length,
        "errors" => errors.first(MAX_ERRORS),
        "source_counts" => public_settings.group_by { |entry| entry.fetch("source") }.transform_values(&:length),
        "dotenv_loaded" => dotenv.loaded,
        "dotenv_path" => dotenv.relative_path,
        "mutation" => "none"
      }
    end

    private

    def stringify_hash(hash)
      hash.to_h.each_with_object({}) { |(key, value), memo| memo[key.to_s] = value.to_s }
    end

    def parse_overrides
      return [{}, ["too many CLI overrides; maximum is #{MAX_OVERRIDES}"]] if @override_inputs.length > MAX_OVERRIDES

      parsed = {}
      errors = []
      @override_inputs.each do |input|
        text = input.to_s
        unless text.include?("=")
          errors << "CLI override must use canonical.key=value"
          next
        end
        key, value = text.split("=", 2)
        definition = ConfigurationSchema.find(key)
        unless definition
          errors << "unknown configuration key #{key}"
          next
        end
        if definition.fetch("secret")
          errors << "secret configuration key #{key} cannot be set through CLI arguments"
          next
        end
        if parsed.key?(key)
          errors << "duplicate CLI override for #{key}"
          next
        end
        parsed[key] = value
      end
      [parsed, errors.first(MAX_ERRORS)]
    end

    def raw_value(definition, overrides, dotenv, resolved)
      key = definition.fetch("key")
      return [overrides.fetch(key), "cli_override", key] if overrides.key?(key)

      environment_names = environment_names_for(definition, resolved)
      process_key = environment_names.find { |name| @process_env.key?(name) }
      return [@process_env.fetch(process_key), "process_environment", process_key] if process_key

      dotenv_key = environment_names.find { |name| dotenv.key?(name) }
      return [dotenv.fetch(dotenv_key), "dotenv", dotenv_key] if dotenv_key

      [definition.fetch("default"), "default", nil]
    end

    def environment_names_for(definition, resolved)
      if definition.fetch("type") == "secret"
        credential = resolved.dig("providers.cloud_openai.credential_env", "value").to_s
        return [credential.empty? ? definition.fetch("environment") : credential]
      end

      [definition.fetch("environment"), *definition.fetch("aliases")]
    end

    def coerce(definition, raw)
      type = definition.fetch("type")
      return nil if type == "secret" && raw.nil?

      text = raw.to_s.strip
      case type
      when "boolean"
        return true if %w[1 true yes on].include?(text.downcase)
        return false if %w[0 false no off].include?(text.downcase)
        raise ArgumentError, "must be a boolean"
      when "integer"
        value = Integer(text, 10)
        validate_range!(definition, value)
      when "float"
        value = Float(text)
        raise ArgumentError, "must be finite" unless value.finite?
        validate_range!(definition, value)
      when "enum"
        values = definition.fetch("values")
        raise ArgumentError, "must be one of #{values.reject(&:empty?).join(', ')}" unless values.include?(text)
        text
      when "url"
        return "" if text.empty? && definition.fetch("allow_empty")
        uri = URI.parse(text)
        raise ArgumentError, "must be an HTTP or HTTPS URL" unless %w[http https].include?(uri.scheme) && !uri.host.to_s.empty?
        text
      when "https_origin"
        return "" if text.empty? && definition.fetch("allow_empty")
        uri = URI.parse(text)
        valid_path = uri.path.to_s.empty? || uri.path == "/"
        raise ArgumentError, "must be an exact HTTPS origin" unless uri.scheme == "https" && !uri.host.to_s.empty? && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? && valid_path
        host = uri.host.include?(":") ? "[#{uri.host}]" : uri.host
        "https://#{host}#{uri.port == 443 ? '' : ":#{uri.port}"}"
      when "env_name"
        raise ArgumentError, "must be an uppercase environment identifier" unless text.match?(DotenvReader::ENV_NAME)
        text
      when "loopback_host"
        raise ArgumentError, "must be a loopback host" unless loopback?(text)
        text
      when "secret"
        text.empty? ? nil : text
      when "string"
        text
      else
        raise ArgumentError, "has unsupported schema type"
      end
    rescue URI::InvalidURIError
      raise ArgumentError, type == "https_origin" ? "must be an exact HTTPS origin" : "must be an HTTP or HTTPS URL"
    rescue ArgumentError => error
      raise error if error.message.start_with?("must ", "has ")

      raise ArgumentError, "must be a #{type}"
    end

    def validate_range!(definition, value)
      range = definition.fetch("range")
      raise ArgumentError, "must be between #{range.begin} and #{range.end}" unless range.cover?(value)

      value
    end

    def loopback?(value)
      return true if value == "localhost"

      IPAddr.new(value).loopback?
    rescue IPAddr::InvalidAddressError
      false
    end

    def build_effective_environment(resolved, dotenv)
      @effective_environment = dotenv.merge(@process_env)
      resolved.each_value do |entry|
        next unless entry.fetch("valid")

        definition = entry.fetch("definition")
        value = entry.fetch("value")
        next if definition.fetch("secret")

        @effective_environment[definition.fetch("environment")] = environment_value(value)
      end
      @effective_environment.freeze
    end

    def environment_value(value)
      return value ? "1" : "0" if value == true || value == false

      value.to_s
    end

    def public_entry(entry)
      definition = entry.fetch("definition")
      secret = definition.fetch("secret")
      value = entry.fetch("value")
      {
        "key" => definition.fetch("key"),
        "value" => secret ? (value.nil? ? nil : "[REDACTED]") : value,
        "configured" => secret ? !value.nil? : nil,
        "source" => entry.fetch("source"),
        "source_key" => entry.fetch("source_key"),
        "type" => definition.fetch("type"),
        "valid" => entry.fetch("valid"),
        "default" => secret ? nil : definition.fetch("default"),
        "accepted_values" => accepted_values(definition),
        "behavioral_effect" => definition.fetch("behavioral_effect"),
        "privacy_risk" => definition.fetch("privacy_risk"),
        "restart_required" => definition.fetch("restart_required"),
        "secret" => secret,
        "environment" => definition.fetch("environment"),
        "aliases" => definition.fetch("aliases")
      }.compact
    end

    def accepted_values(definition)
      return definition.fetch("values") if definition.fetch("values")
      range = definition.fetch("range")
      return { "minimum" => range.begin, "maximum" => range.end } if range

      definition.fetch("type")
    end

    def failure_report(lifecycle:, errors:, dotenv:)
      @effective_environment = @process_env.dup.freeze
      {
        "ok" => false,
        "lifecycle_state" => lifecycle,
        "settings" => [],
        "setting_count" => 0,
        "error_count" => Array(errors).length,
        "errors" => Array(errors).first(MAX_ERRORS),
        "source_counts" => {},
        "dotenv_loaded" => false,
        "dotenv_path" => dotenv.relative_path,
        "mutation" => "none"
      }
    end
  end
end
