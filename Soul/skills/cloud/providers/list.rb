#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "time"

ROOT = File.expand_path("../../../..", __dir__)
$LOAD_PATH.unshift(File.join(ROOT, "lib"))

begin
  require "soul_core/env_loader"
  SoulCore::EnvLoader.load if defined?(SoulCore::EnvLoader)
rescue LoadError
  # .env loading is optional for this skill. Shell env still works.
end

require "soul_core/cloud_provider_config"

module SoulSkills
  module CloudProviders
    class List
      def initialize(argv)
        @argv = argv
      end

      def run
        path = option_value("--config")
        config = SoulCore::CloudProviderConfig.load(path: path)

        if @argv.include?("--help") || @argv.include?("-h")
          puts help_text
          return 0
        end

        result = build_result(config)
        puts JSON.pretty_generate(result)
        config.valid? ? 0 : 1
      rescue StandardError => e
        puts JSON.pretty_generate(
          {
            "skill" => "cloud.providers.list",
            "generated_at" => Time.now.iso8601,
            "status" => "error",
            "outcome" => "failed",
            "error" => {
              "class" => e.class.name,
              "message" => e.message
            },
            "verification" => {
              "read_only" => true,
              "network_used" => false,
              "secrets_printed" => false,
              "complete" => false,
              "final_state" => "failed"
            }
          }
        )
        1
      end

      private

      def build_result(config)
        providers = config.providers.map do |provider|
          provider_hash(provider)
        end

        {
          "skill" => "cloud.providers.list",
          "generated_at" => Time.now.iso8601,
          "status" => config.valid? ? "ok" : "warning",
          "outcome" => "complete",
          "config" => {
            "path" => config.path,
            "configured" => File.exist?(config.path),
            "cloud_llm_enabled" => config.enabled?,
            "provider_count" => providers.length,
            "enabled_provider_count" => providers.count { |item| item["enabled"] }
          },
          "providers" => providers,
          "errors" => config.errors,
          "warnings" => config.warnings,
          "recommendation" => recommendation(config, providers),
          "verification" => {
            "read_only" => true,
            "network_used" => false,
            "secrets_printed" => false,
            "api_key_values_printed" => false,
            "complete" => true,
            "final_state" => "complete"
          }
        }
      end

      def provider_hash(provider)
        {
          "name" => provider.name,
          "enabled" => provider.enabled,
          "auth_mode" => provider.auth_mode,
          "api_key_env" => provider.api_key_env,
          "api_key_present" => provider.api_key_present?,
          "base_url" => provider.base_url,
          "default_model" => provider.default_model,
          "requires_credit_card" => provider.requires_credit_card,
          "credit_card_policy" => provider.credit_card_policy,
          "programmatic_key_acquisition" => provider.programmatic_key_acquisition,
          "trust_level" => provider.trust_level,
          "roles" => provider.roles,
          "notes" => provider.notes,
          "status" => provider_status(provider)
        }
      end

      def provider_status(provider)
        return "disabled" unless provider.enabled
        return "ready_for_no_key_smoke_test" if provider.no_key?
        return "blocked_missing_manual_api_key" if provider.manual_key_required? && !provider.api_key_present?
        return "ready_for_manual_key_smoke_test" if provider.manual_key_required? && provider.api_key_present?

        "configured"
      end

      def recommendation(config, providers)
        return "Provider configuration has validation errors. Review errors before enabling cloud assist." unless config.valid?

        enabled = providers.select { |item| item["enabled"] }
        return "Cloud provider config is readable. No providers are enabled yet. That is safe for the policy scaffold stage." if enabled.empty?

        blocked = enabled.select { |item| item["status"] == "blocked_missing_manual_api_key" }
        no_key = enabled.select { |item| item["status"] == "ready_for_no_key_smoke_test" }
        manual = enabled.select { |item| item["status"] == "ready_for_manual_key_smoke_test" }

        parts = []
        parts << "#{no_key.length} no-key provider(s) ready for smoke testing." unless no_key.empty?
        parts << "#{manual.length} manual-key provider(s) ready for smoke testing." unless manual.empty?
        parts << "#{blocked.length} manual-key provider(s) blocked because the expected environment variable is missing." unless blocked.empty?
        parts.empty? ? "Provider config is readable. No provider is ready for testing yet." : parts.join(" ")
      end

      def option_value(flag)
        idx = @argv.index(flag)
        return nil unless idx

        @argv[idx + 1]
      end

      def help_text
        <<~TEXT
          cloud.providers.list

          Lists configured cloud LLM providers without making network calls.

          Usage:
            ruby Soul/skills/cloud/providers/list.rb
            ruby Soul/skills/cloud/providers/list.rb --config Soul/config/cloud_providers.yaml

          Notes:
            - Does not print API key values.
            - Does not test providers.
            - Does not write .env.
            - Does not make outbound network calls.
        TEXT
      end
    end
  end
end

exit SoulSkills::CloudProviders::List.new(ARGV).run
