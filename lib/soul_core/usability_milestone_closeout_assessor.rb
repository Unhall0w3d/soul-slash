# frozen_string_literal: true

require "json"
require "open3"
require "time"

module SoulCore
  class UsabilityMilestoneCloseoutAssessor
    REQUIRED_ASSESSMENTS = [
      "execution-adapter-registry",
      "read-only-skill-gate",
      "downloads-cleanup-approval-design",
      "approval-token-store",
      "approval-token-chat-controls",
      "downloads-move-dry-run",
      "downloads-move-to-trash",
      "repo-curation"
    ].freeze

    REQUIRED_FILES = [
      "docs/USABILITY_RETARGET_BACKLOG.md",
      "docs/USABILITY_MILESTONE_CLOSEOUT.md",
      "docs/USABILITY_MANUAL_ACCEPTANCE.md",
      "docs/DOWNLOADS_CLEANUP_APPROVAL_DESIGN.md",
      "docs/APPROVAL_TOKEN_STORE.md",
      "docs/APPROVAL_TOKEN_CHAT_CONTROLS.md",
      "docs/DOWNLOADS_MOVE_DRY_RUN.md",
      "docs/DOWNLOADS_MOVE_TO_TRASH.md",
      "docs/maintenance/PHASE63_USABILITY_MILESTONE_CLOSEOUT.md"
    ].freeze

    REQUIRED_VERIFIERS = [
      "scripts/verify-downloads-cleanup-approval-design-phase58.rb",
      "scripts/verify-approval-token-store-phase59.rb",
      "scripts/verify-approval-token-chat-controls-phase60.rb",
      "scripts/verify-downloads-move-dry-run-phase61.rb",
      "scripts/verify-downloads-move-to-trash-phase62.rb",
      "scripts/verify-usability-milestone-phase63.rb"
    ].freeze

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      assessment_results = REQUIRED_ASSESSMENTS.map { |name| run_assessment(name) }
      missing_files = REQUIRED_FILES.reject { |path| File.exist?(File.join(@root, path)) }
      missing_verifiers = REQUIRED_VERIFIERS.reject { |path| File.exist?(File.join(@root, path)) }

      backlog_path = File.join(@root, "docs/USABILITY_RETARGET_BACKLOG.md")
      backlog = File.exist?(backlog_path) ? File.read(backlog_path) : ""

      ignore_ok = system(
        "git",
        "check-ignore",
        "Soul/runtime/approvals/approval_tokens.json",
        chdir: @root,
        out: File::NULL,
        err: File::NULL
      )

      blockers = []
      failed_assessments = assessment_results.reject { |result| result["ok"] == true }
      blockers << "One or more required assessments failed" unless failed_assessments.empty?
      blockers << "Missing required closeout files: #{missing_files.join(', ')}" unless missing_files.empty?
      blockers << "Missing required verifier scripts: #{missing_verifiers.join(', ')}" unless missing_verifiers.empty?
      blockers << "Runtime approval path is not gitignored" unless ignore_ok
      blockers << "Backlog is not marked closed" unless backlog.include?("Status: closed")
      blockers << "Backlog does not identify Phase 63 as the stopping point" unless backlog.include?("Phase 63")

      {
        "ok" => blockers.empty?,
        "assessment" => "usability_milestone_closeout",
        "phase" => 63,
        "generated_at" => Time.now.iso8601,
        "root" => @root,
        "status" => blockers.empty? ? "closed" : "blocked",
        "milestone" => "safe_local_action",
        "assessment_results" => assessment_results,
        "missing_files" => missing_files,
        "missing_verifiers" => missing_verifiers,
        "runtime_approval_path_ignored" => ignore_ok,
        "blockers" => blockers,
        "verification" => {
          "all_required_assessments_pass" => failed_assessments.empty?,
          "all_required_files_present" => missing_files.empty?,
          "all_required_verifiers_present" => missing_verifiers.empty?,
          "runtime_approval_path_ignored" => ignore_ok,
          "backlog_closed" => backlog.include?("Status: closed"),
          "clear_stopping_point_reached" => backlog.include?("Phase 63")
        }
      }
    end

    def render(report)
      lines = []
      lines << "Soul Usability Milestone Closeout Assessment"
      lines << "Generated: #{report['generated_at']}"
      lines << "Milestone: #{report['milestone']}"
      lines << "Status: #{report['status']}"
      lines << ""
      lines << "Assessment results"
      report.fetch("assessment_results").each do |result|
        lines << "- #{result['name']}: #{result['ok'] ? 'ok' : 'failed'}"
      end
      lines << ""
      lines << "Verification"
      report.fetch("verification").each do |key, value|
        lines << "- #{key}: #{value}"
      end
      lines << ""
      lines << "Blockers"
      report.fetch("blockers").empty? ? lines << "- None" : report.fetch("blockers").each { |blocker| lines << "- #{blocker}" }
      lines.join("\n")
    end

    private

    def run_assessment(name)
      stdout, stderr, status = Open3.capture3(
        "ruby",
        "bin/soul",
        "assess",
        name,
        "--json",
        chdir: @root
      )

      parsed = JSON.parse(stdout)
      {
        "name" => name,
        "ok" => status.success? && parsed["ok"] == true,
        "status" => parsed["status"],
        "phase" => parsed["phase"],
        "stderr" => stderr
      }
    rescue JSON::ParserError => error
      {
        "name" => name,
        "ok" => false,
        "status" => "invalid_json",
        "error" => error.message,
        "stdout" => stdout.to_s,
        "stderr" => stderr.to_s
      }
    end
  end
end
