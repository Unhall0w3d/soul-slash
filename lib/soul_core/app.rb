
# frozen_string_literal: true

require "json"
require_relative "confirmation_parser"
require_relative "env_loader"
require_relative "intent_router"
require_relative "skill_invocation_planner"
require_relative "read_only_skill_execution_gate"
require_relative "execution_adapter_registry"
require_relative "execution_adapter_registry_assessor"
require_relative "downloads_cleanup_approval_design_assessor"
require_relative "approval_token_store"
require_relative "approval_token_chat_controls"
require_relative "downloads_move_dry_run_executor"
require_relative "downloads_move_to_trash_executor"
require_relative "downloads_move_to_trash_assessor"
require_relative "usability_milestone_closeout_assessor"
require_relative "conversational_architecture_assessor"
require_relative "conversation_provider_contract"
require_relative "conversation_provider_registry"
require_relative "conversation_provider_probe"
require_relative "conversation_provider_foundation_assessor"
require_relative "multiturn_conversation_runtime_assessor"
require_relative "downloads_move_dry_run_assessor"
require_relative "approval_token_store_assessor"
require_relative "approval_token_chat_controls_assessor"
require_relative "chat_execution_history"
require_relative "chat_execution_history_assessor"
require_relative "read_only_skill_execution_gate_assessor"
require_relative "skill_invocation_planner_assessor"
require_relative "intent_router_assessor"
require_relative "skill_registry"
require_relative "skill_runner"
require_relative "workflow_runner"
require_relative "workflow_tools"
require_relative "workflow_registry"
require_relative "workflow_intent_handler_dispatch"
require_relative "workflow_registry_execution"
require_relative "workflow_handler_registry"
require_relative "workflow_contract_validator"
require_relative "environment_assessor"
require_relative "model_runtime_assessor"
require_relative "model_suitability_assessor"
require_relative "model_suitability_policy_assessor"
require_relative "codex_handoff_contract_assessor"
require_relative "codex_dry_run_review"
require_relative "codex_dry_run_fixture_pack"
require_relative "first_bounded_codex_task"
require_relative "alpha_implementation_task_pack_generator"
require_relative "alpha_implementation_review_gate"
require_relative "skill_loop_completion_assessor"
require_relative "codex_loop_completion_assessor"
require_relative "ruby_runtime_compatibility_assessor"
require_relative "doctor_surface_assessor"
require_relative "documentation_registry_refresh_assessor"
require_relative "chat_command"
require_relative "assistant_skill_catalog"
require_relative "capability_matrix"
require_relative "improvement_proposal_generator"
require_relative "proposal_locator"
require_relative "alpha_skill_plan_generator"
require_relative "alpha_behavior_scaffold"
require_relative "alpha_skill_generator"
require_relative "alpha_review"
require_relative "alpha_promotion_gate"
require_relative "repo_curation_assessor"
require_relative "feature_direction_assessor"
require_relative "response_renderer"
require_relative "workflow_session"

module SoulCore
  class App
    def initialize(positional_argv = nil, argv: nil)
      @argv = (argv || positional_argv || []).dup
      EnvLoader.load
      validate_workflow_contracts!
    end

    def run
      command = @argv.shift
      case command
  when "chat", "chats"
  ChatCommand.new(argv: @argv, root: Dir.pwd).run
    when "skills" then puts JSON.pretty_generate(SkillRegistry.new.to_h); 0
      when "skill" then run_skill
      when "intent" then run_intent
      when "do" then run_do
      when "respond" then run_respond
      when "reflect" then run_reflect
      when "workflow" then run_workflow_command
      when "workflows" then run_workflows_command
      when "doctor" then run_doctor
      when "assess" then run_assess
      when "improve" then run_improve
      else
        print_help
        command ? 1 : 0
      end
    rescue StandardError => e
      warn "Soul failed: #{e.class}: #{e.message}"
      1
    end

    private

    def validate_workflow_contracts!
      return if ENV["SOUL_SKIP_WORKFLOW_CONTRACT_VALIDATION"] == "1"
      WorkflowContractValidator.new.validate_registry!(WorkflowHandlerRegistry.new)
    end

    def run_improve
      subcommand = @argv.shift
      case subcommand
when "assistant-skill-catalog-refresh", "skill-catalog-refresh", "skills-catalog-refresh"
  catalog = AssistantSkillCatalog.new(root: Dir.pwd)
  ok, message = catalog.generate
  puts message
  ok ? 0 : 1
      when "proposals"
        write_files = @argv.include?("--write")
        json = @argv.include?("--json")
        generator = ImprovementProposalGenerator.new(root: Dir.pwd)
        report = generator.generate(write_files: write_files)
        puts(json ? JSON.pretty_generate(report) : generator.render(report))
        report["ok"] ? 0 : 1
      when "alpha"
        json = @argv.include?("--json")
        proposal_path = resolve_alpha_proposal_path
        unless proposal_path
          puts "Missing proposal path."
          puts
          puts "Examples:"
          puts "  ruby bin/soul improve alpha --latest"
          puts "  ruby bin/soul improve alpha --proposal-rank 1"
          puts "  ruby bin/soul improve alpha --proposal Soul/improvement/proposals/<proposal-folder>"
          return 1
        end
        generator = AlphaSkillGenerator.new(root: Dir.pwd)
        report = generator.generate(proposal_path: proposal_path)
        puts(json ? JSON.pretty_generate(report) : generator.render(report))
        report["ok"] ? 0 : 1
      when "codex-fixtures", "codex-fixture-pack", "dry-run-fixtures"
        json = @argv.include?("--json")
        generator = CodexDryRunFixturePack.new(root: Dir.pwd)
        report = generator.generate
        puts(json ? JSON.pretty_generate(report) : generator.render(report))
        report["ok"] ? 0 : 1
  when "documentation-registry-refresh", "doc-registry-refresh", "docs-registry-refresh"
  assessor = DocumentationRegistryRefreshAssessor.new(root: Dir.pwd)
  ok, message = assessor.generate_snapshot
  puts message
  ok ? 0 : 1
    when "bounded-codex-task", "first-codex-task", "codex-task"
        json = @argv.include?("--json")
        generator = FirstBoundedCodexTask.new(root: Dir.pwd)
        report = generator.generate
        puts(json ? JSON.pretty_generate(report) : generator.render(report))
        report["ok"] ? 0 : 1
      when "implementation-pack", "task-pack", "alpha-task-pack"
        json = @argv.include?("--json")
        proposal_path = resolve_alpha_review_proposal_path
        unless proposal_path
          puts "Missing alpha proposal path."
          puts
          puts "Examples:"
          puts "  ruby bin/soul improve implementation-pack --latest"
          puts "  ruby bin/soul improve implementation-pack --proposal-rank 1"
          puts "  ruby bin/soul improve implementation-pack --proposal Soul/improvement/proposals/<proposal-folder>"
          return 1
        end
        generator = AlphaImplementationTaskPackGenerator.new(root: Dir.pwd)
        report = generator.generate(proposal_path: proposal_path)
        puts(json ? JSON.pretty_generate(report) : generator.render(report))
        report["ok"] ? 0 : 1
      when "implementation-review", "implementation-gate", "review-implementation"
        json = @argv.include?("--json")
        proposal_path = resolve_alpha_review_proposal_path
        unless proposal_path
          puts "Missing alpha proposal path."
          puts
          puts "Examples:"
          puts "  ruby bin/soul improve implementation-review --latest"
          puts "  ruby bin/soul improve implementation-review --proposal-rank 1"
          puts "  ruby bin/soul improve implementation-review --proposal Soul/improvement/proposals/<proposal-folder>"
          return 1
        end
        gate = AlphaImplementationReviewGate.new(root: Dir.pwd)
        report = gate.review(proposal_path: proposal_path)
        puts(json ? JSON.pretty_generate(report) : gate.render(report))
        report["ok"] ? 0 : 1
      when "alpha-review", "review-alpha"
        json = @argv.include?("--json")
        proposal_path = resolve_alpha_review_proposal_path
        unless proposal_path
          puts "Missing reviewable alpha proposal path."
          return 1
        end
        reviewer = AlphaReview.new(root: Dir.pwd)
        report = reviewer.review(proposal_path: proposal_path)
        puts(json ? JSON.pretty_generate(report) : reviewer.render(report))
        report["ok"] ? 0 : 1
      when "promotion-gate", "alpha-promotion-gate", "promotion-check"
        json = @argv.include?("--json")
        proposal_path = resolve_alpha_review_proposal_path
        unless proposal_path
          puts "Missing promotion-gate proposal path."
          puts
          puts "Examples:"
          puts "  ruby bin/soul improve promotion-gate --latest"
          puts "  ruby bin/soul improve promotion-gate --proposal-rank 1"
          return 1
        end
        gate = AlphaPromotionGate.new(root: Dir.pwd)
        report = gate.assess(proposal_path: proposal_path)
        puts(json ? JSON.pretty_generate(report) : gate.render(report))
        report["ok"] ? 0 : 1
      else
        puts "Unknown improve command."
        puts
        puts "Examples:"
        puts "  ruby bin/soul improve proposals --write"
        puts "  ruby bin/soul improve alpha --latest"
        puts "  ruby bin/soul improve codex-fixtures"
        puts "  ruby bin/soul improve bounded-codex-task"
      puts "  ruby bin/soul improve documentation-registry-refresh"
      puts "  ruby bin/soul improve assistant-skill-catalog-refresh"
        puts "  ruby bin/soul improve implementation-pack --latest"
        puts "  ruby bin/soul improve implementation-review --latest"
        puts "  ruby bin/soul improve alpha-review --latest"
        puts "  ruby bin/soul improve promotion-gate --latest"
        1
      end
    end

    def resolve_alpha_proposal_path
      locator = ProposalLocator.new(root: Dir.pwd)
      explicit = option_value("--proposal")
      return explicit if explicit
      rank = option_value("--proposal-rank")
      return locator.by_rank(rank.to_i) if rank
      return locator.latest if @argv.include?("--latest")
      @argv.find { |arg| !arg.start_with?("--") }
    end

    def resolve_alpha_review_proposal_path
      locator = ProposalLocator.new(root: Dir.pwd)
      explicit = option_value("--proposal")
      return explicit if explicit
      rank = option_value("--proposal-rank")
      return locator.by_rank(rank.to_i) if rank
      return locator.latest_with_alpha if @argv.include?("--latest")
      @argv.find { |arg| !arg.start_with?("--") }
    end

    def option_value(name)
      index = @argv.index(name)
      return nil unless index
      @argv[index + 1]
    end

    def run_assess
      target = @argv.shift
      case target
when "multiturn-conversation-runtime", "conversation-runtime", "multiturn-chat"
  json = @argv.include?("--json")
  assessor = MultiturnConversationRuntimeAssessor.new(root: Dir.pwd)
  report = assessor.assess
  puts(json ? JSON.pretty_generate(report) : assessor.render(report))
  report["ok"] ? 0 : 1
when "conversation-provider-foundation", "conversation-providers", "model-provider-foundation"
  json = @argv.include?("--json")
  assessor = ConversationProviderFoundationAssessor.new(root: Dir.pwd)
  report = assessor.assess
  puts(json ? JSON.pretty_generate(report) : assessor.render(report))
  report["ok"] ? 0 : 1
when "conversational-architecture", "conversational-soul", "conversation-architecture"
  json = @argv.include?("--json")
  assessor = ConversationalArchitectureAssessor.new(root: Dir.pwd)
  report = assessor.assess
  puts(json ? JSON.pretty_generate(report) : assessor.render(report))
  report["ok"] ? 0 : 1
when "usability-milestone-closeout", "usability-closeout", "safe-local-action-closeout"
  json = @argv.include?("--json")
  assessor = UsabilityMilestoneCloseoutAssessor.new(root: Dir.pwd)
  report = assessor.assess
  puts(json ? JSON.pretty_generate(report) : assessor.render(report))
  report["ok"] ? 0 : 1
when "downloads-move-to-trash", "downloads-trash-executor", "move-to-trash"
  json = @argv.include?("--json")
  assessor = DownloadsMoveToTrashAssessor.new(root: Dir.pwd)
  report = assessor.assess
  puts(json ? JSON.pretty_generate(report) : assessor.render(report))
  report["ok"] ? 0 : 1
when "downloads-move-dry-run", "downloads-trash-dry-run", "move-dry-run"
  json = @argv.include?("--json")
  assessor = DownloadsMoveDryRunAssessor.new(root: Dir.pwd)
  report = assessor.assess
  puts(json ? JSON.pretty_generate(report) : assessor.render(report))
  report["ok"] ? 0 : 1
when "approval-token-chat-controls", "approval-chat-controls", "approval-controls"
  json = @argv.include?("--json")
  assessor = ApprovalTokenChatControlsAssessor.new(root: Dir.pwd)
  report = assessor.assess
  puts(json ? JSON.pretty_generate(report) : assessor.render(report))
  report["ok"] ? 0 : 1
when "approval-token-store", "approval-tokens", "downloads-approval-token"
  json = @argv.include?("--json")
  assessor = ApprovalTokenStoreAssessor.new(root: Dir.pwd)
  report = assessor.assess
  puts(json ? JSON.pretty_generate(report) : assessor.render(report))
  report["ok"] ? 0 : 1
when "downloads-cleanup-approval-design", "cleanup-approval-design", "downloads-approval-design"
  json = @argv.include?("--json")
  assessor = DownloadsCleanupApprovalDesignAssessor.new(root: Dir.pwd)
  report = assessor.assess
  puts(json ? JSON.pretty_generate(report) : assessor.render(report))
  report["ok"] ? 0 : 1
when "execution-adapter-registry", "adapter-registry", "adapters"
  json = @argv.include?("--json")
  assessor = ExecutionAdapterRegistryAssessor.new(root: Dir.pwd)
  report = assessor.assess
  puts(json ? JSON.pretty_generate(report) : assessor.render(report))
  report["ok"] ? 0 : 1
when "chat-execution-history", "execution-history", "chat-history"
  json = @argv.include?("--json")
  assessor = ChatExecutionHistoryAssessor.new(root: Dir.pwd)
  report = assessor.assess
  puts(json ? JSON.pretty_generate(report) : assessor.render(report))
  report["ok"] ? 0 : 1
when "read-only-skill-gate", "read-only-execution", "skill-execution-gate"
  json = @argv.include?("--json")
  assessor = ReadOnlySkillExecutionGateAssessor.new(root: Dir.pwd)
  report = assessor.assess
  puts(json ? JSON.pretty_generate(report) : assessor.render(report))
  report["ok"] ? 0 : 1
when "skill-invocation-planner", "invocation-planner", "skill-planner"
  json = @argv.include?("--json")
  assessor = SkillInvocationPlannerAssessor.new(root: Dir.pwd)
  report = assessor.assess
  puts(json ? JSON.pretty_generate(report) : assessor.render(report))
  report["ok"] ? 0 : 1
when "intent-router", "intent-router-mvp", "chat-intents"
  json = @argv.include?("--json")
  assessor = IntentRouterAssessor.new(root: Dir.pwd)
  report = assessor.assess
  puts(json ? JSON.pretty_generate(report) : assessor.render(report))
  report["ok"] ? 0 : 1
when "assistant-skill-catalog", "skill-catalog", "skills-catalog"
  json = @argv.include?("--json")
  catalog = AssistantSkillCatalog.new(root: Dir.pwd)
  report = catalog.assess
  puts(json ? JSON.pretty_generate(report) : catalog.render(report))
  report["ok"] ? 0 : 1
      when "environment"
        include_updates = @argv.include?("--updates")
        json = @argv.include?("--json")
        assessor = EnvironmentAssessor.new(root: Dir.pwd)
        report = assessor.assess(include_updates: include_updates)
        puts(json ? JSON.pretty_generate(report) : assessor.render(report))
        0
      when "models", "model-runtime"
        json = @argv.include?("--json")
        include_processes = @argv.include?("--processes")
        assessor = ModelRuntimeAssessor.new(root: Dir.pwd)
        report = assessor.assess(include_processes: include_processes)
        puts(json ? JSON.pretty_generate(report) : assessor.render(report))
        0
      when "model-suitability", "models-suitability", "suitability"
        json = @argv.include?("--json")
        task = option_value("--task")
        assessor = ModelSuitabilityAssessor.new(root: Dir.pwd)
        report = assessor.assess(task: task)
        puts(json ? JSON.pretty_generate(report) : assessor.render(report))
        0
      when "model-policy", "model-suitability-policy", "suitability-policy"
        json = @argv.include?("--json")
        task = option_value("--task")
        assessor = ModelSuitabilityPolicyAssessor.new(root: Dir.pwd)
        report = assessor.assess(task: task)
        puts(json ? JSON.pretty_generate(report) : assessor.render(report))
        0
      when "codex-handoff", "handoff-contract", "codex-contract"
        json = @argv.include?("--json")
        write_files = @argv.include?("--write")
        task = option_value("--task")
        assessor = CodexHandoffContractAssessor.new(root: Dir.pwd)
        report = assessor.assess(write_files: write_files, task: task)
        puts(json ? JSON.pretty_generate(report) : assessor.render(report))
        0
      when "codex-dry-run-review", "codex-review", "handoff-review"
        json = @argv.include?("--json")
        contract = option_value("--contract")
        response = option_value("--response")
        unless contract && response
          puts "Missing required --contract and/or --response path."
          puts "Example:"
          puts "  ruby bin/soul assess codex-dry-run-review --contract Soul/codex/handoffs/example.json --response Soul/codex/responses/example.json"
          return 1
        end
        reviewer = CodexDryRunReview.new(root: Dir.pwd)
        report = reviewer.review(contract_path: contract, response_path: response)
        puts(json ? JSON.pretty_generate(report) : reviewer.render(report))
        report["ok"] ? 0 : 1
      when "skill-loop", "skill-loop-completion", "loop-completion"
        json = @argv.include?("--json")
        assessor = SkillLoopCompletionAssessor.new(root: Dir.pwd)
        report = assessor.assess
        puts(json ? JSON.pretty_generate(report) : assessor.render(report))
        report["ok"] ? 0 : 1
  when "codex-loop", "codex-loop-completion", "bounded-codex-loop"
  json = @argv.include?("--json")
  assessor = CodexLoopCompletionAssessor.new(root: Dir.pwd)
  report = assessor.assess
  puts(json ? JSON.pretty_generate(report) : assessor.render(report))
  report["ok"] ? 0 : 1
when "ruby-runtime", "runtime-compatibility", "ruby-compatibility"
  json = @argv.include?("--json")
  assessor = RubyRuntimeCompatibilityAssessor.new(root: Dir.pwd)
  report = assessor.assess
  puts(json ? JSON.pretty_generate(report) : assessor.render(report))
  report["ok"] ? 0 : 1
when "doctor-surface", "doctor-coverage", "surface-doctor"
  json = @argv.include?("--json")
  assessor = DoctorSurfaceAssessor.new(root: Dir.pwd)
  report = assessor.assess
  puts(json ? JSON.pretty_generate(report) : assessor.render(report))
  report["ok"] ? 0 : 1
when "documentation-registry", "doc-registry", "docs-registry"
  json = @argv.include?("--json")
  assessor = DocumentationRegistryRefreshAssessor.new(root: Dir.pwd)
  report = assessor.assess
  puts(json ? JSON.pretty_generate(report) : assessor.render(report))
  report["ok"] ? 0 : 1
    when "capabilities", "capability-matrix"
        json = @argv.include?("--json")
        persist = @argv.include?("--persist")
        assessor = CapabilityMatrix.new(root: Dir.pwd)
        report = assessor.assess(persist: persist)
        puts(json ? JSON.pretty_generate(report) : assessor.render(report))
        0
      when "repo-curation", "repository-curation", "curation"
        json = @argv.include?("--json")
        assessor = RepoCurationAssessor.new(root: Dir.pwd)
        report = assessor.assess
        puts(json ? JSON.pretty_generate(report) : assessor.render(report))
        0
      when "feature-direction", "features", "next-feature"
        json = @argv.include?("--json")
        assessor = FeatureDirectionAssessor.new(root: Dir.pwd)
        report = assessor.assess
        puts(json ? JSON.pretty_generate(report) : assessor.render(report))
        0
      else
        puts "Unknown assessment target."
        1
      end
    end

    def run_doctor
      report = WorkflowContractValidator.new.health_report(WorkflowHandlerRegistry.new)
      puts(@argv.include?("--json") ? JSON.pretty_generate(report) : report.fetch("message"))
      report.fetch("valid") ? 0 : 1
    end

    def run_skill
      name = @argv.shift
      separator_index = @argv.index("--")
      args = separator_index ? (@argv[(separator_index + 1)..] || []) : @argv
      result = SkillRunner.new(registry: SkillRegistry.new).run(name, args: args)
      puts JSON.pretty_generate(result[:json])
      result[:ok] ? 0 : 1
    end

    def run_intent
      text = @argv.join(" ").strip
      result = IntentRouter.new.route(text)
      puts JSON.pretty_generate({"ok"=>result.ok,"intent"=>result.intent,"parameters"=>result.parameters,"confidence"=>result.confidence,"reason"=>result.reason,"source"=>result.source})
      result.ok ? 0 : 1
    end

    def run_do
      text = @argv.join(" ").strip
      intent = IntentRouter.new.route(text)
      unless intent.ok
        puts "I could not map that request to a supported workflow."
        puts
        puts "Reason: #{intent.reason}"
        return 1
      end
      result = WorkflowRunner.new.run(intent: intent.intent, parameters: intent.parameters, original_text: text)
      puts "Intent: #{intent.intent}"
      puts "Workflow state: #{result.dig(:state, 'status') || 'unknown'}"
      puts "Workflow file: #{result[:workflow_path]}" if result[:workflow_path]
      puts
      puts result[:user_message]
      result[:ok] ? 0 : 1
    end

    def run_respond
      text = @argv.join(" ").strip
      result = WorkflowSession.new.respond(text)
      puts result[:message]
      result[:ok] ? 0 : 1
    end

    def run_reflect
      target = @argv.shift || "last"
      result = ResponseRenderer.new.reflect(target)
      puts result[:message]
      result[:ok] ? 0 : 1
    end

    def run_workflow_command
      subcommand = @argv.shift
      case subcommand
      when "show"
        puts JSON.pretty_generate(WorkflowTools.new.show(@argv.shift || "latest")); 0
      when "status"
        result = WorkflowTools.new.status(@argv.shift || "latest"); puts result.fetch("message"); result.fetch("ok") ? 0 : 1
      when "list"
        puts JSON.pretty_generate(WorkflowTools.new.list(active_only: @argv.include?("--active"))); 0
      when "clear-complete"
        result = WorkflowTools.new.clear_complete(confirm: @argv.include?("--confirm") && @argv.include?("CLEAR_COMPLETE")); puts JSON.pretty_generate(result); result.fetch("ok") ? 0 : 1
      else
        puts "Unknown workflow command."
        1
      end
    end

    def run_workflows_command
      registry = WorkflowRegistry.new
      if @argv.include?("--json")
        puts JSON.pretty_generate(registry.respond_to?(:to_h) ? registry.to_h : {"workflows" => []})
      elsif registry.respond_to?(:definitions)
        registry.definitions.each { |definition| puts "#{definition.intent} - #{definition.description}" }
      else
        puts JSON.pretty_generate({"status" => "unavailable", "reason" => "workflow registry listing API not exposed"})
      end
      0
    end

    def print_help
      puts "Soul command examples:"
      puts "  ruby bin/soul skills"
      puts "  ruby bin/soul chat [message]"
      puts "  ruby bin/soul assess capabilities"
      puts "  ruby bin/soul assess models"
      puts "  ruby bin/soul assess model-suitability"
      puts "  ruby bin/soul assess model-policy"
      puts "  ruby bin/soul assess codex-handoff"
      puts "  ruby bin/soul assess codex-dry-run-review --contract <path> --response <path>"
      puts "  ruby bin/soul assess skill-loop"
      puts "  ruby bin/soul assess codex-loop"
      puts "  ruby bin/soul assess ruby-runtime"
      puts "  ruby bin/soul assess doctor-surface"
      puts "  ruby bin/soul assess documentation-registry"
      puts "  ruby bin/soul assess assistant-skill-catalog"
      puts "  ruby bin/soul assess intent-router"
      puts "  ruby bin/soul assess skill-invocation-planner"
      puts "  ruby bin/soul assess read-only-skill-gate"
      puts "  ruby bin/soul assess execution-adapter-registry"
      puts "  ruby bin/soul assess downloads-cleanup-approval-design"
      puts "  ruby bin/soul assess approval-token-store"
      puts "  ruby bin/soul assess approval-token-chat-controls"
      puts "  ruby bin/soul assess downloads-move-dry-run"
      puts "  ruby bin/soul assess downloads-move-to-trash"
      puts "  ruby bin/soul assess usability-milestone-closeout"
      puts "  ruby bin/soul assess conversational-architecture"
      puts "  ruby bin/soul assess conversation-provider-foundation"
      puts "  ruby bin/soul assess multiturn-conversation-runtime"
      puts "  ruby bin/soul assess chat-execution-history"
      puts "  ruby bin/soul assess repo-curation"
      puts "  ruby bin/soul assess feature-direction"
      puts "  ruby bin/soul improve proposals --write"
      puts "  ruby bin/soul improve alpha --latest"
      puts "  ruby bin/soul improve codex-fixtures"
      puts "  ruby bin/soul improve bounded-codex-task"
      puts "  ruby bin/soul improve implementation-pack --latest"
      puts "  ruby bin/soul improve implementation-review --latest"
      puts "  ruby bin/soul improve alpha-review --latest"
      puts "  ruby bin/soul improve promotion-gate --latest"
    end
  end
end
