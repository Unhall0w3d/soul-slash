# frozen_string_literal: true

require "json"
require "time"
require "tmpdir"
require_relative "approval_token_store"

module SoulCore
  class ApprovalTokenStoreAssessor
    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      Dir.mktmpdir("soul-approval-token-phase59-") do |dir|
        now = Time.utc(2026, 7, 10, 12, 0, 0)
        clock_value = now
        clock = -> { clock_value }

        store = ApprovalTokenStore.new(
          root: @root,
          path: File.join(dir, "approval_tokens.json"),
          clock: clock
        )

        scope = {
          "target_path" => "~/Downloads",
          "candidate_rule" => "files older than 30 days or larger than 100 MiB",
          "candidate_count" => 3,
          "candidate_bytes" => 4096,
          "preview_timestamp" => now.iso8601
        }

        token = store.issue(
          skill_id: "downloads.move_to_trash",
          scope: scope,
          ttl_seconds: 300
        )

        valid = store.validate(
          token_id: token["token_id"],
          skill_id: "downloads.move_to_trash",
          scope: scope
        )

        mismatch = store.validate(
          token_id: token["token_id"],
          skill_id: "downloads.move_to_trash",
          scope: scope.merge("candidate_count" => 4)
        )

        used = store.mark_used(token["token_id"])
        used_again = store.validate(
          token_id: token["token_id"],
          skill_id: "downloads.move_to_trash",
          scope: scope
        )

        second = store.issue(
          skill_id: "downloads.move_to_trash",
          scope: scope,
          ttl_seconds: 60
        )
        revoked = store.revoke(second["token_id"])
        revoked_validation = store.validate(
          token_id: second["token_id"],
          skill_id: "downloads.move_to_trash",
          scope: scope
        )

        third = store.issue(
          skill_id: "downloads.move_to_trash",
          scope: scope,
          ttl_seconds: 1
        )
        clock_value = now + 2
        expired = store.validate(
          token_id: third["token_id"],
          skill_id: "downloads.move_to_trash",
          scope: scope
        )

        blockers = []
        blockers << "Expected initial token validation to succeed" unless valid["ok"] == true
        blockers << "Expected scope mismatch to be rejected" unless mismatch["reason"] == "token_scope_mismatch"
        blockers << "Expected token to become used" unless used["status"] == "used"
        blockers << "Expected reused token to be rejected" unless used_again["reason"] == "token_already_used"
        blockers << "Expected token revoke to succeed" unless revoked["status"] == "revoked"
        blockers << "Expected revoked token to be rejected" unless revoked_validation["reason"] == "token_revoked"
        blockers << "Expected expired token to be rejected" unless expired["reason"] == "token_expired"
        blockers << "Expected runtime-only default path" unless ApprovalTokenStore::DEFAULT_PATH.start_with?(File.join("Soul", "runtime"))

        {
          "ok" => blockers.empty?,
          "assessment" => "approval_token_store",
          "phase" => 59,
          "generated_at" => Time.now.iso8601,
          "root" => @root,
          "status" => blockers.empty? ? "ready" : "blocked",
          "blockers" => blockers,
          "warnings" => [
            "Phase 59 scaffolds runtime-only approval tokens.",
            "No chat approval flow exists yet.",
            "No mutation adapter is enabled.",
            "downloads.move_to_trash remains blocked."
          ],
          "verification" => {
            "valid_token_accepted" => valid["ok"] == true,
            "scope_binding_enforced" => mismatch["reason"] == "token_scope_mismatch",
            "single_use_enforced" => used_again["reason"] == "token_already_used",
            "revocation_enforced" => revoked_validation["reason"] == "token_revoked",
            "expiry_enforced" => expired["reason"] == "token_expired",
            "runtime_only_path" => ApprovalTokenStore::DEFAULT_PATH.start_with?(File.join("Soul", "runtime")),
            "assessment_uses_tempdir" => true,
            "mutation_enabled" => false
          }
        }
      end
    end

    def render(report)
      lines = []
      lines << "Soul Approval Token Store Assessment"
      lines << "Generated: #{report['generated_at']}"
      lines << "Status: #{report['status']}"
      lines << ""
      lines << "Verification"
      report.fetch("verification").each do |key, value|
        lines << "- #{key}: #{value}"
      end
      lines << ""
      lines << "Warnings"
      report.fetch("warnings").each do |warning|
        lines << "- #{warning}"
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
  end
end
