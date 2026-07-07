#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require "time"
require "fileutils"

ROOT = File.expand_path("../../../..", __dir__)
$LOAD_PATH.unshift(File.join(ROOT, "lib"))

begin
  require "soul_core/env_loader"
  SoulCore::EnvLoader.load if defined?(SoulCore::EnvLoader)
rescue LoadError
  # .env loading is optional. Shell environment still works.
end

require "soul_core/cloud_provider_config"

module SoulSkills
  module CloudProviders
    class Test
      EXPECTED = "SOUL_PROVIDER_TEST_OK"
      DEFAULT_TIMEOUT_SECONDS = 30

      def initialize(argv)
        @argv = argv
      end

      def run
        if @argv.include?("--help") || @argv.include?("-h")
          puts help_text
          return 0
        end

        config = SoulCore::CloudProviderConfig.load(path: option_value("--config"))
        selected_provider = option_value("--provider")

        result =
          if !config.valid?
            build_config_error_result(config)
          elsif selected_provider
            test_one(config, selected_provider)
          else
            test_enabled(config)
          end

        log_path = write_log(result)
        result["task_log"] = log_path if log_path
        puts JSON.pretty_generate(result)

        result["status"] == "error" ? 1 : 0
      rescue StandardError => e
        result = {
          "skill" => "cloud.providers.test",
          "generated_at" => Time.now.iso8601,
          "status" => "error",
          "outcome" => "failed",
          "error" => {
            "class" => e.class.name,
            "message" => e.message
          },
          "verification" => verification(false)
        }
        log_path = write_log(result)
        result["task_log"] = log_path if log_path
        puts JSON.pretty_generate(result)
        1
      end

      private

      def test_enabled(config)
        providers = config.enabled_providers

        if providers.empty?
          return {
            "skill" => "cloud.providers.test",
            "generated_at" => Time.now.iso8601,
            "status" => "warning",
            "outcome" => "blocked_for_input",
            "config" => config_summary(config),
            "tests" => [],
            "recommendation" => "No cloud providers are enabled. Enable a provider in Soul/config/cloud_providers.yaml before smoke testing.",
            "verification" => verification(true)
          }
        end

        tests = providers.map { |provider| test_provider(provider) }
        aggregate_result(config, tests)
      end

      def test_one(config, provider_name)
        provider = config.provider(provider_name)

        unless provider
          return {
            "skill" => "cloud.providers.test",
            "generated_at" => Time.now.iso8601,
            "status" => "error",
            "outcome" => "failed",
            "config" => config_summary(config),
            "tests" => [],
            "errors" => ["Unknown provider: #{provider_name}"],
            "verification" => verification(false)
          }
        end

        aggregate_result(config, [test_provider(provider)])
      end

      def test_provider(provider)
        started_at = Time.now

        base = {
          "provider" => provider.name,
          "enabled" => provider.enabled,
          "auth_mode" => provider.auth_mode,
          "api_key_env" => provider.api_key_env,
          "api_key_present" => provider.api_key_present?,
          "base_url" => provider.base_url,
          "model" => option_value("--model") || provider.default_model,
          "role" => "cloud_smoke_test",
          "purpose" => "provider_smoke_test",
          "data_class" => "tiny_test_prompt",
          "secrets_included" => false,
          "private_repo_content_included" => false,
          "user_memory_included" => false,
          "output_mode" => "review_artifact_only",
          "expected_response" => EXPECTED,
          "started_at" => started_at.iso8601
        }

        return base.merge(disabled_result) unless provider.enabled
        return base.merge(unsupported_provider_result(provider)) unless provider.name == "mistral"
        return base.merge(missing_key_result(provider)) if provider.manual_key_required? && !provider.api_key_present?

        mistral_test(provider, base)
      rescue StandardError => e
        base.merge(
          "status" => "error",
          "outcome" => "failed",
          "error_class" => e.class.name,
          "error_message" => e.message,
          "completed_at" => Time.now.iso8601,
          "duration_seconds" => elapsed(started_at)
        )
      end

      def mistral_test(provider, base)
        model = base["model"]
        return base.merge(config_error("Mistral default_model is missing.")) if model.to_s.strip.empty?
        return base.merge(config_error("Mistral base_url is missing.")) if provider.base_url.to_s.strip.empty?

        endpoint = join_url(provider.base_url, "/chat/completions")
        uri = URI(endpoint)

        body = {
          "model" => model,
          "messages" => [
            {
              "role" => "user",
              "content" => "Reply with exactly: #{EXPECTED}"
            }
          ],
          "temperature" => 0,
          "max_tokens" => 16
        }

        response = nil
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: DEFAULT_TIMEOUT_SECONDS, open_timeout: DEFAULT_TIMEOUT_SECONDS) do |http|
          request = Net::HTTP::Post.new(uri)
          request["Authorization"] = "Bearer #{ENV.fetch(provider.api_key_env)}"
          request["Content-Type"] = "application/json"
          request["Accept"] = "application/json"
          request.body = JSON.generate(body)
          response = http.request(request)
        end

        parsed = parse_json(response.body)
        assistant_text = parsed.dig("choices", 0, "message", "content").to_s.strip
        exact = assistant_text == EXPECTED
        ok_http = response.code.to_i.between?(200, 299)

        status =
          if ok_http && exact
            "ok"
          elsif ok_http
            "warning"
          else
            "error"
          end

        outcome = status == "error" ? "failed" : "complete"

        base.merge(
          "status" => status,
          "outcome" => outcome,
          "endpoint" => endpoint,
          "http_status" => response.code.to_i,
          "response_body_present" => !response.body.to_s.empty?,
          "assistant_text" => assistant_text,
          "exact_match" => exact,
          "error_message" => ok_http ? nil : mistral_error(parsed, response),
          "completed_at" => Time.now.iso8601,
          "duration_seconds" => elapsed(Time.parse(base["started_at"]))
        )
      end

      def aggregate_result(config, tests)
        statuses = tests.map { |test| test["status"] }

        status =
          if statuses.include?("error")
            "error"
          elsif statuses.include?("warning") || statuses.include?("blocked_for_input")
            "warning"
          else
            "ok"
          end

        {
          "skill" => "cloud.providers.test",
          "generated_at" => Time.now.iso8601,
          "status" => status,
          "outcome" => status == "error" ? "failed" : "complete",
          "config" => config_summary(config),
          "tests" => tests,
          "recommendation" => recommendation(tests),
          "verification" => verification(status != "error")
        }
      end

      def build_config_error_result(config)
        {
          "skill" => "cloud.providers.test",
          "generated_at" => Time.now.iso8601,
          "status" => "error",
          "outcome" => "failed",
          "config" => config_summary(config),
          "tests" => [],
          "errors" => config.errors,
          "warnings" => config.warnings,
          "verification" => verification(false)
        }
      end

      def config_summary(config)
        {
          "path" => config.path,
          "cloud_llm_enabled" => config.enabled?,
          "valid" => config.valid?,
          "errors" => config.errors,
          "warnings" => config.warnings
        }
      end

      def disabled_result
        {
          "status" => "warning",
          "outcome" => "blocked_for_input",
          "error_message" => "Provider is disabled in config. Enable it in Soul/config/cloud_providers.yaml before testing.",
          "completed_at" => Time.now.iso8601
        }
      end

      def unsupported_provider_result(provider)
        {
          "status" => "warning",
          "outcome" => "blocked_for_human_review",
          "error_message" => "Provider #{provider.name} is configured, but this overlay only implements Mistral smoke testing.",
          "completed_at" => Time.now.iso8601
        }
      end

      def missing_key_result(provider)
        {
          "status" => "warning",
          "outcome" => "blocked_for_input",
          "error_message" => "Missing environment variable #{provider.api_key_env}. Create the key manually, store it in .env or shell environment, and rerun the smoke test.",
          "completed_at" => Time.now.iso8601
        }
      end

      def config_error(message)
        {
          "status" => "error",
          "outcome" => "failed",
          "error_message" => message,
          "completed_at" => Time.now.iso8601
        }
      end

      def verification(complete)
        {
          "read_only" => true,
          "network_used" => true,
          "secrets_printed" => false,
          "api_key_values_printed" => false,
          "private_repo_content_sent" => false,
          "user_memory_sent" => false,
          "tiny_test_prompt_only" => true,
          "complete" => complete,
          "final_state" => complete ? "complete" : "failed"
        }
      end

      def recommendation(tests)
        return "Provider smoke test passed." if tests.all? { |test| test["status"] == "ok" }

        missing = tests.select { |test| test["outcome"] == "blocked_for_input" }
        errors = tests.select { |test| test["status"] == "error" }
        warnings = tests.select { |test| test["status"] == "warning" }

        parts = []
        parts << "#{missing.length} provider(s) need configuration before testing." unless missing.empty?
        parts << "#{errors.length} provider(s) failed smoke testing." unless errors.empty?
        parts << "#{warnings.length} provider(s) returned warnings." unless warnings.empty?
        parts.join(" ")
      end

      def join_url(base, suffix)
        base.to_s.sub(%r{/\z}, "") + suffix
      end

      def parse_json(text)
        JSON.parse(text.to_s)
      rescue JSON::ParserError
        {}
      end

      def mistral_error(parsed, response)
        parsed.dig("message") ||
          parsed.dig("error", "message") ||
          parsed.dig("detail") ||
          "HTTP #{response.code}"
      end

      def elapsed(started_at)
        (Time.now - started_at).round(3)
      end

      def write_log(result)
        dir = File.join(ROOT, "Soul", "logs", "tasks")
        FileUtils.mkdir_p(dir)
        stamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
        path = File.join(dir, "#{stamp}-cloud.providers.test.json")
        File.write(path, JSON.pretty_generate(result) + "\n")
        path.sub("#{ROOT}/", "")
      rescue StandardError
        nil
      end

      def option_value(flag)
        idx = @argv.index(flag)
        return nil unless idx

        @argv[idx + 1]
      end

      def help_text
        <<~TEXT
          cloud.providers.test

          Runs bounded smoke tests for configured cloud LLM providers.

          Usage:
            ruby Soul/skills/cloud/providers/test.rb
            ruby Soul/skills/cloud/providers/test.rb --provider mistral
            ruby Soul/skills/cloud/providers/test.rb --provider mistral --config Soul/config/cloud_providers.yaml
            ruby Soul/skills/cloud/providers/test.rb --provider mistral --model mistral-small-latest

          Notes:
            - This overlay implements Mistral smoke testing only.
            - It sends only a tiny smoke-test prompt.
            - It does not send repo content, user memory, or secrets.
            - It never prints API key values.
            - Mistral account/API-key setup must be manual.
        TEXT
      end
    end
  end
end

exit SoulSkills::CloudProviders::Test.new(ARGV).run
