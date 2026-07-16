# frozen_string_literal: true

require "digest"
require "time"
require_relative "application_chat_service"
require_relative "application_contract"
require_relative "approval_token_store"
require_relative "chat_execution_history"
require_relative "chat_store"
require_relative "configuration_resolver"
require_relative "conversation_provider_registry"
require_relative "conversation_runtime"
require_relative "conversation_clear_service"
require_relative "conversation_forget_service"
require_relative "conversation_workspace_service"
require_relative "host_system_status_collector"
require_relative "model_runtime_control_service"
require_relative "skill_registry"
require_relative "skill_studio_service"
require_relative "self_improvement_service"
require_relative "host_improvement_plan_service"
require_relative "self_augmentation_service"
require_relative "self_augmentation_experiment_service"

module SoulCore
  class ApplicationFacade
    Contract = ApplicationContract
    CHAT_LIMIT = 50
    MESSAGE_LIMIT = 200
    SKILL_LIMIT = 100
    APPROVAL_LIMIT = 50
    ACTIVITY_LIMIT = 100

    def initialize(
      root: Dir.pwd,
      process_env: ENV,
      clock: -> { Time.now },
      chat_store: nil,
      conversation_runtime: nil,
      chat_service: nil,
      conversation_clear_service: nil,
      conversation_forget_service: nil,
      workspace_service: nil,
      status_collector: nil,
      model_runtime_control_service: nil,
      approval_store: nil,
      activity_store: nil,
      skill_registry: nil,
      skill_studio_service: nil,
      self_improvement_service: nil,
      host_improvement_plan_service: nil,
      self_augmentation_service: nil,
      self_augmentation_experiment_service: nil
    )
      @root = File.expand_path(root)
      @process_env = process_env.to_h
      @clock = clock
      @injected_chat_store = chat_store
      @injected_runtime = conversation_runtime
      @injected_chat_service = chat_service
      @conversation_clear_service = conversation_clear_service
      @conversation_forget_service = conversation_forget_service
      @workspace_service = workspace_service
      @status_collector = status_collector
      @model_runtime_control_service = model_runtime_control_service
      @approval_store = approval_store
      @activity_store = activity_store
      @skill_registry = skill_registry
      @skill_studio_service = skill_studio_service
      @self_improvement_service = self_improvement_service
      @host_improvement_plan_service = host_improvement_plan_service
      @self_augmentation_service = self_augmentation_service
      @self_augmentation_experiment_service = self_augmentation_experiment_service
    end

    def call(request)
      validation = Contract.validate(request)
      return envelope_from_validation(request, validation) unless validation.fetch("ok")

      operation = request.fetch("operation")
      return envelope(request, lifecycle: "canceled", data: { "reason" => "application request canceled" }) if operation == "application.cancel"

      data, lifecycle, mutation, replay = dispatch(operation, request.fetch("parameters", {}), request.fetch("context", {}), request.fetch("request_id"))
      envelope(
        request,
        lifecycle: lifecycle,
        data: data,
        mutation: mutation,
        idempotent_replay: replay
      )
    rescue ArgumentError => error
      safe_error_envelope(request, "failed", "invalid_input", error.message)
    rescue RuntimeError => error
      safe_error_envelope(request, "blocked_for_human_review", "runtime_integrity", error.message)
    rescue StandardError => error
      safe_error_envelope(request, "failed", "dependency_failure", "application dependency failed safely: #{error.class}")
    end

    private

    def dispatch(operation, parameters, context, request_id)
      case operation
      when "application.bootstrap" then [bootstrap, "complete", "none", false]
      when "chats.list" then [chats_list(parameters), "complete", "none", false]
      when "chats.get" then domain(chats_get(parameters))
      when "chats.messages" then domain(chats_messages(parameters))
      when "chats.create" then domain(chats_create(parameters))
      when "chats.send" then domain(chats_send(parameters, context, request_id))
      when "chats.pin" then domain(chat_flag(parameters, true))
      when "chats.unpin" then domain(chat_flag(parameters, false))
      when "chats.clear.preview" then domain(conversation_clear_service.preview(mode: required(parameters, "mode"), title: parameters["title"], chat_ids: parameters["chat_ids"]))
      when "chats.clear.execute" then domain(conversation_clear_service.execute(mode: required(parameters, "mode"), title: parameters["title"], chat_ids: parameters["chat_ids"], confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "chats.forget.preview" then domain(conversation_forget_service.preview(chat_id: required(parameters, "chat_id")))
      when "chats.forget.execute" then domain(conversation_forget_service.execute(chat_id: required(parameters, "chat_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "chats.forget_many.preview" then domain(conversation_forget_service.preview_many(mode: required(parameters, "mode"), title: parameters["title"], chat_ids: parameters["chat_ids"]))
      when "chats.forget_many.execute" then domain(conversation_forget_service.execute_many(mode: required(parameters, "mode"), title: parameters["title"], chat_ids: parameters["chat_ids"], confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "workspace.list" then domain(workspace.list(**workspace_filters(parameters)))
      when "workspace.chat" then domain(workspace.list(**workspace_filters(parameters, require_chat: true)))
      when "workspace.detail" then domain(workspace.detail(artifact_id: required(parameters, "artifact_id")))
      when "inbox.list" then domain(workspace.inbox(chat_id: required(parameters, "chat_id"), state: parameters["state"], limit: bounded_limit(parameters["limit"], CHAT_LIMIT)))
      when "inbox.deliver" then domain(workspace.deliver(artifact_id: required(parameters, "artifact_id"), chat_id: required(parameters, "chat_id")))
      when "inbox.mark_seen" then domain(workspace.change_state(delivery_id: required(parameters, "delivery_id"), chat_id: required(parameters, "chat_id"), state: "seen"))
      when "inbox.dismiss" then domain(workspace.change_state(delivery_id: required(parameters, "delivery_id"), chat_id: required(parameters, "chat_id"), state: "dismissed"))
      when "system_status.refresh" then [status_collector.collect, "complete", "none", false]
      when "model_runtime.status" then domain(model_runtime_control.status)
      when "model_runtime.load.preview" then domain(model_runtime_control.preview(action: "load", profile_id: parameters["profile_id"]))
      when "model_runtime.load.execute" then domain(model_runtime_control.execute(action: "load", profile_id: parameters["profile_id"], confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "model_runtime.unload.preview" then domain(model_runtime_control.preview(action: "unload", profile_id: parameters["profile_id"]))
      when "model_runtime.unload.execute" then domain(model_runtime_control.execute(action: "unload", profile_id: parameters["profile_id"], confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "model_runtime.switch.preview" then domain(model_runtime_control.preview(action: "switch", profile_id: required(parameters, "profile_id")))
      when "model_runtime.switch.execute" then domain(model_runtime_control.execute(action: "switch", profile_id: required(parameters, "profile_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "configuration.show" then domain(configuration_report)
      when "configuration.explain" then domain(configuration_explain(parameters))
      when "configuration.validate" then domain(configuration_validate)
      when "skills.list" then [skills_list(parameters), "complete", "none", false]
      when "skill_studio.proposals.list" then domain(skill_studio.proposals(limit: bounded_limit(parameters["limit"], SkillStudioService::MAX_RECORDS)))
      when "skill_studio.proposals.get" then domain(skill_studio.proposal(proposal_id: required(parameters, "proposal_id")))
      when "skill_studio.proposals.approval.preview" then domain(skill_studio.proposal_approval_preview(proposal_id: required(parameters, "proposal_id")))
      when "skill_studio.proposals.approval.execute" then domain(skill_studio.approve_proposal(proposal_id: required(parameters, "proposal_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "skill_studio.proposals.beta_build.preview" then domain(skill_studio.beta_build_preview(proposal_id: required(parameters, "proposal_id"), skill_id: required(parameters, "skill_id")))
      when "skill_studio.proposals.beta_build.execute" then domain(skill_studio.prepare_beta_build(proposal_id: required(parameters, "proposal_id"), skill_id: required(parameters, "skill_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "skill_studio.proposals.close.preview" then domain(skill_studio.proposal_close_preview(proposal_id: required(parameters, "proposal_id")))
      when "skill_studio.proposals.close.execute" then domain(skill_studio.close_production_proposal(proposal_id: required(parameters, "proposal_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "skill_studio.betas.list" then domain(skill_studio.betas(limit: bounded_limit(parameters["limit"], SkillStudioService::MAX_RECORDS)))
      when "skill_studio.betas.get" then domain(skill_studio.beta(beta_id: required(parameters, "beta_id")))
      when "skill_studio.betas.run.preview" then domain(skill_studio.beta_run_preview(beta_id: required(parameters, "beta_id"), args: parameters.fetch("args", [])))
      when "skill_studio.betas.run.execute" then domain(skill_studio.run_beta(beta_id: required(parameters, "beta_id"), args: parameters.fetch("args", []), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "skill_studio.betas.promotion.preview" then domain(skill_studio.promotion_preview(beta_id: required(parameters, "beta_id")))
      when "skill_studio.betas.promotion.approve" then domain(skill_studio.approve_beta_for_promotion(beta_id: required(parameters, "beta_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "skill_studio.betas.production.preview" then domain(skill_studio.production_promotion_preview(beta_id: required(parameters, "beta_id")))
      when "skill_studio.betas.production.execute" then domain(skill_studio.promote_beta_to_production(beta_id: required(parameters, "beta_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "self_improvement.snapshot" then domain(self_improvement.snapshot)
      when "self_improvement.refresh" then domain(self_improvement.refresh(scope: required(parameters, "scope")))
      when "self_improvement.proposals.preview" then domain(self_improvement.proposal_preview)
      when "self_improvement.proposals.execute" then domain(self_improvement.generate_proposals(confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "host_improvement.plans.list" then domain(host_improvement.list(limit: bounded_limit(parameters["limit"], HostImprovementPlanService::MAX_RECORDS)))
      when "host_improvement.arch_upgrade.preview" then domain(host_improvement.preview_arch_upgrade)
      when "host_improvement.arch_upgrade.handoff" then domain(host_improvement.create_arch_handoff(confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "host_improvement.plans.verify" then domain(host_improvement.verify(plan_id: required(parameters, "plan_id")))
      when "self_augmentation.census" then domain(self_augmentation.census)
      when "self_augmentation.proposals.list" then domain(self_augmentation.inventory(limit: bounded_limit(parameters["limit"], SelfAugmentationService::MAX_RECORDS)))
      when "self_augmentation.proposals.preview" then domain(self_augmentation.preview(objective: required(parameters, "objective"), why_not_skill: required(parameters, "why_not_skill")))
      when "self_augmentation.proposals.execute" then domain(self_augmentation.create_proposal(objective: required(parameters, "objective"), why_not_skill: required(parameters, "why_not_skill"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "self_augmentation.experiments.list" then domain(self_augmentation_experiments.inventory(limit: bounded_limit(parameters["limit"], SelfAugmentationExperimentService::MAX_RECORDS)))
      when "self_augmentation.experiments.gate_a1.preview" then domain(self_augmentation_experiments.gate_a1_preview(proposal_id: required(parameters,"proposal_id"), allowed_files: required(parameters,"allowed_files")))
      when "self_augmentation.experiments.gate_a1.execute" then domain(self_augmentation_experiments.prepare_experiment(proposal_id: required(parameters,"proposal_id"), allowed_files: required(parameters,"allowed_files"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "self_augmentation.reviews.generate" then domain(self_augmentation_experiments.generate_dossier(experiment_id: required(parameters,"experiment_id")))
      when "self_augmentation.reviews.gate_a2.preview" then domain(self_augmentation_experiments.gate_a2_preview(experiment_id: required(parameters,"experiment_id")))
      when "self_augmentation.reviews.gate_a2.execute" then domain(self_augmentation_experiments.approve_for_integration(experiment_id: required(parameters,"experiment_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "self_augmentation.model_qualification.preview" then domain(self_augmentation_experiments.model_qualification_preview(experiment_id: required(parameters,"experiment_id"), suite_id: required(parameters,"suite_id"), model_profile: required(parameters,"model_profile"), result: required(parameters,"result"), evidence_digest: required(parameters,"evidence_digest")))
      when "self_augmentation.model_qualification.execute" then domain(self_augmentation_experiments.record_model_qualification(experiment_id: required(parameters,"experiment_id"), suite_id: required(parameters,"suite_id"), model_profile: required(parameters,"model_profile"), result: required(parameters,"result"), evidence_digest: required(parameters,"evidence_digest"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "self_augmentation.experiments.cleanup.preview" then domain(self_augmentation_experiments.cleanup_preview(experiment_id: required(parameters,"experiment_id")))
      when "self_augmentation.experiments.cleanup.execute" then domain(self_augmentation_experiments.cleanup(experiment_id: required(parameters,"experiment_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "approvals.pending" then [approvals_pending(parameters), "complete", "none", false]
      when "activities.recent" then [activities_recent(parameters), "complete", "none", false]
      else
        raise ArgumentError, "unsupported registered operation"
      end
    end

    def bootstrap
      report, resolver = resolved_configuration
      providers = report.fetch("ok") ? ConversationProviderRegistry.new(env: resolver.effective_environment).summary : { "providers" => [] }
      {
        "application_schema_version" => Contract::SCHEMA_VERSION,
        "operations" => Contract::OPERATIONS.keys,
        "product_tabs" => ["Chat", "Skill Studio", "Self Assessment", "Self Augmentation"],
        "configuration" => {
          "ok" => report.fetch("ok"),
          "lifecycle_state" => report.fetch("lifecycle_state"),
          "error_count" => report.fetch("error_count"),
          "dotenv_loaded" => report.fetch("dotenv_loaded")
        },
        "providers" => providers,
        "system_status" => { "collected" => false, "refresh_operation" => "system_status.refresh" },
        "model_runtime" => {
          "available" => true,
          "manual_only" => true,
          "automatic_load" => false,
          "automatic_unload" => false,
          "automatic_switch" => false,
          "status_operation" => "model_runtime.status",
          "load_gate" => "preview_digest_and_exact_confirmation",
          "unload_gate" => "active_work_check_preview_digest_and_exact_confirmation",
          "switch_gate" => "active_work_check_target_bound_preview_digest_and_exact_confirmation"
        },
        "skill_studio" => {
          "available" => true,
          "phase" => "12D.5",
          "maturity_name" => "Beta",
          "proposal_gate" => "human_exact_confirmation",
          "beta_gate" => "human_exact_confirmation",
          "automatic_promotion" => false,
          "beta_build_preparation" => "preview_and_exact_confirmation",
          "production_promotion" => "preview_digest_and_exact_confirmation"
        },
        "self_improvement" => {
          "available" => true,
          "phase" => "12D.3",
          "automatic_scope" => "read_only_environment_snapshot",
          "proposal_gate" => "human_exact_confirmation",
          "host_mutation_available" => false,
          "host_handoff_available" => true,
          "automatic_refresh" => false
        },
        "self_augmentation" => {
          "available" => true,
          "stage" => "observe_propose_experiment_review",
          "implementation_available" => "external_handoff_only",
          "automatic_codex_invocation" => false,
          "worktree_creation" => "human_gate_a1_only"
        },
        "unified_operations" => {
          "available" => true,
          "surface" => "Review Center",
          "read_only" => true,
          "operations" => %w[approvals.pending activities.recent],
          "approval_values_exposed" => false,
          "private_messages_exposed" => false
        }
      }
    end

    def chats_list(parameters)
      limit = bounded_limit(parameters["limit"], CHAT_LIMIT)
      records = chat_store.list_chats.first(limit).map { |chat| chat_projection(chat) }
      { "records" => records, "count" => records.length, "limit" => limit }
    end

    def chats_get(parameters)
      chat = chat_store.chat(required(parameters, "chat_id"))
      return awaiting("unknown chat ID") unless chat

      success({ "record" => chat_projection(chat) })
    end

    def chats_messages(parameters)
      chat_id = required(parameters, "chat_id")
      return awaiting("unknown chat ID") unless chat_store.chat(chat_id)

      limit = bounded_limit(parameters["limit"], MESSAGE_LIMIT)
      records = chat_store.messages(chat_id, limit: limit, scan_limit: ChatStore::APPLICATION_SCAN_LIMIT)
      success({ "records" => records, "count" => records.length, "limit" => limit })
    end

    def chats_create(parameters)
      title = parameters["title"].to_s.strip
      raise ArgumentError, "chat title exceeds 120 characters" if title.length > 120

      chat = chat_store.create_chat(initial_title: title.empty? ? nil : title)
      success({ "record" => chat_projection(chat) }, mutation: "chat_created")
    end

    def chats_send(parameters, context, request_id)
      chat_id = parameters["chat_id"] || context["current_chat_id"]
      return awaiting("chat_id is required") if chat_id.to_s.empty?
      return awaiting("message is required") if parameters["message"].to_s.strip.empty?

      chat_service.send(
        chat_id: chat_id,
        message: parameters["message"],
        request_id: request_id,
        interface: context.fetch("interface", "internal")
      )
    end

    def chat_flag(parameters, pinned)
      chat_id = required(parameters, "chat_id")
      return awaiting("unknown chat ID") unless chat_store.chat(chat_id)

      record = pinned ? chat_store.pin(chat_id) : chat_store.unpin(chat_id)
      success({ "record" => chat_projection(record) }, mutation: pinned ? "chat_pinned" : "chat_unpinned")
    end

    def workspace_filters(parameters, require_chat: false)
      chat_id = parameters["chat_id"]
      raise ArgumentError, "chat_id is required" if require_chat && chat_id.to_s.empty?
      {
        chat_id: chat_id,
        kind: parameters["kind"],
        lifecycle: parameters["lifecycle"],
        privacy: parameters["privacy"],
        delivery_state: parameters["delivery_state"],
        limit: bounded_limit(parameters["limit"], ConversationWorkspaceService::MAX_RECORDS)
      }
    end

    def conversation_clear_service
      @conversation_clear_service ||= ConversationClearService.new(root: @root, store: chat_store)
    end

    def conversation_forget_service
      @conversation_forget_service ||= ConversationForgetService.new(root: @root, chat_store: chat_store)
    end

    def configuration_report
      resolved_configuration.first
    end

    def configuration_explain(parameters)
      key = required(parameters, "key")
      report = configuration_report
      return report unless report.fetch("ok")

      setting = report.fetch("settings").find { |record| record.fetch("key") == key }
      return awaiting("unknown configuration key") unless setting

      report.merge("settings" => [setting], "setting_count" => 1)
    end

    def configuration_validate
      report = configuration_report
      report.merge("settings" => [])
    end

    def skills_list(parameters)
      limit = bounded_limit(parameters["limit"], SKILL_LIMIT)
      records = skill_registry.list.sort_by { |skill_id, _definition| skill_id }.first(limit).map do |skill_id, definition|
        {
          "skill_id" => skill_id,
          "description" => definition["description"],
          "risk" => definition["risk"],
          "requires_approval" => definition["requires_approval"] == true,
          "writes_files" => definition["writes_files"] == true,
          "available" => !definition["path"].to_s.empty?
        }
      end
      { "records" => records, "count" => records.length, "limit" => limit, "read_only" => true }
    end

    def approvals_pending(parameters)
      limit = bounded_limit(parameters["limit"], APPROVAL_LIMIT)
      records = approval_store.pending.sort_by { |record| record["issued_at"].to_s }.reverse.first(limit).map do |record|
        {
          "approval_ref" => Digest::SHA256.hexdigest(record.fetch("token_id"))[0, 16],
          "skill_id" => record["skill_id"],
          "status" => record["status"],
          "issued_at" => record["issued_at"],
          "expires_at" => record["expires_at"],
          "scope_digest" => record["scope_digest"],
          "scope_keys" => record.fetch("scope", {}).keys.sort.first(20),
          "authorization_value_exposed" => false
        }
      end
      { "records" => records, "count" => records.length, "limit" => limit, "read_only" => true }
    end

    def activities_recent(parameters)
      limit = bounded_limit(parameters["limit"], ACTIVITY_LIMIT)
      filters = parameters.fetch("filters", {})
      allowed = %w[skill_id status source risk executed ok confirmation_required]
      raise ArgumentError, "unknown activity filter" unless filters.is_a?(Hash) && (filters.keys - allowed).empty?

      rows = activity_store.entries(limit: limit, filters: filters).reverse.map do |entry|
        entry.slice("timestamp", "source", "skill_id", "status", "ok", "executed", "risk", "confirmation_required", "exit_status").merge(
          "blocked_categories" => Array(entry["blocked_by"]).map(&:to_s).select { |value| value.match?(/\A[a-z0-9_.:-]{1,80}\z/i) }.first(10),
          "blocked_count" => Array(entry["blocked_by"]).length
        )
      end
      { "records" => rows, "count" => rows.length, "limit" => limit, "private_messages_exposed" => false }
    end

    def resolved_configuration
      resolver = ConfigurationResolver.new(root: @root, process_env: @process_env)
      [resolver.resolve, resolver]
    end

    def chat_store
      @chat_store ||= @injected_chat_store || ChatStore.new(root: @root)
    end

    def conversation_runtime
      return @injected_runtime if @injected_runtime

      report, resolver = resolved_configuration
      raise RuntimeError, "configuration is invalid" unless report.fetch("ok")
      @conversation_runtime ||= ConversationRuntime.new(root: @root, store: chat_store, env: resolver.effective_environment)
    end

    def chat_service
      @chat_service ||= @injected_chat_service || ApplicationChatService.new(root: @root, store: chat_store, runtime: conversation_runtime)
    end

    def workspace
      @workspace_service ||= ConversationWorkspaceService.new(root: @root)
    end

    def status_collector
      @status_collector ||= HostSystemStatusCollector.new
    end

    def model_runtime_control
      return @model_runtime_control_service if @model_runtime_control_service

      _report, resolver = resolved_configuration
      @model_runtime_control_service ||= ModelRuntimeControlService.new(root: @root, env: resolver.effective_environment)
    end

    def approval_store
      @approval_store ||= ApprovalTokenStore.new(root: @root)
    end

    def activity_store
      @activity_store ||= ChatExecutionHistory.new(root: @root)
    end

    def skill_registry
      @skill_registry ||= SkillRegistry.new(path: File.join(@root, "Soul", "skills", "registry.yaml"))
    end

    def skill_studio
      @skill_studio_service ||= SkillStudioService.new(root: @root, clock: @clock)
    end

    def self_improvement
      @self_improvement_service ||= SelfImprovementService.new(root: @root, clock: @clock)
    end

    def host_improvement
      @host_improvement_plan_service ||= HostImprovementPlanService.new(root: @root, clock: @clock)
    end

    def self_augmentation
      @self_augmentation_service ||= SelfAugmentationService.new(root: @root, clock: @clock)
    end

    def self_augmentation_experiments
      @self_augmentation_experiment_service ||= SelfAugmentationExperimentService.new(root: @root, clock: @clock)
    end

    def chat_projection(chat)
      chat.slice("id", "title", "created_at", "updated_at", "pinned", "pin_order", "archived", "summary")
    end

    def required(parameters, key)
      value = parameters[key]
      raise ArgumentError, "#{key} is required" if value.nil? || (value.respond_to?(:empty?) && value.empty?)

      value
    end

    def bounded_limit(value, maximum)
      return maximum if value.nil?

      number = Integer(value)
      raise ArgumentError, "limit must be positive" unless number.positive?

      [number, maximum].min
    end

    def domain(result)
      lifecycle = result.fetch("lifecycle_state", result.fetch("ok", false) ? "complete" : "failed")
      mutation = result.fetch("mutation", result.fetch("file_mutated", false) ? "domain_mutation" : "none")
      replay = result.fetch("idempotent_replay", false)
      [result, lifecycle, mutation, replay]
    end

    def success(data = {}, mutation: "none")
      { "ok" => true, "lifecycle_state" => "complete", "data" => data, "mutation" => mutation }
    end

    def awaiting(reason)
      { "ok" => false, "lifecycle_state" => "awaiting_input", "reason" => reason, "mutation" => "none" }
    end

    def envelope_from_validation(request, validation)
      envelope(
        request.is_a?(Hash) ? request : {},
        lifecycle: validation.fetch("lifecycle_state"),
        data: {},
        errors: [{ "code" => "invalid_request", "message" => validation.fetch("reason") }]
      )
    end

    def safe_error_envelope(request, lifecycle, code, message)
      envelope(
        request.is_a?(Hash) ? request : {},
        lifecycle: lifecycle,
        data: {},
        errors: [{ "code" => code, "message" => safe_message(message) }]
      )
    end

    def envelope(request, lifecycle:, data:, errors: [], mutation: "none", idempotent_replay: false)
      if data.is_a?(Hash) && data.key?("data") && data.key?("lifecycle_state")
        errors = [{ "code" => "domain_failure", "message" => safe_message(data["reason"]) }] unless data.fetch("ok", false)
        mutation = data.fetch("mutation", mutation)
        data = data.fetch("data")
      elsif data.is_a?(Hash) && data.key?("lifecycle_state")
        errors = [{ "code" => "domain_failure", "message" => safe_message(data["reason"]) }] unless data.fetch("ok", false)
      end
      {
        "schema_version" => Contract::SCHEMA_VERSION,
        "request_id" => request["request_id"].to_s,
        "operation" => request["operation"].to_s,
        "ok" => lifecycle == "complete",
        "lifecycle_state" => lifecycle,
        "data" => data,
        "errors" => errors,
        "warnings" => [],
        "meta" => {
          "generated_at" => @clock.call.iso8601,
          "mutation" => mutation,
          "idempotent_replay" => idempotent_replay,
          "limits" => {
            "chats" => CHAT_LIMIT,
            "messages" => MESSAGE_LIMIT,
            "workspace" => ConversationWorkspaceService::MAX_RECORDS,
            "skills" => SKILL_LIMIT,
            "approvals" => APPROVAL_LIMIT,
            "activities" => ACTIVITY_LIMIT
          }
        }
      }
    end

    def safe_message(message)
      message.to_s
        .gsub(@root, "[PROJECT_ROOT]")
        .gsub(%r{(?:/[A-Za-z0-9._-]+){2,}}, "[REDACTED_PATH]")
        .gsub(/[A-Za-z]:\\(?:[^\\\s]+\\)+[^\\\s]+/, "[REDACTED_PATH]")
        .slice(0, 300)
    end
  end
end
