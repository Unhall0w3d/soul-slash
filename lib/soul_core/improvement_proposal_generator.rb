# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

require_relative "capability_matrix"
require_relative "improvement_proposal_paths"

module SoulCore
  class ImprovementProposalGenerator
    OUTPUT_ROOT = ImprovementProposalPaths::DEFAULT_ROOT

    def initialize(root: Dir.pwd, proposals_root: nil, env: ENV)
      @root = File.expand_path(root)
      @output_root = ImprovementProposalPaths.relative_root(
        root: @root,
        env: env,
        configured: proposals_root
      )
    end

    def generate(write_files: false)
      matrix = CapabilityMatrix.new(root: @root).assess(persist: false)
      proposals = proposal_specs(matrix.fetch("capabilities"))

      report = {
        "ok" => true,
        "assessment" => "improvement_proposals",
        "generated_at" => Time.now.iso8601,
        "read_only" => !write_files,
        "write_requested" => write_files,
        "proposal_root" => File.join(@root, @output_root),
        "source_summary" => matrix.fetch("summary"),
        "proposal_count" => proposals.length,
        "proposals" => proposals,
        "verification" => {
          "no_code_modified" => true,
          "no_skills_registered" => true,
          "no_workflows_registered" => true,
          "no_packages_installed" => true,
          "proposal_files_written_only_when_requested" => write_files
        }
      }

      write_proposals(report, matrix) if write_files
      report
    end

    def render(report)
      lines = []
      lines << "Soul Improvement Proposals"
      lines << "Generated: #{report['generated_at']}"
      lines << "Write requested: #{report['write_requested']}"
      lines << "Proposal count: #{report['proposal_count']}"
      lines << ""

      report.fetch("proposals").each_with_index do |proposal, index|
        lines << "#{index + 1}. #{proposal['title']}"
        lines << "   Capability: #{proposal['capability']}"
        lines << "   Priority: #{proposal['priority']}"
        lines << "   Status: #{proposal['status']}"
        lines << "   Summary: #{proposal['summary']}"
        lines << "   Safety: #{proposal['safety']}"
        lines << "   Path: #{proposal['path']}" if proposal["path"]
        lines << ""
      end

      lines << "No proposal files were written. Re-run with `--write` to create proposal folders." unless report["write_requested"]
      lines.join("\n")
    end

    private

    def proposal_specs(capabilities)
      candidates = []

      candidates << alpha_skill_generation if capabilities.dig("alpha_skill_generation", "status") == "missing"
      candidates << model_suitability_routing if capabilities.dig("model_suitability_routing", "status") != "available"
      candidates << vision_screen_understanding if capabilities.dig("vision_screen_understanding", "status") == "missing"
      candidates << speech_to_text if capabilities.dig("speech_to_text", "status") == "missing"

      candidates.each_with_index.map do |proposal, index|
        proposal.merge(
          "id" => slug(proposal.fetch("title")),
          "rank" => index + 1,
          "status" => "draft",
          "requires_human_approval" => true,
          "implementation_allowed" => false
        )
      end
    end

    def alpha_skill_generation
      {
        "capability" => "alpha_skill_generation",
        "priority" => "high",
        "title" => "Add alpha skill generation pipeline",
        "summary" => "Generate isolated alpha skill artifacts from approved skill proposals without registering them automatically.",
        "rationale" => [
          "Soul already drafts and reviews skill proposals.",
          "The missing step is producing bounded alpha artifacts for human review.",
          "Alpha output should stay proposal-local until promoted."
        ],
        "must_always" => [
          "Preserve Soul stability.",
          "Require human approval before implementation or promotion.",
          "Generate verifiers and documentation with every alpha skill.",
          "Keep alpha skills unregistered by default."
        ],
        "must_not" => [
          "Register generated skills automatically.",
          "Modify production skills without promotion.",
          "Bypass workflow or handler contracts."
        ],
        "first_steps" => [
          "Define alpha artifact folder structure.",
          "Generate implementation_plan.md from approved proposals.",
          "Generate alpha skill skeleton, verifier, and README.",
          "Add promotion checklist."
        ],
        "safety" => "Advisory only; proposal generation does not modify runtime skills."
      }
    end

    def model_suitability_routing
      {
        "capability" => "model_suitability_routing",
        "priority" => "medium",
        "title" => "Add model capability registry and task routing policy",
        "summary" => "Map models to appropriate task types so Soul can recommend or select the right local/cloud model for bounded work.",
        "rationale" => [
          "Soul can detect local model endpoints.",
          "It cannot yet decide which model should handle vision, coding, summarization, routing, or drafting.",
          "A registry reduces guesswork and prevents replacing useful models just because a new one exists."
        ],
        "must_always" => [
          "Keep model recommendations capability-gap driven.",
          "Preserve existing useful models unless a replacement is explicitly justified.",
          "Record resource impact and rollback guidance."
        ],
        "must_not" => [
          "Download models automatically.",
          "Assume online model rankings are authoritative without review.",
          "Route sensitive work to cloud providers without explicit policy."
        ],
        "first_steps" => [
          "Create a local model capability schema.",
          "Record known model roles and limitations.",
          "Add task categories such as coding, vision, STT, TTS, long context, and routing.",
          "Generate recommendations from capability gaps."
        ],
        "safety" => "Advisory only; no model downloads or endpoint changes."
      }
    end

    def vision_screen_understanding
      {
        "capability" => "vision_screen_understanding",
        "priority" => "medium",
        "title" => "Add bounded screen understanding capability",
        "summary" => "Enable screenshot capture and vision-model assessment so Soul can answer questions about visible screen content.",
        "rationale" => [
          "Soul currently cannot inspect the screen.",
          "Screen understanding unlocks troubleshooting, accessibility, UI review, and visual documentation workflows.",
          "The capability should be bounded and user-triggered."
        ],
        "must_always" => [
          "Require explicit user request before screenshot capture.",
          "Store screenshots only in clearly configured locations.",
          "Avoid background screen monitoring.",
          "Use a vision model only for the requested image context."
        ],
        "must_not" => [
          "Continuously watch the screen.",
          "Capture private content without user action.",
          "Send screenshots to cloud providers without explicit approval."
        ],
        "first_steps" => [
          "Define screenshot capture skill boundaries.",
          "Add local image artifact directory policy.",
          "Add vision model runtime requirement detection.",
          "Create a vision workflow handler with confirmation gates."
        ],
        "safety" => "Requires explicit user action; no background monitoring."
      }
    end

    def speech_to_text
      {
        "capability" => "speech_to_text",
        "priority" => "medium",
        "title" => "Add local speech-to-text capability assessment",
        "summary" => "Assess and later add local transcription support for voice workflows.",
        "rationale" => [
          "Soul does not yet have local transcription.",
          "Speech-to-text is needed for richer voice assistant behavior.",
          "A local-first approach keeps routine voice processing private."
        ],
        "must_always" => [
          "Require explicit activation.",
          "Prefer local transcription for private voice workflows.",
          "Document microphone and audio capture boundaries."
        ],
        "must_not" => [
          "Record continuously without a wake/activation policy.",
          "Store raw audio indefinitely by default.",
          "Send audio to cloud providers without explicit approval."
        ],
        "first_steps" => [
          "Detect audio stack and microphone availability.",
          "Assess local STT runtimes.",
          "Define audio artifact retention policy.",
          "Add transcription skill proposal."
        ],
        "safety" => "Advisory only; no audio capture added in this phase."
      }
    end

    def write_proposals(report, matrix)
      root = File.join(@root, @output_root)
      FileUtils.mkdir_p(root)
      timestamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")

      report.fetch("proposals").each do |proposal|
        folder = File.join(root, "#{timestamp}-#{proposal.fetch('rank')}-#{proposal.fetch('id')}")
        FileUtils.mkdir_p(folder)
        proposal["path"] = folder
        File.write(File.join(folder, "proposal.md"), proposal_markdown(proposal))
        File.write(File.join(folder, "metadata.json"), JSON.pretty_generate(proposal))
        File.write(File.join(folder, "source_capability_matrix.json"), JSON.pretty_generate(matrix))
      end
    end

    def proposal_markdown(proposal)
      lines = []
      lines << "# #{proposal.fetch('title')}"
      lines << ""
      lines << "Capability: `#{proposal.fetch('capability')}`"
      lines << ""
      lines << "Priority: `#{proposal.fetch('priority')}`"
      lines << ""
      lines << "Status: `#{proposal.fetch('status')}`"
      lines << ""
      lines << "Requires human approval: `#{proposal.fetch('requires_human_approval')}`"
      lines << ""
      lines << "Implementation allowed: `#{proposal.fetch('implementation_allowed')}`"
      lines << ""
      lines << "## Summary"
      lines << ""
      lines << proposal.fetch("summary")
      lines << ""
      lines << "## Rationale"
      lines << ""
      proposal.fetch("rationale").each { |item| lines << "- #{item}" }
      lines << ""
      lines << "## Must always"
      lines << ""
      proposal.fetch("must_always").each { |item| lines << "- #{item}" }
      lines << ""
      lines << "## Must not"
      lines << ""
      proposal.fetch("must_not").each { |item| lines << "- #{item}" }
      lines << ""
      lines << "## First steps"
      lines << ""
      proposal.fetch("first_steps").each { |item| lines << "- #{item}" }
      lines << ""
      lines << "## Safety"
      lines << ""
      lines << proposal.fetch("safety")
      lines << ""
      lines << "## Approval"
      lines << ""
      lines << "This proposal is advisory only. It must be reviewed and approved by a human before implementation."
      lines.join("\n")
    end

    def slug(value)
      value.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-+\z/, "")
    end
  end
end
