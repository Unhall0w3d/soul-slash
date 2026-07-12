# frozen_string_literal: true

require_relative "conversation_context_builder"
require_relative "conversation_identity_controls"
require_relative "conversation_identity_profile"

module SoulCore
  class Phase10IdentityStyleFoundationAssessor
    FakeStore = Struct.new(:message_list, keyword_init: true) do
      def chat(chat_id)
        { "id" => chat_id, "summary" => "" }
      end

      def messages(chat_id)
        Array(message_list)
      end
    end

    FakeMemoryStore = Struct.new(:rendered, keyword_init: true) do
      def context_for(query:, chat_id:, limit:)
        {
          "records" => [],
          "record_ids" => [],
          "layers" => [],
          "count" => 0,
          "rendered" => rendered.to_s
        }
      end
    end

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      profile = ConversationIdentityProfile.new
      controls = ConversationIdentityControls.new(profile: profile)
      context = build_context(profile)
      profile_hash = profile.to_h
      interest_status = profile_hash.fetch("interests_status")
      interest_boundary = Array(profile_hash["boundaries"]).any? do |boundary|
        boundary.match?(/do not invent .*interests/i)
      end

      verification = {
        "stable_profile_id" => profile.profile_id == "soul.identity.v1",
        "technical_tone_detected" => profile.classify_tone("Review this Ruby stack trace and git diff") == "technical",
        "supportive_tone_detected" => profile.classify_tone("I am frustrated and stuck") == "supportive",
        "supportive_tone_precedes_technical" => profile.classify_tone("I am frustrated with this Ruby error") == "supportive",
        "casual_tone_detected" => profile.classify_tone("Hello, what do you think?") == "casual",
        "high_stakes_tone_takes_precedence" => profile.classify_tone("Delete the leaked credentials from the server") == "high_stakes",
        "identity_is_injected_into_context" => context.dig("identity", "profile_id") == profile.profile_id,
        "context_reports_active_tone" => context.dig("identity", "tone_mode") == "technical",
        "no_fabricated_biography_boundary" => context.fetch("messages").first.fetch("content").include?("Do not fabricate a human biography"),
        "no_embodiment_boundary" => context.fetch("messages").first.fetch("content").include?("Do not claim biological embodiment"),
        "no_false_action_boundary" => context.fetch("messages").first.fetch("content").include?("Never claim that an action ran"),
        "interests_are_not_invented" =>
          %w[not_declared_in_this_phase reviewed_registry].include?(interest_status) &&
          interest_boundary &&
          profile_hash.fetch("automatic_identity_mutation") == false,
        "identity_controls_are_read_only" => controls.respond("identity help").include?("Mutation: none"),
        "identity_profile_is_inspectable" => controls.respond("show identity").include?(profile.profile_id),
        "punctuated_identity_command_is_supported" => controls.match?("Show identity?"),
        "broad_who_question_is_not_misparsed_as_control" => !controls.match?("Who are you?"),
        "profile_backed_identity_summary" => controls.summary.include?("do not have a human biography"),
        "canonical_identity_document_exists" => File.exist?(File.join(@root, "docs/soul/IDENTITY_AND_STYLE_POLICY.md")),
        "assessment_document_exists" => File.exist?(File.join(@root, "docs/assessments/CONVERSATIONAL_SOUL_PHASE10_IDENTITY_STYLE_FOUNDATION.md"))
      }

      blockers = verification.filter_map do |name, ok|
        name.tr("_", " ") unless ok
      end

      {
        "ok" => blockers.empty?,
        "assessment" => "phase10_identity_style_foundation",
        "milestone" => "conversational_soul",
        "phase" => 10,
        "status" => blockers.empty? ? "ready" : "blocked",
        "profile" => profile_hash,
        "sample_context" => {
          "identity" => context.fetch("identity"),
          "system_prompt_contains_identity_policy" => context.fetch("messages").first.fetch("content").include?("Soul identity policy")
        },
        "verification" => verification,
        "blockers" => blockers
      }
    end

    def render(report = assess)
      lines = [
        "Soul Phase 10 Identity and Style Policy Foundation Assessment",
        "Milestone: #{report['milestone']}",
        "Phase: #{report['phase']}",
        "Status: #{report['status']}",
        "",
        "Verification"
      ]
      report.fetch("verification").each do |name, ok|
        lines << "- #{name}: #{ok}"
      end
      lines << ""
      lines << "Blockers"
      if report.fetch("blockers").empty?
        lines << "- None"
      else
        report.fetch("blockers").each { |blocker| lines << "- #{blocker}" }
      end
      lines.join("\n")
    end

    private

    def build_context(profile)
      store = FakeStore.new(
        message_list: [
          {
            "role" => "user",
            "content" => "Please review this Ruby error and git patch.",
            "created_at" => "2026-07-11T00:00:00Z"
          }
        ]
      )
      memory = FakeMemoryStore.new(rendered: "")
      builder = ConversationContextBuilder.new(
        store: store,
        memory_store: memory,
        identity_profile: profile
      )
      builder.build(chat_id: "phase10-assessment")
    end
  end
end
