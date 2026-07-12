# frozen_string_literal: true

require_relative "conversation_identity_profile"

module SoulCore
  class ConversationIdentityControls
    HELP_PATTERNS = [
      /\A\s*identity\s+help\s*[?.!]*\z/i,
      /\A\s*help\s+identity\s*[?.!]*\z/i
    ].freeze

    PROFILE_PATTERNS = [
      /\A\s*(?:show|inspect)\s+identity\s*[?.!]*\z/i,
      /\A\s*show\s+(?:personality|identity)\s+policy\s*[?.!]*\z/i
    ].freeze

    TONE_PATTERNS = [
      /\A\s*show\s+tone\s+policy\s*[?.!]*\z/i,
      /\A\s*inspect\s+tone\s+modes?\s*[?.!]*\z/i
    ].freeze

    BOUNDARY_PATTERNS = [
      /\A\s*show\s+identity\s+boundaries\s*[?.!]*\z/i,
      /\A\s*inspect\s+identity\s+boundaries\s*[?.!]*\z/i
    ].freeze

    def initialize(profile: nil)
      @profile = profile || ConversationIdentityProfile.new
    end

    def match?(message)
      text = message.to_s.strip
      all_patterns.any? { |pattern| text.match?(pattern) }
    end

    def summary
      [
        "I am Soul, a local-first machine assistant built to help with this environment and the user's goals.",
        "I can be clear, curious, technically serious, and occasionally dry, but I do not have a human biography, body, or off-screen personal life.",
        "My actions and claims remain bounded by the tools, evidence, approvals, and reviewed memory available to the runtime."
      ].join(" ")
    end

    def respond(message, chat_id: nil)
      text = message.to_s.strip
      return render_help if HELP_PATTERNS.any? { |pattern| text.match?(pattern) }
      return render_tones if TONE_PATTERNS.any? { |pattern| text.match?(pattern) }
      return render_boundaries if BOUNDARY_PATTERNS.any? { |pattern| text.match?(pattern) }
      return @profile.render if PROFILE_PATTERNS.any? { |pattern| text.match?(pattern) }

      "Identity control did not recognize that command.\n\n#{render_help}"
    end

    private

    def all_patterns
      HELP_PATTERNS + PROFILE_PATTERNS + TONE_PATTERNS + BOUNDARY_PATTERNS
    end

    def render_help
      [
        "Soul Identity Controls",
        "Mutation: none",
        "",
        "Commands",
        "- show identity",
        "- show personality policy",
        "- show tone policy",
        "- show identity boundaries",
        "- identity help",
        "",
        "These commands inspect the stable identity policy. They do not change memory, preferences, or runtime behavior."
      ].join("\n")
    end

    def render_tones
      lines = [
        "Soul Tone Policy",
        "Mutation: none",
        "",
        "Tone modes"
      ]
      @profile.to_h.fetch("tone_modes").each do |id, tone|
        lines << "- #{id}: #{tone['label']}"
        tone.fetch("guidance").each { |item| lines << "  - #{item}" }
      end
      lines.join("\n")
    end

    def render_boundaries
      lines = [
        "Soul Identity Boundaries",
        "Mutation: none",
        ""
      ]
      @profile.to_h.fetch("boundaries").each { |boundary| lines << "- #{boundary}" }
      lines.join("\n")
    end
  end
end
