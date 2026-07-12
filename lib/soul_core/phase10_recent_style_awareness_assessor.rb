# frozen_string_literal: true

require_relative "conversation_context_builder"
require_relative "conversation_identity_profile"
require_relative "conversation_style_analyzer"
require_relative "conversation_style_controls"

module SoulCore
  class Phase10RecentStyleAwarenessAssessor
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
      analyzer = ConversationStyleAnalyzer.new(window: 8)
      repeated = analyzer.analyze(messages: repeated_messages)
      clean = analyzer.analyze(messages: clean_messages)
      context = build_context(analyzer)
      controls = ConversationStyleControls.new(
        store: FakeStore.new(message_list: repeated_messages),
        analyzer: analyzer
      )
      recent_render = controls.respond("show recent style", chat_id: "phase10b-assessment")

      verification = {
        "bounded_window_is_declared" => repeated["window_size"] == 8,
        "minimum_sample_is_enforced" => !analyzer.analyze(messages: repeated_messages.first(2))["eligible"],
        "repeated_opening_is_detected" => signal?(repeated, "repeated_opening"),
        "repeated_closing_is_detected" => signal?(repeated, "repeated_closing"),
        "repeated_sentence_is_detected" => signal?(repeated, "repeated_sentence"),
        "repeated_structure_is_detected" => signal?(repeated, "repeated_structure"),
        "disclaimer_overuse_is_detected" => signal?(repeated, "disclaimer_overuse"),
        "clean_sample_has_no_guidance" => clean.fetch("guidance").empty?,
        "guidance_is_bounded" => repeated.fetch("guidance").length <= ConversationStyleAnalyzer::MAX_GUIDANCE,
        "guidance_preserves_priority_boundaries" => analyzer.render_system_guidance(repeated).include?("never overrides truth, safety, deterministic routing, evidence, approvals, or the user's requested format"),
        "context_exposes_style_metadata" => context.dig("style", "assistant_sample_count") == 4,
        "context_injects_variation_guidance" => context.fetch("messages").first.fetch("content").include?("Recent style awareness"),
        "identity_mutation_remains_disabled" => context.dig("style", "automatic_identity_mutation") == false,
        "persistent_style_profile_remains_disabled" => context.dig("style", "persistent_style_profile") == false,
        "style_controls_are_read_only" => controls.respond("style help").include?("Mutation: none"),
        "recent_style_is_inspectable" => recent_render.include?("repeated_opening"),
        "raw_responses_are_not_rendered" => !recent_render.include?("private diagnostic payload"),
        "broad_style_question_is_not_misparsed" => !controls.match?("What writing style do you recommend?"),
        "canonical_document_exists" => File.exist?(File.join(@root, "docs/soul/RECENT_STYLE_AWARENESS.md")),
        "assessment_document_exists" => File.exist?(File.join(@root, "docs/assessments/CONVERSATIONAL_SOUL_PHASE10_RECENT_STYLE_AWARENESS.md"))
      }

      blockers = verification.filter_map do |name, ok|
        name.tr("_", " ") unless ok
      end

      {
        "ok" => blockers.empty?,
        "assessment" => "phase10_recent_style_awareness",
        "milestone" => "conversational_soul",
        "phase" => 10,
        "slice" => "10B",
        "status" => blockers.empty? ? "ready" : "blocked",
        "sample_analysis" => repeated,
        "verification" => verification,
        "blockers" => blockers
      }
    end

    def render(report = assess)
      lines = [
        "Soul Phase 10 Recent-Style Awareness Assessment",
        "Milestone: #{report['milestone']}",
        "Phase: #{report['phase']}#{report['slice'] ? " (#{report['slice']})" : ""}",
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

    def signal?(analysis, type)
      analysis.fetch("signals").any? { |signal| signal["type"] == type }
    end

    def repeated_messages
      [
        assistant("Here is the result. The boundary remains unchanged. I cannot access the private diagnostic payload.\n\n- Check one\n- Check two\n- Check three\n\nThe boundary remains unchanged."),
        user("Can you check again?"),
        assistant("Here is the result. The boundary remains unchanged. I cannot inspect the private diagnostic payload.\n\n- Check one\n- Check two\n- Check three\n\nThe boundary remains unchanged."),
        user("And once more?"),
        assistant("Here is the result. The boundary remains unchanged. I can't read the private diagnostic payload.\n\n- Check one\n- Check two\n- Check three\n\nThe boundary remains unchanged."),
        user("Summarize it."),
        assistant("Here is the result. The boundary remains unchanged.\n\n- Check one\n- Check two\n- Check three\n\nThe boundary remains unchanged."),
        user("What should change?")
      ]
    end

    def clean_messages
      [
        assistant("The parser fails before it reaches the route."),
        assistant("Three checks passed; the fourth found a stale fixture."),
        assistant("Use the existing rollback command, then rerun the verifier.")
      ]
    end

    def build_context(analyzer)
      store = FakeStore.new(message_list: repeated_messages)
      memory = FakeMemoryStore.new(rendered: "")
      builder = ConversationContextBuilder.new(
        store: store,
        memory_store: memory,
        identity_profile: ConversationIdentityProfile.new,
        style_analyzer: analyzer
      )
      builder.build(chat_id: "phase10b-assessment")
    end

    def assistant(content)
      { "role" => "assistant", "content" => content, "created_at" => "2026-07-11T00:00:00Z" }
    end

    def user(content)
      { "role" => "user", "content" => content, "created_at" => "2026-07-11T00:00:00Z" }
    end
  end
end
