
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
        return @gate.explain(text)
      end

      case intent.id
      when "identity"
        identity
      when "skill_catalog"
        skill_summary
      when "pending_work"
        pending_work
      when "repo_status"
        status_guidance
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

    def gated_skill(intent)
      result = @gate.evaluate(intent.skill_id || intent.label.to_s)
      result = @gate.evaluate_plan(@planner.send(:build_plan, intent)) if result.skill_id.nil? && intent.skill_id

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

    def skill_summary
      catalog_path = File.join(@root, "docs/ASSISTANT_SKILL_CATALOG.md")
      if File.exist?(catalog_path)
        return "I have an assistant-facing skill catalog at `docs/ASSISTANT_SKILL_CATALOG.md`. I can use it for explanations, intent routing, and skill invocation planning. Phase 47 adds a read-only execution gate, but still defaults to dry-run behavior."
      end

      "I can look for my skill registry, but the assistant-facing catalog should be generated first. A tool shelf without labels is just a medieval injury generator."
    end

    def pending_work
      "The next planned implementation thread is real read-only execution adapters: choose one safe skill, run it through the gate, capture output, and keep approval-required skills blocked. The baby dragon has reached the locked cabinet stage."
    end

    def status_guidance
      "For current health, run: `ruby bin/soul assess read-only-skill-gate`, `ruby bin/soul assess skill-invocation-planner`, `ruby bin/soul assess intent-router`, and the existing doctor/runtime/curation assessments. Chat can model the gate now, but Phase 47 does not execute skills."
    end

    def fallback(intent)
      [
        "I heard you. I can now route intents, build invocation plans, and pass them through a read-only execution gate, but this request did not match a known skill-backed path.",
        "",
        "Intent: #{intent.label}",
        "Reason: #{intent.reason}",
        "Next step: #{intent.next_step}"
      ].join("\n")
    end
  end
end
