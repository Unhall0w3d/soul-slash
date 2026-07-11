# frozen_string_literal: true

require "tmpdir"
require "time"
require_relative "chat_store"
require_relative "conversation_context_builder"
require_relative "conversation_memory_store"

module SoulCore
  class Phase9LayeredMemoryFoundationAssessor
    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      fixture = build_fixture
      verification = fixture.fetch("verification")
      blockers = verification.filter_map do |name, passed|
        name.tr("_", " ").capitalize unless passed
      end

      {
        "ok" => blockers.empty?,
        "assessment" => "phase9_layered_memory_foundation",
        "milestone" => "conversational_soul",
        "phase" => 9,
        "status" => blockers.empty? ? "ready" : "blocked",
        "summary" => fixture.fetch("summary"),
        "verification" => verification,
        "samples" => fixture.fetch("samples"),
        "blockers" => blockers
      }
    end

    def render(report = assess)
      lines = [
        "Soul Phase 9 Layered Memory Foundation Assessment",
        "Milestone: #{report['milestone']}",
        "Phase: #{report['phase']}",
        "Status: #{report['status']}",
        "",
        "Memory summary"
      ]

      report.fetch("summary").each do |name, value|
        lines << "- #{name}: #{value}"
      end

      lines << ""
      lines << "Verification"
      report.fetch("verification").each do |name, passed|
        lines << "- #{name}: #{passed}"
      end

      lines << ""
      lines << "Blockers"
      blockers = Array(report["blockers"])
      if blockers.empty?
        lines << "- None"
      else
        blockers.each { |blocker| lines << "- #{blocker}" }
      end

      lines.join("\n")
    end

    private

    def build_fixture
      Dir.mktmpdir("soul-phase9-memory") do |directory|
        clock = deterministic_clock
        sequence = 0
        generator = lambda do
          sequence += 1
          format("%010d", sequence)
        end
        memory = ConversationMemoryStore.new(
          root: directory,
          clock: clock,
          id_generator: generator
        )
        chats = ChatStore.new(root: directory)
        chat = chats.create_chat(initial_title: "Phase 9 fixture")
        chat_id = chat.fetch("id")

        old_project = memory.propose(
          layer: "project",
          content: "Soul development uses focused ZIP overlays.",
          source: { "kind" => "user_review", "reference" => "phase7" },
          confidence: 0.82,
          tags: %w[soul overlay]
        )
        candidate_hidden_before_approval = memory.context_for(
          query: "Soul overlay development",
          chat_id: chat_id
        ).fetch("records").empty?
        memory.approve(old_project.fetch("id"), note: "Approved fixture memory")

        current_project = memory.propose(
          layer: "project",
          content: "Soul development uses focused, idempotent ZIP overlays with deterministic verifiers.",
          source: { "kind" => "user_review", "reference" => "phase8" },
          confidence: 0.96,
          tags: %w[soul overlay verifier]
        )
        memory.approve(current_project.fetch("id"))
        memory.supersede(
          old_project.fetch("id"),
          by: current_project.fetch("id"),
          reason: "The newer project memory is more specific."
        )

        deleted_preference = memory.propose(
          layer: "preference",
          content: "Shell examples should be compatible with zsh.",
          source: { "kind" => "explicit_preference", "reference" => "conversation" },
          confidence: 1.0,
          metadata: { "always_include" => true }
        )
        memory.approve(deleted_preference.fetch("id"))
        memory.delete(deleted_preference.fetch("id"), reason: "Fixture deletion test")

        episode = memory.propose(
          layer: "episodic",
          content: "Phase 8 declared capability boundaries was completed, committed, and pushed.",
          source: { "kind" => "conversation", "reference" => chat_id },
          confidence: 0.94,
          chat_id: chat_id,
          tags: %w[phase8 capability]
        )
        memory.approve(episode.fetch("id"))

        candidate_semantic = memory.propose(
          layer: "semantic",
          content: "This unapproved candidate must never enter model context.",
          source: { "kind" => "reflection_candidate", "reference" => "fixture" },
          confidence: 0.75,
          metadata: { "always_include" => true }
        )

        approved_semantic = memory.propose(
          layer: "semantic",
          content: "Approved memory must retain provenance and confidence when supplied to conversation context.",
          source: { "kind" => "reviewed_rule", "reference" => "phase9-fixture" },
          confidence: 0.99,
          metadata: { "always_include" => true }
        )
        memory.approve(approved_semantic.fetch("id"))

        query = "What is the current Soul overlay workflow and Phase 8 status?"
        chats.add_message(chat_id, role: "user", content: query)
        memory_context = memory.context_for(query: query, chat_id: chat_id)
        builder = ConversationContextBuilder.new(store: chats, memory_store: memory)
        context = builder.build(chat_id: chat_id)
        system_message = context.fetch("messages").first.fetch("content")
        selected_ids = memory_context.fetch("record_ids")

        verification = {
          "working_memory_remains_recent_conversation_context" =>
            context.fetch("messages").any? { |message| message["role"] == "user" && message["content"] == query },
          "project_preference_episodic_and_semantic_layers_are_declared" =>
            ConversationMemoryStore::LAYERS == %w[project preference episodic semantic],
          "new_memory_starts_as_candidate" => old_project["status"] == "candidate",
          "candidate_memory_is_not_retrieved_before_approval" => candidate_hidden_before_approval,
          "approved_memory_is_retrievable" =>
            selected_ids.include?(current_project.fetch("id")) &&
            selected_ids.include?(episode.fetch("id")) &&
            selected_ids.include?(approved_semantic.fetch("id")),
          "unapproved_memory_is_excluded" => !selected_ids.include?(candidate_semantic.fetch("id")),
          "superseded_memory_is_excluded" => !selected_ids.include?(old_project.fetch("id")),
          "deleted_memory_is_excluded" => !selected_ids.include?(deleted_preference.fetch("id")),
          "supersession_preserves_replacement_identity" =>
            memory.find(old_project.fetch("id"))["superseded_by"] == current_project.fetch("id"),
          "logical_deletion_preserves_audit_events" =>
            memory.find(deleted_preference.fetch("id"))["status"] == "deleted" &&
            memory.events(memory_id: deleted_preference.fetch("id")).length == 3,
          "provenance_and_confidence_are_rendered" =>
            memory_context.fetch("rendered").include?("source user_review:phase8") &&
            memory_context.fetch("rendered").include?("confidence 0.96"),
          "approved_memory_is_injected_into_system_context" =>
            system_message.include?("Approved memory context:") &&
            system_message.include?(current_project.fetch("content")),
          "memory_context_reports_selected_ids_and_layers" =>
            context.dig("memory", "record_ids").include?(current_project.fetch("id")) &&
            context.dig("memory", "layers").include?("project"),
          "automatic_promotion_is_disabled" =>
            memory.events.all? { |event| event["promote_automatically"] != true },
          "ledger_is_append_only_jsonl" =>
            File.extname(memory.path) == ".jsonl" &&
            File.readlines(memory.path).length == memory.events.length,
          "chat_store_exposes_project_root_for_memory_wiring" => chats.project_root == File.expand_path(directory),
          "context_builder_uses_null_memory_for_non_project_stores" => null_store_context_works,
          "implementation_does_not_call_models" => memory_store_is_model_independent,
          "runtime_files_declare_phase9_integration" =>
            file_contains?("lib/soul_core/conversation_context_builder.rb", "Approved memory context") &&
            file_contains?("lib/soul_core/chat_store.rb", "attr_reader :project_root, :root")
        }

        {
          "summary" => {
            "event_count" => memory.events.length,
            "materialized_record_count" => memory.records(include_deleted: true).length,
            "approved_active_count" => memory.records(status: "approved").length,
            "selected_context_count" => memory_context.fetch("count"),
            "selected_layers" => memory_context.fetch("layers")
          },
          "verification" => verification,
          "samples" => {
            "current_project" => memory.find(current_project.fetch("id")),
            "superseded_project" => memory.find(old_project.fetch("id")),
            "deleted_preference" => memory.find(deleted_preference.fetch("id")),
            "candidate_semantic" => memory.find(candidate_semantic.fetch("id")),
            "memory_context" => memory_context,
            "context_memory_metadata" => context.fetch("memory")
          }
        }
      end
    end

    def deterministic_clock
      value = Time.utc(2026, 7, 11, 19, 0, 0)
      -> { value }
    end

    def null_store_context_works
      fake_store = Object.new
      fake_store.define_singleton_method(:chat) { |_id| { "summary" => "" } }
      fake_store.define_singleton_method(:messages) { |_id| [] }
      context = ConversationContextBuilder.new(store: fake_store).build(chat_id: "fixture")
      context.dig("memory", "count").zero?
    rescue StandardError
      false
    end

    def memory_store_is_model_independent
      path = File.join(@root, "lib/soul_core/conversation_memory_store.rb")
      return false unless File.exist?(path)

      source = File.read(path, encoding: "UTF-8")
      !source.match?(/provider|model_client|\.chat\s*\(|Open3|spawn|exec\s*\(/)
    end

    def file_contains?(relative_path, text)
      path = File.join(@root, relative_path)
      File.exist?(path) && File.read(path, encoding: "UTF-8").include?(text)
    end
  end
end
