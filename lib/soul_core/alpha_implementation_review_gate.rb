
# frozen_string_literal: true

require "json"
require "time"
require "pathname"

module SoulCore
  class AlphaImplementationReviewGate
    REQUIRED_TASK_PACK_FILES = [
      "implementation_task_pack.json",
      "implementation_task_pack.md",
      "codex_handoff_contract.json",
      "human_review_checklist.md",
      "rollback_plan.md"
    ].freeze

    REQUIRED_PACK_KEYS = [
      "task",
      "codex_handoff_contract",
      "allowed_files",
      "forbidden_files",
      "acceptance_criteria",
      "verifier_expectations",
      "security_boundaries",
      "human_review_checklist",
      "rollback_plan",
      "boundaries"
    ].freeze

    REQUIRED_CONTRACT_KEYS = [
      "task",
      "repo_context",
      "allowed_files",
      "forbidden_files",
      "acceptance_criteria",
      "verifier_expectations",
      "security_boundaries",
      "output_format",
      "rollback_notes"
    ].freeze

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def review(proposal_path:)
      absolute_proposal_path = File.expand_path(proposal_path, @root)
      alpha_path = File.join(absolute_proposal_path, "alpha")

      blockers = []
      warnings = []

      blockers << "Proposal path does not exist: #{proposal_path}" unless Dir.exist?(absolute_proposal_path)
      blockers << "Alpha folder does not exist for proposal: #{proposal_path}" unless Dir.exist?(alpha_path)

      task_pack_path = File.join(alpha_path, "implementation_task_pack.json")
      contract_path = File.join(alpha_path, "codex_handoff_contract.json")

      missing_files = REQUIRED_TASK_PACK_FILES.reject { |file| File.exist?(File.join(alpha_path, file)) }
      blockers << "Missing implementation task-pack file(s): #{missing_files.join(', ')}" unless missing_files.empty?

      pack = read_json(task_pack_path)
      contract = read_json(contract_path)

      blockers << "implementation_task_pack.json is missing or invalid JSON." if File.exist?(task_pack_path) && pack.nil?
      blockers << "codex_handoff_contract.json is missing or invalid JSON." if File.exist?(contract_path) && contract.nil?

      if pack
        missing_pack_keys = REQUIRED_PACK_KEYS.reject { |key| pack.key?(key) }
        blockers << "Task pack missing required key(s): #{missing_pack_keys.join(', ')}" unless missing_pack_keys.empty?

        warnings << "Task pack has no acceptance criteria." if Array(pack["acceptance_criteria"]).empty?
        warnings << "Task pack has no verifier expectations." if Array(pack["verifier_expectations"]).empty?
        warnings << "Task pack has no human review checklist." if Array(pack["human_review_checklist"]).empty?
        warnings << "Task pack has no rollback plan." if Array(pack["rollback_plan"]).empty?

        forbidden_boundary_missing = !Array(pack["boundaries"]).include?("Do not invoke Codex.")
        blockers << "Task pack does not explicitly block Codex invocation." if forbidden_boundary_missing

        production_write_boundary_missing = !Array(pack["boundaries"]).include?("Do not write production implementation.")
        blockers << "Task pack does not explicitly block production implementation writes." if production_write_boundary_missing
      end

      if contract
        missing_contract_keys = REQUIRED_CONTRACT_KEYS.reject { |key| contract.key?(key) }
        blockers << "Codex handoff contract missing required key(s): #{missing_contract_keys.join(', ')}" unless missing_contract_keys.empty?

        warnings << "Codex handoff contract has no allowed files." if Array(contract["allowed_files"]).empty?
        warnings << "Codex handoff contract has no forbidden files." if Array(contract["forbidden_files"]).empty?
        warnings << "Codex handoff contract has no security boundaries." if Array(contract["security_boundaries"]).empty?

        model = contract.dig("task", "model_recommendation")
        warnings << "Codex handoff contract does not recommend gpt-5.5 medium." unless model == "gpt-5.5 medium"
      end

      checklist_path = File.join(alpha_path, "human_review_checklist.md")
      rollback_path = File.join(alpha_path, "rollback_plan.md")
      pack_md_path = File.join(alpha_path, "implementation_task_pack.md")

      checklist = File.exist?(checklist_path) ? File.read(checklist_path) : ""
      rollback = File.exist?(rollback_path) ? File.read(rollback_path) : ""
      pack_md = File.exist?(pack_md_path) ? File.read(pack_md_path) : ""

      warnings << "Human review checklist has no checkbox items." if checklist && !checklist.include?("- [ ]")
      warnings << "Rollback plan does not mention promotion." if rollback && !rollback.downcase.include?("promot")
      warnings << "Implementation task pack markdown does not mention boundaries." if pack_md && !pack_md.include?("## Boundaries")

      readiness = blockers.empty? ? (warnings.empty? ? "review_ready" : "review_ready_with_warnings") : "blocked"

      {
        "ok" => blockers.empty?,
        "assessment" => "alpha_implementation_review_gate",
        "generated_at" => Time.now.iso8601,
        "root" => @root,
        "proposal_path" => Dir.exist?(absolute_proposal_path) ? relative_path(absolute_proposal_path) : proposal_path,
        "alpha_path" => Dir.exist?(alpha_path) ? relative_path(alpha_path) : nil,
        "readiness" => readiness,
        "blockers" => blockers,
        "warnings" => warnings,
        "files" => {
          "required" => REQUIRED_TASK_PACK_FILES,
          "missing" => missing_files,
          "task_pack_path" => File.exist?(task_pack_path) ? relative_path(task_pack_path) : nil,
          "codex_handoff_contract_path" => File.exist?(contract_path) ? relative_path(contract_path) : nil,
          "human_review_checklist_path" => File.exist?(checklist_path) ? relative_path(checklist_path) : nil,
          "rollback_plan_path" => File.exist?(rollback_path) ? relative_path(rollback_path) : nil
        },
        "task_pack" => {
          "valid_json" => !pack.nil?,
          "required_keys" => REQUIRED_PACK_KEYS,
          "present_keys" => pack ? REQUIRED_PACK_KEYS.select { |key| pack.key?(key) } : [],
          "missing_keys" => pack ? REQUIRED_PACK_KEYS.reject { |key| pack.key?(key) } : REQUIRED_PACK_KEYS
        },
        "codex_handoff_contract" => {
          "valid_json" => !contract.nil?,
          "required_keys" => REQUIRED_CONTRACT_KEYS,
          "present_keys" => contract ? REQUIRED_CONTRACT_KEYS.select { |key| contract.key?(key) } : [],
          "missing_keys" => contract ? REQUIRED_CONTRACT_KEYS.reject { |key| contract.key?(key) } : REQUIRED_CONTRACT_KEYS
        },
        "promotion_allowed" => false,
        "implementation_allowed" => false,
        "codex_invoked" => false,
        "verification" => {
          "review_only" => true,
          "proposal_local_only" => true,
          "no_codex_invoked" => true,
          "no_patches_applied" => true,
          "no_production_files_modified" => true,
          "no_runtime_configuration_changed" => true,
          "no_secrets_read" => true
        }
      }
    end

    def render(report)
      lines = []
      lines << "Soul Alpha Implementation Review Gate"
      lines << "Generated: #{report['generated_at']}"
      lines << "Proposal: #{report['proposal_path']}"
      lines << "Readiness: #{report['readiness']}"
      lines << "Promotion allowed: #{report['promotion_allowed']}"
      lines << "Implementation allowed: #{report['implementation_allowed']}"
      lines << ""
      lines << "Blockers"
      append_items(lines, report.fetch("blockers"))
      lines << ""
      lines << "Warnings"
      append_items(lines, report.fetch("warnings"))
      lines << ""
      lines << "Required files"
      report.dig("files", "required").each { |item| lines << "- #{item}" }
      lines << ""
      lines << "Missing files"
      append_items(lines, report.dig("files", "missing"))
      lines << ""
      lines << "Verification"
      report.fetch("verification").each { |key, value| lines << "- #{key}: #{value}" }
      lines.join("\n")
    end

    private

    def read_json(path)
      return nil unless File.exist?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError
      nil
    end

    def relative_path(path)
      Pathname.new(path).relative_path_from(Pathname.new(@root)).to_s
    end

    def append_items(lines, items)
      items = Array(items)
      if items.empty?
        lines << "- None"
      else
        items.each { |item| lines << "- #{item}" }
      end
    end
  end
end
