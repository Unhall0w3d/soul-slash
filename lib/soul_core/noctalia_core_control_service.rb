# frozen_string_literal: true

require "soul_core/configuration_resolver"
require "soul_core/core_orchestration_service"

module SoulCore
  class NoctaliaCoreControlService
    SCHEMA_VERSION = "soul.noctalia.core_control.v1"
    CORE_IDS = %w[daily amd-free music free dev].freeze
    PROFILE_ID = /\A[a-z][a-z0-9-]{0,39}\z/
    CONFIRMATION = /\A[A-Z][A-Z0-9_-]{1,95}\z/
    DIGEST = /\A[a-f0-9]{64}\z/
    MAX_TEXT_BYTES = 240

    def initialize(root: Dir.pwd, process_env: ENV, core_service: nil)
      @root = File.expand_path(root)
      @process_env = process_env.to_h
      @core_service = core_service
    end

    def preview(core_id:)
      return invalid("known Core is required") unless CORE_IDS.include?(core_id.to_s)

      project_preview(core_service.preview(core_id: core_id.to_s))
    rescue StandardError => error
      failed(error)
    end

    def execute(core_id:, target_profile_id:, confirmation:, expected_digest:)
      return invalid("known Core is required") unless CORE_IDS.include?(core_id.to_s)
      return invalid("bounded target profile is required") unless target_profile_id.to_s.match?(PROFILE_ID)
      return invalid("bounded Core confirmation is required") unless confirmation.to_s.match?(CONFIRMATION)
      return invalid("exact preview digest is required") unless expected_digest.to_s.match?(DIGEST)

      project_execution(core_service.execute(
        core_id: core_id.to_s,
        target_profile_id: target_profile_id.to_s,
        confirmation: confirmation.to_s,
        expected_digest: expected_digest.to_s
      ))
    rescue StandardError => error
      failed(error)
    end

    private

    def core_service
      return @core_service if @core_service

      resolver = ConfigurationResolver.new(root: @root, process_env: @process_env)
      report = resolver.resolve
      raise "Soul configuration is unavailable" unless report.fetch("ok")

      @core_service = CoreOrchestrationService.new(root: @root, env: resolver.effective_environment)
    end

    def project_preview(source)
      data = source.fetch("data", {})
      target_profile_id = data.dig("target_profile", "id").to_s
      confirmation = data["confirmation_phrase"].to_s
      digest = data["expected_digest"].to_s
      executable = source.fetch("ok", false) &&
        target_profile_id.match?(PROFILE_ID) && confirmation.match?(CONFIRMATION) && digest.match?(DIGEST)

      projected = {
        "source_core" => project_core(data["source_core"]),
        "target_core" => project_core(data["target_core"]),
        "target_profile_id" => executable ? target_profile_id : nil,
        "confirmation_phrase" => executable ? confirmation : nil,
        "expected_digest" => executable ? digest : nil,
        "service_mutation_required" => data["service_mutation_required"] == true || %w[load unload switch].include?(data["action"]),
        "executable" => executable
      }.compact
      envelope(projected, source: source)
    end

    def project_execution(source)
      data = source.fetch("data", {})
      projected = {
        "active_core_id" => safe_text(data["active_core_id"], 40),
        "active_core_label" => safe_text(data["active_core_label"], 80),
        "core_mode" => safe_text(data["core_mode"], 40),
        "mutation" => safe_text(source["mutation"] || data["mutation"], 80)
      }.reject { |_key, value| value.empty? }
      envelope(projected, source: source)
    end

    def project_core(value)
      return nil unless value.is_a?(Hash)

      {
        "id" => safe_text(value["id"], 40),
        "label" => safe_text(value["label"], 80),
        "purpose" => safe_text(value["purpose"])
      }.reject { |_key, item| item.empty? }
    end

    def envelope(data, source:)
      {
        "schema_version" => SCHEMA_VERSION,
        "ok" => source.fetch("ok", false),
        "lifecycle_state" => safe_text(source.fetch("lifecycle_state", "failed"), 48),
        "message" => safe_text(source["message"] || source["reason"]),
        "data" => data
      }
    end

    def invalid(message)
      {
        "schema_version" => SCHEMA_VERSION,
        "ok" => false,
        "lifecycle_state" => "awaiting_input",
        "message" => message,
        "data" => {"executable" => false}
      }
    end

    def failed(error)
      {
        "schema_version" => SCHEMA_VERSION,
        "ok" => false,
        "lifecycle_state" => "failed",
        "message" => "Core control failed safely",
        "data" => {"executable" => false},
        "error" => error.class.name
      }
    end

    def safe_text(value, bytes = MAX_TEXT_BYTES)
      value.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
        .gsub(/[[:cntrl:]]+/, " ").strip.byteslice(0, bytes).to_s
    end
  end
end
