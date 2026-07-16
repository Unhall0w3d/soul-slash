# frozen_string_literal: true

require "tmpdir"
require_relative "conversation_context_builder"
require_relative "conversation_identity_profile"
require_relative "conversation_interest_controls"
require_relative "conversation_interest_store"
require_relative "conversation_style_analyzer"
require_relative "conversation_style_controls"

module SoulCore
  class Phase10InspectableInterestsCloseoutAssessor
    FakeStore = Struct.new(:root, :message_list, keyword_init: true) do
      def project_root = root
      def chat(chat_id) = { "id" => chat_id, "summary" => "" }
      def messages(_chat_id) = Array(message_list)
    end

    FakeMemoryStore = Struct.new(:unused, keyword_init: true) do
      def context_for(query:, chat_id:, limit:)
        _unused = [query, chat_id, limit]
        { "records" => [], "record_ids" => [], "layers" => [], "count" => 0, "rendered" => "" }
      end
    end

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      verification = Dir.mktmpdir("soul-phase10c") { |tmp| exercise(tmp) }
      blockers = verification.filter_map { |name, ok| name.tr("_", " ") unless ok }
      {
        "ok" => blockers.empty?,
        "assessment" => "phase10_inspectable_interests_closeout",
        "milestone" => "conversational_soul",
        "phase" => 10,
        "slice" => "10C",
        "status" => blockers.empty? ? "ready" : "blocked",
        "verification" => verification,
        "blockers" => blockers
      }
    end

    def render(report = assess)
      lines = [
        "Soul Phase 10 Inspectable Interests and Closeout Assessment",
        "Milestone: #{report['milestone']}",
        "Phase: #{report['phase']} (#{report['slice']})",
        "Status: #{report['status']}", "", "Verification"
      ]
      report.fetch("verification").each { |name, ok| lines << "- #{name}: #{ok}" }
      lines << "" << "Blockers"
      report.fetch("blockers").empty? ? lines << "- None" : report.fetch("blockers").each { |item| lines << "- #{item}" }
      lines.join("\n")
    end

    private

    def exercise(tmp)
      clock = -> { Time.utc(2026, 7, 12, 3, 0, 0) }
      sequence = 0
      ids = -> { sequence += 1; format("fixture%02d", sequence) }
      interests = ConversationInterestStore.new(root: tmp, clock: clock, id_generator: ids)
      controls = ConversationInterestControls.new(store: interests)

      candidate = interests.propose(
        topic: "Ruby runtime architecture",
        description: "Inspectable local-first assistant runtime design",
        source: { "kind" => "phase10c_fixture", "reference" => "assessment" },
        confidence: 0.9,
        chat_id: "phase10c-chat",
        tags: %w[ruby runtime architecture]
      )
      before = interests.context_for(query: "Ruby runtime architecture")
      approved = interests.approve(candidate.fetch("id"), note: "fixture approval")
      relevant = interests.context_for(query: "Ruby runtime architecture")
      unrelated = interests.context_for(query: "sourdough bread recipe")

      messages = [
        { "role" => "assistant", "content" => "Here is the result. token ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" },
        { "role" => "assistant", "content" => "Here is the result. token ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" },
        { "role" => "assistant", "content" => "Here is the result. token ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" },
        { "role" => "user", "content" => "Explain the Ruby runtime architecture." }
      ]
      fake_store = FakeStore.new(root: tmp, message_list: messages)
      context = ConversationContextBuilder.new(
        store: fake_store,
        memory_store: FakeMemoryStore.new,
        identity_profile: ConversationIdentityProfile.new,
        style_analyzer: ConversationStyleAnalyzer.new,
        interest_store: interests
      ).build(chat_id: "phase10c-chat")

      style_controls = ConversationStyleControls.new(store: fake_store, analyzer: ConversationStyleAnalyzer.new)
      style_render = style_controls.respond("show recent style", chat_id: "phase10c-chat")
      help_render = controls.respond("interest help", chat_id: "phase10c-chat")
      deactivate_preview = controls.respond("deactivate interest #{approved['id']}", chat_id: "phase10c-chat")
      controls.respond("deactivate interest #{approved['id']} confirm", chat_id: "phase10c-chat")
      inactive = interests.context_for(query: "Ruby runtime architecture")
      controls.respond("reactivate interest #{approved['id']}", chat_id: "phase10c-chat")
      controls.respond("retire interest #{approved['id']} confirm", chat_id: "phase10c-chat")
      retired = interests.context_for(query: "Ruby runtime architecture")

      profile = ConversationIdentityProfile.new.to_h
      {
        "candidate_interests_stay_out_of_context" => before.fetch("records").empty?,
        "approved_relevant_interest_enters_context" => relevant.fetch("record_ids").include?(approved.fetch("id")),
        "approved_unrelated_interest_stays_out_of_context" => unrelated.fetch("records").empty?,
        "context_includes_reviewed_interest_guidance" => context.fetch("messages").first.fetch("content").include?("Reviewed Soul interests"),
        "context_exposes_bounded_interest_metadata" => context.dig("interests", "count") == 1 && context.dig("interests", "automatic_inference") == false,
        "inactive_interests_stay_out_of_context" => inactive.fetch("records").empty?,
        "retired_interests_stay_out_of_context" => retired.fetch("records").empty?,
        "interest_events_remain_append_only" => interests.events(id: approved.fetch("id")).map { |event| event["event"] } == %w[created approved deactivated reactivated retired],
        "mutations_require_review_boundaries" => help_render.include?("Proposals remain candidates") && deactivate_preview.include?("Mutation: none") && deactivate_preview.include?("Confirmation required"),
        "ordinary_interesting_language_is_not_hijacked" => !controls.match?("What are the interesting parts of Ruby?"),
        "identity_profile_id_remains_stable" => profile["profile_id"] == "soul.identity.v1",
        "identity_profile_declares_reviewed_registry" => profile["profile_version"].to_i >= 2 && profile["interests_status"] == "reviewed_registry",
        "interests_do_not_imply_experience_or_authority" => context.fetch("messages").first.fetch("content").include?("do not imply personal experience, feelings, credentials, embodiment, or authority"),
        "style_inspection_suppresses_sensitive_values" => style_render.include?("preview suppressed") && !style_render.include?("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"),
        "canonical_interest_document_exists" => File.exist?(File.join(@root, "docs/soul/REVIEWED_INTERESTS.md")),
        "phase10_closeout_document_exists" => File.exist?(File.join(@root, "docs/assessments/CONVERSATIONAL_SOUL_PHASE10_CLOSEOUT.md"))
      }
    end
  end
end
