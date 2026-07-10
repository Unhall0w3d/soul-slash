# frozen_string_literal: true

require "json"
require "time"
require "tmpdir"
require_relative "approval_token_chat_controls"
require_relative "approval_token_store"
require_relative "chat_execution_history"
require_relative "downloads_move_dry_run_executor"
require_relative "read_only_skill_execution_gate"

module SoulCore
  class DownloadsMoveDryRunAssessor
    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      Dir.mktmpdir("soul-downloads-dry-run-phase61-") do |dir|
        history = ChatExecutionHistory.new(root: @root, path: File.join(dir, "history.jsonl"))
        store = ApprovalTokenStore.new(root: @root, path: File.join(dir, "approval_tokens.json"))
        gate = ReadOnlySkillExecutionGate.new(root: @root, history: history)
        controls = ApprovalTokenChatControls.new(root: @root, gate: gate, store: store)
        executor = DownloadsMoveDryRunExecutor.new(root: @root, gate: gate, store: store)

        approved = controls.approve_downloads_cleanup_preview(ttl_seconds: 300)
        token_id = approved.dig("token", "token_id")
        dry_run = executor.execute(token_id: token_id)
        token_after = store.find(token_id)

        revoked_token = controls.approve_downloads_cleanup_preview(ttl_seconds: 300).dig("token", "token_id")
        store.revoke(revoked_token)
        revoked_run = executor.execute(token_id: revoked_token)

        blockers = []
        blockers << "Expected approval token" if token_id.to_s.empty?
        blockers << "Expected dry-run to succeed" unless dry_run["ok"] == true && dry_run["status"] == "dry_run_ready"
        blockers << "Expected mutation none" unless dry_run["mutation"] == "none"
        blockers << "Expected token not consumed" unless dry_run["token_consumed"] == false
        blockers << "Expected token to remain pending" unless token_after && token_after["status"] == "pending"
        blockers << "Expected revoked token to fail" unless revoked_run["reason"] == "token_revoked"

        {
          "ok" => blockers.empty?,
          "assessment" => "downloads_move_dry_run",
          "phase" => 61,
          "generated_at" => Time.now.iso8601,
          "root" => @root,
          "status" => blockers.empty? ? "ready" : "blocked",
          "dry_run" => dry_run,
          "blockers" => blockers,
          "warnings" => [
            "Phase 61 performs no file movement.",
            "Dry-run validates a scope-bound approval token.",
            "Dry-run does not consume the token.",
            "Real execution remains disabled."
          ],
          "verification" => {
            "approval_required" => !token_id.to_s.empty?,
            "dry_run_succeeds" => dry_run["ok"] == true,
            "reports_would_move_count" => dry_run.key?("would_move_count"),
            "reports_would_move_bytes" => dry_run.key?("would_move_bytes"),
            "mutation_none" => dry_run["mutation"] == "none",
            "token_not_consumed" => token_after && token_after["status"] == "pending",
            "revoked_token_blocked" => revoked_run["reason"] == "token_revoked",
            "assessment_uses_tempdir" => true
          }
        }
      end
    end

    def render(report)
      lines = []
      lines << "Soul Downloads Move Dry-Run Assessment"
      lines << "Generated: #{report['generated_at']}"
      lines << "Status: #{report['status']}"
      lines << ""
      lines << "Dry-run"
      lines << "- would_move_count: #{report.dig('dry_run', 'would_move_count') || 0}"
      lines << "- would_move_bytes: #{report.dig('dry_run', 'would_move_bytes') || 0}"
      lines << "- mutation: #{report.dig('dry_run', 'mutation')}"
      lines << "- token_consumed: #{report.dig('dry_run', 'token_consumed')}"
      lines << ""
      lines << "Blockers"
      report.fetch("blockers").empty? ? lines << "- None" : report.fetch("blockers").each { |b| lines << "- #{b}" }
      lines.join("\n")
    end
  end
end
