# frozen_string_literal: true

require_relative "conversation_request_shape"
require_relative "operator_capability_catalog"
require_relative "skill_registry"

module SoulCore
  class DashboardCapabilityGuide
    REQUEST_PATTERNS = [
      /\A\s*(?:please\s+)?(?:show|list|explain|describe)\s+(?:the\s+)?(?:dashboard|studio)\s+(?:capabilities|actions|invocations|workflows)\b/i,
      /\A\s*(?:what|which)\s+(?:dashboard|studio)\s+(?:capabilities|actions|workflows)\s+(?:can|do)\b/i,
      /\A\s*what\s+can\s+(?:i\s+ask\s+)?you\s+(?:to\s+)?do\s+(?:through|in|with|from)\s+(?:the\s+)?(?:dashboard|chat|music studio|visual studio|mix studio|skill studio|self assessment|self augmentation|guided maintenance|project timeline|review center|core control|backup and recovery|fleet|operations topology)\b/i,
      /\A\s*how\s+(?:can|do)\s+i\s+use\s+(?:the\s+)?(?:dashboard|chat|music studio|visual studio|mix studio|skill studio|self assessment|self augmentation|guided maintenance|project timeline|review center|core control|backup and recovery|fleet|operations topology)\s+(?:through|from|in|with)\s+(?:chat|soul)\b/i
    ].freeze

    def initialize(root: Dir.pwd, registry: nil, catalog: nil)
      path = File.join(File.expand_path(root), "Soul", "skills", "registry.yaml")
      @registry = registry || SkillRegistry.new(path: path)
      @catalog = catalog || OperatorCapabilityCatalog.new(root: root)
    end

    def match?(message)
      text = message.to_s.strip
      ConversationRequestShape.new.request?(text) && REQUEST_PATTERNS.any? { |pattern| text.match?(pattern) }
    end

    def respond(message)
      surface = resolve_surface(message)
      surface ? render_surface(surface) : render_overview
    end

    private

    def resolve_surface(message)
      text = message.to_s.downcase
      surfaces
        .reject { |surface| surface["id"] == "chat" && text.match?(/\bdashboard\b/) }
        .select { |surface| surface.fetch("aliases").any? { |name| text.match?(/\b#{Regexp.escape(name)}\b/) } }
        .max_by { |surface| surface.fetch("aliases").map(&:length).max }
    end

    def render_overview
      lines = [
        "Dashboard capabilities through Chat",
        "",
        "This is a read-only map of what Soul can currently reach conversationally. It does not invoke any capability."
      ]
      surfaces.each do |surface|
        lines << "- #{surface.fetch('label')} — #{availability(surface)}. #{surface.fetch('summary')}"
      end
      lines.concat([
        "",
        "Ask what I can do in a named surface for its required inputs, interfaces, authority boundary, and completion evidence.",
        "Lifecycle: complete. Mutation: none."
      ])
      lines.join("\n")
    end

    def render_surface(surface)
      [
        "#{surface.fetch('label')} through Chat",
        "Availability: #{availability(surface)}",
        "",
        surface.fetch("summary"),
        "Inputs: #{surface.fetch('inputs')}",
        "Boundary: #{surface.fetch('boundary')}",
        "Interfaces: #{surface.fetch('interfaces').join(', ')}.",
        "Authority: #{authority_line(surface)}",
        "Completion: progress #{surface.dig('completion', 'progress')}; receipt #{surface.dig('completion', 'receipt')}.",
        skill_line(surface),
        "",
        "Lifecycle: complete. Mutation: none."
      ].reject(&:empty?).join("\n")
    end

    def availability(surface)
      case surface.dig("coverage", "chat")
      when "available" then registered_skills_available?(surface) ? "available" : "partial"
      when "partial" then "partial"
      when "dashboard_only" then "Dashboard-only review surface"
      else "not yet mapped to Chat"
      end
    end

    def skill_line(surface)
      ids = surface.fetch("skills")
      return "Registered conversational skills: none." if ids.empty?

      "Registered conversational skills: #{ids.map { |id| "`#{id}` (#{registry_status(id)})" }.join(', ')}."
    end

    def registry_status(skill_id)
      record = @registry.list[skill_id]
      return "missing" unless record

      declared = record["status"].to_s
      declared.empty? ? "available" : declared
    end

    def registered_skills_available?(surface)
      ids = surface.fetch("skills")
      ids.empty? || ids.all? { |id| registry_status(id) == "available" }
    end

    def authority_line(surface)
      authority = surface.fetch("authority")
      conversational = Array(authority["conversational_confirmation"])
      protected_actions = Array(authority["operator_gesture_required"])
      parts = ["default #{authority.fetch('default')}"]
      parts << "conversational confirmation for #{conversational.join(', ')}" unless conversational.empty?
      parts << "Operator gesture required for #{protected_actions.join(', ')}" unless protected_actions.empty?
      "#{parts.join('; ')}."
    end

    def surfaces
      @surfaces ||= @catalog.surfaces
    end
  end
end
