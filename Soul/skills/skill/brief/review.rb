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
require "soul_core/cloud_llm_client"

module SoulSkills
  module SkillBrief
    class Review
      ROLE = "skill_design_review"

      DESIGN_DOCS = [
        "docs/soul/SOUL_DESIGN_ETHOS.md",
        "docs/soul/CLOUD_LLM_POLICY.md",
        "docs/soul/HUMAN_REVIEW_GATE.md",
        "docs/soul/SKILL_PROPOSAL_FORMAT.md",
        "docs/soul/CLOUD_ASSIST_ARTIFACTS.md"
      ].freeze

      REQUIRED_PROPOSAL_FILES = [
        "proposal.md"
      ].freeze

      def initialize(argv)
        @argv = argv
      end

      def run
        if @argv.include?("--help") || @argv.include?("-h")
          puts help_text
          return 0
        end

        proposal_path = option_value("--proposal") || option_value("--path") || positional_path
        if proposal_path.to_s.strip.empty?
          puts JSON.pretty_generate(blocked_result("Missing proposal path. Use --proposal Soul/proposals/skills/<folder> or pass a proposal.md path."))
          return 1
        end

        resolved = resolve_proposal_path(proposal_path)
        unless resolved["ok"]
          puts JSON.pretty_generate(blocked_result(resolved["error"]))
          return 1
        end

        config = SoulCore::CloudProviderConfig.load(path: option_value("--config"))
        result =
          if @argv.include?("--dry-run")
            dry_run_result(resolved)
          elsif !config.valid?
            config_error_result(config)
          else
            review_with_provider(config, resolved)
          end

        log_path = write_log(result)
        result["task_log"] = log_path if log_path
        puts JSON.pretty_generate(result)

        result["status"] == "error" ? 1 : 0
      rescue StandardError => e
        result = {
          "skill" => "skill.brief.review",
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

      def review_with_provider(config, resolved)
        provider = selected_provider(config)
        return blocked_result("No enabled provider supports #{ROLE}. Enable Mistral in Soul/config/cloud_providers.yaml and ensure MISTRAL_API_KEY is present.", config: config) unless provider
        return blocked_result("Selected provider #{provider.name} requires #{provider.api_key_env}, but it is not present.", config: config, provider: provider) if provider.manual_key_required? && !provider.api_key_present?

        prompt = build_prompt(resolved)
        client = SoulCore::CloudLLMClient.new(provider)
        response = client.chat(messages: prompt_messages(prompt), temperature: 0.1, max_tokens: 2200, model: option_value("--model"))

        if response.ok?
          review_path = write_review_artifact(resolved: resolved, provider: provider, response: response, prompt: prompt, dry_run: false)
          {
            "skill" => "skill.brief.review",
            "generated_at" => Time.now.iso8601,
            "status" => "ok",
            "outcome" => "complete",
            "proposal" => proposal_summary(resolved),
            "provider" => provider_summary(provider),
            "response" => response.to_h,
            "review_path" => review_path,
            "recommendation" => "Skill proposal review drafted as a review artifact. Human approval is still required.",
            "verification" => verification(true, network_used: true)
          }
        else
          {
            "skill" => "skill.brief.review",
            "generated_at" => Time.now.iso8601,
            "status" => "error",
            "outcome" => "failed",
            "proposal" => proposal_summary(resolved),
            "provider" => provider_summary(provider),
            "response" => response.to_h,
            "recommendation" => "Provider call failed. No skill review artifact was created.",
            "verification" => verification(false, network_used: true)
          }
        end
      end

      def dry_run_result(resolved)
        response = DryRunResponse.new(
          provider: "dry_run",
          model: "none",
          status: "ok",
          http_status: nil,
          text: dry_run_markdown(resolved),
          error_message: nil,
          duration_seconds: 0
        )

        review_path = write_review_artifact(
          resolved: resolved,
          provider: DryRunProvider.new,
          response: response,
          prompt: build_prompt(resolved),
          dry_run: true
        )

        {
          "skill" => "skill.brief.review",
          "generated_at" => Time.now.iso8601,
          "status" => "ok",
          "outcome" => "complete",
          "proposal" => proposal_summary(resolved),
          "provider" => { "name" => "dry_run" },
          "response" => response.to_h,
          "review_path" => review_path,
          "recommendation" => "Dry-run skill proposal review artifact created. No provider call was made.",
          "verification" => verification(true, network_used: false)
        }
      end

      def write_review_artifact(resolved:, provider:, response:, prompt:, dry_run:)
        stamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
        review_dir = File.join(resolved["proposal_dir"], "reviews", "#{stamp}-skill-brief-review")
        FileUtils.mkdir_p(review_dir)

        metadata = {
          "artifact_type" => "skill_brief_review",
          "purpose" => ROLE,
          "created_at" => Time.now.utc.iso8601,
          "provider" => provider.name,
          "model" => response.model,
          "proposal_dir" => resolved["proposal_dir"],
          "proposal_file" => resolved["proposal_file"],
          "data_class" => "skill_proposal_plus_soul_design_docs",
          "secrets_included" => false,
          "private_repo_content_included" => false,
          "user_memory_included" => false,
          "source_bundle" => nil,
          "dry_run" => dry_run,
          "provider_response_status" => response.status,
          "provider_http_status" => response.http_status,
          "provider_error_message" => response.error_message,
          "output_mode" => "review_artifact_only",
          "direct_repo_mutation" => false,
          "human_review_required" => true
        }

        File.write(File.join(review_dir, "metadata.json"), JSON.pretty_generate(metadata) + "\n")
        File.write(File.join(review_dir, "review.md"), response.text.to_s)
        File.write(File.join(review_dir, "provider_response.md"), response.text.to_s)
        File.write(File.join(review_dir, "prompt.md"), prompt)
        File.write(File.join(review_dir, "sources.md"), sources_markdown(resolved))

        review_dir.sub("#{ROOT}/", "")
      end

      def resolve_proposal_path(input)
        expanded = File.expand_path(input, ROOT)

        if File.directory?(expanded)
          proposal_dir = expanded
          proposal_file = File.join(expanded, "proposal.md")
        else
          proposal_file = expanded
          proposal_dir = File.dirname(expanded)
        end

        missing = REQUIRED_PROPOSAL_FILES.reject do |file|
          File.exist?(File.join(proposal_dir, file))
        end

        return { "ok" => false, "error" => "Proposal file not found: #{proposal_file}" } unless File.exist?(proposal_file)
        return { "ok" => false, "error" => "Missing required proposal file(s): #{missing.join(', ')}" } unless missing.empty?

        {
          "ok" => true,
          "proposal_dir" => proposal_dir.sub("#{ROOT}/", ""),
          "proposal_file" => proposal_file.sub("#{ROOT}/", ""),
          "proposal_text" => File.read(proposal_file),
          "metadata_text" => read_optional(File.join(proposal_dir, "metadata.json")),
          "review_checklist_text" => read_optional(File.join(proposal_dir, "review_checklist.md")),
          "sources_text" => read_optional(File.join(proposal_dir, "sources.md"))
        }
      end

      def selected_provider(config)
        explicit = option_value("--provider")
        return config.provider(explicit) if explicit

        candidates = config.providers_for_role(ROLE)
        candidates.find { |provider| provider.name == "mistral" } || candidates.first
      end

      def build_prompt(resolved)
        docs = DESIGN_DOCS.map do |path|
          next unless File.exist?(File.join(ROOT, path))

          "# #{path}\n\n#{File.read(File.join(ROOT, path))}"
        end.compact.join("\n\n---\n\n")

        <<~PROMPT
          You are reviewing a Soul/ skill proposal.

          Soul/ is a local assistant substrate built around bounded skills, deterministic safety boundaries, verification gates, and human-approved memory.

          This output is a review artifact only. Do not approve implementation. Do not claim the proposal is merged, accepted, or safe. You may recommend ready_for_human_review, needs_revision, or blocked_for_human_review.

          PROPOSAL PATH:

          #{resolved["proposal_file"]}

          PROPOSAL METADATA:

          #{resolved["metadata_text"]}

          PROPOSAL:

          #{resolved["proposal_text"]}

          EXISTING REVIEW CHECKLIST:

          #{resolved["review_checklist_text"]}

          SOURCES:

          #{resolved["sources_text"]}

          RELEVANT SOUL/ DESIGN DOCS:

          #{docs}

          REQUIRED OUTPUT FORMAT:

          # Skill Proposal Review: <short title>

          ## Recommendation

          Use exactly one:

          ```text
          ready_for_human_review
          needs_revision
          blocked_for_human_review
          ```

          ## Summary
          ## Strengths
          ## Required Revisions
          ## Scope Creep Risks
          ## Persistence / Background Behavior Risks
          ## Secret and Private Data Risks
          ## Memory Usage Review
          ## Lifecycle State Review
          ## Failure Behavior Review
          ## Test and Eval Review
          ## Reflection Review
          ## Human Review Checklist
          ## Final Notes

          Be specific. If the proposal is missing a section, say so. If a risk is not present, say "No issue found." Do not invent implementation details.
        PROMPT
      end

      def prompt_messages(prompt)
        [
          {
            "role" => "system",
            "content" => "You review Soul/ skill proposal artifacts. You must preserve human approval authority, identify risks, and avoid claiming approval."
          },
          {
            "role" => "user",
            "content" => prompt
          }
        ]
      end

      def dry_run_markdown(resolved)
        <<~MARKDOWN
          # Skill Proposal Review: Dry Run

          ## Recommendation

          ```text
          needs_revision
          ```

          ## Summary

          Dry-run review fixture for `#{resolved["proposal_file"]}`.

          ## Strengths

          - Proposal file was readable.
          - Review artifact path was created.

          ## Required Revisions

          - Dry-run mode does not evaluate content.

          ## Scope Creep Risks

          No issue found in dry-run mode.

          ## Persistence / Background Behavior Risks

          No issue found in dry-run mode.

          ## Secret and Private Data Risks

          No issue found in dry-run mode.

          ## Memory Usage Review

          Dry-run mode did not evaluate memory usage.

          ## Lifecycle State Review

          Dry-run mode did not evaluate lifecycle states.

          ## Failure Behavior Review

          Dry-run mode did not evaluate failure behavior.

          ## Test and Eval Review

          Dry-run mode did not evaluate tests.

          ## Reflection Review

          Dry-run mode did not evaluate reflection.

          ## Human Review Checklist

          - [ ] Human reviewed generated proposal.
          - [ ] Human reviewed this review artifact.

          ## Final Notes

          Dry-run artifact only. No cloud provider was called.
        MARKDOWN
      end

      def proposal_summary(resolved)
        {
          "proposal_dir" => resolved["proposal_dir"],
          "proposal_file" => resolved["proposal_file"],
          "proposal_bytes" => resolved["proposal_text"].bytesize,
          "metadata_present" => !resolved["metadata_text"].to_s.empty?
        }
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

      def sources_markdown(resolved)
        <<~MARKDOWN
          # Sources

          Reviewed proposal:

          - `#{resolved["proposal_file"]}`

          Supporting proposal files:

          - `#{File.join(resolved["proposal_dir"], "metadata.json")}`
          - `#{File.join(resolved["proposal_dir"], "review_checklist.md")}`
          - `#{File.join(resolved["proposal_dir"], "sources.md")}`

          Design docs:

          #{DESIGN_DOCS.map { |path| "- `#{path}`" }.join("\n")}
        MARKDOWN
      end

      def config_error_result(config)
        {
          "skill" => "skill.brief.review",
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
          "skill" => "skill.brief.review",
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

      def read_optional(path)
        File.exist?(path) ? File.read(path) : ""
      end

      def write_log(result)
        dir = File.join(ROOT, "Soul", "logs", "tasks")
        FileUtils.mkdir_p(dir)
        stamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
        path = File.join(dir, "#{stamp}-skill.brief.review.json")
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

      def positional_path
        remaining = []
        skip = false
        @argv.each_with_index do |arg, idx|
          if skip
            skip = false
            next
          end

          if arg.start_with?("--")
            skip = %w[--proposal --path --config --provider --model].include?(arg) && @argv[idx + 1]
            next
          end

          remaining << arg
        end
        remaining.join(" ").strip
      end

      def help_text
        <<~TEXT
          skill.brief.review

          Reviews a Soul/ skill proposal and writes a review-only artifact under the proposal folder.

          Usage:
            ruby Soul/skills/skill/brief/review.rb --proposal Soul/proposals/skills/<folder> --dry-run
            ruby Soul/skills/skill/brief/review.rb --proposal Soul/proposals/skills/<folder> --config Soul/config/cloud_providers.yaml --provider mistral

          Notes:
            - Uses provider role: #{ROLE}
            - Mistral is the first supported provider.
            - Writes review artifacts only.
            - Does not approve the proposal.
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

      class DryRunProvider
        def name
          "dry_run"
        end

        def auth_mode
          "none"
        end

        def api_key_env
          nil
        end

        def api_key_present?
          false
        end

        def default_model
          "none"
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

exit SoulSkills::SkillBrief::Review.new(ARGV).run
