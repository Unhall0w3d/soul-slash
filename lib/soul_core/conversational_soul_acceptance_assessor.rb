# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require "yaml"
require_relative "application_facade"
require_relative "bounded_host_system_status_assessor"
require_relative "chat_store"
require_relative "conversation_memory_store"
require_relative "conversation_orchestrator"
require_relative "conversation_provider_contract"
require_relative "conversation_runtime"
require_relative "phase10_identity_style_foundation_assessor"
require_relative "phase10_recent_style_awareness_assessor"
require_relative "phase11c_bounded_artifact_creation_assessor"
require_relative "skill_studio_service"

module SoulCore
  class ConversationalSoulAcceptanceAssessor
    Contract = ConversationProviderContract
    TURN_LIMIT = 20

    class FixtureRegistry
      def initialize(provider)
        @provider = provider
      end

      def find(id)
        @provider if id.to_s == @provider.id
      end

      def configured
        [@provider]
      end
    end

    class FixtureProviderClient
      attr_reader :requests

      def initialize(fail: false)
        @fail = fail
        @requests = []
      end

      def chat(provider:, request:, timeout_seconds:)
        @requests << request
        if @fail
          return Contract::ResponseEnvelope.new(
            request_id: request.request_id,
            provider_id: provider.id,
            model: provider.model,
            content: "",
            error: { "type" => "synthetic_provider_failure", "message" => "bounded acceptance fixture" }
          )
        end

        user_text = request.messages.reverse.find { |message| message["role"] == "user" }&.fetch("content", "").to_s
        content = if user_text.include?("codename")
                    "The synthetic project codename is Lantern. I will keep the observation and task together."
                  elsif user_text.include?("artifacts/acceptance.md")
                    "# Acceptance Note\n\nSynthetic bounded artifact content."
                  else
                    "Synthetic conversational response #{@requests.length}; the active thread remains available."
                  end
        Contract::ResponseEnvelope.new(
          request_id: request.request_id,
          provider_id: provider.id,
          model: provider.model,
          content: content,
          finish_reason: "stop",
          usage: { "input_tokens" => 16, "output_tokens" => 12 },
          latency_ms: 1.0
        )
      end
    end

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      scenarios = {}
      details = {}

      Dir.mktmpdir("soul-phase13a-") do |temp_root|
        FileUtils.mkdir_p(File.join(temp_root, "artifacts"))
        store = ChatStore.new(root: temp_root)
        provider = fixture_provider
        client = FixtureProviderClient.new
        runtime = ConversationRuntime.new(
          root: temp_root,
          store: store,
          env: fixture_env,
          registry: FixtureRegistry.new(provider),
          provider_client: client
        )
        facade = ApplicationFacade.new(
          root: temp_root,
          process_env: fixture_env,
          chat_store: store,
          conversation_runtime: runtime
        )

        created = call(facade, "chats.create", { "title" => "Phase 13 integrated acceptance" }, 0)
        chat_id = created.dig("data", "record", "id")
        results = acceptance_turns.each_with_index.map do |message, index|
          call(facade, "chats.send", { "chat_id" => chat_id, "message" => message }, index + 1)
        end
        messages = store.messages(chat_id)
        provider_messages = client.requests.flat_map(&:messages)

        scenarios["mixed_commentary_and_task"] =
          results.first.fetch("lifecycle_state") == "complete" &&
          results.first.dig("data", "result", "content").to_s.include?("Lantern")

        scenarios["multi_turn_continuity"] =
          results.length == TURN_LIMIT && results.all? { |result| result["lifecycle_state"] == "complete" } &&
          messages.count { |message| message["role"] == "user" } == TURN_LIMIT &&
          messages.count { |message| message["role"] == "assistant" } == TURN_LIMIT &&
          provider_messages.any? { |message| message["content"].to_s.include?("Lantern") }

        status_result = results[7]
        return_result = results[9]
        status_metadata = status_result.dig("data", "result", "metadata") || {}
        scenarios["skill_invocation_and_return"] =
          Array(status_metadata.dig("orchestration", "tool_ids")).include?("host.system_status") &&
          Array(status_metadata["evidence"]).any? { |item| item["tool_id"] == "host.system_status" } &&
          return_result.fetch("lifecycle_state") == "complete"

        artifact_report = Phase11cBoundedArtifactCreationAssessor.new(root: @root).assess
        scenarios["artifact_instead_of_chat_dumping"] =
          artifact_report["ok"] == true &&
          artifact_report.dig("verification", "creation_preview_is_non_mutating") == true &&
          artifact_report.dig("verification", "confirmed_creation_is_verified_registered_and_attached") == true

        memory_store = ConversationMemoryStore.new(root: temp_root)
        approved_memory = memory_store.records(status: "approved").find { |record| record["content"].include?("Lantern") }
        scenarios["project_state_continuity"] =
          approved_memory && results[6].dig("data", "result", "content").to_s.include?("Lantern")

        failing_runtime = ConversationRuntime.new(
          root: temp_root,
          store: store,
          env: fixture_env,
          registry: FixtureRegistry.new(provider),
          provider_client: FixtureProviderClient.new(fail: true)
        )
        failed = ApplicationFacade.new(root: temp_root, process_env: fixture_env, chat_store: store, conversation_runtime: failing_runtime)
        failure_result = call(failed, "chats.send", { "chat_id" => chat_id, "message" => "Continue safely after the synthetic provider fails." }, 90)
        scenarios["safe_tool_failure"] =
          failure_result["lifecycle_state"] == "complete" &&
          failure_result.dig("data", "result", "mode") == "fallback" &&
          failure_result.dig("data", "result", "content").to_s.include?("unavailable")

        unrelated = ConversationOrchestrator.new.plan(
          message: "Let's discuss organizing local files conceptually; do not inspect or change anything.",
          provider_available: true,
          recent_evidence: []
        )
        scenarios["unrelated_skill_avoidance"] = unrelated.kind == "direct_model" && unrelated.tool_ids.empty?

        identity = Phase10IdentityStyleFoundationAssessor.new(root: @root).assess
        style = Phase10RecentStyleAwarenessAssessor.new(root: @root).assess
        scenarios["conversational_variation"] = identity["ok"] == true && style["ok"] == true

        candidate_result = results[4].dig("data", "result", "content").to_s
        approved_result = results[5].dig("data", "result", "content").to_s
        scenarios["memory_promotion"] =
          candidate_result.include?("Memory candidate created") &&
          approved_result.include?("Memory approved") && !approved_memory.nil?

        gate = exercise_skill_studio_gate(temp_root)
        scenarios["approval_gated_mutation"] = gate.fetch("ok")

        host = BoundedHostSystemStatusAssessor.new(root: @root).assess
        details = {
          "turn_count" => TURN_LIMIT,
          "stored_message_count" => messages.length,
          "provider_request_count" => client.requests.length,
          "host_assessment_ok" => host["ok"],
          "artifact_assessment_ok" => artifact_report["ok"],
          "identity_assessment_ok" => identity["ok"],
          "style_assessment_ok" => style["ok"],
          "skill_studio_gate" => gate,
          "temporary_root_removed_on_return" => true,
          "external_provider_used" => false
        }
        scenarios["skill_invocation_and_return"] &&= host["ok"] == true
      end

      blockers = scenarios.filter_map { |name, passed| name.tr("_", " ") unless passed }
      {
        "ok" => blockers.empty?,
        "assessment" => "conversational_soul_integrated_acceptance",
        "milestone" => "conversational_soul",
        "phase" => "13A",
        "status" => blockers.empty? ? "candidate_ready" : "blocked_for_human_review",
        "lifecycle_state" => blockers.empty? ? "complete" : "blocked_for_human_review",
        "scenario_count" => scenarios.length,
        "scenarios" => scenarios,
        "details" => details,
        "blockers" => blockers,
        "human_review_required" => true
      }
    end

    def render(report = assess)
      lines = [
        "Soul Conversational Milestone Integrated Acceptance",
        "Phase: #{report['phase']}",
        "Status: #{report['status']}",
        "Lifecycle: #{report['lifecycle_state']}",
        "",
        "Scenarios"
      ]
      report.fetch("scenarios").each { |name, passed| lines << "- #{name}: #{passed}" }
      lines << ""
      lines << "Blockers"
      lines.concat(report.fetch("blockers").empty? ? ["- None"] : report.fetch("blockers").map { |item| "- #{item}" })
      lines << ""
      lines << "Human review required: yes"
      lines.join("\n")
    end

    private

    def call(facade, operation, parameters, sequence)
      facade.call({
        "schema_version" => ApplicationContract::SCHEMA_VERSION,
        "request_id" => format("phase13a.request.%03d", sequence),
        "operation" => operation,
        "parameters" => parameters,
        "context" => { "interface" => "internal" }
      })
    end

    def fixture_provider
      Contract::ProviderDefinition.new(
        id: "local.phase13_fixture",
        label: "Phase 13 deterministic fixture",
        transport: "openai_compatible",
        endpoint: "http://127.0.0.1:1/v1",
        model: "phase13-fixture",
        privacy_class: "local_only",
        capabilities: %w[chat structured_output],
        configured: true
      )
    end

    def fixture_env
      {
        "SOUL_CONVERSATION_PROVIDER" => "local.phase13_fixture",
        "SOUL_CONVERSATION_MAX_MESSAGES" => "60",
        "SOUL_CONVERSATION_MAX_CHARACTERS" => "64000",
        "SOUL_CONVERSATION_TIMEOUT_SECONDS" => "2"
      }
    end

    def acceptance_turns
      [
        "Lantern is a dramatic codename, but useful. Please keep it as the synthetic project name and summarize that task.",
        "The synthetic project codename is Lantern.",
        "What codename did I just establish?",
        "That name still works; continue the same project discussion.",
        "Please remember as project: The synthetic acceptance project is named Lantern.",
        "approve memory latest",
        "what do you remember",
        "show system status",
        "What did that deterministic check actually collect?",
        "Now return to the Lantern project discussion.",
        "Let's discuss organizing local files conceptually; do not inspect or change anything.",
        "Keep this response concise while preserving the active subject.",
        "What remains unresolved in our synthetic project?",
        "Change topics briefly: explain why bounded operations terminate.",
        "Return to the earlier Lantern topic.",
        "Restate the project name without inventing a release date.",
        "Acknowledge this observation and keep the thread intact.",
        "What safety boundary have we been emphasizing?",
        "Summarize the active synthetic thread in one sentence.",
        "Close this acceptance discussion without claiming human approval."
      ].freeze
    end

    def exercise_skill_studio_gate(root)
      proposal_id = "phase13-acceptance-proposal"
      skill_id = "acceptance.fixture_skill"
      proposal = File.join(root, "Soul/proposals/skills", proposal_id)
      FileUtils.mkdir_p(proposal)
      FileUtils.mkdir_p(File.join(root, "Soul/skills"))
      File.write(File.join(root, "Soul/skills/registry.yaml"), YAML.dump({ "skills" => {} }))
      File.write(File.join(proposal, "metadata.json"), JSON.generate({ "title" => "Acceptance fixture" }))
      File.write(File.join(proposal, "proposal.md"), "# Acceptance Fixture\n\nBounded deterministic fixture.\n")
      File.write(File.join(proposal, "review_checklist.md"), "- [x] Scope reviewed\n")
      service = SkillStudioService.new(root: root, clock: -> { Time.utc(2026, 7, 15, 12, 0, 0) })

      gate1_preview = service.proposal_approval_preview(proposal_id: proposal_id)
      wrong_gate1 = service.approve_proposal(proposal_id: proposal_id, expected_digest: gate1_preview.dig("data", "expected_digest"), confirmation: "APPROVE")
      gate1 = service.approve_proposal(proposal_id: proposal_id, expected_digest: gate1_preview.dig("data", "expected_digest"), confirmation: SkillStudioService::PROPOSAL_CONFIRMATION)
      build_preview = service.beta_build_preview(proposal_id: proposal_id, skill_id: skill_id)
      build = service.prepare_beta_build(proposal_id: proposal_id, skill_id: skill_id, expected_digest: build_preview.dig("data", "expected_digest"), confirmation: "PREPARE_BETA_BUILD #{skill_id}")

      beta = File.join(proposal, "beta")
      manifest_path = File.join(beta, "beta_manifest.json")
      manifest = JSON.parse(File.read(manifest_path)).merge(
        "description" => "Deterministic acceptance fixture.",
        "risk" => "read_only",
        "implementation_complete" => true,
        "requires_approval" => false,
        "confirmation_phrase" => "",
        "writes_files" => false,
        "required_tests" => [{ "id" => "output", "description" => "Returns JSON", "kind" => "deterministic" }],
        "known_weaknesses" => ["Acceptance fixture only"],
        "failure_behavior" => ["Returns failed JSON"]
      )
      File.write(manifest_path, JSON.pretty_generate(manifest))
      source = "# frozen_string_literal: true\nrequire \"json\"\nputs JSON.generate({\"ok\" => true, \"lifecycle_state\" => \"complete\"})\n"
      File.write(File.join(beta, "skill.rb"), source)
      beta_digest = service.send(:beta_digest, beta, manifest)
      File.write(File.join(beta, "test_results.json"), JSON.pretty_generate({
        "passed" => true,
        "tested_at" => "2026-07-15T12:00:00Z",
        "beta_digest" => beta_digest,
        "results" => [{ "id" => "output", "passed" => true }]
      }))

      gate2_preview = service.promotion_preview(beta_id: skill_id)
      gate2 = service.approve_beta_for_promotion(beta_id: skill_id, expected_digest: gate2_preview.dig("data", "expected_digest"), confirmation: SkillStudioService::PROMOTION_CONFIRMATION)
      production_preview = service.production_promotion_preview(beta_id: skill_id)
      wrong_production = service.promote_beta_to_production(beta_id: skill_id, expected_digest: production_preview.dig("data", "expected_digest"), confirmation: "PROMOTE")
      production = service.promote_beta_to_production(beta_id: skill_id, expected_digest: production_preview.dig("data", "expected_digest"), confirmation: "PROMOTE_BETA_SKILL #{skill_id}")
      target = File.join(root, "Soul/skills/generated", skill_id, "skill.rb")
      registry = YAML.safe_load(File.read(File.join(root, "Soul/skills/registry.yaml")))

      {
        "ok" => wrong_gate1["lifecycle_state"] == "awaiting_input" && gate1["lifecycle_state"] == "complete" &&
          build["lifecycle_state"] == "complete" && gate2["lifecycle_state"] == "complete" &&
          wrong_production["lifecycle_state"] == "awaiting_input" && production["lifecycle_state"] == "complete" &&
          File.binread(target) == source && registry.dig("skills", skill_id, "path") == "Soul/skills/generated/#{skill_id}/skill.rb",
        "wrong_gate1_blocked" => wrong_gate1["lifecycle_state"] == "awaiting_input",
        "wrong_production_confirmation_blocked" => wrong_production["lifecycle_state"] == "awaiting_input",
        "exact_bytes_published" => File.binread(target) == source
      }
    end
  end
end
