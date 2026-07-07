#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "time"
require "fileutils"

ROOT = File.expand_path("../../../..", __dir__)
$LOAD_PATH.unshift(File.join(ROOT, "lib"))

begin
  require "soul_core/env_loader"
  SoulCore::EnvLoader.load if defined?(SoulCore::EnvLoader)
rescue LoadError
  # .env loading is optional. Shell environment still works.
end

require "soul_core/cloud_provider_config"
require "soul_core/cloud_assist_artifact"
require "soul_core/cloud_llm_client"

module SoulSkills
  module SkillBrief
    class Draft
      ROLE = "skill_brief_draft"

      DESIGN_DOCS = [
        "docs/soul/SOUL_DESIGN_ETHOS.md",
        "docs/soul/CLOUD_LLM_POLICY.md",
        "docs/soul/HUMAN_REVIEW_GATE.md",
        "docs/soul/SKILL_PROPOSAL_FORMAT.md"
      ].freeze

      def initialize(argv)
        @argv = argv
      end

      def run
        if @argv.include?("--help") || @argv.include?("-h")
          puts help_text
          return 0
        end

        idea = option_value("--idea") || positional_idea
        if idea.to_s.strip.empty?
          puts JSON.pretty_generate(blocked_result("Missing skill idea. Use --idea \"...\" or pass the idea as arguments."))
          return 1
        end

        config = SoulCore::CloudProviderConfig.load(path: option_value("--config"))
        result =
          if @argv.include?("--dry-run")
            dry_run_result(config, idea)
          elsif !config.valid?
            config_error_result(config)
          else
            draft_with_provider(config, idea)
          end

        log_path = write_log(result)
        result["task_log"] = log_path if log_path
        puts JSON.pretty_generate(result)

        result["status"] == "error" ? 1 : 0
      rescue StandardError => e
        result = {
          "skill" => "skill.brief.draft",
          "generated_at" => Time.now.iso8601,
          "status" => "error",
          "outcome" => "failed",
          "error" => {
            "class" => e.class.name,
            "message" => e.message
          },
          "verification" => verification(false, network_used: false)
        }
        log_path = write_log(result)
        result["task_log"] = log_path if log_path
        puts JSON.pretty_generate(result)
        1
      end

      private

      def draft_with_provider(config, idea)
        provider = selected_provider(config)
        return blocked_result("No enabled provider supports #{ROLE}. Enable Mistral in Soul/config/cloud_providers.yaml and ensure MISTRAL_API_KEY is present.", config: config) unless provider
        return blocked_result("Selected provider #{provider.name} requires #{provider.api_key_env}, but it is not present.", config: config, provider: provider) if provider.manual_key_required? && !provider.api_key_present?

        prompt = build_prompt(idea)
        client = SoulCore::CloudLLMClient.new(provider)
        response = client.chat(messages: prompt_messages(prompt), temperature: 0.2, max_tokens: 2200, model: option_value("--model"))

        if response.ok?
          artifact = write_proposal_artifact(idea: idea, provider: provider, response: response, prompt: prompt, dry_run: false)
          {
            "skill" => "skill.brief.draft",
            "generated_at" => Time.now.iso8601,
            "status" => "ok",
            "outcome" => "complete",
            "idea" => idea,
            "provider" => provider_summary(provider),
            "response" => response.to_h,
            "proposal_path" => artifact.relative_path,
            "recommendation" => "Skill proposal drafted as a review artifact. Review it before implementation. Cloud output was not applied to repo code.",
            "verification" => verification(true, network_used: true)
          }
        else
          {
            "skill" => "skill.brief.draft",
            "generated_at" => Time.now.iso8601,
            "status" => "error",
            "outcome" => "failed",
            "idea" => idea,
            "provider" => provider_summary(provider),
            "response" => response.to_h,
            "recommendation" => "Provider call failed. No skill proposal was created.",
            "verification" => verification(false, network_used: true)
          }
        end
      end
def dry_run_result(config, idea)
  provider = selected_provider(config)
  fake_provider = provider || OpenStructLike.new(
    name: "dry_run",
    default_model: "none",
    api_key_env: nil,
    auth_mode: "none"
  )

  fake_response = DryRunResponse.new(
    provider: fake_provider.name,
    model: fake_provider.default_model,
    status: "ok",
    http_status: nil,
    text: dry_run_markdown(idea),
    error_message: nil,
    duration_seconds: 0
  )

  artifact = write_proposal_artifact(
    idea: idea,
    provider: fake_provider,
    response: fake_response,
    prompt: build_prompt(idea),
    dry_run: true
  )

  {
    "skill" => "skill.brief.draft",
    "generated_at" => Time.now.iso8601,
    "status" => "ok",
    "outcome" => "complete",
    "idea" => idea,
    "provider" => provider ? provider_summary(provider) : { "name" => "dry_run" },
    "response" => fake_response.to_h,
    "proposal_path" => artifact.relative_path,
    "recommendation" => "Dry-run skill proposal artifact created. No provider call was made.",
    "verification" => verification(true, network_used: false)
  }
end

      def write_proposal_artifact(idea:, provider:, response:, prompt:, dry_run:)
        slug = idea.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")[0, 50]
        slug = "skill-brief-draft" if slug.empty?

        metadata = {
          "provider" => provider.name,
          "model" => response.model,
          "purpose" => ROLE,
          "data_class" => "repo_design_summary_plus_user_skill_idea",
          "secrets_included" => false,
          "private_repo_content_included" => false,
          "user_memory_included" => false,
          "source_bundle" => nil,
          "dry_run" => dry_run,
          "idea" => idea,
          "provider_response_status" => response.status,
          "provider_http_status" => response.http_status,
          "provider_error_message" => response.error_message
        }

        SoulCore::CloudAssistArtifact.create(
          kind: "skill_proposal",
          purpose: ROLE,
          slug: slug,
          metadata: metadata,
          files: {
            "proposal.md" => response.text,
            "provider_response.md" => response.text,
            "prompt.md" => prompt,
            "review_checklist.md" => review_checklist,
            "sources.md" => sources_markdown
          }
        )
      end

      def selected_provider(config)
        explicit = option_value("--provider")
        return config.provider(explicit) if explicit

        candidates = config.providers_for_role(ROLE)
        candidates.find { |provider| provider.name == "mistral" } || candidates.first
      end

      def provider_summary(provider)
        {
          "name" => provider.name,
          "auth_mode" => provider.auth_mode,
          "api_key_env" => provider.api_key_env,
          "api_key_present" => provider.api_key_present?,
          "default_model" => provider.default_model,
          "roles" => provider.roles
        }
      end

      def build_prompt(idea)
        docs = DESIGN_DOCS.map do |path|
          next unless File.exist?(File.join(ROOT, path))

          "# #{path}\n\n#{File.read(File.join(ROOT, path))}"
        end.compact.join("\n\n---\n\n")

        <<~PROMPT
          You are drafting a Soul/ skill proposal.

          Soul/ is a local assistant substrate built around bounded skills, deterministic safety boundaries, verification gates, and human-approved memory.

          This output is a review artifact only. Do not claim implementation is complete. Do not write code. Do not approve memory. Do not approve safety policy. Do not propose persistent/background behavior unless explicitly required by the skill idea, and if so mark it blocked_for_human_review.

          USER SKILL IDEA:

          #{idea}

          RELEVANT SOUL/ DESIGN DOCS:

          #{docs}

          REQUIRED OUTPUT FORMAT:

          Produce Markdown with these sections:

          # Skill Proposal: <short title>

          ## Purpose
          ## User-Facing Behavior
          ## Inputs
          ## Outputs
          ## Required Config
          ## Lifecycle States
          ## Safety Boundaries
          ## Memory Usage
          ## Logs and Artifacts
          ## Failure Behavior
          ## Acceptance Criteria
          ## Deterministic Tests
          ## Local LLM Behavioral Evals
          ## Reflection Candidates
          ## Human Review Checklist

          Keep the proposal practical and implementation-ready, but do not include full source code.
        PROMPT
      end

      def prompt_messages(prompt)
        [
          {
            "role" => "system",
            "content" => "You draft careful, bounded Soul/ skill proposal artifacts. You must preserve human review authority and avoid direct repo mutation."
          },
          {
            "role" => "user",
            "content" => prompt
          }
        ]
      end

      def review_checklist
        <<~MARKDOWN
          # Human Review Checklist

          - [ ] Proposal matches the requested skill idea.
          - [ ] Scope is bounded.
          - [ ] No persistent/background behavior unless explicitly approved.
          - [ ] No direct cloud mutation of repo files.
          - [ ] No secrets are requested or transmitted.
          - [ ] Memory usage is shared and justified.
          - [ ] Failure states are predictable.
          - [ ] Terminal states are defined.
          - [ ] Deterministic tests are identified.
          - [ ] Local LLM behavioral evals are identified where useful.
          - [ ] Human approval is required before implementation.
        MARKDOWN
      end

      def sources_markdown
        <<~MARKDOWN
          # Sources

          No external source bundle supplied.

          This proposal is based on:

          #{DESIGN_DOCS.map { |path| "- `#{path}`" }.join("\n")}

          This is a skill proposal draft, not sourced research.
        MARKDOWN
      end

      def dry_run_markdown(idea)
        <<~MARKDOWN
          # Skill Proposal: Dry Run

          ## Purpose

          Draft a bounded Soul/ skill proposal for:

          ```text
          #{idea}
          ```

          ## User-Facing Behavior

          Dry-run fixture only. No provider was called.

          ## Inputs

          - User-provided skill idea.

          ## Outputs

          - Review-only proposal artifact.

          ## Required Config

          - None for dry-run.

          ## Lifecycle States

          - complete
          - failed
          - blocked_for_human_review

          ## Safety Boundaries

          - No direct repo mutation.
          - No secrets transmitted.
          - No background/persistent behavior.

          ## Memory Usage

          - None proposed.

          ## Logs and Artifacts

          - Proposal folder under `Soul/proposals/skills/`.

          ## Failure Behavior

          - Return failed or blocked status with evidence.

          ## Acceptance Criteria

          - Artifact is created with metadata.
          - Human review is required.

          ## Deterministic Tests

          - Verify proposal folder and metadata exist.

          ## Local LLM Behavioral Evals

          - Not applicable for dry-run.

          ## Reflection Candidates

          - None.

          ## Human Review Checklist

          - [ ] Dry-run artifact reviewed.
        MARKDOWN
      end

      def config_error_result(config)
        {
          "skill" => "skill.brief.draft",
          "generated_at" => Time.now.iso8601,
          "status" => "error",
          "outcome" => "failed",
          "config" => {
            "path" => config.path,
            "errors" => config.errors,
            "warnings" => config.warnings
          },
          "verification" => verification(false, network_used: false)
        }
      end

      def blocked_result(message, config: nil, provider: nil)
        out = {
          "skill" => "skill.brief.draft",
          "generated_at" => Time.now.iso8601,
          "status" => "warning",
          "outcome" => "blocked_for_input",
          "recommendation" => message,
          "verification" => verification(false, network_used: false)
        }
        out["config"] = { "path" => config.path, "errors" => config.errors, "warnings" => config.warnings } if config
        out["provider"] = provider_summary(provider) if provider
        out
      end

      def verification(complete, network_used:)
        {
          "read_only" => true,
          "network_used" => network_used,
          "secrets_printed" => false,
          "api_key_values_printed" => false,
          "private_repo_content_sent" => false,
          "user_memory_sent" => false,
          "review_artifact_only" => true,
          "direct_repo_mutation" => false,
          "complete" => complete,
          "final_state" => complete ? "complete" : "blocked_or_failed"
        }
      end

      def write_log(result)
        dir = File.join(ROOT, "Soul", "logs", "tasks")
        FileUtils.mkdir_p(dir)
        stamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
        path = File.join(dir, "#{stamp}-skill.brief.draft.json")
        File.write(path, JSON.pretty_generate(result) + "\n")
        path.sub("#{ROOT}/", "")
      rescue StandardError
        nil
      end

      def option_value(flag)
        idx = @argv.index(flag)
        return nil unless idx

        @argv[idx + 1]
      end

      def positional_idea
        remaining = []
        skip = false
        @argv.each_with_index do |arg, idx|
          if skip
            skip = false
            next
          end

          if arg.start_with?("--")
            skip = %w[--idea --config --provider --model].include?(arg) && @argv[idx + 1]
            next
          end

          remaining << arg
        end
        remaining.join(" ").strip
      end

      def help_text
        <<~TEXT
          skill.brief.draft

          Drafts a review-only Soul/ skill proposal into Soul/proposals/skills/.

          Usage:
            ruby Soul/skills/skill/brief/draft.rb --idea "Add a bounded notes cleanup skill"
            ruby Soul/skills/skill/brief/draft.rb --idea "Add a bounded notes cleanup skill" --config Soul/config/cloud_providers.yaml
            ruby Soul/skills/skill/brief/draft.rb --idea "Add a bounded notes cleanup skill" --dry-run

          Notes:
            - Uses provider role: #{ROLE}
            - Mistral is the first supported provider.
            - Writes review artifacts only.
            - Does not implement the skill.
            - Does not send secrets, user memory, or private repo content.
        TEXT
      end
DryRunResponse = Struct.new(
  :provider,
  :model,
  :status,
  :http_status,
  :text,
  :error_message,
  :duration_seconds,
  keyword_init: true
) do
  def to_h
    {
      "provider" => provider,
      "model" => model,
      "status" => status,
      "http_status" => http_status,
      "text_present" => !text.to_s.empty?,
      "error_message" => error_message,
      "duration_seconds" => duration_seconds
    }
  end
end


      OpenStructLike = Struct.new(:name, :default_model, :api_key_env, :auth_mode, keyword_init: true) do
        def api_key_present?
          false
        end

        def roles
          []
        end

        def manual_key_required?
          false
        end
      end
    end
  end
end

exit SoulSkills::SkillBrief::Draft.new(ARGV).run
