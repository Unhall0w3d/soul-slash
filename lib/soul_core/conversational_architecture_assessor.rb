# frozen_string_literal: true

require "json"
require "time"

module SoulCore
  class ConversationalArchitectureAssessor
    REQUIRED_DOCUMENTS = [
      "docs/CONVERSATIONAL_SOUL_ARCHITECTURE.md",
      "docs/CONVERSATIONAL_SOUL_ACCEPTANCE.md",
      "docs/CONVERSATIONAL_SOUL_ROADMAP.md",
      "docs/maintenance/CONVERSATIONAL_SOUL_PHASE1.md",
      "docs/MILESTONES.md"
    ].freeze

    REQUIRED_ARCHITECTURE_SECTIONS = [
      "## Interaction loop",
      "## Conversation state",
      "## Orchestration decisions",
      "## Skill invocation inside conversation",
      "## Layered memory",
      "## Artifact-aware conversation",
      "## Personality and variation",
      "## Safety boundary",
      "## Interface direction"
    ].freeze

    REQUIRED_ACCEPTANCE_SCENARIOS = [
      "mixed commentary and task",
      "multi-turn continuity",
      "skill invocation and return",
      "artifact instead of chat dumping",
      "project-state continuity",
      "safe tool failure",
      "unrelated-skill avoidance",
      "conversational variation"
    ].freeze

    REQUIRED_ANTI_PATTERNS = [
      "command parser with decorative prose",
      "tool-output dumping machine",
      "canned-quipping persona",
      "unrestricted autonomous agent",
      "a memory system without provenance"
    ].freeze

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      missing_documents = REQUIRED_DOCUMENTS.reject do |path|
        File.exist?(File.join(@root, path))
      end

      architecture = read("docs/CONVERSATIONAL_SOUL_ARCHITECTURE.md")
      acceptance = read("docs/CONVERSATIONAL_SOUL_ACCEPTANCE.md")
      roadmap = read("docs/CONVERSATIONAL_SOUL_ROADMAP.md")
      milestones = read("docs/MILESTONES.md")

      missing_sections = REQUIRED_ARCHITECTURE_SECTIONS.reject do |section|
        architecture.include?(section)
      end

      missing_scenarios = REQUIRED_ACCEPTANCE_SCENARIOS.reject do |scenario|
        acceptance.include?(scenario)
      end

      missing_anti_patterns = REQUIRED_ANTI_PATTERNS.reject do |pattern|
        architecture.include?(pattern)
      end

      blockers = []
      blockers << "Missing required documents: #{missing_documents.join(', ')}" unless missing_documents.empty?
      blockers << "Missing architecture sections: #{missing_sections.join(', ')}" unless missing_sections.empty?
      blockers << "Missing acceptance scenarios: #{missing_scenarios.join(', ')}" unless missing_scenarios.empty?
      blockers << "Missing anti-patterns: #{missing_anti_patterns.join(', ')}" unless missing_anti_patterns.empty?
      blockers << "Roadmap must define nine phases" unless roadmap.scan(/^### Phase \d+:/).length == 9
      blockers << "Roadmap must define Phase 9 as the stopping point" unless roadmap.include?("Phase 9 is the clear stopping point")
      blockers << "Milestones must mark Conversational Soul in progress" unless milestones.include?("Conversational Soul") && milestones.include?("in progress")
      blockers << "Architecture must preserve deterministic action gates" unless architecture.include?("plan -> approval -> execute -> verify -> record")
      blockers << "Architecture must keep Codex outside automatic repo mutation" unless architecture.include?("Codex remains outside automatic repository mutation")

      {
        "ok" => blockers.empty?,
        "assessment" => "conversational_architecture",
        "milestone" => "conversational_soul",
        "phase" => 1,
        "generated_at" => Time.now.iso8601,
        "root" => @root,
        "status" => blockers.empty? ? "ready" : "blocked",
        "missing_documents" => missing_documents,
        "missing_architecture_sections" => missing_sections,
        "missing_acceptance_scenarios" => missing_scenarios,
        "missing_anti_patterns" => missing_anti_patterns,
        "blockers" => blockers,
        "verification" => {
          "required_documents_present" => missing_documents.empty?,
          "architecture_contract_complete" => missing_sections.empty?,
          "acceptance_contract_complete" => missing_scenarios.empty?,
          "anti_patterns_documented" => missing_anti_patterns.empty?,
          "nine_phase_roadmap" => roadmap.scan(/^### Phase \d+:/).length == 9,
          "phase_nine_stopping_point" => roadmap.include?("Phase 9 is the clear stopping point"),
          "milestone_in_progress" => milestones.include?("Conversational Soul") && milestones.include?("in progress"),
          "deterministic_action_boundary_preserved" => architecture.include?("plan -> approval -> execute -> verify -> record"),
          "codex_boundary_preserved" => architecture.include?("Codex remains outside automatic repository mutation")
        }
      }
    end

    def render(report)
      lines = []
      lines << "Soul Conversational Architecture Assessment"
      lines << "Generated: #{report['generated_at']}"
      lines << "Milestone: #{report['milestone']}"
      lines << "Phase: #{report['phase']}"
      lines << "Status: #{report['status']}"
      lines << ""
      lines << "Verification"
      report.fetch("verification").each do |key, value|
        lines << "- #{key}: #{value}"
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

    private

    def read(path)
      full_path = File.join(@root, path)
      File.exist?(full_path) ? File.read(full_path) : ""
    end
  end
end
