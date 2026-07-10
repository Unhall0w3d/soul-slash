# frozen_string_literal: true

require "json"
require "time"
require "tmpdir"
require_relative "approval_token_chat_controls"
require_relative "chat_execution_history"
require_relative "read_only_skill_execution_gate"

module SoulCore
  class ApprovalTokenChatControlsAssessor
    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      Dir.mktmpdir("soul-approval-chat-phase60-") do |dir|
        history = ChatExecutionHistory.new(root: @root, path: File.join(dir, "history.jsonl"))
        store = ApprovalTokenStore.new(root: @root, path: File.join(dir, "approval_tokens.json"))
        gate = ReadOnlySkillExecutionGate.new(root: @root, history: history)
        controls = ApprovalTokenChatControls.new(root: @root, gate: gate, store: store)

        approved = controls.approve_downloads_cleanup_preview(ttl_seconds: 300)
        pending_before = controls.pending
        token_id = approved.dig("token", "token_id")
        revoked = controls.revoke(token_id)
        pending_after = controls.pending

        blockers = []
        blockers << "Expected preview approval to issue a token" unless approved["ok"] == true && token_id
        blockers << "Expected one pending token before revoke" unless pending_before["count"] == 1
        blockers << "Expected revoke to succeed" unless revoked["status"] == "revoked"
        blockers << "Expected no pending tokens after revoke" unless pending_after["count"] == 0
        blockers << "Expected preview mutation to remain none" unless approved.dig("preview", "mutation") == "none"
        blockers << "Expected mutation to remain disabled" unless approved["mutation_enabled"] == false

        {
          "ok" => blockers.empty?,
          "assessment" => "approval_token_chat_controls",
          "phase" => 60,
          "generated_at" => Time.now.iso8601,
          "root" => @root,
          "status" => blockers.empty? ? "ready" : "blocked",
          "blockers" => blockers,
          "warnings" => [
            "Phase 60 adds approve/list/revoke chat controls.",
            "No file movement or deletion is enabled.",
            "Tokens authorize a future executor that does not exist yet."
          ],
          "verification" => {
            "approval_issues_token" => approved["ok"] == true && !token_id.to_s.empty?,
            "pending_list_works" => pending_before["count"] == 1,
            "revoke_works" => revoked["status"] == "revoked",
            "revoked_removed_from_pending" => pending_after["count"] == 0,
            "preview_remains_non_mutating" => approved.dig("preview", "mutation") == "none",
            "mutation_enabled" => false,
            "assessment_uses_tempdir" => true
          }
        }
      end
    end

    def render(report)
      lines = []
      lines << "Soul Approval Token Chat Controls Assessment"
      lines << "Generated: #{report['generated_at']}"
      lines << "Status: #{report['status']}"
      lines << ""
      lines << "Verification"
      report.fetch("verification").each { |key, value| lines << "- #{key}: #{value}" }
      lines << ""
      lines << "Warnings"
      report.fetch("warnings").each { |warning| lines << "- #{warning}" }
      lines << ""
      lines << "Blockers"
      report.fetch("blockers").empty? ? lines << "- None" : report.fetch("blockers").each { |blocker| lines << "- #{blocker}" }
      lines.join("\n")
    end
  end
end
