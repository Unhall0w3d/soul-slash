# frozen_string_literal: true

require_relative "conversation_request_shape"
require_relative "skill_registry"

module SoulCore
  class DashboardCapabilityGuide
    SURFACES = [
      {
        "id" => "chat",
        "label" => "Chat",
        "aliases" => %w[chat conversation transmission],
        "skills" => %w[system.status weather.report web.lookup web.research knowledge.vault.search local.search],
        "summary" => "Conversation, bounded public research, local project/document search, weather, system status, and reviewed knowledge access.",
        "inputs" => "Ask naturally. Explicit action wording is required before Soul invokes a capability.",
        "boundary" => "A topical mention remains conversation; it does not run a skill."
      },
      {
        "id" => "music_studio",
        "label" => "Music Studio",
        "aliases" => ["music studio", "music", "song", "composition"],
        "skills" => %w[creative.music_production],
        "summary" => "Gather a brief, draft optional musical choices, generate, review, revise, and prepare kept-song disposition gates.",
        "inputs" => "Required: intent, supported duration, vocal or instrumental mode, and rights status. Soul may propose title, BPM, key, meter, seed, Sound and Structure, and lyrics.",
        "boundary" => "Generation, Core transfer, disposition, and export remain server-authored review actions; a model response is never approval."
      },
      {
        "id" => "visual_studio",
        "label" => "Visual Studio",
        "aliases" => ["visual studio", "visual", "image", "artwork"],
        "skills" => %w[creative.visual_production creative.companion_production],
        "summary" => "Gather or draft a visual brief, generate and review a still, revise it, generate or revise contextual native motion, and carry a reviewed companion through local rendering and package export.",
        "inputs" => "Required for a new visual: a clear visual intent. Native motion additionally requires a reviewed visual context, a 4-, 8-, or 12-second duration, and a chronological scene direction.",
        "boundary" => "Supported still, native text-to-video, and post-binding output are Chat-capable through the same exact Studio gates. Motion review and binding, image-guided motion, destructive visual actions, and external publication retain Studio or human authority."
      },
      {
        "id" => "project_timeline",
        "label" => "Project Timeline",
        "aliases" => ["project timeline", "timeline", "project tracker", "tracker"],
        "skills" => %w[project.timeline.inspect project.timeline.update],
        "summary" => "Read the implementation ledger, inspect one item, or make one explicit bounded edit.",
        "inputs" => "Name the timeline item and the field or state to change. Ambiguous matches are returned for clarification.",
        "boundary" => "Chat and Dashboard use the same owner-local ledger; no background project manager is created."
      },
      {
        "id" => "cores",
        "label" => "Core control",
        "aliases" => ["core", "cores", "core control", "runtime mode"],
        "skills" => %w[cores.activate],
        "summary" => "Inspect and preview an exact transition among configured Cores without rebooting.",
        "inputs" => "Name the target Core.",
        "boundary" => "The server checks active work and presents the exact transition; only the action click authorizes it."
      },
      {
        "id" => "skill_studio",
        "label" => "Skill Studio",
        "aliases" => ["skill studio", "skills studio", "capability workshop"],
        "skills" => [],
        "summary" => "Review proposals, Beta candidates, testing evidence, and production promotion.",
        "inputs" => "Use the Dashboard for proposal approval, Beta build, promotion, and closeout.",
        "boundary" => "These lifecycle gates are intentionally Dashboard-only until each conversational operation has an exact bounded mapping."
      },
      {
        "id" => "self_assessment",
        "label" => "Self Assessment",
        "aliases" => ["self assessment", "assessment", "system assessment"],
        "skills" => %w[system.status],
        "summary" => "Chat can perform the bounded system-status read. The Dashboard exposes the broader reviewed assessment scopes.",
        "inputs" => "Ask explicitly for system status, or use the Dashboard for environment, updates, models, capabilities, and storage.",
        "boundary" => "Assessment is evidence gathering, not permission to mutate the host."
      },
      {
        "id" => "self_augmentation",
        "label" => "Self Augmentation",
        "aliases" => ["self augmentation", "augmentation"],
        "skills" => [],
        "summary" => "Inspect and review architecture-level augmentation proposals.",
        "inputs" => "Use the Dashboard review surface.",
        "boundary" => "Code inspection and proposal review do not authorize implementation or host mutation."
      },
      {
        "id" => "guided_maintenance",
        "label" => "Guided Maintenance",
        "aliases" => ["guided maintenance", "maintenance rehearsal", "update rehearsal"],
        "skills" => [],
        "summary" => "Preview the reviewed Arch/AUR and Flatpak transaction and run its visible no-mutation terminal rehearsal.",
        "inputs" => "Use Administration for normal yay -Syu or explicit forced-refresh yay -Syyu planning and exact click authorization.",
        "boundary" => "Chat can explain but cannot authorize it. Native evidence uses a single-use visible desktop handoff. Live A2 remains disabled pending supervised approval, and no A2 path can reboot or restore a session."
      },
      {
        "id" => "review_center",
        "label" => "Review Center",
        "aliases" => ["review center", "reviews"],
        "skills" => [],
        "summary" => "Aggregate pending human-review gates from the Dashboard.",
        "inputs" => "Use the Dashboard to inspect and act on the exact originating record.",
        "boundary" => "The Review Center does not replace the authority or lineage rules of the owning Studio."
      }
    ].freeze

    REQUEST_PATTERNS = [
      /\A\s*(?:please\s+)?(?:show|list|explain|describe)\s+(?:the\s+)?(?:dashboard|studio)\s+(?:capabilities|actions|invocations|workflows)\b/i,
      /\A\s*(?:what|which)\s+(?:dashboard|studio)\s+(?:capabilities|actions|workflows)\s+(?:can|do)\b/i,
      /\A\s*what\s+can\s+(?:i\s+ask\s+)?you\s+(?:to\s+)?do\s+(?:through|in|with|from)\s+(?:the\s+)?(?:dashboard|chat|music studio|visual studio|skill studio|self assessment|self augmentation|guided maintenance|project timeline|review center|core control)\b/i,
      /\A\s*how\s+(?:can|do)\s+i\s+use\s+(?:the\s+)?(?:dashboard|chat|music studio|visual studio|skill studio|self assessment|self augmentation|guided maintenance|project timeline|review center|core control)\s+(?:through|from|in|with)\s+(?:chat|soul)\b/i
    ].freeze

    def initialize(root: Dir.pwd, registry: nil)
      path = File.join(File.expand_path(root), "Soul", "skills", "registry.yaml")
      @registry = registry || SkillRegistry.new(path: path)
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
      SURFACES
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
      SURFACES.each do |surface|
        lines << "- #{surface.fetch('label')} — #{availability(surface)}. #{surface.fetch('summary')}"
      end
      lines.concat([
        "",
        "Ask what I can do in a named surface for its required inputs and authority boundary.",
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
        skill_line(surface),
        "",
        "Lifecycle: complete. Mutation: none."
      ].reject(&:empty?).join("\n")
    end

    def availability(surface)
      ids = surface.fetch("skills")
      return "Dashboard-only review surface" if ids.empty?

      statuses = ids.map { |id| registry_status(id) }
      return "available" if statuses.all? { |status| status == "available" }
      return "partial" if statuses.any? { |status| status == "available" || status == "partial" }

      "unavailable"
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
  end
end
