# frozen_string_literal: true

module SoulCore
  class ConversationCoreWorkflowService
    REQUEST = /\A\s*(?:please\s+)?(?:switch|change|move|activate|use)\s+(?:over\s+)?(?:to\s+)?(?:(daily|amd[- ]?free|music)\s+core|core\s+(daily|amd[- ]?free|music))\s*[.!]*\s*\z/i

    def initialize(core_orchestration:) = (@core_orchestration = core_orchestration)

    def candidate_message?(message:) = message.to_s.match?(REQUEST)

    def plan(message:)
      match = message.to_s.match(REQUEST)
      return nil unless match

      core_id = normalize(match[1] || match[2])
      preview = @core_orchestration.preview(core_id: core_id)
      return failure(preview["reason"] || "Core activation is unavailable") unless preview.fetch("ok", false)

      data = preview.fetch("data")
      action = {
        "action_id" => "core_activate", "operation" => "core.activate.execute",
        "label" => "Activate #{data.dig('target_core', 'label') || core_id}",
        "core_id" => core_id, "target_profile_id" => data.dig("target_profile", "id") || data.dig("target_core", "target_profile", "id"),
        "confirmation_phrase" => data.fetch("confirmation_phrase"), "expected_digest" => data.fetch("expected_digest"),
        "risk" => "runtime_mutation"
      }
      {
        "content" => "The Core transfer is ready. Clicking the action authorizes this exact target profile; active work and runtime state are checked again before either service changes.",
        "mode" => "core_activation_ready", "metadata" => { "core_activation" => data.slice("source_core", "target_core", "target_profile"), "actions" => [action] }
      }
    rescue KeyError, ArgumentError => error
      failure(error.message)
    end

    private

    def normalize(value)
      case value.to_s.downcase.tr(" ", "-")
      when "daily" then "daily"
      when "amd-free" then "amd-free"
      when "music" then "music"
      else raise ArgumentError, "known Core is required"
      end
    end

    def failure(reason)
      { "content" => "The Core transfer is blocked: #{reason}.", "mode" => "core_activation_blocked", "metadata" => { "core_activation" => { "lifecycle_state" => "blocked_for_human_review" } } }
    end
  end
end
