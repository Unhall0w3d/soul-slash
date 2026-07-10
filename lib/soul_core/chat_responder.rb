
# frozen_string_literal: true

require "json"
require_relative "intent_router"

module SoulCore
  class ChatResponder
    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
      @router = IntentRouter.new
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
        mapped_skill(intent, "That sounds like a weather request. I can map it to `weather.report`, but Phase 45 does not execute skills from chat yet.")
      when "downloads_inspect", "downloads_cleanup_plan", "downloads_move_to_trash"
        downloads_guidance(intent)
      when "cloud_providers"
        mapped_skill(intent, "That sounds provider-related. I can map it toward cloud provider skills, but chat-side skill execution is still gated for a later phase.")
      when "youtube_request"
        mapped_skill(intent, "That sounds like a YouTube lookup. I can map it toward the YouTube skills, but I will not invoke them from chat yet.")
      when "skill_brief"
        mapped_skill(intent, "That sounds like skill design or review work. I can map it toward skill brief tooling, but Phase 45 stops at routing.")
      else
        fallback(intent)
      end
    end

    private

    def route_explanation(text)
      "I classified that as:\n#{@router.explain(text)}"
    end

    def mapped_skill(intent, intro)
      [
        intro,
        "",
        "Intent: #{intent.label}",
        "Skill candidate: #{intent.skill_id || 'none'}",
        "Risk: #{intent.risk}",
        "Confirmation required: #{intent.confirmation_required}",
        "Next step: #{intent.next_step}"
      ].join("\n")
    end

    def downloads_guidance(intent)
      if intent.confirmation_required
        mapped_skill(intent, "That sounds like a local filesystem change. I can recognize the intent, but I will not move or delete anything without an approval-gated skill invocation planner.")
      else
        mapped_skill(intent, "That sounds like Downloads-related work. I can recognize the likely skill path, but Phase 45 does not execute it from chat yet.")
      end
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
        return "I have an assistant-facing skill catalog at `docs/ASSISTANT_SKILL_CATALOG.md`. I can use it for explanations and routing hints. Direct skill execution from chat is still intentionally blocked until the invocation planner exists."
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
      "The next planned implementation thread is skill invocation planning: use the intent router, identify a candidate skill, describe the risk, and ask for confirmation before anything with side effects. The baby dragon has learned to point at tools. It still does not get to swing them."
    end

    def status_guidance
      "For current health, run the existing assessments: `ruby bin/soul assess doctor-surface`, `ruby bin/soul assess ruby-runtime`, `ruby bin/soul assess repo-curation`, `ruby bin/soul assess documentation-registry`, and `ruby bin/soul assess assistant-skill-catalog`. I can route this request now, but direct assessment execution from chat waits for the skill invocation planner."
    end

    def fallback(intent)
      [
        "I heard you. The chat layer is awake, and I can now attempt deterministic intent routing, but this did not match a known Phase 45 intent.",
        "",
        "Intent: #{intent.label}",
        "Reason: #{intent.reason}",
        "Next step: #{intent.next_step}"
      ].join("\n")
    end
  end
end
