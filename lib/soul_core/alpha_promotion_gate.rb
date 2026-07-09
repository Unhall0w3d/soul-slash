
# frozen_string_literal: true

require "json"
require "time"

require_relative "alpha_review"

module SoulCore
  class AlphaPromotionGate
    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess(proposal_path:)
      review = AlphaReview.new(root: @root).review(proposal_path: proposal_path)
      blockers = []
      warnings = []

      blockers << "Alpha review is not clean: #{review['readiness'] || 'unknown'}" unless review["ok"] == true
      blockers.concat(Array(review["blockers"]).map { |item| "Review blocker: #{item}" })

      manifest_path = File.join(review["alpha_path"].to_s, "alpha_manifest.json")
      skill_path = File.join(review["alpha_path"].to_s, "skill.rb")
      checklist_path = File.join(review["alpha_path"].to_s, "promotion_checklist.md")

      manifest = read_json(manifest_path)
      checklist = File.exist?(checklist_path) ? File.read(checklist_path) : ""

      blockers << "Manifest missing" unless manifest
      if manifest
        blockers << "Manifest does not require human review" unless manifest["requires_human_review"] == true
        blockers << "Manifest indicates alpha is registered" unless manifest["registered"] == false
        blockers << "Manifest indicates production was modified" unless manifest["production_modified"] == false
      end

      if File.exist?(skill_path)
        skill = File.read(skill_path)
        blockers << "Alpha behavior is scaffold-only" if skill.include?("alpha_behavior_scaffold") || skill.include?("Alpha behavior scaffold only")
        blockers << "Alpha placeholder behavior still present" if skill.include?("alpha_placeholder")
      else
        blockers << "skill.rb missing"
      end

      checklist_open_items = checklist.lines.grep(/^- \[ \]/).map { |line| line.sub(/^- \[ \]\s*/, "").strip }
      blockers << "Promotion checklist has open items" if checklist_open_items.any?

      warnings << "Promotion checklist is missing" if checklist.empty?
      warnings << "No rollback item found in checklist" unless checklist.downcase.include?("rollback")

      {
        "ok" => false,
        "assessment" => "alpha_promotion_gate",
        "generated_at" => Time.now.iso8601,
        "proposal_path" => review["proposal_path"],
        "alpha_path" => review["alpha_path"],
        "gate_status" => blockers.empty? ? "candidate_ready" : "blocked",
        "promotion_allowed" => false,
        "reason" => "Phase 19 is a promotion gate assessment only. Promotion is intentionally not implemented.",
        "review_readiness" => review["readiness"],
        "review_ok" => review["ok"],
        "blockers" => blockers.uniq,
        "warnings" => warnings.uniq,
        "checklist_open_items" => checklist_open_items,
        "required_next_actions" => next_actions(blockers, checklist_open_items),
        "review" => review,
        "verification" => {
          "gate_only" => true,
          "no_files_modified" => true,
          "no_registry_modified" => true,
          "no_promotion_performed" => true,
          "promotion_allowed" => false
        }
      }
    end

    def render(report)
      lines = []
      lines << "Soul Alpha Promotion Gate"
      lines << "Generated: #{report['generated_at']}"
      lines << "Alpha path: #{report['alpha_path']}"
      lines << "Gate status: #{report['gate_status']}"
      lines << "Promotion allowed: #{report['promotion_allowed']}"
      lines << "Review readiness: #{report['review_readiness']}"
      lines << ""
      lines << "Blockers"
      report.fetch("blockers").empty? ? lines << "- None" : report.fetch("blockers").each { |item| lines << "- #{item}" }
      lines << ""
      lines << "Warnings"
      report.fetch("warnings").empty? ? lines << "- None" : report.fetch("warnings").each { |item| lines << "- #{item}" }
      lines << ""
      lines << "Open checklist items"
      report.fetch("checklist_open_items").empty? ? lines << "- None" : report.fetch("checklist_open_items").each { |item| lines << "- #{item}" }
      lines << ""
      lines << "Required next actions"
      report.fetch("required_next_actions").each { |item| lines << "- #{item}" }
      lines << ""
      lines << "Reason"
      lines << report["reason"]
      lines.join("\n")
    end

    private

    def read_json(path)
      return nil unless File.exist?(path)
      JSON.parse(File.read(path))
    rescue JSON::ParserError
      nil
    end

    def next_actions(blockers, checklist_open_items)
      actions = []
      actions << "Implement real alpha behavior before promotion can be considered." if blockers.any? { |item| item.include?("scaffold") || item.include?("placeholder") }
      actions << "Complete and review promotion checklist items." if checklist_open_items.any?
      actions << "Resolve alpha review blockers." if blockers.any? { |item| item.start_with?("Review blocker") }
      actions << "Keep promotion manual until an explicit promotion workflow is implemented."
      actions.uniq
    end
  end
end
