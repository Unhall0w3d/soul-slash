
# frozen_string_literal: true

require "json"
require_relative "intent_router"
require_relative "skill_invocation_planner"

module SoulCore
  class ChatResponder
    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
      @router = IntentRouter.new
      @planner = SkillInvocationPlanner.new(router: @router)
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

      case intent.id
      when "identity"
        identity
      when "skill_catalog"
        skill_summary
      when "pending_work"
        pending_work
      when "repo_status"
        status_guidance
      when "weather_request"
        planned_skill(intent)
      when "downloads_inspect", "downloads_cleanup_plan", "downloads_move_to_trash"
        planned_skill(intent)
      when "cloud_providers"
        planned_skill(intent)
      when "youtube_request"
        planned_skill(intent)
      when "skill_brief"
        planned_skill(intent)
      else
        fallback(intent)
      end
    end

    private

    def route_explanation(text)
      "I classified that as:\n#{@router.explain(text)}"
    end

    def planned_skill(intent)
      plan = @planner.plan(intent.skill_id || intent.label.to_s)
      # Use original intent if planning by skill string falls back oddly.
      plan = @planner.send(:build_plan, intent) if plan.skill_id.nil? && intent.skill_id

      [
        "I can map this request to a skill invocation plan.",
        "",
        "Intent: #{intent.label}",
        "Skill candidate: #{intent.skill_id || 'none'}",
        "Risk: #{intent.risk}",
        "Confirmation required: #{intent.confirmation_required}",
        "Executable now: false",
        "",
        "Phase 46 prepares plans only. I will not run the skill from chat yet, because apparently we are avoiding haunted automation incidents."
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
        return "I have an assistant-facing skill catalog at `docs/ASSISTANT_SKILL_CATALOG.md`. I can use it for explanations, intent routing, and skill invocation planning. Direct skill execution from chat is still intentionally blocked."
      end

      registry_path = File.join(@root, "Soul/skills/registry.yaml")
      unless File.exist?(registry_path)
        return "I cannot find my skill registry yet. That means I should not invent skills just to look impressive. Revolutionary restraint."
      end

      begin
        require "yaml"
        registry = YAML.load_file(registry_path) || {}
        skills = registry.is_a?(Hash) ? (registry["skills"] || registry[:skills] || registry) : registry
        ids =
          case skills
          when Array
            skills.map { |entry| entry.is_a?(Hash) ? (entry["id"] || entry[:id]) : nil }.compact
          when Hash
            skills.keys
          else
            []
          end
        return "I found my skill registry, but no skill IDs were readable yet." if ids.empty?

        "I currently know #{ids.length} registered skill(s): #{ids.sort.join(', ')}. I can explain them more cleanly once the assistant-facing skill catalog is expanded."
      rescue StandardError => error
        "I found the skill registry, but could not read it cleanly: #{error.class}: #{error.message}"
      end
    end

    def pending_work
      "The next planned implementation thread is approval-gated skill invocation: taking these plans, requiring owner confirmation where needed, and only then calling safe skill adapters. The baby dragon can now point at tools and draft a handling plan. It still does not get to swing them."
    end

    def status_guidance
      "For current health, run the existing assessments: `ruby bin/soul assess doctor-surface`, `ruby bin/soul assess ruby-runtime`, `ruby bin/soul assess repo-curation`, `ruby bin/soul assess documentation-registry`, `ruby bin/soul assess assistant-skill-catalog`, and `ruby bin/soul assess skill-invocation-planner`. I can plan this request now, but direct assessment execution from chat waits for the approval-gated invocation layer."
    end

    def fallback(intent)
      [
        "I heard you. The chat layer is awake, and I can now attempt deterministic intent routing and skill invocation planning, but this did not match a known skill-backed Phase 46 path.",
        "",
        "Intent: #{intent.label}",
        "Reason: #{intent.reason}",
        "Next step: #{intent.next_step}"
      ].join("\n")
    end
  end
end
