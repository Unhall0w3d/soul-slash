# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module SoulCore
  class ConversationStateStore
    DEFAULT_ROOT = "Soul/runtime/conversation_state"

    def initialize(root: Dir.pwd, state_root: DEFAULT_ROOT)
      @project_root = File.expand_path(root)
      @root = File.join(@project_root, state_root)
      FileUtils.mkdir_p(@root)
    end

    def state(chat_id)
      path = state_path(chat_id)
      return default_state(chat_id) unless File.exist?(path)

      parsed = JSON.parse(File.read(path))
      default_state(chat_id).merge(parsed)
    rescue JSON::ParserError
      default_state(chat_id)
    end

    def record_turn(
      chat_id:,
      user_message:,
      assistant_message:,
      mode:,
      provider_id: nil,
      fallback_reason: nil,
      context: {},
      orchestration: nil,
      tool_ids: [],
      evidence_ids: [],
      grounding: nil
    )
      current = state(chat_id)
      now = Time.now.iso8601

      current["schema"] = "conversational_soul_phase5"
      current["chat_id"] = chat_id.to_s
      current["updated_at"] = now
      current["turn_count"] = current.fetch("turn_count", 0).to_i + 1
      current["active_subject"] = subject_hint(user_message)
      current["active_task"] = task_hint(user_message, current["active_task"])
      current["last_user_message"] = user_message.to_s
      current["last_assistant_message"] = assistant_message.to_s
      current["last_response_mode"] = mode.to_s
      current["last_provider_id"] = provider_id
      current["last_fallback_reason"] = fallback_reason
      current["last_orchestration_kind"] = orchestration&.fetch("kind", nil)
      current["last_orchestration_reason"] = orchestration&.fetch("reason", nil)
      current["last_tool_ids"] = Array(tool_ids).map(&:to_s)
      current["last_evidence_ids"] = Array(evidence_ids).map(&:to_s)
      current["last_grounding"] = grounding
      current["context_digest"] = context.fetch("context_digest", "").to_s
      current["context_stats"] = {
        "total_message_count" => context.fetch("total_message_count", 0).to_i,
        "included_message_count" => context.fetch("included_message_count", 0).to_i,
        "truncated_message_count" => context.fetch("truncated_message_count", 0).to_i,
        "character_count" => context.fetch("character_count", 0).to_i,
        "evidence_count" => context.fetch("evidence_count", 0).to_i
      }

      File.write(state_path(chat_id), "#{JSON.pretty_generate(current)}\n")
      current
    end

    private

    def default_state(chat_id)
      {
        "schema" => "conversational_soul_phase5",
        "chat_id" => chat_id.to_s,
        "created_at" => Time.now.iso8601,
        "updated_at" => nil,
        "turn_count" => 0,
        "active_subject" => nil,
        "active_task" => nil,
        "last_user_message" => nil,
        "last_assistant_message" => nil,
        "last_response_mode" => nil,
        "last_provider_id" => nil,
        "last_fallback_reason" => nil,
        "last_orchestration_kind" => nil,
        "last_orchestration_reason" => nil,
        "last_tool_ids" => [],
        "last_evidence_ids" => [],
        "last_grounding" => nil,
        "context_digest" => "",
        "context_stats" => {}
      }
    end

    def state_path(chat_id)
      File.join(@root, "#{safe_id(chat_id)}.json")
    end

    def safe_id(value)
      value.to_s.gsub(/[^a-zA-Z0-9_.-]/, "_")
    end

    def subject_hint(message)
      text = message.to_s.gsub(/\s+/, " ").strip
      text = text.split(/[.!?]/, 2).first.to_s.strip
      text.empty? ? nil : text[0, 160]
    end

    def task_hint(message, existing)
      text = message.to_s.gsub(/\s+/, " ").strip
      action = text.match?(
        /\b(prepare|create|build|fix|repair|review|generate|update|write|make|run|check|inspect|move|remove|configure|test)\b/i
      )
      action ? text[0, 240] : existing
    end
  end
end
