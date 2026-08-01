# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "pathname"
require "securerandom"
require "time"
require "timeout"
require "yaml"
require_relative "skill_registry"
require_relative "bounded_command_runner"
require_relative "local_development_model_client"

module SoulCore
  class SkillStudioService
    PROPOSALS_ROOT = "Soul/proposals/skills"
    LEGACY_PROPOSALS_ROOT = "Soul/improvement/proposals"
    STATE_FILE = "studio_state.json"
    BETA_DIR = "beta"
    BETA_MANIFEST = "beta_manifest.json"
    TEST_RESULTS = "test_results.json"
    PROPOSAL_CONFIRMATION = "APPROVE_PROPOSAL_FOR_BETA_BUILD"
    PROMOTION_CONFIRMATION = "APPROVE_BETA_FOR_PROMOTION"
    MAX_RECORDS = 100
    MAX_TEXT_BYTES = 64 * 1024
    MAX_ARGS = 20
    MAX_ARG_BYTES = 4 * 1024
    MAX_OUTPUT_BYTES = 32 * 1024
    MAX_TIMEOUT_SECONDS = 60
    DEV_BUILD_CONFIRMATION_PREFIX = "BUILD_BETA_WITH_DEV_CORE"
    DEV_MODEL_MAX_TOKENS = 8_192
    DEV_TEST_LIMIT = 12
    DEV_SOURCE_DENY = /(?:\bsystem\s*\(|\bexec\s*\(|\bspawn\s*\(|IO\.popen|Open3|File\.(?:write|open|delete|unlink|rename)|Net::|TCPSocket|UDPSocket|Socket\.|Process\.(?:spawn|fork)|Thread\.new|`)/

    CLOSE_CONFIRMATION = "CLOSE_PRODUCTION_PROPOSAL"
    BETA_BUILD_CONFIRMATION_PREFIX = "PREPARE_BETA_BUILD"
    PRODUCTION_CONFIRMATION_PREFIX = "PROMOTE_BETA_SKILL"
    PRODUCTION_ROOT = "Soul/skills/generated"
    REGISTRY_PATH = "Soul/skills/registry.yaml"
    PRODUCTION_RECEIPT = "PROMOTION.json"
    SKILL_ID = /\A[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+\z/

    def initialize(root: Dir.pwd, clock: -> { Time.now }, production_registry: nil,
                   development_model_client: nil, runner: BoundedCommandRunner.new,
                   ruby_path: "/usr/bin/ruby", bwrap_path: "/usr/bin/bwrap")
      @root = File.expand_path(root)
      @clock = clock
      @production_registry = production_registry
      @development_model_client = development_model_client
      @runner = runner
      @ruby_path = ruby_path
      @bwrap_path = bwrap_path
    end

    def proposals(limit: MAX_RECORDS)
      records = proposal_directories.first(bounded_limit(limit)).filter_map { |directory| proposal_projection(directory) }
      success({ "records" => records, "count" => records.length, "limit" => bounded_limit(limit), "read_only" => true })
    end

    def proposal(proposal_id:)
      directory = proposal_directory(proposal_id)
      return awaiting("unknown proposal ID") unless directory

      projection = proposal_projection(directory, detail: true)
      return failed("proposal packet is invalid") unless projection

      success({ "record" => projection, "read_only" => true })
    end

    def proposal_approval_preview(proposal_id:)
      directory = proposal_directory(proposal_id)
      return awaiting("unknown proposal ID") unless directory

      record = proposal_projection(directory)
      return failed("proposal packet is invalid") unless record
      return blocked("proposal is already approved for Beta implementation") if record["proposal_gate"] == "approved"

      digest = proposal_digest(directory)
      success(
        {
          "proposal_id" => proposal_id,
          "title" => record["title"],
          "expected_digest" => digest,
          "confirmation_phrase" => PROPOSAL_CONFIRMATION,
          "effect" => "authorize bounded Beta implementation for this exact proposal revision",
          "does_not" => ["generate code", "invoke Codex", "run a Beta", "register a skill", "promote to production"]
        },
        lifecycle: "blocked_for_human_review"
      )
    end

    def approve_proposal(proposal_id:, expected_digest:, confirmation:)
      directory = proposal_directory(proposal_id)
      return awaiting("unknown proposal ID") unless directory
      return awaiting("exact proposal approval confirmation is required") unless confirmation == PROPOSAL_CONFIRMATION

      current_digest = proposal_digest(directory)
      return blocked("proposal changed after preview; review the current revision") unless secure_equal?(expected_digest, current_digest)

      state = read_state(directory)
      state["schema_version"] = "soul.skill_studio.v1"
      state["proposal_gate"] = {
        "status" => "approved",
        "approved_at" => now,
        "proposal_digest" => current_digest,
        "authority" => "human_exact_confirmation"
      }
      state["beta_gate"] ||= { "status" => "not_ready" }
      write_json(File.join(directory, STATE_FILE), state)
      success(
        { "proposal_id" => proposal_id, "proposal_gate" => "approved", "proposal_digest" => current_digest },
        mutation: "proposal_approved_for_beta_build"
      )
    end

    def betas(limit: MAX_RECORDS)
      records = beta_records.first(bounded_limit(limit))
      success({ "records" => records, "count" => records.length, "limit" => bounded_limit(limit), "production_registry_separate" => true, "read_only" => true })
    end

    def beta_build_preview(proposal_id:, skill_id:)
      directory = proposal_directory(proposal_id)
      return awaiting("unknown proposal ID") unless directory
      return awaiting("canonical dotted skill_id is required") unless valid_skill_id?(skill_id)

      state = read_state(directory)
      return blocked("proposal Gate 1 approval is required before Beta preparation") unless state.dig("proposal_gate", "status") == "approved"
      return blocked("proposal path must not be a symlink") if File.symlink?(directory)
      return blocked("a Beta workspace already exists for this proposal") if File.exist?(File.join(directory, BETA_DIR))

      digest = beta_build_digest(directory, skill_id)
      success(
        {
          "proposal_id" => proposal_id,
          "skill_id" => skill_id,
          "expected_digest" => digest,
          "confirmation_phrase" => "#{BETA_BUILD_CONFIRMATION_PREFIX} #{skill_id}",
          "creates" => relative(File.join(directory, BETA_DIR)),
          "effect" => "prepare an incomplete proposal-local Beta workspace and bounded Codex handoff",
          "implementation_complete" => false,
          "codex_invoked" => false,
          "production_modified" => false
        },
        lifecycle: "blocked_for_human_review"
      )
    end

    def prepare_beta_build(proposal_id:, skill_id:, expected_digest:, confirmation:)
      directory = proposal_directory(proposal_id)
      return awaiting("unknown proposal ID") unless directory
      return awaiting("canonical dotted skill_id is required") unless valid_skill_id?(skill_id)
      return awaiting("exact Beta preparation confirmation is required") unless confirmation == "#{BETA_BUILD_CONFIRMATION_PREFIX} #{skill_id}"

      state = read_state(directory)
      return blocked("proposal Gate 1 approval is required before Beta preparation") unless state.dig("proposal_gate", "status") == "approved"
      return blocked("proposal path must not be a symlink") if File.symlink?(directory)
      return blocked("proposal or Gate 1 approval changed after preview") unless secure_equal?(expected_digest, beta_build_digest(directory, skill_id))

      beta_directory = File.join(directory, BETA_DIR)
      return blocked("a Beta workspace already exists for this proposal") if File.exist?(beta_directory) || File.symlink?(beta_directory)

      record = proposal_projection(directory)
      Dir.mkdir(beta_directory, 0o700)
      manifest = beta_workspace_manifest(skill_id, record)
      write_json(File.join(beta_directory, BETA_MANIFEST), manifest)
      File.write(File.join(beta_directory, "skill.rb"), beta_placeholder(skill_id), mode: "w", perm: 0o600)
      File.write(File.join(beta_directory, "IMPLEMENTATION.md"), beta_implementation_pack(directory, skill_id), mode: "w", perm: 0o600)
      File.write(File.join(beta_directory, "REVIEW.md"), beta_review_artifact(skill_id), mode: "w", perm: 0o600)
      File.write(File.join(beta_directory, "ROLLBACK.md"), "# Beta Rollback\n\nDelete only this proposal-local `beta/` directory before promotion. No production or registry state has changed.\n", mode: "w", perm: 0o600)
      success(
        {
          "proposal_id" => proposal_id,
          "beta_id" => skill_id,
          "package_path" => relative(beta_directory),
          "implementation_complete" => false,
          "codex_invoked" => false,
          "production_modified" => false,
          "files" => Dir.children(beta_directory).sort
        },
        mutation: "proposal_local_beta_workspace_prepared"
      )
    rescue StandardError => error
      FileUtils.remove_entry_secure(beta_directory) if beta_directory && File.directory?(beta_directory) && File.dirname(beta_directory) == directory
      failed("Beta workspace preparation failed safely: #{error.class}")
    end

    def beta(beta_id:)
      located = locate_beta(beta_id)
      return awaiting("unknown Beta skill ID") unless located

      success({ "record" => beta_projection(*located, detail: true), "read_only" => true })
    end

    def dev_build_preview(beta_id:)
      located = locate_beta(beta_id)
      return awaiting("unknown Beta skill ID") unless located
      directory, manifest, proposal_directory = located
      return blocked("legacy alpha scaffold cannot use Dev Core") if manifest["schema_version"] != "soul.beta.v1"
      return blocked("proposal Gate 1 approval is required") unless read_state(proposal_directory).dig("proposal_gate", "status") == "approved"
      return blocked("Beta implementation is already complete") if manifest["implementation_complete"] == true
      return blocked("Beta package path must not be a symlink") if File.symlink?(directory)

      scope = dev_build_scope(directory, manifest, proposal_directory)
      success({
        "beta_id" => beta_id,
        "expected_digest" => digest(scope),
        "confirmation_phrase" => "#{DEV_BUILD_CONFIRMATION_PREFIX} #{beta_id}",
        "effect" => "run one local GPT-OSS draft, isolated syntax and behavior tests, then return a Beta candidate for human review",
        "model" => LocalDevelopmentModelClient::MODEL,
        "automatic_repair_attempts" => 0,
        "production_modified" => false,
        "vault_access" => false,
        "scope" => scope
      }, lifecycle: "blocked_for_human_review")
    end

    def build_beta_with_dev_core(beta_id:, expected_digest:, confirmation:, on_progress: nil)
      located = locate_beta(beta_id)
      return awaiting("unknown Beta skill ID") unless located
      directory, manifest, proposal_directory = located
      return awaiting("exact Dev Core Beta build confirmation is required") unless confirmation == "#{DEV_BUILD_CONFIRMATION_PREFIX} #{beta_id}"
      return blocked("proposal Gate 1 approval is required") unless read_state(proposal_directory).dig("proposal_gate", "status") == "approved"
      return blocked("Beta implementation is already complete") if manifest["implementation_complete"] == true
      scope = dev_build_scope(directory, manifest, proposal_directory)
      return blocked("Beta or proposal changed after preview; review the current revision") unless secure_equal?(expected_digest, digest(scope))

      progress(on_progress, "dev_build_drafting", "GPT-OSS is drafting one proposal-bound Beta candidate.")
      response = development_model_client.chat(
        messages: dev_build_messages(directory, manifest, proposal_directory),
        purpose: "Skill Studio Beta build #{beta_id}",
        response_schema: dev_build_schema,
        temperature: 0.1,
        max_tokens: DEV_MODEL_MAX_TOKENS,
        reasoning: true,
        on_progress: on_progress,
        request_id: "skill_dev_#{SecureRandom.hex(10)}"
      )
      return failed("Dev Core draft failed safely: #{response.error_message}") unless response.ok? && response.structured.is_a?(Hash)

      candidate = validate_dev_candidate(response.structured, beta_id)
      return candidate if candidate.is_a?(Hash) && candidate["lifecycle_state"]
      progress(on_progress, "dev_build_testing", "Running isolated syntax and model-declared behavior checks.")
      result = materialize_and_test_dev_candidate(directory, manifest, candidate, response)
      lifecycle = result.fetch("implementation_complete") ? "blocked_for_human_review" : "failed"
      success(result.merge(
        "beta_id" => beta_id,
        "provider" => response.to_h,
        "production_modified" => false,
        "vault_access" => false,
        "human_review_required" => true
      ), lifecycle:, mutation: "dev_core_beta_candidate_built_and_tested")
    rescue StandardError => error
      failed("Dev Core Beta build failed safely: #{error.class}: #{error.message}"[0, 1_000])
    ensure
      FileUtils.remove_entry_secure(staging) if defined?(staging) && staging && File.directory?(staging) && File.dirname(staging) == directory
    end

    def beta_run_preview(beta_id:, args: [])
      located = locate_beta(beta_id)
      return awaiting("unknown Beta skill ID") unless located
      directory, manifest, proposal_directory = located
      record = beta_projection(directory, manifest, proposal_directory)
      return blocked("legacy alpha scaffold is not runnable") if record["maturity"] == "legacy_alpha_scaffold"
      return blocked("Beta implementation is incomplete") unless record["runnable"]

      validated_args = validate_args(args)
      return validated_args unless validated_args.is_a?(Array)

      digest = beta_digest(directory, manifest)
      success(
        {
          "beta_id" => beta_id,
          "description" => record["description"],
          "expected_digest" => digest,
          "confirmation_phrase" => "RUN_BETA_SKILL #{beta_id}",
          "argument_count" => validated_args.length,
          "timeout_seconds" => execution_timeout(manifest),
          "execution_isolation" => manifest["development_provider"] == "local.dev" ? "networkless_read_only_bubblewrap" : "bounded_local_process",
          "diagnostic_logging" => "bounded local JSONL; output may contain skill-produced content",
          "production_skill" => false
        },
        lifecycle: "blocked_for_human_review"
      )
    end

    def run_beta(beta_id:, args:, expected_digest:, confirmation:)
      located = locate_beta(beta_id)
      return awaiting("unknown Beta skill ID") unless located
      directory, manifest, proposal_directory = located
      record = beta_projection(directory, manifest, proposal_directory)
      return blocked("legacy alpha scaffold is not runnable") if record["maturity"] == "legacy_alpha_scaffold"
      return blocked("Beta implementation is incomplete") unless record["runnable"]
      return awaiting("exact Beta run confirmation is required") unless confirmation == "RUN_BETA_SKILL #{beta_id}"

      current_digest = beta_digest(directory, manifest)
      return blocked("Beta changed after preview; review the current revision") unless secure_equal?(expected_digest, current_digest)

      validated_args = validate_args(args)
      return validated_args unless validated_args.is_a?(Array)

      result = execute_beta(directory, manifest, validated_args)
      log_path = append_beta_log(beta_id, current_digest, validated_args.length, result)
      lifecycle = result.fetch("timed_out") ? "failed" : (result.fetch("exit_status") == 0 ? "complete" : "failed")
      success(
        result.merge(
          "beta_id" => beta_id,
          "beta_digest" => current_digest,
          "diagnostic_log" => relative(log_path),
          "production_registry_modified" => false
        ),
        lifecycle: lifecycle,
        mutation: "beta_executed_and_diagnostic_recorded"
      )
    end

    def promotion_preview(beta_id:)
      located = locate_beta(beta_id)
      return awaiting("unknown Beta skill ID") unless located
      directory, manifest, proposal_directory = located
      record = beta_projection(directory, manifest, proposal_directory, detail: true)
      return blocked("legacy alpha scaffold cannot be promoted") if record["maturity"] == "legacy_alpha_scaffold"

      blockers = promotion_blockers(record, proposal_directory)
      digest = beta_digest(directory, manifest)
      success(
        {
          "beta_id" => beta_id,
          "expected_digest" => digest,
          "confirmation_phrase" => PROMOTION_CONFIRMATION,
          "blockers" => blockers,
          "ready" => blockers.empty?,
          "effect" => "record human approval of this Beta revision for a later explicit promotion workflow",
          "promotion_performed" => false
        },
        lifecycle: "blocked_for_human_review"
      )
    end

    def approve_beta_for_promotion(beta_id:, expected_digest:, confirmation:)
      located = locate_beta(beta_id)
      return awaiting("unknown Beta skill ID") unless located
      directory, manifest, proposal_directory = located
      return awaiting("exact Beta promotion confirmation is required") unless confirmation == PROMOTION_CONFIRMATION

      record = beta_projection(directory, manifest, proposal_directory, detail: true)
      blockers = promotion_blockers(record, proposal_directory)
      return blocked("Beta is not ready for promotion review: #{blockers.join('; ')}") unless blockers.empty?

      current_digest = beta_digest(directory, manifest)
      return blocked("Beta changed after preview; review and retest the current revision") unless secure_equal?(expected_digest, current_digest)

      state = read_state(proposal_directory)
      state["schema_version"] = "soul.skill_studio.v1"
      state["beta_gate"] = {
        "status" => "approved_for_promotion",
        "approved_at" => now,
        "beta_id" => beta_id,
        "beta_digest" => current_digest,
        "authority" => "human_exact_confirmation",
        "promotion_performed" => false
      }
      write_json(File.join(proposal_directory, STATE_FILE), state)
      success(
        { "beta_id" => beta_id, "beta_gate" => "approved_for_promotion", "beta_digest" => current_digest, "promotion_performed" => false },
        mutation: "beta_approved_for_later_promotion"
      )
    end

    def production_promotion_preview(beta_id:)
      context = production_promotion_context(beta_id)
      return context if context.is_a?(Hash) && context["lifecycle_state"]

      success(
        context.merge(
          "expected_digest" => production_promotion_digest(context),
          "confirmation_phrase" => "#{PRODUCTION_CONFIRMATION_PREFIX} #{beta_id}",
          "effect" => "copy the exact reviewed Beta entrypoint into production and atomically register one new skill",
          "rollback" => ["remove the exact new registry entry", "remove only the generated production directory after registry removal"]
        ),
        lifecycle: "blocked_for_human_review"
      )
    end

    def promote_beta_to_production(beta_id:, expected_digest:, confirmation:)
      return awaiting("exact production promotion confirmation is required") unless confirmation == "#{PRODUCTION_CONFIRMATION_PREFIX} #{beta_id}"
      context = production_promotion_context(beta_id)
      return context if context.is_a?(Hash) && context["lifecycle_state"]
      return blocked("Beta, approval, registry, or target state changed after preview") unless secure_equal?(expected_digest, production_promotion_digest(context))

      target_directory = full(context.fetch("production_directory"))
      source = full(context.fetch("source_entrypoint"))
      registry_path = full(REGISTRY_PATH)
      created = false
      Dir.mkdir(full(PRODUCTION_ROOT), 0o755) unless Dir.exist?(full(PRODUCTION_ROOT))
      Dir.mkdir(target_directory, 0o755)
      created = true
      File.open(File.join(target_directory, "skill.rb"), File::WRONLY | File::CREAT | File::EXCL, 0o644) { |file| file.write(File.binread(source)) }
      File.write(File.join(target_directory, "skill_manifest.yaml"), YAML.dump(context.fetch("registry_definition")), mode: "w", perm: 0o644)
      receipt = {
        "schema_version" => "soul.skill_promotion.v1",
        "promoted_at" => now,
        "skill_id" => beta_id,
        "beta_digest" => context.fetch("beta_digest"),
        "source_sha256" => context.fetch("source_sha256"),
        "target_sha256" => Digest::SHA256.file(File.join(target_directory, "skill.rb")).hexdigest,
        "registry_definition" => context.fetch("registry_definition"),
        "rollback" => ["remove registry entry #{beta_id}", "remove #{context.fetch('production_directory')} only after registry removal"]
      }
      write_json(File.join(target_directory, PRODUCTION_RECEIPT), receipt)
      write_registry_with_new_skill(registry_path, beta_id, context.fetch("registry_definition"))
      success(
        context.merge(
          "promotion_performed" => true,
          "receipt" => relative(File.join(target_directory, PRODUCTION_RECEIPT)),
          "target_sha256" => receipt.fetch("target_sha256"),
          "registry_modified" => true
        ),
        mutation: "beta_promoted_to_production"
      )
    rescue StandardError => error
      FileUtils.remove_entry_secure(target_directory) if created && target_directory && File.directory?(target_directory) && File.dirname(target_directory) == full(PRODUCTION_ROOT)
      failed("production promotion failed safely and removed the unpublished target: #{error.class}")
    end

    def proposal_close_preview(proposal_id:)
      directory = proposal_directory(proposal_id)
      return awaiting("unknown proposal ID") unless directory

      context = closeout_context(directory)
      return blocked("proposal closeout is available only after the exact linked skill is registered in production") unless context["stage"] == "production"

      success(
        context.merge(
          "expected_digest" => closeout_digest(directory, context),
          "confirmation_phrase" => CLOSE_CONFIRMATION,
          "effect" => "permanently delete this production-linked proposal and its superseded Beta candidate copy",
          "preserves" => ["production skill", "production registry", "shared Beta diagnostics", "chats", "memories", "artifacts", "activity history"]
        ),
        lifecycle: "blocked_for_human_review"
      )
    end

    def close_production_proposal(proposal_id:, expected_digest:, confirmation:)
      directory = proposal_directory(proposal_id)
      return awaiting("unknown proposal ID") unless directory
      return awaiting("exact production proposal close confirmation is required") unless confirmation == CLOSE_CONFIRMATION

      context = closeout_context(directory)
      return blocked("proposal is not linked to an exact registered production skill") unless context["stage"] == "production"
      return blocked("proposal or production linkage changed after preview; review the current revision") unless secure_equal?(expected_digest, closeout_digest(directory, context))
      return blocked("proposal path failed the direct-child deletion boundary") unless File.dirname(directory) == full(PROPOSALS_ROOT) && !File.symlink?(directory)

      FileUtils.remove_entry_secure(directory)
      success(
        {
          "proposal_id" => proposal_id,
          "linked_skill_id" => context["linked_skill_id"],
          "stage" => "closed",
          "proposal_deleted" => !File.exist?(directory),
          "production_skill_preserved" => production_definition(context["linked_skill_id"]).is_a?(Hash),
          "shared_diagnostics_preserved" => true
        },
        mutation: "production_proposal_permanently_deleted"
      )
    rescue Errno::EACCES, Errno::EPERM, Errno::ENOTEMPTY => error
      failed("proposal closeout failed safely: #{error.class}")
    end

    private

    def valid_skill_id?(value)
      value.is_a?(String) && value.bytesize <= 120 && value.match?(SKILL_ID)
    end

    def beta_build_digest(directory, skill_id)
      Digest::SHA256.hexdigest(JSON.generate({
        "proposal_digest" => proposal_digest(directory),
        "proposal_gate" => read_state(directory)["proposal_gate"],
        "skill_id" => skill_id,
        "beta_absent" => !File.exist?(File.join(directory, BETA_DIR))
      }))
    end

    def beta_workspace_manifest(skill_id, proposal_record)
      {
        "schema_version" => "soul.beta.v1",
        "skill_id" => skill_id,
        "description" => proposal_record["description"].to_s.empty? ? proposal_record["title"] : proposal_record["description"],
        "risk" => "unclassified",
        "entrypoint" => "skill.rb",
        "implementation_complete" => false,
        "timeout_seconds" => 30,
        "requires_approval" => true,
        "confirmation_phrase" => "REPLACE_WITH_REVIEWED_CONFIRMATION",
        "writes_files" => false,
        "expected_output" => "json",
        "verifier" => "schema_basic",
        "lifecycle_states" => %w[complete failed awaiting_input canceled blocked_for_human_review],
        "required_tests" => [{ "id" => "replace-with-deterministic-test", "description" => "Replace during implementation with a deterministic behavior test", "kind" => "deterministic" }],
        "known_weaknesses" => ["Implementation has not started."],
        "failure_behavior" => ["Return blocked_for_human_review until implementation and review are complete."]
      }
    end

    def beta_placeholder(skill_id)
      <<~RUBY
        # frozen_string_literal: true

        require "json"

        puts JSON.generate({
          "ok" => false,
          "skill" => #{skill_id.inspect},
          "lifecycle_state" => "blocked_for_human_review",
          "reason" => "Beta implementation has not been completed or reviewed."
        })
      RUBY
    end

    def beta_implementation_pack(directory, skill_id)
      <<~MARKDOWN
        # Beta Implementation Task Pack

        Skill ID: `#{skill_id}`

        Proposal: `#{relative(directory)}`

        ## Allowed files

        Only files below `#{relative(File.join(directory, BETA_DIR))}/`.

        ## Required work

        - Implement one self-contained `skill.rb` entrypoint.
        - Replace placeholder manifest risk, confirmation, tests, weaknesses, and failure behavior.
        - Keep `implementation_complete: false` until deterministic tests and the review artifact are complete.
        - Write `test_results.json` bound to the current Beta digest.

        ## Boundaries

        - Do not modify `Soul/skills/registry.yaml` or production skill paths.
        - Do not invoke cloud providers or read secrets unless a later human-approved skill brief explicitly allows it.
        - Do not add services, daemons, watchers, schedules, or background continuation.
        - Do not weaken confirmation, path, memory, or human-review gates.
        - Codex output remains candidate material for human review.
      MARKDOWN
    end

    def beta_review_artifact(skill_id)
      <<~MARKDOWN
        # Beta Skill Candidate Review: #{skill_id}

        ## Implementation summary

        Pending.

        ## Files changed

        Pending.

        ## Commands run

        Pending.

        ## Deterministic test results

        Pending.

        ## Local LLM eval results

        Pending or not required.

        ## Known weaknesses

        - Implementation has not started.

        ## Memory keys

        None declared.

        ## Lifecycle states touched

        `blocked_for_human_review`

        ## Risk classification

        Unclassified pending implementation.

        ## Human review checklist

        - [ ] Behavior is implemented rather than scaffolded.
        - [ ] Required deterministic tests pass against the current digest.
        - [ ] Safety, memory, path, persistence, and confirmation boundaries are reviewed.
        - [ ] Known weaknesses and rollback are acceptable.
      MARKDOWN
    end

    def dev_build_scope(directory, manifest, proposal_directory)
      {
        "operation" => "skill_studio_dev_beta_build",
        "beta_id" => manifest.fetch("skill_id"),
        "proposal_id" => File.basename(proposal_directory),
        "proposal_digest" => proposal_digest(proposal_directory),
        "beta_digest" => beta_digest(directory, manifest),
        "gate_1_digest" => read_state(proposal_directory).dig("proposal_gate", "proposal_digest"),
        "implementation_complete" => manifest["implementation_complete"] == true,
        "allowed_root" => relative(directory),
        "model" => LocalDevelopmentModelClient::MODEL,
        "model_digest" => DevModelRuntimeCoordinator::DEFAULT_DIGEST,
        "test_limit" => DEV_TEST_LIMIT,
        "network_access" => false,
        "production_mutation" => false,
        "vault_access" => false
      }
    end

    def dev_build_messages(directory, manifest, proposal_directory)
      proposal = read_text(File.join(proposal_directory, "proposal.md"))
      implementation = read_text(File.join(directory, "IMPLEMENTATION.md"))
      [{
        "role" => "system",
        "content" => <<~PROMPT
          You are Soul's local Dev Core drafting one candidate Beta skill after human Gate 1 approval.
          Return only the requested JSON object. Produce a self-contained Ruby CLI that reads bounded argv and prints exactly one JSON object.
          Allowed runtime libraries: json, time, digest, uri. No shell commands, subprocesses, network, sockets, filesystem writes,
          persistent processes, threads, dynamic loading, eval, secrets, credentials, private memory, or production mutation.
          Every path remains inside the proposal-local Beta workspace. The candidate is not production and must end at human review.
          Declare 1..#{DEV_TEST_LIMIT} deterministic tests. Each test must use argv only and expect ok plus a lifecycle state.
        PROMPT
      }, {
        "role" => "user",
        "content" => <<~PROMPT
          Skill ID: #{manifest.fetch("skill_id")}

          Approved proposal:
          #{proposal}

          Existing bounded implementation task pack:
          #{implementation}

          Draft the smallest complete read-only Beta candidate. If the proposal cannot be safely implemented within these bounds,
          return a candidate whose default behavior clearly ends blocked_for_human_review and name the missing authority as a weakness.
        PROMPT
      }]
    end

    def dev_build_schema
      {
        "type" => "object",
        "additionalProperties" => false,
        "required" => %w[description risk requires_approval confirmation_phrase expected_output timeout_seconds inputs known_weaknesses failure_behavior skill_rb test_cases],
        "properties" => {
          "description" => { "type" => "string", "maxLength" => 500 },
          "risk" => { "type" => "string", "enum" => ["read_only"] },
          "requires_approval" => { "type" => "boolean" },
          "confirmation_phrase" => { "type" => "string", "maxLength" => 80 },
          "expected_output" => { "type" => "string", "enum" => ["json"] },
          "timeout_seconds" => { "type" => "integer", "minimum" => 1, "maximum" => MAX_TIMEOUT_SECONDS },
          "inputs" => { "type" => "array", "maxItems" => 20, "items" => { "type" => "string", "maxLength" => 200 } },
          "known_weaknesses" => { "type" => "array", "maxItems" => 20, "items" => { "type" => "string", "maxLength" => 500 } },
          "failure_behavior" => { "type" => "array", "minItems" => 1, "maxItems" => 20, "items" => { "type" => "string", "maxLength" => 500 } },
          "skill_rb" => { "type" => "string", "maxLength" => MAX_TEXT_BYTES },
          "test_cases" => {
            "type" => "array", "minItems" => 1, "maxItems" => DEV_TEST_LIMIT,
            "items" => {
              "type" => "object", "additionalProperties" => false,
              "required" => %w[id description args expected_ok expected_lifecycle],
              "properties" => {
                "id" => { "type" => "string", "pattern" => "^[a-z][a-z0-9_-]{1,63}$" },
                "description" => { "type" => "string", "maxLength" => 300 },
                "args" => { "type" => "array", "maxItems" => MAX_ARGS, "items" => { "type" => "string", "maxLength" => MAX_ARG_BYTES } },
                "expected_ok" => { "type" => "boolean" },
                "expected_lifecycle" => { "type" => "string", "enum" => %w[complete failed awaiting_input canceled blocked_for_human_review] }
              }
            }
          }
        }
      }
    end

    def validate_dev_candidate(value, beta_id)
      source = value["skill_rb"].to_s
      tests = value["test_cases"]
      return failed("Dev candidate source is empty or exceeds the Beta text limit") if source.empty? || source.bytesize > MAX_TEXT_BYTES
      return failed("Dev candidate uses an operation outside the read-only Beta boundary") if source.match?(DEV_SOURCE_DENY)
      return failed("Dev candidate tests are invalid") unless tests.is_a?(Array) && tests.length.between?(1, DEV_TEST_LIMIT)
      return failed("Dev candidate test IDs must be unique and bounded") unless tests.all? { |item| item.is_a?(Hash) && item["id"].to_s.match?(/\A[a-z][a-z0-9_-]{1,63}\z/) } && tests.map { |item| item["id"] }.uniq.length == tests.length
      return failed("Dev candidate test arguments are invalid") unless tests.all? { |item| validate_args(item["args"]).is_a?(Array) }
      return failed("Dev candidate risk must remain read-only") unless value["risk"] == "read_only"
      phrase = value["confirmation_phrase"].to_s
      return failed("Dev candidate confirmation phrase is invalid") if value["requires_approval"] == true && !phrase.match?(/\A[A-Z][A-Z0-9_ ]{7,79}\z/)

      {
        "skill_id" => beta_id,
        "description" => value["description"].to_s[0, 500],
        "risk" => "read_only",
        "requires_approval" => value["requires_approval"] == true,
        "confirmation_phrase" => phrase,
        "expected_output" => "json",
        "timeout_seconds" => value["timeout_seconds"].to_i.clamp(1, MAX_TIMEOUT_SECONDS),
        "inputs" => Array(value["inputs"]).map { |item| item.to_s[0, 200] }.first(20),
        "known_weaknesses" => Array(value["known_weaknesses"]).map { |item| item.to_s[0, 500] }.first(20),
        "failure_behavior" => Array(value["failure_behavior"]).map { |item| item.to_s[0, 500] }.first(20),
        "skill_rb" => source,
        "test_cases" => tests.first(DEV_TEST_LIMIT)
      }
    end

    def materialize_and_test_dev_candidate(directory, previous_manifest, candidate, response)
      staging = File.join(directory, ".dev-build-#{SecureRandom.hex(6)}")
      Dir.mkdir(staging, 0o700)
      source_path = File.join(staging, "skill.rb")
      File.write(source_path, candidate.fetch("skill_rb"), mode: "w", perm: 0o600)
      required_tests = [{ "id" => "ruby-syntax", "description" => "Ruby parser accepts the exact candidate", "kind" => "deterministic" }] +
                       candidate.fetch("test_cases").map { |item| item.slice("id", "description").merge("kind" => "deterministic") }
      manifest = previous_manifest.merge(
        "description" => candidate.fetch("description"), "risk" => candidate.fetch("risk"),
        "entrypoint" => "skill.rb", "implementation_complete" => true,
        "timeout_seconds" => candidate.fetch("timeout_seconds"),
        "requires_approval" => candidate.fetch("requires_approval"),
        "confirmation_phrase" => candidate.fetch("confirmation_phrase"),
        "writes_files" => false, "expected_output" => "json", "verifier" => "schema_basic",
        "lifecycle_states" => %w[complete failed awaiting_input canceled blocked_for_human_review],
        "inputs" => candidate.fetch("inputs"), "required_tests" => required_tests,
        "known_weaknesses" => candidate.fetch("known_weaknesses"),
        "failure_behavior" => candidate.fetch("failure_behavior"),
        "development_provider" => "local.dev", "development_model" => LocalDevelopmentModelClient::MODEL,
        "development_model_digest" => DevModelRuntimeCoordinator::DEFAULT_DIGEST
      )
      write_json(File.join(staging, BETA_MANIFEST), manifest)
      results = []
      syntax = @runner.run(@ruby_path, "--disable-gems", "-c", source_path, timeout_seconds: 10, max_output_bytes: MAX_OUTPUT_BYTES)
      results << { "id" => "ruby-syntax", "passed" => syntax.success?, "stdout" => truncate(syntax.stdout), "stderr" => truncate(syntax.stderr) }
      candidate.fetch("test_cases").each do |test|
        execution = run_isolated_dev_test(staging, test, manifest.fetch("timeout_seconds"))
        results << execution.merge("id" => test.fetch("id"))
      end
      passed = results.all? { |item| item["passed"] == true }
      manifest["implementation_complete"] = passed
      write_json(File.join(staging, BETA_MANIFEST), manifest)
      candidate_digest = beta_digest(staging, manifest)
      test_results = {
        "schema_version" => "soul.beta_tests.v1", "tested_at" => now,
        "beta_digest" => candidate_digest, "passed" => passed, "results" => results
      }
      write_json(File.join(staging, TEST_RESULTS), test_results)
      File.write(File.join(staging, "REVIEW.md"), dev_candidate_review(candidate, response, results, passed), mode: "w", perm: 0o600)
      %w[skill.rb beta_manifest.json test_results.json REVIEW.md].each do |name|
        File.rename(File.join(staging, name), File.join(directory, name))
      end
      FileUtils.remove_entry_secure(staging)
      {
        "implementation_complete" => passed,
        "test_summary" => { "declared" => results.length, "passed" => results.count { |item| item["passed"] }, "failed" => results.count { |item| !item["passed"] } },
        "beta_digest" => candidate_digest,
        "package_path" => relative(directory),
        "review_artifact" => relative(File.join(directory, "REVIEW.md")),
        "lifecycle_state" => passed ? "blocked_for_human_review" : "failed"
      }
    ensure
      FileUtils.remove_entry_secure(staging) if staging && File.directory?(staging) && File.dirname(staging) == directory
    end

    def run_isolated_dev_test(staging, test, timeout_seconds)
      return { "passed" => false, "reason" => "bubblewrap is unavailable" } unless safe_test_executable?(@bwrap_path) && safe_test_executable?(@ruby_path)
      command = [@bwrap_path, "--unshare-all", "--die-with-parent", "--new-session", "--ro-bind", "/usr", "/usr"]
      command.concat(["--ro-bind", "/lib", "/lib"]) if File.directory?("/lib")
      command.concat(["--ro-bind", "/lib64", "/lib64"]) if File.directory?("/lib64")
      command.concat(["--proc", "/proc", "--dev", "/dev", "--tmpfs", "/tmp", "--ro-bind", staging, "/work", "--chdir", "/work", @ruby_path, "--disable-gems", "skill.rb"])
      command.concat(test.fetch("args"))
      result = @runner.run(*command, timeout_seconds: timeout_seconds, max_output_bytes: MAX_OUTPUT_BYTES)
      parsed = JSON.parse(result.stdout.to_s.lines.last.to_s)
      passed = result.success? && parsed["ok"] == test.fetch("expected_ok") && parsed["lifecycle_state"] == test.fetch("expected_lifecycle")
      { "passed" => passed, "exit_status" => result.exit_status, "stdout" => truncate(result.stdout), "stderr" => truncate(result.stderr) }
    rescue JSON::ParserError, KeyError => error
      { "passed" => false, "reason" => "isolated output was invalid: #{error.class}", "stdout" => truncate(result&.stdout), "stderr" => truncate(result&.stderr) }
    end

    def safe_test_executable?(path)
      stat = File.lstat(path)
      stat.file? && !stat.symlink? && File.executable?(path)
    rescue Errno::ENOENT, Errno::EACCES
      false
    end

    def dev_candidate_review(candidate, response, results, passed)
      <<~MARKDOWN
        # Beta Skill Candidate Review: #{candidate.fetch("skill_id")}

        ## Implementation summary

        Locally drafted by GPT-OSS and #{passed ? "accepted by" : "stopped at"} the isolated deterministic machine-test gate.

        ## Files changed

        - `skill.rb`
        - `beta_manifest.json`
        - `test_results.json`
        - `REVIEW.md`

        ## Commands run

        - Ruby syntax check with gems disabled
        - #{candidate.fetch("test_cases").length} networkless bubblewrap behavior test(s)

        ## Deterministic test results

        #{results.map { |item| "- #{item.fetch('id')}: #{item['passed'] ? 'passed' : 'failed'}" }.join("\n")}

        ## Local LLM eval results

        Provider `local.dev`; model `#{LocalDevelopmentModelClient::MODEL}`; request duration #{response.duration_seconds}s. LLM output did not decide safety or promotion.

        ## Known weaknesses

        #{candidate.fetch("known_weaknesses").map { |item| "- #{item}" }.join("\n")}

        ## Memory keys

        None. Soul Vault was not read or written.

        ## Lifecycle states touched

        `#{passed ? 'blocked_for_human_review' : 'failed'}`

        ## Risk classification

        `read_only`; generated candidates are denied shell, subprocess, network, persistence, and file-write APIs.

        ## Human review checklist

        - [ ] Read the complete generated entrypoint.
        - [ ] Confirm declared inputs, outputs, failure behavior, and weaknesses match the approved proposal.
        - [ ] Invoke the Beta manually with representative arguments.
        - [ ] Approve Gate 2 only after reviewing current-revision test and diagnostic evidence.
      MARKDOWN
    end

    def development_model_client
      @development_model_client ||= LocalDevelopmentModelClient.new(root: @root)
    end

    def progress(callback, stage, message)
      callback&.call("stage" => stage, "message" => message)
    rescue StandardError
      nil
    end

    def digest(value)
      Digest::SHA256.hexdigest(JSON.generate(canonicalize(value)))
    end

    def canonicalize(value)
      case value
      when Hash then value.keys.map(&:to_s).sort.to_h { |key| [key, canonicalize(value.fetch(key))] }
      when Array then value.map { |item| canonicalize(item) }
      else value
      end
    end

    def production_promotion_context(beta_id)
      located = locate_beta(beta_id)
      return awaiting("unknown Beta skill ID") unless located
      directory, manifest, proposal_directory = located
      return blocked("canonical dotted Beta skill ID is required") unless valid_skill_id?(beta_id)
      record = beta_projection(directory, manifest, proposal_directory, detail: true)
      return blocked("legacy alpha scaffold cannot be promoted") if record["maturity"] == "legacy_alpha_scaffold"
      blockers = promotion_blockers(record, proposal_directory)
      state = read_state(proposal_directory)
      current_digest = beta_digest(directory, manifest)
      blockers << "Human Gate 2 is not approved for this exact Beta revision" unless state.dig("beta_gate", "status") == "approved_for_promotion" && secure_equal?(state.dig("beta_gate", "beta_digest"), current_digest)
      entrypoint = manifest["entrypoint"].to_s
      source = File.expand_path(entrypoint, directory)
      blockers << "production promotion requires the self-contained skill.rb entrypoint" unless entrypoint == "skill.rb"
      blockers << "Beta entrypoint must not be a symlink" if File.symlink?(source)
      blockers << "Beta entrypoint exceeds #{MAX_TEXT_BYTES} bytes" if File.file?(source) && File.size(source) > MAX_TEXT_BYTES
      blockers << "Beta risk classification is incomplete" if manifest["risk"].to_s.empty? || manifest["risk"] == "unclassified"
      blockers << "Beta confirmation phrase is still a placeholder" if manifest["confirmation_phrase"] == "REPLACE_WITH_REVIEWED_CONFIRMATION"
      target = File.join(full(PRODUCTION_ROOT), beta_id)
      blockers << "generated production root must not be a symlink" if File.symlink?(full(PRODUCTION_ROOT))
      registry_path = full(REGISTRY_PATH)
      blockers << "production registry must be a regular non-symlink file" unless File.file?(registry_path) && !File.symlink?(registry_path)
      blockers << "production skill ID already exists" if production_definition(beta_id)
      blockers << "production target directory already exists" if File.exist?(target) || File.symlink?(target)
      return blocked("Beta cannot be promoted: #{blockers.join('; ')}") unless blockers.empty?

      definition = {
        "path" => relative(File.join(target, "skill.rb")),
        "language" => "ruby",
        "description" => manifest["description"].to_s[0, 500],
        "risk" => manifest["risk"].to_s,
        "requires_approval" => manifest["requires_approval"] == true,
        "writes_files" => manifest["writes_files"] == true,
        "expected_output" => manifest["expected_output"].to_s.empty? ? "json" : manifest["expected_output"].to_s,
        "verifier" => manifest["verifier"].to_s.empty? ? "schema_basic" : manifest["verifier"].to_s
      }
      phrase = manifest["confirmation_phrase"].to_s
      definition["confirmation_phrase"] = phrase if definition["requires_approval"] && !phrase.empty?
      {
        "beta_id" => beta_id,
        "proposal_id" => File.basename(proposal_directory),
        "beta_digest" => current_digest,
        "source_entrypoint" => relative(source),
        "source_sha256" => Digest::SHA256.file(source).hexdigest,
        "production_directory" => relative(target),
        "production_entrypoint" => relative(File.join(target, "skill.rb")),
        "registry_definition" => definition,
        "registry_path" => REGISTRY_PATH
      }
    end

    def production_promotion_digest(context)
      registry_path = full(REGISTRY_PATH)
      Digest::SHA256.hexdigest(JSON.generate(context.merge(
        "registry_sha256" => Digest::SHA256.file(registry_path).hexdigest,
        "target_absent" => !File.exist?(full(context.fetch("production_directory")))
      )))
    end

    def write_registry_with_new_skill(path, skill_id, definition)
      raise "production registry must not be a symlink" if File.symlink?(path)
      mode = File.stat(path).mode & 0o777
      data = YAML.safe_load(File.read(path), permitted_classes: [], aliases: false)
      raise "production registry is invalid" unless data.is_a?(Hash) && data["skills"].is_a?(Hash)
      raise "production skill ID already exists" if data.fetch("skills").key?(skill_id)
      updated = Marshal.load(Marshal.dump(data))
      updated.fetch("skills")[skill_id] = definition
      temporary = "#{path}.tmp-#{Process.pid}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, mode) do |file|
        file.write(YAML.dump(updated))
        file.flush
        file.fsync
      end
      File.rename(temporary, path)
      File.chmod(mode, path)
    ensure
      File.delete(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
    end

    def proposal_directories
      base = full(PROPOSALS_ROOT)
      return [] unless Dir.exist?(base)

      Dir.children(base).sort.reverse.filter_map do |name|
        next unless safe_id?(name)
        path = File.join(base, name)
        path if File.directory?(path) && File.file?(File.join(path, "metadata.json")) && File.file?(File.join(path, "proposal.md"))
      end
    end

    def proposal_directory(proposal_id)
      return nil unless safe_id?(proposal_id)
      candidate = File.join(full(PROPOSALS_ROOT), proposal_id)
      return nil unless inside?(candidate, full(PROPOSALS_ROOT)) && File.directory?(candidate)
      return nil unless File.file?(File.join(candidate, "metadata.json")) && File.file?(File.join(candidate, "proposal.md"))

      candidate
    end

    def proposal_projection(directory, detail: false)
      metadata = read_json(File.join(directory, "metadata.json"))
      return nil unless metadata.is_a?(Hash)

      proposal_text = read_text(File.join(directory, "proposal.md"))
      state = read_state(directory)
      beta_manifest = read_json(File.join(directory, BETA_DIR, BETA_MANIFEST))
      linked_skill_id = beta_manifest.is_a?(Hash) ? beta_manifest["skill_id"].to_s : ""
      linked_skill_id = nil if linked_skill_id.empty?
      production_registered = !linked_skill_id.nil? && production_definition(linked_skill_id).is_a?(Hash)
      title = proposal_text[/^#\s+(?:Skill Proposal:\s*)?(.+)$/, 1] || metadata["title"] || metadata["idea"] || File.basename(directory)
      record = {
        "proposal_id" => File.basename(directory),
        "title" => title.to_s.strip[0, 240],
        "description" => proposal_section(proposal_text, "Purpose") || metadata["idea"].to_s[0, 500],
        "created_at" => metadata["created_at"],
        "provider" => metadata["provider"],
        "model" => metadata["model"],
        "proposal_gate" => state.dig("proposal_gate", "status") || "awaiting_review",
        "beta_gate" => state.dig("beta_gate", "status") || "not_ready",
        "proposal_digest" => proposal_digest(directory),
        "human_review_required" => true,
        "beta_present" => beta_manifest.is_a?(Hash),
        "stage" => proposal_stage(directory, state, beta_manifest, production_registered),
        "linked_skill_id" => linked_skill_id,
        "linked_skill_maturity" => production_registered ? "production" : (linked_skill_id ? "beta" : "unbuilt"),
        "production_registered" => production_registered,
        "closable" => production_registered
      }
      if metadata["purpose"] == "capability_gap_intake"
        record["intake"] = true
        record["intake_status"] = state.dig("intake", "status") || metadata["status"] || "awaiting_human_triage"
        record["gap_classification"] = metadata.dig("origin", "classification")
        record["origin_chat_id"] = metadata.dig("origin", "chat_id")
        record["occurrence_count"] = bounded_line_count(File.join(directory, "gap_events.jsonl"), 1_000)
      end
      if detail
        record["proposal_markdown"] = proposal_text
        record["review_checklist"] = checklist_items(File.join(directory, "review_checklist.md"))
        record["cloud_assisted"] = !metadata["provider"].to_s.empty?
        record["cloud_data_class"] = metadata["data_class"]
        record["secrets_included"] = metadata["secrets_included"] == true
        if record["intake"]
          record["request_summary"] = metadata["request_summary"].to_s[0, 4_096]
          record["gap_reason"] = metadata.dig("origin", "reason").to_s[0, 500]
          record["declared_capability_id"] = metadata.dig("origin", "capability_id")
          record["automatic_cloud_use"] = false
        end
      end
      record
    rescue JSON::ParserError, Errno::ENOENT
      nil
    end

    def beta_records
      canonical = proposal_directories.filter_map do |proposal_directory|
        beta_directory = File.join(proposal_directory, BETA_DIR)
        manifest = read_json(File.join(beta_directory, BETA_MANIFEST))
        beta_projection(beta_directory, manifest, proposal_directory) if manifest.is_a?(Hash)
      end
      legacy = legacy_alpha_directories.filter_map do |alpha_directory|
        manifest = read_json(File.join(alpha_directory, "alpha_manifest.json")) || {}
        beta_projection(alpha_directory, manifest.merge("skill_id" => "legacy.#{File.basename(File.dirname(alpha_directory))}"), File.dirname(alpha_directory), legacy: true)
      end
      (canonical + legacy).sort_by { |record| record["beta_id"] }
    end

    def legacy_alpha_directories
      base = full(LEGACY_PROPOSALS_ROOT)
      return [] unless Dir.exist?(base)
      Dir.glob(File.join(base, "*", "alpha")).select { |path| File.directory?(path) && inside?(path, base) }
    end

    def locate_beta(beta_id)
      beta_records.each do |record|
        next unless record["beta_id"] == beta_id
        directory = full(record.fetch("package_path"))
        manifest_name = record["maturity"] == "legacy_alpha_scaffold" ? "alpha_manifest.json" : BETA_MANIFEST
        manifest = read_json(File.join(directory, manifest_name)) || {}
        manifest = manifest.merge("skill_id" => beta_id) if record["maturity"] == "legacy_alpha_scaffold"
        return [directory, manifest, File.dirname(directory)]
      end
      nil
    end

    def beta_projection(directory, manifest, proposal_directory, detail: false, legacy: false)
      entrypoint = manifest["entrypoint"].to_s
      entrypoint_path = File.expand_path(entrypoint, directory) unless entrypoint.empty?
      safe_entrypoint = entrypoint_path && inside?(entrypoint_path, directory) && File.file?(entrypoint_path)
      tests = read_json(File.join(directory, TEST_RESULTS)) || {}
      digest = legacy ? nil : beta_digest(directory, manifest)
      required_tests = Array(manifest["required_tests"]).first(50).map do |item|
        item.is_a?(Hash) ? item.slice("id", "description", "kind") : { "id" => item.to_s, "description" => item.to_s }
      end
      record = {
        "beta_id" => manifest["skill_id"].to_s.empty? ? "invalid.#{File.basename(proposal_directory)}" : manifest["skill_id"].to_s,
        "proposal_id" => File.basename(proposal_directory),
        "description" => (manifest["description"] || manifest["summary"] || "Legacy alpha behavior scaffold").to_s[0, 500],
        "maturity" => legacy ? "legacy_alpha_scaffold" : "beta",
        "risk" => (manifest["risk"] || "unknown").to_s,
        "lifecycle_states" => Array(manifest["lifecycle_states"]).map(&:to_s).first(10),
        "implementation_complete" => manifest["implementation_complete"] == true,
        "runnable" => !legacy && manifest["implementation_complete"] == true && safe_entrypoint,
        "required_tests" => required_tests,
        "test_summary" => test_summary(tests, digest),
        "beta_digest" => digest,
        "package_path" => relative(directory),
        "diagnostic_log_available_after_run" => !legacy,
        "production_registered" => production_definition(manifest["skill_id"].to_s).is_a?(Hash),
        "promotion_state" => read_state(proposal_directory).dig("beta_gate", "status") || "not_ready"
      }
      if detail
        record["known_weaknesses"] = Array(manifest["known_weaknesses"]).map(&:to_s).first(20)
        record["inputs"] = Array(manifest["inputs"]).first(20)
        record["failure_behavior"] = Array(manifest["failure_behavior"]).map(&:to_s).first(20)
        record["test_results"] = Array(tests["results"]).first(50)
        record["entrypoint_valid"] = !!safe_entrypoint
      end
      record
    end

    def test_summary(tests, digest)
      results = Array(tests["results"])
      {
        "declared" => results.length,
        "passed" => results.count { |item| item.is_a?(Hash) && item["passed"] == true },
        "failed" => results.count { |item| !item.is_a?(Hash) || item["passed"] != true },
        "suite_passed" => tests["passed"] == true,
        "tested_current_revision" => !digest.nil? && secure_equal?(tests["beta_digest"], digest),
        "tested_at" => tests["tested_at"]
      }
    end

    def promotion_blockers(record, proposal_directory)
      blockers = []
      blockers << "proposal Gate 1 is not approved" unless read_state(proposal_directory).dig("proposal_gate", "status") == "approved"
      blockers << "Beta implementation is incomplete" unless record["implementation_complete"]
      blockers << "Beta entrypoint is invalid" unless record["entrypoint_valid"]
      blockers << "no required tests are declared" if record["required_tests"].empty?
      blockers << "test suite has not passed" unless record.dig("test_summary", "suite_passed")
      blockers << "test evidence does not match the current Beta revision" unless record.dig("test_summary", "tested_current_revision")
      required_ids = record["required_tests"].map { |item| item["id"].to_s }.reject(&:empty?)
      passing_ids = Array(record["test_results"]).filter_map { |item| item["id"].to_s if item.is_a?(Hash) && item["passed"] == true }
      missing = required_ids - passing_ids
      blockers << "required tests are not passing: #{missing.join(', ')}" unless missing.empty?
      blockers
    end

    def proposal_stage(directory, state, beta_manifest, production_registered)
      return "production" if production_registered
      return "approved_for_promotion" if state.dig("beta_gate", "status") == "approved_for_promotion"
      return state.dig("proposal_gate", "status") == "approved" ? "approved_for_beta_build" : "awaiting_proposal_review" unless beta_manifest.is_a?(Hash)

      beta_directory = File.join(directory, BETA_DIR)
      beta = beta_projection(beta_directory, beta_manifest, directory, detail: true)
      return "beta_build" unless beta["implementation_complete"] && beta["runnable"]
      return "ready_for_promotion_review" if promotion_blockers(beta, directory).empty?

      "beta_testing"
    end

    def closeout_context(directory)
      record = proposal_projection(directory)
      {
        "proposal_id" => File.basename(directory),
        "title" => record["title"],
        "stage" => record["stage"],
        "linked_skill_id" => record["linked_skill_id"],
        "production_registered" => record["production_registered"],
        "proposal_path" => relative(directory)
      }
    end

    def closeout_digest(directory, context)
      manifest = read_json(File.join(directory, BETA_DIR, BETA_MANIFEST)) || {}
      definition = production_definition(context["linked_skill_id"]) || {}
      Digest::SHA256.hexdigest(JSON.generate({
        "proposal_digest" => proposal_digest(directory),
        "beta_digest" => manifest.empty? ? nil : beta_digest(File.join(directory, BETA_DIR), manifest),
        "studio_state" => read_state(directory),
        "linked_skill_id" => context["linked_skill_id"],
        "production_definition" => definition
      }))
    end

    def production_definition(skill_id)
      return nil if skill_id.to_s.empty?
      definition = production_registry.list[skill_id.to_s]
      definition if definition.is_a?(Hash) && !definition["path"].to_s.empty?
    end

    def production_registry
      @production_registry || SkillRegistry.new(path: full("Soul/skills/registry.yaml"))
    end

    def execute_beta(directory, manifest, args)
      entrypoint = File.expand_path(manifest.fetch("entrypoint"), directory)
      timeout_seconds = execution_timeout(manifest)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      isolated = manifest["development_provider"] == "local.dev"
      if isolated && (!safe_test_executable?(@bwrap_path) || !safe_test_executable?(@ruby_path))
        return { "ok" => false, "exit_status" => nil, "timed_out" => false, "duration_ms" => 0, "stdout" => "", "stderr" => "networkless Beta sandbox is unavailable", "output_truncated" => false }
      end
      command = isolated ? isolated_beta_command(directory, args) : [@ruby_path, entrypoint, *args]
      result = @runner.run(*command, timeout_seconds: timeout_seconds, max_output_bytes: MAX_OUTPUT_BYTES, chdir: isolated ? nil : directory)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      {
        "ok" => result.success?,
        "exit_status" => result.exit_status,
        "timed_out" => result.status == "timeout",
        "duration_ms" => duration_ms,
        "stdout" => truncate(result.stdout),
        "stderr" => truncate(result.stderr),
        "output_truncated" => result.truncated == true
      }
    rescue StandardError => error
      { "ok" => false, "exit_status" => nil, "timed_out" => false, "duration_ms" => 0, "stdout" => "", "stderr" => "#{error.class}: #{error.message}"[0, 1000], "output_truncated" => false }
    end

    def isolated_beta_command(directory, args)
      command = [@bwrap_path, "--unshare-all", "--die-with-parent", "--new-session", "--ro-bind", "/usr", "/usr"]
      command.concat(["--ro-bind", "/lib", "/lib"]) if File.directory?("/lib")
      command.concat(["--ro-bind", "/lib64", "/lib64"]) if File.directory?("/lib64")
      command.concat(["--proc", "/proc", "--dev", "/dev", "--tmpfs", "/tmp", "--ro-bind", directory, "/work", "--chdir", "/work", @ruby_path, "--disable-gems", "skill.rb"])
      command.concat(args)
    end

    def append_beta_log(beta_id, digest, argument_count, result)
      safe_name = beta_id.gsub(/[^A-Za-z0-9_.-]/, "_")
      directory = full("Soul/logs/beta_skills")
      FileUtils.mkdir_p(directory)
      path = File.join(directory, "#{safe_name}.jsonl")
      record = {
        "schema_version" => "soul.beta_diagnostic.v1",
        "timestamp" => now,
        "beta_id" => beta_id,
        "beta_digest" => digest,
        "argument_count" => argument_count,
        "ok" => result["ok"],
        "exit_status" => result["exit_status"],
        "timed_out" => result["timed_out"],
        "duration_ms" => result["duration_ms"],
        "stdout" => result["stdout"],
        "stderr" => result["stderr"],
        "output_truncated" => result["output_truncated"]
      }
      File.open(path, "a", 0o600) { |file| file.puts(JSON.generate(record)) }
      path
    end

    def validate_args(args)
      return failed("Beta args must be an array") unless args.is_a?(Array)
      return failed("Beta args exceed #{MAX_ARGS}") if args.length > MAX_ARGS
      return failed("Beta args must be strings") unless args.all? { |item| item.is_a?(String) }
      return failed("a Beta argument exceeds #{MAX_ARG_BYTES} bytes") if args.any? { |item| item.bytesize > MAX_ARG_BYTES }
      args
    end

    def execution_timeout(manifest)
      value = manifest.fetch("timeout_seconds", 30).to_i
      [[value, 1].max, MAX_TIMEOUT_SECONDS].min
    end

    def proposal_digest(directory)
      digest_files(directory, %w[metadata.json proposal.md review_checklist.md sources.md])
    end

    def beta_digest(directory, manifest)
      entrypoint = manifest["entrypoint"].to_s
      files = [BETA_MANIFEST]
      files << entrypoint if !entrypoint.empty? && inside?(File.expand_path(entrypoint, directory), directory)
      digest_files(directory, files)
    end

    def digest_files(directory, names)
      digest = Digest::SHA256.new
      names.sort.each do |name|
        path = File.expand_path(name, directory)
        next unless inside?(path, directory) && File.file?(path)
        digest << name << "\0" << File.binread(path) << "\0"
      end
      digest.hexdigest
    end

    def read_state(directory)
      read_json(File.join(directory, STATE_FILE)) || {}
    end

    def read_json(path)
      JSON.parse(File.read(path, MAX_TEXT_BYTES))
    rescue Errno::ENOENT, JSON::ParserError, ArgumentError
      nil
    end

    def read_text(path)
      File.read(path, MAX_TEXT_BYTES).encode("UTF-8", invalid: :replace, undef: :replace, replace: "�")
    end

    def checklist_items(path)
      return [] unless File.file?(path)
      read_text(path).lines.filter_map do |line|
        match = line.match(/^\s*-\s*\[([ xX])\]\s*(.+)$/)
        { "complete" => !match[1].casecmp("x").nonzero?, "text" => match[2].strip[0, 500] } if match
      end.first(50)
    end

    def bounded_line_count(path, limit)
      return 0 unless File.file?(path)
      File.foreach(path).take(limit + 1).length.clamp(0, limit)
    rescue StandardError
      0
    end

    def proposal_section(text, heading)
      match = text.match(/^##\s+#{Regexp.escape(heading)}\s*$\n(.*?)(?=^##\s+|\z)/mi)
      return nil unless match
      match[1].strip.gsub(/\s+/, " ")[0, 500]
    end

    def write_json(path, value)
      temporary = "#{path}.tmp-#{Process.pid}"
      File.open(temporary, "w", 0o600) { |file| file.write(JSON.pretty_generate(value)); file.write("\n") }
      File.rename(temporary, path)
    ensure
      File.delete(temporary) if temporary && File.exist?(temporary)
    end

    def safe_id?(value)
      value.to_s.match?(/\A[A-Za-z0-9][A-Za-z0-9_.-]{0,199}\z/)
    end

    def inside?(path, boundary)
      expanded = File.expand_path(path)
      root = File.expand_path(boundary)
      expanded == root || expanded.start_with?("#{root}#{File::SEPARATOR}")
    end

    def full(relative_path)
      File.expand_path(relative_path, @root)
    end

    def relative(path)
      Pathname.new(path).relative_path_from(Pathname.new(@root)).to_s
    end

    def bounded_limit(limit)
      value = limit.to_i
      value = MAX_RECORDS if value <= 0
      [value, MAX_RECORDS].min
    end

    def truncate(value)
      value.to_s.byteslice(0, MAX_OUTPUT_BYTES).to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "�")
    end

    def secure_equal?(left, right)
      left = left.to_s
      right = right.to_s
      return false unless left.bytesize == right.bytesize && !left.empty?
      left.bytes.zip(right.bytes).reduce(0) { |memo, (a, b)| memo | (a ^ b) }.zero?
    end

    def now
      @clock.call.utc.iso8601
    end

    def success(data, lifecycle: "complete", mutation: "none")
      { "ok" => lifecycle == "complete", "lifecycle_state" => lifecycle, "mutation" => mutation, "data" => data }
    end

    def awaiting(reason)
      { "ok" => false, "lifecycle_state" => "awaiting_input", "mutation" => "none", "data" => { "reason" => reason } }
    end

    def blocked(reason)
      { "ok" => false, "lifecycle_state" => "blocked_for_human_review", "mutation" => "none", "data" => { "reason" => reason } }
    end

    def failed(reason)
      { "ok" => false, "lifecycle_state" => "failed", "mutation" => "none", "data" => { "reason" => reason } }
    end
  end
end
