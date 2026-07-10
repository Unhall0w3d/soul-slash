# frozen_string_literal: true

require "json"
require "time"

module SoulCore
  class DownloadsCleanupApprovalDesignAssessor
    REQUIRED_STAGES = [
      "preview",
      "approval_token",
      "execution",
      "post_execution_report"
    ].freeze

    REQUIRED_SAFETY_RULES = [
      "preview_before_mutation",
      "explicit_owner_confirmation",
      "single_use_token",
      "token_scope_binding",
      "trash_not_delete",
      "filenames_not_printed_by_default",
      "execution_history_recorded",
      "dry_run_available"
    ].freeze

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      design_path = File.join(@root, "docs/DOWNLOADS_CLEANUP_APPROVAL_DESIGN.md")
      phase_path = File.join(@root, "docs/maintenance/PHASE58_DOWNLOADS_CLEANUP_APPROVAL_DESIGN.md")
      design = File.exist?(design_path) ? File.read(design_path) : ""
      phase = File.exist?(phase_path) ? File.read(phase_path) : ""

      blockers = []
      blockers << "Missing downloads cleanup approval design document" unless File.exist?(design_path)
      blockers << "Missing phase 58 maintenance document" unless File.exist?(phase_path)

      REQUIRED_STAGES.each do |stage|
        blockers << "Design missing required stage: #{stage}" unless design.include?(stage)
      end

      REQUIRED_SAFETY_RULES.each do |rule|
        blockers << "Design missing required safety rule: #{rule}" unless design.include?(rule)
      end

      blockers << "Design must explicitly keep downloads.move_to_trash blocked" unless design.include?("downloads.move_to_trash remains blocked")
      blockers << "Phase document must identify Phase 58" unless phase.include?("Phase 58")
      blockers << "Phase document must identify this as design-only" unless phase.include?("design-only")

      {
        "ok" => blockers.empty?,
        "assessment" => "downloads_cleanup_approval_design",
        "phase" => 58,
        "generated_at" => Time.now.iso8601,
        "root" => @root,
        "status" => blockers.empty? ? "ready" : "blocked",
        "required_stages" => REQUIRED_STAGES,
        "required_safety_rules" => REQUIRED_SAFETY_RULES,
        "blockers" => blockers,
        "warnings" => [
          "Phase 58 is design-only.",
          "No mutation adapter is enabled in this phase.",
          "downloads.move_to_trash remains approval-required and blocked."
        ],
        "verification" => {
          "design_document_present" => File.exist?(design_path),
          "phase_document_present" => File.exist?(phase_path),
          "all_required_stages_documented" => REQUIRED_STAGES.all? { |stage| design.include?(stage) },
          "all_required_safety_rules_documented" => REQUIRED_SAFETY_RULES.all? { |rule| design.include?(rule) },
          "move_to_trash_remains_blocked" => design.include?("downloads.move_to_trash remains blocked"),
          "design_only" => phase.include?("design-only")
        }
      }
    end

    def render(report)
      lines = []
      lines << "Soul Downloads Cleanup Approval Design Assessment"
      lines << "Generated: #{report['generated_at']}"
      lines << "Status: #{report['status']}"
      lines << ""
      lines << "Required stages"
      report.fetch("required_stages").each { |stage| lines << "- #{stage}" }
      lines << ""
      lines << "Required safety rules"
      report.fetch("required_safety_rules").each { |rule| lines << "- #{rule}" }
      lines << ""
      lines << "Warnings"
      report.fetch("warnings").each { |warning| lines << "- #{warning}" }
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
