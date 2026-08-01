# frozen_string_literal: true

require "securerandom"
require_relative "core_orchestration_service"
require_relative "dev_model_runtime_coordinator"

module SoulCore
  class DevCoreTaskOrchestrator
    class Unavailable < StandardError
      attr_reader :lifecycle_state, :receipt

      def initialize(message, lifecycle_state: "awaiting_input", receipt: {})
        super(message)
        @lifecycle_state = lifecycle_state
        @receipt = receipt
      end
    end

    def initialize(root: Dir.pwd, env: ENV, cores: nil, dev_runtime: nil)
      @dev_runtime = dev_runtime || DevModelRuntimeCoordinator.new(root: root, env: env)
      @cores = cores || CoreOrchestrationService.new(root: root, env: env, dev_runtime: @dev_runtime)
    end

    def with_task(request_id:, purpose:, on_progress: nil)
      before = core_status
      starting_id = before.fetch("active_core_id").to_s
      raise Unavailable.new("Select Soul Core, Soul-Lite Core, or Dev Core before development work") if starting_id == "free" || starting_id.empty?
      raise Unavailable.new("Creative Core owns the AMD lane; leave Creative Core before development work") if starting_id == "music"
      raise Unavailable.new("active Core is not eligible for development work", lifecycle_state: "blocked_for_human_review") unless %w[daily amd-free dev].include?(starting_id)

      selected = starting_id == "dev"
      transition_receipt = nil
      restore_receipt = nil
      if starting_id == "daily"
        progress(on_progress, "dev_chat_handoff", "Moving chat to Soul-Lite while GPT-OSS borrows the AMD lane.")
        transition_receipt = activate_core("amd-free")
      end

      value, runtime_receipt = @dev_runtime.with_request(
        request_id: request_id.to_s.empty? ? "dev_#{SecureRandom.hex(12)}" : request_id,
        purpose: purpose, selected_core: selected, on_progress: on_progress
      ) { |runtime| yield(runtime) }

      receipt = {
        "starting_core_id" => starting_id,
        "selected_dev_core" => selected,
        "chat_transition" => transition_receipt,
        "runtime" => runtime_receipt,
        "restoration" => nil
      }

      if starting_id == "daily" && transition_receipt
        progress(on_progress, "dev_chat_restore", "The Dev transaction is terminal; restoring Soul Core.")
        receipt["restoration"] = activate_core("daily")
        transition_receipt = nil
      end

      [value, receipt]
    rescue DevModelRuntimeCoordinator::Busy => error
      raise Unavailable.new(error.message)
    ensure
      if defined?(starting_id) && starting_id == "daily" && transition_receipt
        progress(on_progress, "dev_chat_restore", "The Dev transaction is terminal; restoring Soul Core.")
        begin
          restore_receipt = activate_core("daily")
        rescue StandardError => error
          raise Unavailable.new(
            "Dev work ended but Soul Core restoration failed: #{error.message}",
            lifecycle_state: "failed",
            receipt: { "starting_core_id" => starting_id, "chat_transition" => transition_receipt, "restoration" => restore_receipt }
          )
        end
      end
    end

    private

    def core_status
      envelope = @cores.status
      raise Unavailable.new(envelope["reason"].to_s.empty? ? "Core status is unavailable" : envelope["reason"], lifecycle_state: envelope.fetch("lifecycle_state", "failed"), receipt: envelope) unless envelope["ok"]
      envelope.fetch("data")
    end

    def activate_core(core_id)
      preview = @cores.preview(core_id: core_id)
      raise Unavailable.new(reason(preview), lifecycle_state: preview.fetch("lifecycle_state", "awaiting_input"), receipt: preview) unless preview["ok"]
      data = preview.fetch("data")
      target = data.fetch("target_profile")
      result = @cores.execute(
        core_id: core_id,
        target_profile_id: target.fetch("id"),
        confirmation: data.fetch("confirmation_phrase"),
        expected_digest: data.fetch("expected_digest")
      )
      raise Unavailable.new(reason(result), lifecycle_state: result.fetch("lifecycle_state", "failed"), receipt: result) unless result["ok"]
      result.fetch("data").slice("source_profile_id", "target_profile_id", "active_core_id", "mutation")
    end

    def reason(envelope)
      envelope["reason"] || envelope.dig("data", "reason") || "Core transition failed safely"
    end

    def progress(callback, stage, message)
      callback&.call("stage" => stage, "message" => message)
    rescue StandardError
      nil
    end
  end
end
