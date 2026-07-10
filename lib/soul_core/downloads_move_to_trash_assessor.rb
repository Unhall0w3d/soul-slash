# frozen_string_literal: true

require "fileutils"
require "json"
require "time"
require "tmpdir"
require_relative "approval_token_store"
require_relative "chat_execution_history"
require_relative "downloads_move_to_trash_executor"

module SoulCore
  class DownloadsMoveToTrashAssessor
    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      Dir.mktmpdir("soul-trash-phase62-") do |dir|
        downloads = File.join(dir, "Downloads")
        trash = File.join(dir, "Trash")
        history_path = File.join(dir, "history.jsonl")
        token_path = File.join(dir, "approval_tokens.json")
        FileUtils.mkdir_p(downloads)

        old_file = File.join(downloads, "old-test.txt")
        recent_file = File.join(downloads, "recent-test.txt")
        File.write(old_file, "old")
        File.write(recent_file, "recent")
        old_time = Time.now - (40 * 86_400)
        File.utime(old_time, old_time, old_file)

        store = ApprovalTokenStore.new(root: @root, path: token_path)
        history = ChatExecutionHistory.new(root: @root, path: history_path)
        executor = DownloadsMoveToTrashExecutor.new(
          root: @root,
          store: store,
          history: history,
          target_dir: downloads,
          trash_root: trash
        )

        preview_scope = executor.preview_scope.merge("preview_timestamp" => Time.now.iso8601)
        token = store.issue(
          skill_id: "downloads.move_to_trash",
          scope: preview_scope,
          ttl_seconds: 300
        )

        unconfirmed = executor.execute(token_id: token["token_id"], confirm: false)
        executed = executor.execute(token_id: token["token_id"], confirm: true)
        token_after = store.find(token["token_id"])
        history_entries = history.entries

        blockers = []
        blockers << "Expected unconfirmed execution to be blocked" unless unconfirmed.blocked_by.include?("explicit_confirmation_required")
        blockers << "Expected approved trash move to execute" unless executed.executed && executed.status == "executed"
        blockers << "Expected old candidate removed from Downloads" if File.exist?(old_file)
        blockers << "Expected recent file preserved" unless File.exist?(recent_file)
        blockers << "Expected one trashed file" unless Dir.glob(File.join(trash, "files", "*")).length == 1
        blockers << "Expected one trashinfo file" unless Dir.glob(File.join(trash, "info", "*.trashinfo")).length == 1
        blockers << "Expected token consumed" unless token_after && token_after["status"] == "used"
        blockers << "Expected execution history records" unless history_entries.length >= 2

        {
          "ok" => blockers.empty?,
          "assessment" => "downloads_move_to_trash",
          "phase" => 62,
          "generated_at" => Time.now.iso8601,
          "root" => @root,
          "status" => blockers.empty? ? "ready" : "blocked",
          "blockers" => blockers,
          "warnings" => [
            "Assessment uses temporary Downloads and Trash directories.",
            "No real user files are touched by assessment.",
            "Production execution requires a scope-bound token and explicit confirm."
          ],
          "verification" => {
            "explicit_confirmation_required" => unconfirmed.blocked_by.include?("explicit_confirmation_required"),
            "approved_execution_succeeds" => executed.executed && executed.status == "executed",
            "candidate_moved_to_trash" => !File.exist?(old_file),
            "non_candidate_preserved" => File.exist?(recent_file),
            "trashinfo_created" => Dir.glob(File.join(trash, "info", "*.trashinfo")).length == 1,
            "token_consumed" => token_after && token_after["status"] == "used",
            "history_recorded" => history_entries.length >= 2,
            "assessment_uses_tempdir" => true
          }
        }
      end
    end

    def render(report)
      lines = []
      lines << "Soul Downloads Move-to-Trash Assessment"
      lines << "Generated: #{report['generated_at']}"
      lines << "Status: #{report['status']}"
      lines << ""
      lines << "Verification"
      report.fetch("verification").each { |key, value| lines << "- #{key}: #{value}" }
      lines << ""
      lines << "Blockers"
      report.fetch("blockers").empty? ? lines << "- None" : report.fetch("blockers").each { |blocker| lines << "- #{blocker}" }
      lines.join("\n")
    end
  end
end
