
# frozen_string_literal: true

require "json"
require_relative "intent_router"
require_relative "skill_invocation_planner"
require_relative "read_only_skill_execution_gate"

module SoulCore
  class ChatResponder
    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
      @router = IntentRouter.new
      @planner = SkillInvocationPlanner.new(router: @router)
      @gate = ReadOnlySkillExecutionGate.new(root: @root, planner: @planner)
    end

    def respond(message)
      text = message.to_s.strip
      lower = text.downcase
      intent = @router.route(text)

      if lower.empty?
        return "I am here. Give me a thread to pull."
      end

      if lower.match?(/\b(intent|route|classify)\b/) && lower.match?(/\b(this|message|request|utterance)\b/)
        return route_explanation(text)
      end

      if lower.match?(/\b(plan|prepare)\b/) && lower.match?(/\b(skill|invocation|execution|run)\b/)
        return @planner.explain(text)
      end

      if lower.match?(/\b(execute|run|invoke)\b/) && lower.match?(/\b(skill|this|it|request)\b/)
        return @gate.explain(text, execute: false)
      end

      case intent.id
      when "identity"
        identity
      when "skill_catalog"
        execute_skill_catalog(intent)
      when "repo_status"
        execute_system_status(intent)
      when "pending_work"
        pending_work
      when "weather_request", "downloads_inspect", "downloads_cleanup_plan", "downloads_move_to_trash",
           "cloud_providers", "youtube_request", "skill_brief"
        gated_skill(intent)
      else
        fallback(intent)
      end
    end

    private

    def route_explanation(text)
      "I classified that as:\n#{@router.explain(text)}"
    end

    def execute_skill_catalog(intent)
      result = @gate.evaluate("what skills do you have?", execute: true)

      unless result.executed && result.ok
        return gate_blocked_message("assistant skill catalog", result)
      end

      begin
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
          "No local state was changed. Humanity survives another request."
        ].join("\n")
      rescue JSON::ParserError
        [
          "I executed the read-only assistant skill catalog check, but could not parse the output as JSON.",
          "",
          result.stdout.to_s[0, 1200]
        ].join("\n")
      end
    end

    def execute_system_status(intent)
      result = @gate.evaluate("check repo health", execute: true)

      unless result.executed && result.ok
        return gate_blocked_message("system status", result)
      end

      begin
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
          "This was read-only. No levers pulled, no altar lit."
        ].join("\n")
      rescue JSON::ParserError
        [
          "I executed the read-only system status check, but could not parse the output as JSON.",
          "",
          result.stdout.to_s[0, 1200]
        ].join("\n")
      end
    end

    def gate_blocked_message(label, result)
      [
        "I mapped this to #{label}, but the execution gate did not allow it.",
        "Gate status: #{result.status}",
        "Blocked by: #{result.blocked_by.join(', ')}",
        result.message
      ].join("\n")
    end

    def gated_skill(intent)
      result = @gate.evaluate(intent.skill_id || intent.label.to_s, execute: false)
      result = @gate.evaluate_plan(@planner.send(:build_plan, intent), execute: false) if result.skill_id.nil? && intent.skill_id

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
      "The next planned implementation thread is either one more read-only adapter with useful local output, or a proper execution-history record so every gated action leaves an audit trail. The baby dragon now opens two drawers. That is enough drawers for one afternoon."
    end

    def fallback(intent)
      [
        "I heard you. I can now route intents, build invocation plans, and execute two read-only chat skill paths, but this request did not match an executable path.",
        "",
        "Intent: #{intent.label}",
        "Reason: #{intent.reason}",
        "Next step: #{intent.next_step}"
      ].join("\n")
    end
  end
end
