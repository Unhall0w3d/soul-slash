
# frozen_string_literal: true

require "json"
require_relative "intent_router"
require_relative "skill_invocation_planner"
require_relative "read_only_skill_execution_gate"
require_relative "chat_execution_history"

module SoulCore
  class ChatResponder
    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
      @router = IntentRouter.new
      @planner = SkillInvocationPlanner.new(router: @router)
      @history = ChatExecutionHistory.new(root: @root)
      @gate = ReadOnlySkillExecutionGate.new(root: @root, planner: @planner, history: @history)
    end

    def respond(message)
      text = message.to_s.strip
      lower = text.downcase
      intent = @router.route(text)

      return "I am here. Give me a thread to pull." if lower.empty?
      return export_history(lower) if lower.match?(/\b(export execution history|export history)\b/)
      return clear_history(lower) if lower.match?(/\b(clear execution history|clear history)\b/)
      return render_history(lower) if lower.match?(/\b(execution history|recent executions|show executions)\b/) || lower == "history"
      return route_explanation(text) if lower.match?(/\b(intent|route|classify)\b/) && lower.match?(/\b(this|message|request|utterance)\b/)
      return @planner.explain(text) if lower.match?(/\b(plan|prepare)\b/) && lower.match?(/\b(skill|invocation|execution|run)\b/)
      return @gate.explain(text, execute: false, record_history: false) if lower.match?(/\b(execute|run|invoke)\b/) && lower.match?(/\b(skill|this|it|request)\b/)

      case intent.id
      when "identity" then identity
      when "skill_catalog" then execute_skill_catalog(intent, text)
      when "repo_status" then execute_system_status(intent, text)
      when "pending_work" then pending_work
      when "weather_request", "downloads_inspect", "downloads_cleanup_plan", "downloads_move_to_trash", "cloud_providers", "youtube_request", "skill_brief"
        gated_skill(intent, text)
      else
        fallback(intent)
      end
    end

    private

    def render_history(lower)
      filters = ChatExecutionHistory.filters_from_text(lower)
      @history.render(limit: 10, filters: filters)
    end

    def export_history(lower)
      format = lower.include?("jsonl") ? "jsonl" : "json"
      filters = ChatExecutionHistory.filters_from_text(lower)
      result = @history.export(format: format, filters: filters)
      [
        "Execution history exported.",
        "Format: #{result['format']}",
        "Entries: #{result['count']}",
        "Filters: #{result['filters'].empty? ? 'none' : result['filters'].map { |key, value| "#{key}=#{value}" }.join(', ')}",
        "Path: #{result['path']}",
        "This is still runtime/private data. Do not commit it, unless you enjoy turning audit logs into public confetti."
      ].join("\n")
    rescue StandardError => error
      "Execution history export failed: #{error.class}: #{error.message}"
    end

    def clear_history(lower)
      confirmed = lower.include?("confirm") || lower.include?("--confirm")
      result = @history.clear(confirm: confirmed)
      [result["message"], "Status: #{result['status']}", "Deleted: #{result['deleted']}", "Path: #{result['path']}"].join("\n")
    end

    def route_explanation(text)
      "I classified that as:\n#{@router.explain(text)}"
    end

    def execute_skill_catalog(intent, message)
      result = @gate.evaluate(message, execute: true, record_history: true)
      return gate_blocked_message("assistant skill catalog", result) unless result.executed && result.ok

      data = JSON.parse(result.stdout)
      count = data.dig("registry", "skill_count")
      ids = Array(data.dig("registry", "skill_ids"))
      [
        "I executed the read-only assistant skill catalog check.",
        "",
        "Skill count: #{count || ids.length}",
        "Skills: #{ids.empty? ? 'none reported' : ids.join(', ')}",
        "",
        "Executed: true",
        "Skill: #{intent.skill_id}",
        "Risk: #{intent.risk}",
        "History recorded: true",
        "No local state was changed except the local execution history."
      ].join("\n")
    rescue JSON::ParserError
      "I executed the read-only assistant skill catalog check, but could not parse the output as JSON.\nHistory recorded: true\n\n#{result.stdout.to_s[0, 1200]}"
    end

    def execute_system_status(intent, message)
      result = @gate.evaluate(message, execute: true, record_history: true)
      return gate_blocked_message("system status", result) unless result.executed && result.ok

      data = JSON.parse(result.stdout)
      status = data["status"] || (data["ok"] == true ? "ready" : "unknown")
      blockers = Array(data["blockers"])
      warnings = Array(data["warnings"])
      [
        "I executed the read-only system status check.",
        "",
        "Status: #{status}",
        "Blockers: #{blockers.empty? ? 'none' : blockers.length}",
        "Warnings: #{warnings.empty? ? 'none' : warnings.length}",
        "",
        "Executed: true",
        "Skill: #{intent.skill_id}",
        "Risk: #{intent.risk}",
        "History recorded: true",
        "This was read-only. No levers pulled, no altar lit, one log entry created."
      ].join("\n")
    rescue JSON::ParserError
      "I executed the read-only system status check, but could not parse the output as JSON.\nHistory recorded: true\n\n#{result.stdout.to_s[0, 1200]}"
    end

    def gate_blocked_message(label, result)
      ["I mapped this to #{label}, but the execution gate did not allow it.", "Gate status: #{result.status}", "Blocked by: #{result.blocked_by.join(', ')}", "History recorded: #{!result.history_entry.nil?}", result.message].join("\n")
    end

    def gated_skill(intent, message)
      result = @gate.evaluate(message, execute: false, record_history: true)
      [
        "I can map this request to the read-only execution gate.",
        "",
        "Intent: #{intent.label}",
        "Skill candidate: #{intent.skill_id || 'none'}",
        "Risk: #{intent.risk}",
        "Confirmation required: #{intent.confirmation_required}",
        "Executed: false",
        "Gate status: #{result.status}",
        "Blocked by: #{result.blocked_by.join(', ')}",
        "History recorded: true",
        "",
        result.message
      ].join("\n")
    end

    def identity
      if File.exist?(File.join(@root, "docs/SOUL_PERSONALITY.md"))
        "I am Soul: a local assistant shaped around this environment, its owner, and the skills I can safely use. I am early in my becoming, so I will not pretend a path is open before it exists."
      else
        "I am Soul, a local assistant runtime. My personality document is not present, so I will avoid improvising a dramatic origin story in the hallway."
      end
    end

    def pending_work
      "The next planned implementation thread is likely history pruning or a third read-only adapter. The logbook can now be searched instead of merely admired like a dusty museum placard."
    end

    def fallback(intent)
      [
        "I heard you. I can route intents, build invocation plans, execute two read-only chat skill paths, record history, and filter history, but this request did not match an executable path.",
        "",
        "Intent: #{intent.label}",
        "Reason: #{intent.reason}",
        "Next step: #{intent.next_step}"
      ].join("\n")
    end
  end
end
