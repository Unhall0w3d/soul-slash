# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require_relative "application_facade"
require_relative "conversation_clear_service"
require_relative "intent_router"
require_relative "skill_registry"
require_relative "skill_runner"

module SoulCore
  class ConversationClearServiceAssessor
    class OversizedStore
      def list_chats
        501.times.map { |index| { "id" => format("chat_fixture_%04d", index), "title" => "Bulk", "archived" => false } }
      end
    end

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      checks = {}
      details = {}

      Dir.mktmpdir("soul-chats-clear-") do |temp_root|
        store = ChatStore.new(root: temp_root)
        alpha_one = store.create_chat(initial_title: "Alpha")
        alpha_two = store.create_chat(initial_title: "alpha")
        beta = store.create_chat(initial_title: "Beta")
        store.add_message(alpha_one.fetch("id"), role: "user", content: "preserve this transcript")
        service = ConversationClearService.new(root: temp_root, store: store)
        before = chat_files(temp_root)

        missing = service.preview(mode: "title", title: "")
        substring = service.preview(mode: "title", title: "Alp")
        conflicting = service.preview(mode: "all", title: "Alpha")
        checks["missing_conflicting_and_substring_selectors_await_input"] =
          [missing, substring, conflicting].all? { |result| result["lifecycle_state"] == "awaiting_input" }

        preview = service.preview(mode: "title", title: "  ALPHA ")
        checks["exact_title_preview_is_trimmed_case_insensitive_and_discloses_duplicates"] =
          preview["ok"] == true && preview.dig("data", "count") == 2 &&
          preview.dig("data", "records").map { |record| record.fetch("id") }.sort == [alpha_one.fetch("id"), alpha_two.fetch("id")].sort &&
          preview.dig("data", "confirmation_phrase") == ConversationClearService::CONFIRMATION

        checks["preview_is_read_only_and_transcript_preserving"] = before == chat_files(temp_root) && preview.dig("data", "transcripts_deleted") == false

        wrong_confirmation = service.execute(mode: "title", title: "Alpha", confirmation: "clear", expected_digest: preview.dig("data", "match_digest"))
        missing_digest = service.execute(mode: "title", title: "Alpha", confirmation: ConversationClearService::CONFIRMATION, expected_digest: nil)
        checks["execution_requires_exact_confirmation_and_preview_digest"] =
          [wrong_confirmation, missing_digest].all? { |result| result["lifecycle_state"] == "awaiting_input" } && store.list_chats.length == 3

        alpha_three = store.create_chat(initial_title: "Alpha")
        stale = service.execute(mode: "title", title: "Alpha", confirmation: ConversationClearService::CONFIRMATION, expected_digest: preview.dig("data", "match_digest"))
        checks["stale_match_digest_blocks_before_mutation"] = stale["lifecycle_state"] == "blocked_for_human_review" && store.list_chats.length == 4

        fresh = service.preview(mode: "title", title: "Alpha")
        transcript_before = File.binread(File.join(temp_root, ChatStore::DEFAULT_ROOT, "#{alpha_one.fetch('id')}.jsonl"))
        executed = service.execute(mode: "title", title: "Alpha", confirmation: ConversationClearService::CONFIRMATION, expected_digest: fresh.dig("data", "match_digest"))
        transcript_after = File.binread(File.join(temp_root, ChatStore::DEFAULT_ROOT, "#{alpha_one.fetch('id')}.jsonl"))
        checks["verified_execution_archives_exact_matches_without_deleting_files"] =
          executed["ok"] == true && executed.dig("data", "count") == 3 && store.list_chats.map { |record| record.fetch("id") } == [beta.fetch("id")] &&
          store.list_chats(include_archived: true).length == 4 && transcript_before == transcript_after && transcript_after.include?("preserve this transcript") &&
          [alpha_one, alpha_two, alpha_three].all? { |record| File.file?(File.join(temp_root, ChatStore::DEFAULT_ROOT, "#{record.fetch('id')}.json")) }

        repeated = service.preview(mode: "title", title: "Alpha")
        checks["repeated_clear_is_safe_and_reports_no_active_matches"] = repeated["lifecycle_state"] == "awaiting_input" && store.list_chats.length == 1

        all_preview = service.preview(mode: "all")
        all_executed = service.execute(mode: "all", confirmation: ConversationClearService::CONFIRMATION, expected_digest: all_preview.dig("data", "match_digest"))
        checks["all_mode_archives_remaining_active_conversations"] = all_executed["ok"] == true && all_executed.dig("data", "count") == 1 && store.list_chats.empty? && store.list_chats(include_archived: true).length == 4

        oversized = ConversationClearService.new(root: temp_root, store: OversizedStore.new).preview(mode: "all")
        checks["match_count_is_bounded_at_500"] = oversized["lifecycle_state"] == "blocked_for_human_review" && oversized["reason"].include?("500")

        facade_store = ChatStore.new(root: File.join(temp_root, "facade"))
        facade_store.create_chat(initial_title: "Facade target")
        facade_service = ConversationClearService.new(root: File.join(temp_root, "facade"), store: facade_store)
        facade = ApplicationFacade.new(root: File.join(temp_root, "facade"), process_env: {}, chat_store: facade_store, conversation_clear_service: facade_service)
        facade_preview = facade.call(request("facade:clear:preview", "chats.clear.preview", { "mode" => "title", "title" => "Facade target" }))
        checks["application_facade_exposes_versioned_preview_without_mutation"] = facade_preview["lifecycle_state"] == "complete" && facade_preview.dig("data", "count") == 1 && facade_preview.dig("meta", "mutation") == "none" && facade_store.list_chats.length == 1

        intent = IntentRouter.new.route("clear all conversations")
        checks["intent_routes_to_confirmation_gated_skill"] = intent.skill_id == "chats.clear" && intent.confirmation_required == true && intent.risk == "approval_required"

        runner_blocked = begin
          SkillRunner.new(registry: SkillRegistry.new(path: File.join(@root, "Soul/skills/registry.yaml"))).run("chats.clear", args: ["--execute", "--all", "--expected-digest", "0" * 64])
          false
        rescue RuntimeError => error
          error.message.include?("exact confirmation")
        end
        checks["skill_runner_retains_independent_write_confirmation_gate"] = runner_blocked

        html = File.read(File.join(@root, "assets/dashboard/index.html"))
        js = File.read(File.join(@root, "assets/dashboard/dashboard.js"))
        checks["dashboard_requires_preview_and_exact_confirmation"] =
          html.include?("Transcripts remain stored locally") && html.include?("CLEAR_CONVERSATIONS") &&
          js.include?('callSoul("chats.clear.preview"') && js.include?('callSoul("chats.clear.execute"') &&
          js.index('callSoul("chats.clear.preview"') < js.index('callSoul("chats.clear.execute"') &&
          js.include?('value !== "CLEAR_CONVERSATIONS"') && !js.include?("innerHTML")

        source = [
          File.read(File.join(@root, "lib/soul_core/conversation_clear_service.rb")),
          File.read(File.join(@root, "Soul/skills/chats/clear.rb"))
        ].join("\n")
        forbidden = %w[File.delete File.unlink File.truncate rm( Thread.new fork( daemon( setInterval setTimeout]
        checks["no_permanent_delete_or_background_primitive_is_added"] = forbidden.none? { |needle| source.include?(needle) }

        details["archived_count"] = store.list_chats(include_archived: true).count { |record| record["archived"] == true }
        details["transcript_bytes_preserved"] = transcript_after.bytesize
      end

      blockers = checks.filter_map { |name, passed| name unless passed }
      {
        "ok" => blockers.empty?,
        "assessment" => "conversation_list_clearing_skill",
        "phase" => "12C-amendment",
        "status" => blockers.empty? ? "candidate_ready" : "blocked",
        "blockers" => blockers,
        "verification" => checks,
        "details" => details,
        "memory_keys" => [],
        "lifecycle_states" => %w[complete failed awaiting_input canceled blocked_for_human_review],
        "risk_class" => "Class 3: Local user-data modification",
        "human_review_required" => true
      }
    end

    def render(report)
      lines = ["Soul Conversation List Clearing Skill Assessment", "Status: #{report['status']}", "", "Verification"]
      report.fetch("verification").each { |key, value| lines << "- #{key}: #{value}" }
      lines << ""
      lines << "Blockers"
      report.fetch("blockers").empty? ? lines << "- None" : report.fetch("blockers").each { |item| lines << "- #{item}" }
      lines.join("\n")
    end

    private

    def request(request_id, operation, parameters)
      { "schema_version" => ApplicationContract::SCHEMA_VERSION, "request_id" => request_id, "operation" => operation, "parameters" => parameters, "context" => { "interface" => "dashboard_test" } }
    end

    def chat_files(root)
      Dir.glob(File.join(root, ChatStore::DEFAULT_ROOT, "*"), File::FNM_DOTMATCH).reject { |path| %w[. ..].include?(File.basename(path)) }.to_h { |path| [File.basename(path), File.binread(path)] }
    end
  end
end
