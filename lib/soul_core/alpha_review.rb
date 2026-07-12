
# frozen_string_literal: true

require "json"
require "open3"
require "time"

module SoulCore
  class AlphaReview
    REQUIRED_ALPHA_FILES = [
      "README.md",
      "implementation_plan.md",
      "skill.rb",
      "verify-alpha.rb",
      "test_cases.json",
      "behavior_scaffold.json",
      "promotion_checklist.md",
      "alpha_manifest.json"
    ].freeze

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def review(proposal_path:)
      proposal_dir = normalize_proposal_path(proposal_path)
      alpha_dir = File.join(proposal_dir, "alpha")

      return error("proposal folder not found", proposal_dir) unless Dir.exist?(proposal_dir)
      return error("alpha folder not found", proposal_dir) unless Dir.exist?(alpha_dir)

      files = file_status(alpha_dir)
      manifest = read_json(File.join(alpha_dir, "alpha_manifest.json"))
      behavior = read_json(File.join(alpha_dir, "behavior_scaffold.json"))
      tests = read_json(File.join(alpha_dir, "test_cases.json"))
      verifier = run_alpha_verifier(alpha_dir)

      blockers = []
      warnings = []

      files.fetch("missing").each { |file| blockers << "Missing alpha file: #{file}" }
      blockers << "alpha_manifest.json is not valid JSON" if File.exist?(File.join(alpha_dir, "alpha_manifest.json")) && manifest.nil?
      blockers << "behavior_scaffold.json is not valid JSON" if File.exist?(File.join(alpha_dir, "behavior_scaffold.json")) && behavior.nil?
      blockers << "test_cases.json is not valid JSON" if File.exist?(File.join(alpha_dir, "test_cases.json")) && tests.nil?
      blockers << "alpha verifier failed" unless verifier.fetch("passed")

      if manifest
        blockers << "Manifest does not require human review" unless manifest["requires_human_review"] == true
        blockers << "Manifest claims alpha is registered" unless manifest["registered"] == false
        blockers << "Manifest claims production was modified" unless manifest["production_modified"] == false
      end

      if behavior
        warnings << "Behavior scaffold has no risks listed" if Array(behavior["risks"]).empty?
        warnings << "Behavior scaffold has no behavior steps listed" if Array(behavior["behavior_steps"]).empty?
        warnings << "Behavior scaffold has no planned artifacts listed" if Array(behavior["planned_artifacts"]).empty?
      end

      {
        "ok" => blockers.empty?,
        "assessment" => "alpha_review",
        "generated_at" => Time.now.iso8601,
        "proposal_path" => proposal_dir,
        "alpha_path" => alpha_dir,
        "readiness" => readiness(blockers: blockers, warnings: warnings, verifier: verifier),
        "files" => files,
        "manifest" => manifest_summary(manifest),
        "behavior" => behavior_summary(behavior),
        "test_cases" => test_summary(tests),
        "verifier" => verifier,
        "blockers" => blockers,
        "warnings" => warnings,
        "promotion" => {
          "allowed" => false,
          "reason" => "Phase 18 is review-only. Promotion is intentionally not implemented.",
          "requires_human_approval" => true
        },
        "verification" => {
          "review_only" => true,
          "no_files_modified" => true,
          "no_registry_modified" => true,
          "no_promotion_performed" => true
        }
      }
    end

    def render(report)
      return "Alpha review failed: #{report['error']}\nPath: #{report['proposal_path']}" unless report["assessment"] == "alpha_review"

      lines = []
      lines << "Soul Alpha Review"
      lines << "Generated: #{report['generated_at']}"
      lines << "Alpha path: #{report['alpha_path']}"
      lines << "Readiness: #{report['readiness']}"
      lines << ""
      lines << "Files"
      lines << "- Present: #{report.dig('files', 'present').length}"
      lines << "- Missing: #{report.dig('files', 'missing').length}"
      report.dig("files", "missing").each { |file| lines << "  - #{file}" } if report.dig("files", "missing").any?
      lines << ""
      lines << "Behavior"
      lines << "- Planned artifacts: #{report.dig('behavior', 'planned_artifacts_count')}"
      lines << "- Behavior steps: #{report.dig('behavior', 'behavior_steps_count')}"
      lines << "- Risks: #{report.dig('behavior', 'risks_count')}"
      lines << ""
      lines << "Verifier"
      lines << "- Passed: #{report.dig('verifier', 'passed')}"
      lines << "- Exit status: #{report.dig('verifier', 'exit_status')}"
      lines << ""
      lines << "Blockers"
      report.fetch("blockers").empty? ? lines << "- None" : report.fetch("blockers").each { |item| lines << "- #{item}" }
      lines << ""
      lines << "Warnings"
      report.fetch("warnings").empty? ? lines << "- None" : report.fetch("warnings").each { |item| lines << "- #{item}" }
      lines << ""
      lines << "Promotion"
      lines << "- Allowed: #{report.dig('promotion', 'allowed')}"
      lines << "- Reason: #{report.dig('promotion', 'reason')}"
      lines.join("\n")
    end

    private

    def normalize_proposal_path(path)
      raw = path.to_s
      File.expand_path(raw.start_with?("/") ? raw : File.join(@root, raw))
    end

    def error(message, path)
      {
        "ok" => false,
        "assessment" => "alpha_review",
        "generated_at" => Time.now.iso8601,
        "proposal_path" => path,
        "error" => message,
        "promotion" => {"allowed" => false}
      }
    end

    def file_status(alpha_dir)
      present = []
      missing = []
      REQUIRED_ALPHA_FILES.each do |file|
        File.exist?(File.join(alpha_dir, file)) ? present << file : missing << file
      end
      {"required" => REQUIRED_ALPHA_FILES, "present" => present, "missing" => missing}
    end

    def read_json(path)
      return nil unless File.exist?(path)
      JSON.parse(File.read(path))
    rescue JSON::ParserError
      nil
    end

    def run_alpha_verifier(alpha_dir)
      verifier_path = File.join(alpha_dir, "verify-alpha.rb")
      return {"passed" => false, "exit_status" => nil, "stdout" => [], "stderr" => ["verify-alpha.rb missing"]} unless File.exist?(verifier_path)

      stdout, stderr, status = Open3.capture3("ruby", verifier_path, chdir: alpha_dir)
      {
        "passed" => status.success?,
        "exit_status" => status.exitstatus,
        "stdout" => stdout.lines.map(&:chomp),
        "stderr" => stderr.lines.map(&:chomp)
      }
    rescue StandardError => e
      {"passed" => false, "exit_status" => nil, "stdout" => [], "stderr" => ["#{e.class}: #{e.message}"]}
    end

    def readiness(blockers:, warnings:, verifier:)
      return "blocked" unless blockers.empty?
      return "review_ready" if verifier.fetch("passed") && warnings.empty?
      "review_ready_with_warnings"
    end

    def manifest_summary(manifest)
      return {"valid" => false} unless manifest
      {
        "valid" => true,
        "status" => manifest["status"],
        "capability" => manifest["capability"],
        "registered" => manifest["registered"],
        "production_modified" => manifest["production_modified"],
        "requires_human_review" => manifest["requires_human_review"],
        "implementation_plan_generated" => manifest["implementation_plan_generated"],
        "behavior_scaffold_generated" => manifest["behavior_scaffold_generated"]
      }
    end

    def behavior_summary(behavior)
      return {"valid" => false, "planned_artifacts_count" => 0, "behavior_steps_count" => 0, "risks_count" => 0} unless behavior
      {
        "valid" => true,
        "planned_artifacts_count" => Array(behavior["planned_artifacts"]).length,
        "behavior_steps_count" => Array(behavior["behavior_steps"]).length,
        "risks_count" => Array(behavior["risks"]).length,
        "planned_artifacts" => Array(behavior["planned_artifacts"]),
        "behavior_steps" => Array(behavior["behavior_steps"]),
        "risks" => Array(behavior["risks"])
      }
    end

    def test_summary(tests)
      return {"valid" => false, "case_count" => 0} unless tests
      {"valid" => true, "case_count" => Array(tests["cases"]).length}
    end
  end
end
