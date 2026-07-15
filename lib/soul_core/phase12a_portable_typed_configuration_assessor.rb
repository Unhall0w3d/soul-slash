# frozen_string_literal: true

require "fileutils"
require "json"
require "stringio"
require "tmpdir"
require_relative "configuration_command"
require_relative "configuration_resolver"
require_relative "configuration_schema"
require_relative "conversation_provider_registry"

module SoulCore
  class Phase12aPortableTypedConfigurationAssessor
    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      checks = {}
      details = {}

      Dir.mktmpdir("soul-phase12a-") do |temp_root|
        empty_env = {}
        defaults_resolver = ConfigurationResolver.new(root: temp_root, process_env: empty_env)
        defaults = defaults_resolver.resolve
        checks["safe_defaults_are_typed_and_read_only"] =
          defaults["ok"] && defaults["setting_count"] == 21 &&
          setting(defaults, "providers.local_openai.model")["value"] == "" &&
          setting(defaults, "dashboard.bind_host")["value"] == "127.0.0.1" &&
          empty_env.empty? && !File.exist?(File.join(temp_root, ".env"))

        File.write(
          File.join(temp_root, ".env"),
          <<~ENVFILE
            SOUL_LOCAL_OPENAI_BASE_URL=http://dotenv.example:8080/v1
            SOUL_LOCAL_OPENAI_MODEL=dotenv-model
            SOUL_CONVERSATION_MAX_MESSAGES=7
          ENVFILE
        )
        process = {
          "SOUL_OPENAI_BASE_URL" => "http://process-alias.example:8081/v1",
          "SOUL_CONVERSATION_MAX_MESSAGES" => "9"
        }
        precedence = ConfigurationResolver.new(
          root: temp_root,
          process_env: process,
          overrides: ["conversation.max_messages=11"]
        ).resolve
        checks["precedence_and_cross_layer_aliases_are_deterministic"] =
          setting(precedence, "conversation.max_messages").slice("value", "source") == { "value" => 11, "source" => "cli_override" } &&
          setting(precedence, "providers.local_openai.endpoint").slice("value", "source", "source_key") == {
            "value" => "http://process-alias.example:8081/v1",
            "source" => "process_environment",
            "source_key" => "SOUL_OPENAI_BASE_URL"
          } &&
          setting(precedence, "providers.local_openai.model")["source"] == "dotenv"

        same_layer = ConfigurationResolver.new(
          root: temp_root,
          process_env: {
            "SOUL_LOCAL_OPENAI_BASE_URL" => "http://primary.example:8080/v1",
            "SOUL_OPENAI_BASE_URL" => "http://alias.example:8080/v1"
          }
        ).resolve
        checks["precedence_and_cross_layer_aliases_are_deterministic"] &&=
          setting(same_layer, "providers.local_openai.endpoint")["value"] == "http://primary.example:8080/v1"

        typed = ConfigurationResolver.new(
          root: temp_root,
          process_env: {},
          overrides: [
            "conversation.allow_cloud=yes",
            "conversation.temperature=1.25",
            "dashboard.port=9000",
            "conversation.mode=deterministic"
          ]
        ).resolve
        checks["supported_types_and_ranges_are_validated"] =
          typed["ok"] &&
          setting(typed, "conversation.allow_cloud")["value"] == true &&
          setting(typed, "conversation.temperature")["value"] == 1.25 &&
          setting(typed, "dashboard.port")["value"] == 9000 &&
          setting(typed, "conversation.mode")["value"] == "deterministic"

        invalid = ConfigurationResolver.new(
          root: temp_root,
          process_env: { "SOUL_CONVERSATION_MAX_MESSAGES" => "secret-sentinel-invalid" }
        ).resolve
        checks["invalid_values_fail_without_echoing_raw_input"] =
          invalid["lifecycle_state"] == "failed" &&
          invalid["errors"].any? { |error| error["key"] == "conversation.max_messages" } &&
          !JSON.generate(invalid).include?("secret-sentinel-invalid")

        secret_env = {
          "SOUL_CLOUD_OPENAI_CREDENTIAL_ENV" => "SOUL_CUSTOM_CLOUD_TOKEN",
          "SOUL_CUSTOM_CLOUD_TOKEN" => "phase12a-super-secret"
        }
        secret = ConfigurationResolver.new(root: temp_root, process_env: secret_env).resolve
        secret_record = setting(secret, "providers.cloud_openai.api_key")
        checks["secrets_are_redacted_and_custom_credential_names_are_bounded"] =
          secret_record["configured"] == true && secret_record["value"] == "[REDACTED]" &&
          secret_record["source_key"] == "SOUL_CUSTOM_CLOUD_TOKEN" &&
          !JSON.generate(secret).include?("phase12a-super-secret")

        secret_override = ConfigurationResolver.new(
          root: temp_root,
          process_env: {},
          overrides: ["providers.cloud_openai.api_key=must-not-appear"]
        ).resolve
        duplicate_override = ConfigurationResolver.new(
          root: temp_root,
          process_env: {},
          overrides: ["dashboard.port=4000", "dashboard.port=4001"]
        ).resolve
        unknown_override = ConfigurationResolver.new(
          root: temp_root,
          process_env: {},
          overrides: ["unknown.setting=value"]
        ).resolve
        checks["unsafe_unknown_and_duplicate_overrides_are_rejected"] =
          !secret_override["ok"] && !JSON.generate(secret_override).include?("must-not-appear") &&
          !duplicate_override["ok"] && !unknown_override["ok"]

        command_sentinel = File.join(temp_root, "should-not-exist")
        File.write(File.join(temp_root, ".env"), "SOUL_LOCAL_OPENAI_MODEL=$(touch #{command_sentinel})\n")
        literal = ConfigurationResolver.new(root: temp_root, process_env: {}).resolve
        checks["dotenv_never_interpolates_or_executes_values"] =
          literal["ok"] && !File.exist?(command_sentinel) &&
          setting(literal, "providers.local_openai.model")["value"].start_with?("$(touch ")

        File.write(File.join(temp_root, ".env"), "MALFORMED\nSOUL_LOCAL_OPENAI_MODEL=partial-model\n")
        malformed = ConfigurationResolver.new(root: temp_root, process_env: {}).resolve
        checks["malformed_dotenv_blocks_without_partial_application"] =
          malformed["lifecycle_state"] == "blocked_for_human_review" && malformed["settings"].empty?

        external = File.join(Dir.tmpdir, "phase12a-outside.env")
        File.write(external, "SOUL_LOCAL_OPENAI_MODEL=outside\n")
        outside = ConfigurationResolver.new(root: temp_root, process_env: {}, dotenv_path: external).resolve
        checks["dotenv_path_is_project_bounded"] = outside["lifecycle_state"] == "blocked_for_human_review"

        target = File.join(temp_root, "target.env")
        File.write(target, "SOUL_LOCAL_OPENAI_MODEL=linked\n")
        link = File.join(temp_root, ".env")
        FileUtils.rm_f(link)
        File.symlink(target, link)
        linked = ConfigurationResolver.new(root: temp_root, process_env: {}).resolve
        FileUtils.rm_f(link)
        File.binwrite(link, "x" * (DotenvReader::MAX_BYTES + 1))
        excessive_bytes = ConfigurationResolver.new(root: temp_root, process_env: {}).resolve
        File.write(link, (["# bounded"] * (DotenvReader::MAX_LINES + 1)).join("\n"))
        excessive_lines = ConfigurationResolver.new(root: temp_root, process_env: {}).resolve
        File.binwrite(link, "SOUL_LOCAL_OPENAI_MODEL=\xFF\n")
        invalid_utf8 = ConfigurationResolver.new(root: temp_root, process_env: {}).resolve
        checks["dotenv_rejects_symlinks_and_unsafe_files"] =
          [linked, excessive_bytes, excessive_lines, invalid_utf8].all? do |report|
            report["lifecycle_state"] == "blocked_for_human_review" && report["settings"].empty?
          end

        FileUtils.rm_f(link)
        File.write(link, "SOUL_LOCAL_OPENAI_MODEL=provider-model\n")
        compatibility_resolver = ConfigurationResolver.new(
          root: temp_root,
          process_env: { "SOUL_OPENAI_BASE_URL" => "http://127.0.0.1:8082/v1" }
        )
        compatibility = compatibility_resolver.resolve
        registry = ConversationProviderRegistry.new(env: compatibility_resolver.effective_environment)
        provider = registry.find("local.openai_compatible")
        checks["provider_registry_consumes_compatibility_projection"] =
          compatibility["ok"] && provider.configured? && provider.model == "provider-model" &&
          provider.endpoint == "http://127.0.0.1:8082/v1"

        cloud = ConfigurationResolver.new(
          root: temp_root,
          process_env: {
            "SOUL_CLOUD_OPENAI_BASE_URL" => "https://cloud.example/v1",
            "SOUL_CLOUD_OPENAI_MODEL" => "cloud-model",
            "SOUL_CLOUD_OPENAI_API_KEY" => "cloud-secret"
          }
        )
        cloud_report = cloud.resolve
        checks["cloud_credentials_do_not_enable_cloud_opt_in"] =
          setting(cloud_report, "providers.cloud_openai.api_key")["configured"] == true &&
          setting(cloud_report, "conversation.allow_cloud")["value"] == false &&
          cloud.effective_environment["SOUL_ALLOW_CLOUD_CONVERSATION"] == "0"

        loopback_ok = ConfigurationResolver.new(root: temp_root, process_env: {}, overrides: ["dashboard.bind_host=::1"]).resolve
        lan_blocked = ConfigurationResolver.new(root: temp_root, process_env: {}, overrides: ["dashboard.bind_host=0.0.0.0"]).resolve
        checks["dashboard_configuration_is_loopback_only_and_inert"] =
          loopback_ok["ok"] && !lan_blocked["ok"] &&
          %w[TCPServer.new HTTPServer WEBrick .listen(].none? { |primitive| source_text.include?(primitive) }

        output = StringIO.new
        command_status = ConfigurationCommand.new(
          argv: ["explain", "providers.cloud_openai.api_key", "--json"],
          root: temp_root,
          process_env: secret_env,
          output: output
        ).run
        command_json = JSON.parse(output.string)
        checks["configuration_commands_are_redacted_and_terminal"] =
          command_status.zero? && command_json["lifecycle_state"] == "complete" &&
          command_json["settings"].length == 1 &&
          !output.string.include?("phase12a-super-secret")

        missing_output = StringIO.new
        missing_status = ConfigurationCommand.new(argv: ["explain"], root: temp_root, process_env: {}, output: missing_output).run
        cancel_output = StringIO.new
        cancel_status = ConfigurationCommand.new(argv: ["cancel"], root: temp_root, process_env: {}, output: cancel_output).run
        checks["configuration_commands_cover_awaiting_input_and_canceled"] =
          missing_status == 1 && missing_output.string.include?("awaiting_input") &&
          cancel_status.zero? && cancel_output.string.include?("canceled")

        schema = ConfigurationSchema.definitions
        checks["schema_exposes_interface_metadata"] =
          schema.length <= ConfigurationSchema::MAX_SETTINGS &&
          schema.all? do |definition|
            %w[key environment type default behavioral_effect privacy_risk restart_required secret].all? { |key| definition.key?(key) }
          end

        before = secret_env.dup
        ConfigurationResolver.new(root: temp_root, process_env: secret_env).resolve
        checks["resolution_does_not_mutate_caller_environment"] = secret_env == before

        details["setting_count"] = defaults["setting_count"]
        details["default_source_count"] = defaults.dig("source_counts", "default")
      ensure
        FileUtils.rm_f(external) if defined?(external)
      end

      checks["tracked_example_is_portable_and_secret_free"] = portable_example?
      blockers = checks.filter_map { |name, passed| name unless passed }
      {
        "ok" => blockers.empty?,
        "assessment" => "phase12a_portable_typed_configuration",
        "milestone" => "conversational_soul",
        "phase" => "12A",
        "status" => blockers.empty? ? "candidate_ready" : "blocked",
        "blockers" => blockers,
        "verification" => checks,
        "details" => details,
        "memory_keys" => [],
        "lifecycle_states" => %w[complete failed awaiting_input canceled blocked_for_human_review],
        "risk_class" => "Class 0: Read-only local or conversational",
        "local_llm_eval_required" => false,
        "human_review_required" => true
      }
    end

    def render(report)
      lines = [
        "Soul Phase 12A Portable Typed Configuration Assessment",
        "Status: #{report['status']}",
        "",
        "Verification"
      ]
      report.fetch("verification").each { |key, value| lines << "- #{key}: #{value}" }
      lines << ""
      lines << "Blockers"
      report.fetch("blockers").empty? ? lines << "- None" : report.fetch("blockers").each { |item| lines << "- #{item}" }
      lines.join("\n")
    end

    private

    def setting(report, key)
      report.fetch("settings").find { |record| record.fetch("key") == key }
    end

    def source_text
      @source_text ||= %w[
        lib/soul_core/configuration_schema.rb
        lib/soul_core/dotenv_reader.rb
        lib/soul_core/configuration_resolver.rb
        lib/soul_core/configuration_command.rb
      ].map { |path| File.read(File.join(@root, path)) }.join("\n")
    end

    def portable_example?
      text = File.read(File.join(@root, ".env.example"))
      !text.match?(/(?:API_KEY|TOKEN|SECRET)=\S+/) &&
        !text.match?(/SOUL_(?:LOCAL_OPENAI_MODEL|MODEL_ALIAS|OLLAMA_MODEL)=\S+/) &&
        !text.match?(%r{/(?:home|Users)/})
    end
  end
end
