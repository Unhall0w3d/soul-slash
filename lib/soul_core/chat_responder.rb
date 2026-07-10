
# frozen_string_literal: true

require "json"

module SoulCore
  class ChatResponder
    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def respond(message)
      text = message.to_s.strip
      lower = text.downcase

      if lower.empty?
        return "I am here. Give me a thread to pull."
      end

      if lower.match?(/\b(what can you do|what skills|skills do you have|list skills)\b/)
        return skill_summary
      end

      if lower.match?(/\b(who are you|what are you|explain yourself|what is soul)\b/)
        return identity
      end

      if lower.match?(/\b(pending skills|skills to build|what should we build|next skill|pending work)\b/)
        return pending_work
      end

      if lower.match?(/\b(status|health|doctor|runtime|repo)\b/)
        return status_guidance
      end

      "I heard you. The chat layer is awake, but I do not have LLM-backed conversation or automatic skill routing yet. I can already explain my skills, point you toward repo/status checks, and record this chat locally. Small spark, real wiring."
    end

    private

    def identity
      if File.exist?(File.join(@root, "docs/SOUL_PERSONALITY.md"))
        "I am Soul: a local assistant shaped around this environment, its owner, and the skills I can safely use. I am early in my becoming, so I will not pretend a path is open before it exists."
      else
        "I am Soul, a local assistant runtime. My personality document is not present, so I will avoid improvising a dramatic origin story in the hallway."
      end
    end

    def skill_summary
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
      "The next planned implementation thread is the interaction layer itself: chat storage, session listing, intent routing, assistant-facing skill descriptions, and then safe skill invocation. More skills can wait until I have a mouth that is not just Ruby subcommands."
    end

    def status_guidance
      "For current health, run the existing assessments: `ruby bin/soul assess doctor-surface`, `ruby bin/soul assess ruby-runtime`, `ruby bin/soul assess repo-curation`, and `ruby bin/soul assess documentation-registry`. I can summarize those directly once skill-aware routing is wired in."
    end
  end
end
