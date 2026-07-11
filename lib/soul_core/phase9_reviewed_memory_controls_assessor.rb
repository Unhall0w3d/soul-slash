# frozen_string_literal: true

require "tmpdir"
require_relative "conversation_memory_controls"

module SoulCore
  class Phase9ReviewedMemoryControlsAssessor
    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      result = exercise_controls
      verification = result.fetch("verification")
      blockers = verification.reject { |_name, passed| passed }.keys.map do |name|
        name.tr("_", " ").capitalize
      end

      {
        "ok" => blockers.empty?,
        "assessment" => "phase9_reviewed_memory_controls",
        "milestone" => "conversational_soul",
        "phase" => 9,
        "slice" => "reviewed_memory_controls",
        "status" => blockers.empty? ? "ready" : "blocked",
        "summary" => result.fetch("summary"),
        "samples" => result.fetch("samples"),
        "blockers" => blockers,
        "verification" => verification
      }
    end

    def render(report)
      lines = [
        "Soul Phase 9 Reviewed Memory Controls Assessment",
        "Milestone: #{report['milestone']}",
        "Phase: #{report['phase']}",
        "Slice: #{report['slice']}",
        "Status: #{report['status']}",
        "",
        "Verification"
      ]
      report.fetch("verification").each do |name, passed|
        lines << "- #{name}: #{passed}"
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

    def exercise_controls
      Dir.mktmpdir("soul-phase9-reviewed-memory") do |directory|
        memory = ConversationMemoryStore.new(
          root: directory,
          clock: deterministic_clock,
          id_generator: deterministic_ids
        )
        controls = ConversationMemoryControls.new(root: directory, store: memory)
        chat_id = "chat_reviewed_memory_fixture"

        ambiguous = "Do you remember when we discussed overlays?"
        proposal_output = controls.respond(
          "remember this as preference: Use compact technical explanations.",
          chat_id: chat_id
        )
        first = memory.records(status: "candidate").first
        before_approval = memory.context_for(query: "technical explanations", chat_id: chat_id)
        list_output = controls.respond("list memory candidates", chat_id: chat_id)
        show_output = controls.respond("show memory #{first.fetch('id')}", chat_id: chat_id)
        approval_output = controls.respond("approve memory latest", chat_id: chat_id)
        approved = memory.find(first.fetch("id"))
        after_approval = memory.context_for(query: "technical explanations", chat_id: chat_id)

        replacement_output = controls.respond(
          "remember preference: Use concise technical explanations with exact commands.",
          chat_id: chat_id
        )
        replacement = memory.records(status: "candidate").first
        controls.respond("approve memory #{replacement.fetch('id')}", chat_id: chat_id)

        supersede_preview = controls.respond(
          "supersede memory #{approved.fetch('id')} with #{replacement.fetch('id')}",
          chat_id: chat_id
        )
        unchanged_before_supersede = memory.find(approved.fetch("id"))["status"] == "approved"
        supersede_output = controls.respond(
          "supersede memory #{approved.fetch('id')} with #{replacement.fetch('id')} confirm",
          chat_id: chat_id
        )
        superseded = memory.find(approved.fetch("id"))

        delete_preview = controls.respond("forget memory #{replacement.fetch('id')}", chat_id: chat_id)
        unchanged_before_delete = memory.find(replacement.fetch("id"))["status"] == "approved"
        delete_output = controls.respond(
          "forget memory #{replacement.fetch('id')} confirm",
          chat_id: chat_id
        )
        deleted = memory.find(replacement.fetch("id"))

        verification = {
          "explicit_remember_creates_candidate" =>
            first["status"] == "candidate" && proposal_output.include?("Approved context: no"),
          "candidate_does_not_enter_context" => before_approval.fetch("records").empty?,
          "conversation_provenance_is_preserved" =>
            first.dig("source", "kind") == "conversation_request" &&
            first.dig("source", "reference") == chat_id &&
            first["chat_id"] == chat_id,
          "candidate_can_be_listed_and_inspected" =>
            list_output.include?(first.fetch("id")) &&
            show_output.include?("Source: conversation_request:#{chat_id}"),
          "approval_is_explicit_and_retrievable" =>
            approved["status"] == "approved" &&
            approval_output.include?("Eligible for relevant context: yes") &&
            after_approval.fetch("record_ids").include?(approved.fetch("id")),
          "supersession_requires_confirmation" =>
            supersede_preview.include?("Mutation: none") && unchanged_before_supersede,
          "confirmed_supersession_preserves_replacement" =>
            superseded["status"] == "superseded" &&
            superseded["superseded_by"] == replacement.fetch("id") &&
            supersede_output.include?("Audit history preserved: yes"),
          "forget_requires_confirmation" =>
            delete_preview.include?("Mutation: none") && unchanged_before_delete,
          "confirmed_forget_is_logical_deletion" =>
            deleted["status"] == "deleted" &&
            delete_output.include?("Physical purge: not performed"),
          "ambiguous_recall_is_not_a_memory_control" => !controls.match?(ambiguous),
          "append_only_events_cover_all_mutations" =>
            File.readlines(memory.path).length == memory.events.length &&
            memory.events.map { |event| event["event"] }.include?("superseded") &&
            memory.events.map { |event| event["event"] }.include?("deleted"),
          "controller_is_model_independent" => controller_is_model_independent,
          "chat_responder_declares_memory_control" =>
            file_contains?("lib/soul_core/chat_responder.rb", "ConversationMemoryControls") &&
            file_contains?("lib/soul_core/chat_responder.rb", "chat_id: nil"),
          "runtime_passes_chat_identity_to_deterministic_controls" =>
            file_contains?("lib/soul_core/conversation_runtime.rb", "deterministic_response(text, chat_id)"),
          "orchestrator_keeps_memory_mutation_deterministic" =>
            file_contains?("lib/soul_core/conversation_orchestrator.rb", "memory_control")
        }

        {
          "summary" => {
            "event_count" => memory.events.length,
            "active_record_count" => memory.records.length,
            "candidate_count" => memory.records(status: "candidate").length,
            "approved_count" => memory.records(status: "approved").length,
            "superseded_count" => memory.records(status: "superseded").length,
            "deleted_count" => memory.records(status: "deleted", include_deleted: true).length
          },
          "samples" => {
            "proposal" => proposal_output,
            "approval" => approval_output,
            "replacement_proposal" => replacement_output,
            "supersession" => supersede_output,
            "deletion" => delete_output
          },
          "verification" => verification
        }
      end
    end

    def deterministic_clock
      value = Time.utc(2026, 7, 11, 23, 30, 0)
      -> { value }
    end

    def deterministic_ids
      number = 0
      lambda do
        number += 1
        format("fixture%04d", number)
      end
    end

    def controller_is_model_independent
      path = File.join(@root, "lib/soul_core/conversation_memory_controls.rb")
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
