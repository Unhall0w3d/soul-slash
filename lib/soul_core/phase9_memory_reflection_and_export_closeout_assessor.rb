# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require_relative "conversation_memory_maintenance_controls"

module SoulCore
  class Phase9MemoryReflectionAndExportCloseoutAssessor
    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      result = exercise_closeout
      verification = result.fetch("verification")
      blockers = verification.reject { |_name, passed| passed }.keys.map do |name|
        name.tr("_", " ").capitalize
      end

      {
        "ok" => blockers.empty?,
        "assessment" => "phase9_memory_reflection_and_export_closeout",
        "milestone" => "conversational_soul",
        "phase" => 9,
        "slice" => "reflection_bridge_and_export_closeout",
        "status" => blockers.empty? ? "ready" : "blocked",
        "summary" => result.fetch("summary"),
        "samples" => result.fetch("samples"),
        "blockers" => blockers,
        "verification" => verification
      }
    end

    def render(report)
      lines = [
        "Soul Phase 9 Memory Reflection and Export Closeout Assessment",
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

    def exercise_closeout
      Dir.mktmpdir("soul-phase9-memory-closeout") do |directory|
        store = ConversationMemoryStore.new(
          root: directory,
          clock: deterministic_clock,
          id_generator: deterministic_ids
        )
        approved_root = File.join(directory, "Soul/reflection/approved")
        pending_root = File.join(directory, "Soul/reflection/pending")
        FileUtils.mkdir_p(approved_root)
        FileUtils.mkdir_p(pending_root)

        approved_path = File.join(approved_root, "20260711-approved-overlay.json")
        File.write(approved_path, JSON.pretty_generate(approved_reflection_fixture), encoding: "UTF-8")
        pending_path = File.join(pending_root, "20260711-pending.json")
        File.write(pending_path, JSON.pretty_generate(pending_reflection_fixture), encoding: "UTF-8")

        bridge = ConversationMemoryReflectionBridge.new(
          root: directory,
          store: store,
          approved_root: approved_root
        )
        snapshot = ConversationMemorySnapshot.new(
          root: directory,
          store: store,
          clock: deterministic_clock
        )
        controls = ConversationMemoryMaintenanceControls.new(
          root: directory,
          store: store,
          bridge: bridge,
          snapshot: snapshot
        )

        preview_output = controls.respond("preview approved reflection latest")
        events_before_import = store.events.length
        import_preview_output = controls.respond("import approved reflection latest")
        events_after_preview = store.events.length
        import_output = controls.respond("import approved reflection latest confirm")
        candidate_records = store.records(status: "candidate")
        context_before_approval = store.context_for(query: "focused ZIP overlays exact commands")
        events_after_import = store.events.length
        repeat_output = controls.respond("import approved reflection latest confirm")
        events_after_repeat = store.events.length

        approved_record = store.approve(
          candidate_records.first.fetch("id"),
          note: "Fixture approval after reflection import review"
        )
        context_after_approval = store.context_for(query: "focused ZIP overlays")

        export_output = controls.respond("export memory snapshot phase9-closeout-fixture")
        verification_output = controls.respond("verify memory snapshot phase9-closeout-fixture")
        valid_verification = snapshot.verify("phase9-closeout-fixture")
        snapshot_path = File.join(directory, "Soul/memory/exports/phase9-closeout-fixture.json")
        tampered = JSON.parse(File.read(snapshot_path, encoding: "UTF-8"))
        tampered.fetch("records").first["content"] = "tampered content"
        File.write(snapshot_path, JSON.pretty_generate(tampered), encoding: "UTF-8")
        invalid_verification = snapshot.verify("phase9-closeout-fixture")

        pending_blocked = begin
          bridge.preview(pending_path)
          false
        rescue ArgumentError
          true
        end

        verification = {
          "approved_reflection_preview_is_read_only" =>
            preview_output.include?("Mutation: none") &&
            import_preview_output.include?("Mutation: none") &&
            events_before_import == events_after_preview,
          "approved_reflection_import_creates_candidates" =>
            candidate_records.length == 2 &&
            import_output.include?("Automatically approved: no") &&
            candidate_records.all? { |record| record["status"] == "candidate" },
          "reflection_provenance_is_preserved" =>
            candidate_records.all? do |record|
              record.dig("source", "kind") == "approved_reflection" &&
                record.dig("metadata", "reflection_path") == "Soul/reflection/approved/20260711-approved-overlay.json" &&
                record.dig("metadata", "reflection_review_status") == "approved"
            end,
          "candidate_import_stays_out_of_context_until_approval" =>
            context_before_approval.fetch("records").empty?,
          "approved_import_becomes_retrievable" =>
            approved_record["status"] == "approved" &&
            context_after_approval.fetch("record_ids").include?(approved_record.fetch("id")),
          "reflection_import_is_idempotent" =>
            events_after_import == events_after_repeat &&
            repeat_output.include?("Skipped as duplicates: 2"),
          "pending_reflections_cannot_be_imported" => pending_blocked,
          "snapshot_contains_events_and_materialized_records" =>
            export_output.include?("Ledger mutation: none") &&
            valid_verification["ok"] == true &&
            valid_verification.dig("checks", "replay_matches_records") == true,
          "snapshot_digest_detects_tampering" =>
            invalid_verification["ok"] == false &&
            invalid_verification.dig("checks", "digest_matches") == false,
          "snapshot_verification_is_rendered" =>
            verification_output.include?("Status: valid") &&
            verification_output.include?("Mutation: none"),
          "maintenance_controls_are_model_independent" => maintenance_controls_are_model_independent,
          "chat_responder_declares_maintenance_controls" =>
            file_contains?("lib/soul_core/chat_responder.rb", "ConversationMemoryMaintenanceControls"),
          "orchestrator_keeps_maintenance_deterministic" =>
            file_contains?("lib/soul_core/conversation_orchestrator.rb", "memory_maintenance_control"),
          "phase9_closeout_is_registered" =>
            file_contains?("lib/soul_core/app.rb", "phase9-memory-closeout")
        }

        {
          "summary" => {
            "approved_reflection_count" => bridge.approved_paths.length,
            "imported_candidate_count" => candidate_records.length,
            "event_count" => store.events.length,
            "snapshot_valid_before_tamper" => valid_verification["ok"],
            "snapshot_valid_after_tamper" => invalid_verification["ok"]
          },
          "samples" => {
            "preview" => preview_output,
            "import" => import_output,
            "repeat_import" => repeat_output,
            "export" => export_output,
            "verify" => verification_output
          },
          "verification" => verification
        }
      end
    end

    def approved_reflection_fixture
      {
        "type" => "reflection_candidate",
        "task_kind" => "ask.think",
        "source_log" => "Soul/logs/tasks/fixture.json",
        "review_status" => "approved",
        "reviewed_at" => "2026-07-11T23:45:00Z",
        "candidate_memory_updates" => [
          "Soul uses focused ZIP overlays.",
          {
            "layer" => "preference",
            "content" => "Use exact commands when documenting overlay application.",
            "confidence" => 0.9,
            "tags" => ["overlays", "commands"]
          }
        ]
      }
    end

    def pending_reflection_fixture
      approved_reflection_fixture.merge(
        "review_status" => nil,
        "status" => "pending_review"
      )
    end

    def deterministic_clock
      value = Time.utc(2026, 7, 11, 23, 50, 0)
      -> { value }
    end

    def deterministic_ids
      number = 0
      lambda do
        number += 1
        format("closeout%04d", number)
      end
    end

    def maintenance_controls_are_model_independent
      paths = %w[
        lib/soul_core/conversation_memory_reflection_bridge.rb
        lib/soul_core/conversation_memory_snapshot.rb
        lib/soul_core/conversation_memory_maintenance_controls.rb
      ]
      paths.all? do |relative_path|
        path = File.join(@root, relative_path)
        next false unless File.exist?(path)

        source = File.read(path, encoding: "UTF-8")
        !source.match?(/provider_client|model_client|\.chat\s*\(|SOUL_ALLOW_CLOUD|curl|Open3|spawn|exec\s*\(/)
      end
    end

    def file_contains?(relative_path, text)
      path = File.join(@root, relative_path)
      File.exist?(path) && File.read(path, encoding: "UTF-8").include?(text)
    end
  end
end
