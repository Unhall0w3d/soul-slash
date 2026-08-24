# frozen_string_literal: true

require "digest"
require "time"
require_relative "application_chat_service"
require_relative "application_contract"
require_relative "application_request_receipt_store"
require_relative "approval_token_store"
require_relative "chat_execution_history"
require_relative "chat_store"
require_relative "configuration_resolver"
require_relative "knowledge_vault_service"
require_relative "local_search_service"
require_relative "conversation_memory_store"
require_relative "memory_retrieval_index"
require_relative "memory_retrieval_service"
require_relative "memory_observatory_service"
require_relative "memory_runtime_private_review_service"
require_relative "semantic_conversation_memory_context"
require_relative "file_inspection_service"
require_relative "network_diagnostic_service"
require_relative "repository_inspection_service"
require_relative "invocation_catalog_service"
require_relative "conversation_provider_registry"
require_relative "conversation_provider_client"
require_relative "conversation_runtime"
require_relative "conversation_security_status_service"
require_relative "conversation_fleet_observability_service"
require_relative "conversation_creative_workflow_service"
require_relative "conversation_maintenance_workflow_service"
require_relative "conversation_core_workflow_service"
require_relative "conversation_clear_service"
require_relative "conversation_forget_service"
require_relative "conversation_workspace_service"
require_relative "host_system_status_collector"
require_relative "host_stewardship_capability_registry"
require_relative "host_stewardship_service"
require_relative "file_steward_service"
require_relative "software_steward_service"
require_relative "storage_steward_service"
require_relative "incident_narrator_service"
require_relative "fleet_observability_summary_service"
require_relative "backup_administration_service"
require_relative "nightly_drs_deployment"
require_relative "project_tracker_service"
require_relative "project_release_service"
require_relative "model_runtime_control_service"
require_relative "core_orchestration_service"
require_relative "memory_embedding_runtime_coordinator"
require_relative "skill_registry"
require_relative "skill_studio_service"
require_relative "self_improvement_service"
require_relative "self_assessment_dev_synthesis_service"
require_relative "maintenance_fleet_status_service"
require_relative "fleet_operations_evidence_service"
require_relative "wazuh_security_status_service"
require_relative "wazuh_alert_evidence_service"
require_relative "wazuh_alert_notification_service"
require_relative "wazuh_compliance_posture_service"
require_relative "maintenance_fleet_discovery_service"
require_relative "maintenance_device_control_service"
require_relative "maintenance_rehearsal_service"
require_relative "maintenance_foreground_execution_service"
require_relative "maintenance_reboot_restore_service"
require_relative "self_augmentation_service"
require_relative "self_augmentation_experiment_service"
require_relative "self_augmentation_dev_critique_service"
require_relative "self_augmentation_dev_handoff_service"
require_relative "music_generation_service"
require_relative "music_vocal_diagnostic_service"
require_relative "music_qualification_service"
require_relative "music_candidate_analysis_service"
require_relative "music_revision_draft_service"
require_relative "music_candidate_disposition_service"
require_relative "music_candidate_trim_service"
require_relative "music_visual_companion_service"
require_relative "music_publication_package_service"
require_relative "youtube_oauth_service"
require_relative "youtube_authenticated_upload_service"
require_relative "music_project_deletion_service"
require_relative "long_form_mix_service"
require_relative "long_form_mix_render_service"
require_relative "long_form_mix_finalization_service"
require_relative "music_reference_library_service"
require_relative "music_reference_analysis_service"
require_relative "music_reference_synthesis_service"
require_relative "visual_studio_service"
require_relative "visual_motion_qualification_service"
require_relative "blender_scene_service"

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
      host_stewardship_capability_registry: nil,
      host_stewardship_service: nil,
      file_steward_service: nil,
      software_steward_service: nil,
      storage_steward_service: nil,
      incident_narrator_service: nil,
      fleet_observability_summary_service: nil,
      backup_administration_service: nil,
      operator_backup_administration_service: nil,
      nightly_drs_deployment: nil,
      operator_nightly_drs_deployment: nil,
      project_tracker_service: nil,
      project_release_service: nil,
      model_runtime_control_service: nil,
      core_orchestration_service: nil,
      approval_store: nil,
      activity_store: nil,
      skill_registry: nil,
      skill_studio_service: nil,
      self_improvement_service: nil,
      self_assessment_dev_synthesis_service: nil,
      maintenance_fleet_status_service: nil,
      fleet_operations_evidence_service: nil,
      wazuh_security_status_service: nil,
      wazuh_alert_evidence_service: nil,
      wazuh_alert_notification_service: nil,
      wazuh_compliance_posture_service: nil,
      maintenance_fleet_discovery_service: nil,
      maintenance_device_control_service: nil,
      maintenance_rehearsal_service: nil,
      maintenance_foreground_execution_service: nil,
      maintenance_reboot_restore_service: nil,
      self_augmentation_service: nil,
      self_augmentation_experiment_service: nil,
      self_augmentation_dev_critique_service: nil,
      self_augmentation_dev_handoff_service: nil,
      music_generation_service: nil,
      music_vocal_diagnostic_service: nil,
      music_qualification_service: nil,
      music_candidate_analysis_service: nil,
      music_revision_draft_service: nil,
      music_revision_provider: nil,
      music_candidate_disposition_service: nil,
      music_candidate_trim_service: nil,
      music_visual_companion_service: nil,
      music_publication_package_service: nil,
      youtube_oauth_service: nil,
      youtube_authenticated_upload_service: nil,
      music_project_deletion_service: nil,
      long_form_mix_service: nil,
      long_form_mix_render_service: nil,
      long_form_mix_finalization_service: nil,
      music_reference_library_service: nil,
      music_reference_analysis_service: nil,
      music_reference_synthesis_service: nil,
      music_reference_synthesis_provider: nil,
      visual_studio_service: nil,
      blender_scene_service: nil,
      knowledge_vault_service: nil,
      local_search_service: nil,
      memory_observatory_service: nil,
      memory_runtime_private_review_service: nil,
      memory_retrieval_service: nil,
      memory_retrieval_index_service: nil,
      conversation_memory_store: nil,
      file_inspection_service: nil,
      network_diagnostic_service: nil,
      repository_inspection_service: nil,
      invocation_catalog_service: nil
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
      @host_stewardship_capability_registry = host_stewardship_capability_registry
      @host_stewardship_service = host_stewardship_service
      @file_steward_service = file_steward_service
      @software_steward_service = software_steward_service
      @storage_steward_service = storage_steward_service
      @incident_narrator_service = incident_narrator_service
      @fleet_observability_summary_service = fleet_observability_summary_service
      @backup_administration_service = backup_administration_service
      @operator_backup_administration_service = operator_backup_administration_service
      @nightly_drs_deployment = nightly_drs_deployment
      @operator_nightly_drs_deployment = operator_nightly_drs_deployment
      @project_tracker_service = project_tracker_service
      @project_release_service = project_release_service
      @model_runtime_control_service = model_runtime_control_service
      @core_orchestration_service = core_orchestration_service
      @approval_store = approval_store
      @activity_store = activity_store
      @skill_registry = skill_registry
      @skill_studio_service = skill_studio_service
      @self_improvement_service = self_improvement_service
      @self_assessment_dev_synthesis_service = self_assessment_dev_synthesis_service
      @maintenance_fleet_status_service = maintenance_fleet_status_service
      @fleet_operations_evidence_service = fleet_operations_evidence_service
      @wazuh_security_status_service = wazuh_security_status_service
      @wazuh_alert_evidence_service = wazuh_alert_evidence_service
      @wazuh_alert_notification_service = wazuh_alert_notification_service
      @wazuh_compliance_posture_service = wazuh_compliance_posture_service
      @maintenance_fleet_discovery_service = maintenance_fleet_discovery_service
      @maintenance_device_control_service = maintenance_device_control_service
      @maintenance_rehearsal_service = maintenance_rehearsal_service
      @maintenance_foreground_execution_service = maintenance_foreground_execution_service
      @maintenance_reboot_restore_service = maintenance_reboot_restore_service
      @self_augmentation_service = self_augmentation_service
      @self_augmentation_experiment_service = self_augmentation_experiment_service
      @self_augmentation_dev_critique_service = self_augmentation_dev_critique_service
      @self_augmentation_dev_handoff_service = self_augmentation_dev_handoff_service
      @music_generation_service = music_generation_service
      @music_vocal_diagnostic_service = music_vocal_diagnostic_service
      @music_qualification_service = music_qualification_service
      @music_candidate_analysis_service = music_candidate_analysis_service
      @music_revision_draft_service = music_revision_draft_service
      @music_revision_provider = music_revision_provider
      @music_candidate_disposition_service = music_candidate_disposition_service
      @music_candidate_trim_service = music_candidate_trim_service
      @music_visual_companion_service = music_visual_companion_service
      @music_publication_package_service = music_publication_package_service
      @youtube_oauth_service = youtube_oauth_service
      @youtube_authenticated_upload_service = youtube_authenticated_upload_service
      @music_project_deletion_service = music_project_deletion_service
      @long_form_mix_service = long_form_mix_service
      @long_form_mix_render_service = long_form_mix_render_service
      @long_form_mix_finalization_service = long_form_mix_finalization_service
      @music_reference_library_service = music_reference_library_service
      @music_reference_analysis_service = music_reference_analysis_service
      @music_reference_synthesis_service = music_reference_synthesis_service
      @music_reference_synthesis_provider = music_reference_synthesis_provider
      @visual_studio_service = visual_studio_service
      @blender_scene_service = blender_scene_service
      @knowledge_vault_service = knowledge_vault_service
      @local_search_service = local_search_service
      @memory_observatory_service = memory_observatory_service
      @memory_runtime_private_review_service = memory_runtime_private_review_service
      @memory_retrieval_service = memory_retrieval_service
      @memory_retrieval_index_service = memory_retrieval_index_service
      @conversation_memory_store = conversation_memory_store
      @file_inspection_service = file_inspection_service
      @network_diagnostic_service = network_diagnostic_service
      @repository_inspection_service = repository_inspection_service
      @invocation_catalog_service = invocation_catalog_service
    end

    def call(request, progress: nil)
      validation = Contract.validate(request)
      return envelope_from_validation(request, validation) unless validation.fetch("ok")

      operation = request.fetch("operation")
      return envelope(request, lifecycle: "canceled", data: { "reason" => "application request canceled" }) if operation == "application.cancel"

      data, lifecycle, mutation, replay = dispatch(operation, request.fetch("parameters", {}), request.fetch("context", {}), request.fetch("request_id"), progress: progress)
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

    def music_artifact_path(project_id:, candidate_id:, artifact:)
      music_generation.artifact_path(project_id: project_id, candidate_id: candidate_id, artifact: artifact)
    end

    def music_visual_artifact_path(project_id:, candidate_id:, visual_id:, artifact:)
      music_visual_companion.artifact_path(project_id: project_id, candidate_id: candidate_id, visual_id: visual_id, artifact: artifact)
    end

    def mix_artifact_path(mix_id:, artifact:)
      long_form_mix_render.artifact_path(mix_id: mix_id, artifact: artifact)
    end

    def visual_artifact_path(project_id:, candidate_id:)
      visual_studio.artifact_path(project_id: project_id, candidate_id: candidate_id)
    end

    def visual_motion_artifact_path(project_id:, motion_id:)
      visual_studio.motion_artifact_path(project_id: project_id, motion_id: motion_id)
    end

    def visual_blender_artifact_path(project_id:, scene_id:, artifact:)
      blender_scene.artifact_path(project_id: project_id, scene_id: scene_id, artifact: artifact)
    end

    private

    def dispatch(operation, parameters, context, request_id, progress: nil)
      case operation
      when "application.bootstrap" then [bootstrap, "complete", "none", false]
      when "chats.list" then [chats_list(parameters), "complete", "none", false]
      when "chats.get" then domain(chats_get(parameters))
      when "chats.messages" then domain(chats_messages(parameters))
      when "chats.progress" then domain(chat_service.progress(chat_id: parameters["chat_id"], limit: bounded_limit(parameters["limit"], ApplicationRequestReceiptStore::MAX_ACTIVE)))
      when "chats.create" then domain(chats_create(parameters))
      when "chats.send" then domain(chats_send(parameters, context, request_id, progress: progress))
      when "chats.creative.execute" then domain(conversation_creative_workflow.execute(chat_id: required(parameters, "chat_id"), flow_id: required(parameters, "flow_id"), action_id: parameters["action_id"], confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"], progress: progress))
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
      when "system_status.refresh" then [collect_system_status, "complete", "none", false]
      when "host_stewardship.capabilities" then domain(host_stewardship_capabilities.snapshot(file_steward_configured: file_steward.configured?))
      when "host_stewardship.snapshot" then domain(host_stewardship.snapshot)
      when "software_steward.refresh" then domain(software_steward.refresh)
      when "storage_steward.refresh" then domain(storage_steward.refresh)
      when "storage_steward.io_diagnostic" then domain(storage_steward.io_diagnostic)
      when "file_steward.roots" then domain(file_steward.roots)
      when "file_steward.inventory" then domain(file_steward.inventory(root_id: required(parameters, "root_id"), relative_path: parameters["relative_path"] || "."))
      when "file_steward.operation.preview" then domain(file_steward.operation_preview(action: required(parameters, "action"), source_root_id: required(parameters, "source_root_id"), source_relative_path: required(parameters, "source_relative_path"), destination_root_id: required(parameters, "destination_root_id"), destination_relative_path: required(parameters, "destination_relative_path")))
      when "file_steward.operation.execute" then domain(file_steward.operation_execute(action: required(parameters, "action"), source_root_id: required(parameters, "source_root_id"), source_relative_path: required(parameters, "source_relative_path"), destination_root_id: required(parameters, "destination_root_id"), destination_relative_path: required(parameters, "destination_relative_path"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "file_steward.quarantine.list" then domain(file_steward.quarantine_list)
      when "file_steward.quarantine.preview" then domain(file_steward.quarantine_preview(root_id: required(parameters, "root_id"), relative_path: required(parameters, "relative_path")))
      when "file_steward.quarantine.execute" then domain(file_steward.quarantine_execute(root_id: required(parameters, "root_id"), relative_path: required(parameters, "relative_path"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "file_steward.restore.preview" then domain(file_steward.restore_preview(quarantine_id: required(parameters, "quarantine_id")))
      when "file_steward.restore.execute" then domain(file_steward.restore_execute(quarantine_id: required(parameters, "quarantine_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "backup.status" then domain(backup_status(password: parameters["password"]))
      when "backup.manifests.reconcile.preview" then domain(backup_administration.manifest_reconciliation_preview)
      when "backup.manifests.reconcile.execute" then domain(backup_administration.manifest_reconciliation_execute(confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "backup.create.preview" then domain(backup_administration.backup_preview(password: required(parameters, "password")))
      when "backup.create.execute" then domain(backup_administration.backup_execute(password: required(parameters, "password"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"], progress: progress))
      when "backup.retention.preview" then domain(backup_administration.retention_preview(password: required(parameters, "password"), snapshot_ids: required(parameters, "snapshot_ids")))
      when "backup.retention.execute" then domain(backup_administration.retention_execute(password: required(parameters, "password"), snapshot_ids: required(parameters, "snapshot_ids"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"], progress: progress))
      when "backup.restore.preview" then domain(backup_administration.restore_preview(password: required(parameters, "password"), snapshot_id: required(parameters, "snapshot_id"), paths: parameters.fetch("paths", []), target_root: parameters["target_root"], repository_source: parameters.fetch("repository_source", "local")))
      when "backup.restore.execute" then domain(backup_administration.restore_execute(password: required(parameters, "password"), snapshot_id: required(parameters, "snapshot_id"), paths: parameters.fetch("paths", []), target_root: parameters["target_root"], repository_source: parameters.fetch("repository_source", "local"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"], progress: progress))
      when "backup.replica.preview" then domain(backup_administration.replica_preview(password: required(parameters, "password")))
      when "backup.replica.execute" then domain(backup_administration.replica_execute(password: required(parameters, "password"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"], progress: progress))
      when "backup.drs.preview" then domain(backup_administration.drs_preview(password: required(parameters, "password")))
      when "backup.drs.execute" then domain(backup_administration.drs_execute(password: required(parameters, "password"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"], progress: progress))
      when "operator_backup.status" then domain(operator_backup_status(password: parameters["password"]))
      when "operator_backup.manifests.reconcile.preview" then domain(operator_backup_administration.manifest_reconciliation_preview)
      when "operator_backup.manifests.reconcile.execute" then domain(operator_backup_administration.manifest_reconciliation_execute(confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "operator_backup.create.preview" then domain(operator_backup_administration.backup_preview(password: required(parameters, "password")))
      when "operator_backup.create.execute" then domain(operator_backup_administration.backup_execute(password: required(parameters, "password"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"], progress: progress))
      when "operator_backup.retention.preview" then domain(operator_backup_administration.retention_preview(password: required(parameters, "password"), snapshot_ids: required(parameters, "snapshot_ids")))
      when "operator_backup.retention.execute" then domain(operator_backup_administration.retention_execute(password: required(parameters, "password"), snapshot_ids: required(parameters, "snapshot_ids"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"], progress: progress))
      when "operator_backup.restore.preview" then domain(operator_backup_administration.restore_preview(password: required(parameters, "password"), snapshot_id: required(parameters, "snapshot_id"), paths: parameters.fetch("paths", []), target_root: parameters["target_root"], repository_source: parameters.fetch("repository_source", "local")))
      when "operator_backup.restore.execute" then domain(operator_backup_administration.restore_execute(password: required(parameters, "password"), snapshot_id: required(parameters, "snapshot_id"), paths: parameters.fetch("paths", []), target_root: parameters["target_root"], repository_source: parameters.fetch("repository_source", "local"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"], progress: progress))
      when "operator_backup.replica.preview" then domain(operator_backup_administration.replica_preview(password: required(parameters, "password")))
      when "operator_backup.replica.execute" then domain(operator_backup_administration.replica_execute(password: required(parameters, "password"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"], progress: progress))
      when "operator_backup.drs.preview" then domain(operator_backup_administration.drs_preview(password: required(parameters, "password")))
      when "operator_backup.drs.execute" then domain(operator_backup_administration.drs_execute(password: required(parameters, "password"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"], progress: progress))
      when "project_tracker.snapshot" then domain(project_tracker.snapshot)
      when "project_tracker.items.create" then domain(project_tracker.create(attributes: required(parameters, "item")))
      when "project_tracker.items.update" then domain(project_tracker.update(item_id: required(parameters, "item_id"), attributes: required(parameters, "item"), expected_revision: required(parameters, "expected_revision")))
      when "core.status" then domain(core_orchestration.status)
      when "core.activate.preview" then domain(core_orchestration.preview(core_id: required(parameters, "core_id")))
      when "core.activate.execute" then domain(core_orchestration.execute(core_id: required(parameters, "core_id"), target_profile_id: required(parameters, "target_profile_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
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
      when "knowledge_vault.status" then domain(knowledge_vault.status)
      when "knowledge_vault.search" then domain(knowledge_vault.search(query: required(parameters, "query"), limit: parameters["limit"]))
      when "knowledge_vault.initialize.preview" then domain(knowledge_vault.initialize_preview)
      when "knowledge_vault.initialize.execute" then domain(knowledge_vault.initialize_execute(confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "knowledge_vault.memory_export.preview" then domain(knowledge_vault.memory_export_preview)
      when "knowledge_vault.memory_export.execute" then domain(knowledge_vault.memory_export_execute(confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "knowledge_vault.memory_import.preview" then domain(knowledge_vault.memory_import_preview(relative_path: required(parameters, "relative_path"), layer: required(parameters, "layer")))
      when "knowledge_vault.memory_import.execute" then domain(knowledge_vault.memory_import_execute(relative_path: required(parameters, "relative_path"), layer: required(parameters, "layer"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "knowledge_vault.reflection.preview"
        domain(knowledge_vault.reflection_preview(
          title: required(parameters, "title"),
          body: required(parameters, "body"),
          knowledge_kind: required(parameters, "knowledge_kind"),
          evidence_status: required(parameters, "evidence_status"),
          source_reference: required(parameters, "source_reference"),
          target_relative_path: parameters["target_relative_path"],
          tags: parameters["tags"] || []
        ))
      when "knowledge_vault.reflection.execute"
        domain(knowledge_vault.reflection_execute(
          title: required(parameters, "title"),
          body: required(parameters, "body"),
          knowledge_kind: required(parameters, "knowledge_kind"),
          evidence_status: required(parameters, "evidence_status"),
          source_reference: required(parameters, "source_reference"),
          target_relative_path: parameters["target_relative_path"],
          tags: parameters["tags"] || [],
          confirmation: parameters["confirmation"],
          expected_digest: parameters["expected_digest"]
        ))
      when "local_search.search"
        domain(local_search.search(
          query: required(parameters, "query"),
          limit: parameters["limit"],
          sources: parameters["sources"]
        ))
      when "memory.observatory.summary" then domain(memory_observatory.summary)
      when "memory.observatory.query" then domain(memory_observatory.query(query: required(parameters, "query"), limit: parameters["limit"]))
      when "memory.observatory.runtime" then domain(memory_runtime_private_review.runtime)
      when "memory.observatory.private_review" then domain(memory_runtime_private_review.private_review)
      when "files.roots" then domain(file_inspection.roots)
      when "files.list" then domain(file_inspection.list(root_id: required(parameters, "root_id"), relative_path: parameters["relative_path"] || "."))
      when "files.stat" then domain(file_inspection.stat(root_id: required(parameters, "root_id"), relative_path: required(parameters, "relative_path")))
      when "files.read" then domain(file_inspection.read(root_id: required(parameters, "root_id"), relative_path: required(parameters, "relative_path")))
      when "network.snapshot" then domain(network_diagnostic.snapshot)
      when "network.resolve" then domain(network_diagnostic.resolve(target: required(parameters, "target")))
      when "network.reachability" then domain(network_diagnostic.reachability(target: required(parameters, "target")))
      when "network.socket" then domain(network_diagnostic.socket(target: required(parameters, "target"), port: required(parameters, "port")))
      when "repositories.roots" then domain(repository_inspection.roots)
      when "repository.inspect" then domain(repository_inspection.inspect(root_id: required(parameters, "root_id")))
      when "invocations.list" then [invocation_catalog.list(category: parameters["category"], query: parameters["query"]), "complete", "none", false]
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
      when "skill_studio.betas.dev_build.preview" then domain(skill_studio.dev_build_preview(beta_id: required(parameters, "beta_id")))
      when "skill_studio.betas.dev_build.execute" then domain(skill_studio.build_beta_with_dev_core(beta_id: required(parameters, "beta_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"], on_progress: progress))
      when "skill_studio.betas.run.preview" then domain(skill_studio.beta_run_preview(beta_id: required(parameters, "beta_id"), args: parameters.fetch("args", [])))
      when "skill_studio.betas.run.execute" then domain(skill_studio.run_beta(beta_id: required(parameters, "beta_id"), args: parameters.fetch("args", []), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "skill_studio.betas.promotion.preview" then domain(skill_studio.promotion_preview(beta_id: required(parameters, "beta_id")))
      when "skill_studio.betas.promotion.approve" then domain(skill_studio.approve_beta_for_promotion(beta_id: required(parameters, "beta_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "skill_studio.betas.production.preview" then domain(skill_studio.production_promotion_preview(beta_id: required(parameters, "beta_id")))
      when "skill_studio.betas.production.execute" then domain(skill_studio.promote_beta_to_production(beta_id: required(parameters, "beta_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "self_improvement.snapshot" then domain(self_improvement.snapshot)
      when "self_improvement.refresh" then domain(self_improvement.refresh(scope: required(parameters, "scope")))
      when "self_improvement.dev_synthesis.preview" then domain(self_assessment_dev_synthesis.preview(scope: required(parameters, "scope")))
      when "self_improvement.dev_synthesis.execute" then domain(self_assessment_dev_synthesis.execute(scope: required(parameters, "scope"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"], on_progress: progress))
      when "self_improvement.dev_synthesis.list" then domain(self_assessment_dev_synthesis.inventory(limit: bounded_limit(parameters["limit"], SelfAssessmentDevSynthesisService::MAX_RECORDS)))
      when "self_improvement.proposals.preview" then domain(self_improvement.proposal_preview)
      when "self_improvement.proposals.execute" then domain(self_improvement.generate_proposals(confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "storage_retention.cleanup.preview" then domain(self_improvement.storage_cleanup_preview(category: required(parameters, "category")))
      when "storage_retention.cleanup.execute" then domain(self_improvement.storage_cleanup_execute(category: required(parameters, "category"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "maintenance.fleet.status" then domain(maintenance_fleet_status.collect)
      when "maintenance.fleet.device.refresh" then domain(maintenance_fleet_status.refresh(device_id: required(parameters, "device_id")))
      when "maintenance.fleet.snapshot" then domain(maintenance_fleet_status.snapshot)
      when "maintenance.fleet.evidence" then domain(fleet_operations_evidence.compose)
      when "security.wazuh.status" then domain(wazuh_security_status.collect)
      when "security.wazuh.snapshot" then domain(wazuh_security_status.snapshot)
      when "security.wazuh.alerts.status" then domain(wazuh_alert_evidence.collect)
      when "security.wazuh.alerts.snapshot" then domain(wazuh_alert_evidence.snapshot)
      when "security.wazuh.notifications.status" then domain(wazuh_alert_notifications.status)
      when "security.wazuh.posture.status" then domain(wazuh_compliance_posture.status)
      when "security.wazuh.posture.snapshot" then domain(wazuh_compliance_posture.snapshot)
      when "incident_narrator.compose" then domain(incident_narrator.compose)
      when "fleet_observability.summary" then domain(fleet_observability_summary.summary)
      when "maintenance.discovery.status" then domain(maintenance_fleet_discovery.status)
      when "maintenance.discovery.scan" then domain(maintenance_fleet_discovery.discover(subnet: required(parameters, "subnet")))
      when "maintenance.discovery.registry" then domain(maintenance_fleet_discovery.registry)
      when "maintenance.discovery.ignored" then domain(maintenance_fleet_discovery.ignored)
      when "maintenance.discovery.ignore.preview" then domain(maintenance_fleet_discovery.ignore_preview(address: required(parameters, "address"), label: required(parameters, "label"), subnet: required(parameters, "subnet"), mac_address: parameters["mac_address"], vendor: parameters["vendor"]))
      when "maintenance.discovery.ignore.execute" then domain(maintenance_fleet_discovery.ignore(address: required(parameters, "address"), label: required(parameters, "label"), subnet: required(parameters, "subnet"), mac_address: parameters["mac_address"], vendor: parameters["vendor"], confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "maintenance.discovery.restore.preview" then domain(maintenance_fleet_discovery.restore_preview(identity_key: required(parameters, "identity_key")))
      when "maintenance.discovery.restore.execute" then domain(maintenance_fleet_discovery.restore(identity_key: required(parameters, "identity_key"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "maintenance.discovery.ssh_alias.preview" then domain(maintenance_fleet_discovery.ssh_alias_preview(address: required(parameters, "address"), ssh_alias: required(parameters, "ssh_alias"), ssh_user: required(parameters, "ssh_user"), identity_file: required(parameters, "identity_file")))
      when "maintenance.discovery.ssh_alias.execute" then domain(maintenance_fleet_discovery.add_ssh_alias(address: required(parameters, "address"), ssh_alias: required(parameters, "ssh_alias"), ssh_user: required(parameters, "ssh_user"), identity_file: required(parameters, "identity_file"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "maintenance.discovery.enroll.preview" then domain(maintenance_fleet_discovery.enrollment_preview(address: required(parameters, "address"), label: required(parameters, "label"), mode: required(parameters, "mode"), ssh_alias: parameters["ssh_alias"], address_policy: parameters.fetch("address_policy", "fixed"), subnet: parameters["subnet"], mac_address: parameters["mac_address"]))
      when "maintenance.discovery.enroll.execute" then domain(maintenance_fleet_discovery.enroll(address: required(parameters, "address"), label: required(parameters, "label"), mode: required(parameters, "mode"), ssh_alias: parameters["ssh_alias"], address_policy: parameters.fetch("address_policy", "fixed"), subnet: parameters["subnet"], mac_address: parameters["mac_address"], confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "maintenance.discovery.remove.preview" then domain(maintenance_fleet_discovery.removal_preview(device_id: required(parameters, "device_id")))
      when "maintenance.discovery.remove.execute" then domain(maintenance_fleet_discovery.remove(device_id: required(parameters, "device_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "maintenance.device.preview" then domain(maintenance_device_control.preview(device_id: required(parameters, "device_id"), action: required(parameters, "action")))
      when "maintenance.device.execute" then domain(maintenance_device_control.execute(device_id: required(parameters, "device_id"), action: required(parameters, "action"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"], progress: progress))
      when "maintenance.device.receipts" then domain(maintenance_device_control.receipts(limit: bounded_limit(parameters["limit"], MaintenanceDeviceControlService::MAX_RECEIPTS)))
      when "maintenance.preview" then domain(maintenance_rehearsal.preview(force_database_refresh: parameters.fetch("force_database_refresh", false)))
      when "maintenance.rehearsal" then domain(maintenance_rehearsal.rehearse(force_database_refresh: parameters.fetch("force_database_refresh", false)))
      when "maintenance.execution.preview" then domain(maintenance_foreground_execution.preview(force_database_refresh: parameters.fetch("force_database_refresh", false)))
      when "maintenance.evidence.reserve" then domain(maintenance_foreground_execution.reserve_native_evidence)
      when "maintenance.aur_review.reserve" then domain(maintenance_foreground_execution.reserve_aur_review)
      when "maintenance.execution.rehearsal" then domain(maintenance_foreground_execution.rehearse(force_database_refresh: parameters.fetch("force_database_refresh", false), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "maintenance.execution.execute" then domain(maintenance_foreground_execution.execute(force_database_refresh: parameters.fetch("force_database_refresh", false), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "maintenance.execution.receipts" then domain(maintenance_foreground_execution.receipts(limit: bounded_limit(parameters["limit"], MaintenanceForegroundExecutionService::MAX_RECEIPTS)))
      when "maintenance.reboot_restore.preview" then domain(maintenance_reboot_restore.preview(force_database_refresh: parameters.fetch("force_database_refresh", false)))
      when "maintenance.reboot_restore.execute" then domain(maintenance_reboot_restore.execute(force_database_refresh: parameters.fetch("force_database_refresh", false), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "maintenance.reboot_restore.status" then domain(maintenance_reboot_restore.status)
      when "self_augmentation.census" then domain(self_augmentation.census)
      when "self_augmentation.proposals.list" then domain(self_augmentation.inventory(limit: bounded_limit(parameters["limit"], SelfAugmentationService::MAX_RECORDS)))
      when "self_augmentation.proposals.preview" then domain(self_augmentation.preview(objective: required(parameters, "objective"), why_not_skill: required(parameters, "why_not_skill")))
      when "self_augmentation.proposals.execute" then domain(self_augmentation.create_proposal(objective: required(parameters, "objective"), why_not_skill: required(parameters, "why_not_skill"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "self_augmentation.dev_critique.list" then domain(self_augmentation_dev_critique.inventory(limit: bounded_limit(parameters["limit"], SelfAugmentationDevCritiqueService::MAX_RECORDS)))
      when "self_augmentation.dev_critique.preview" then domain(self_augmentation_dev_critique.preview(proposal_id: required(parameters, "proposal_id")))
      when "self_augmentation.dev_critique.execute" then domain(self_augmentation_dev_critique.execute(proposal_id: required(parameters, "proposal_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"], on_progress: progress))
      when "self_augmentation.experiments.list" then domain(self_augmentation_experiments.inventory(limit: bounded_limit(parameters["limit"], SelfAugmentationExperimentService::MAX_RECORDS)))
      when "self_augmentation.experiments.gate_a1.preview" then domain(self_augmentation_experiments.gate_a1_preview(proposal_id: required(parameters,"proposal_id"), allowed_files: required(parameters,"allowed_files")))
      when "self_augmentation.experiments.gate_a1.execute" then domain(self_augmentation_experiments.prepare_experiment(proposal_id: required(parameters,"proposal_id"), allowed_files: required(parameters,"allowed_files"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "self_augmentation.dev_handoff.list" then domain(self_augmentation_dev_handoff.inventory(limit: bounded_limit(parameters["limit"], SelfAugmentationDevHandoffService::MAX_RECORDS)))
      when "self_augmentation.dev_handoff.preview" then domain(self_augmentation_dev_handoff.preview(experiment_id: required(parameters,"experiment_id")))
      when "self_augmentation.dev_handoff.execute" then domain(self_augmentation_dev_handoff.execute(experiment_id: required(parameters,"experiment_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"], on_progress: progress))
      when "self_augmentation.reviews.generate" then domain(self_augmentation_experiments.generate_dossier(experiment_id: required(parameters,"experiment_id")))
      when "self_augmentation.reviews.gate_a2.preview" then domain(self_augmentation_experiments.gate_a2_preview(experiment_id: required(parameters,"experiment_id")))
      when "self_augmentation.reviews.gate_a2.execute" then domain(self_augmentation_experiments.approve_for_integration(experiment_id: required(parameters,"experiment_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "self_augmentation.model_qualification.preview" then domain(self_augmentation_experiments.model_qualification_preview(experiment_id: required(parameters,"experiment_id"), suite_id: required(parameters,"suite_id"), model_profile: required(parameters,"model_profile"), result: required(parameters,"result"), evidence_digest: required(parameters,"evidence_digest")))
      when "self_augmentation.model_qualification.execute" then domain(self_augmentation_experiments.record_model_qualification(experiment_id: required(parameters,"experiment_id"), suite_id: required(parameters,"suite_id"), model_profile: required(parameters,"model_profile"), result: required(parameters,"result"), evidence_digest: required(parameters,"evidence_digest"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "self_augmentation.experiments.cleanup.preview" then domain(self_augmentation_experiments.cleanup_preview(experiment_id: required(parameters,"experiment_id")))
      when "self_augmentation.experiments.cleanup.execute" then domain(self_augmentation_experiments.cleanup(experiment_id: required(parameters,"experiment_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "music.projects.list" then domain(project_release.decorate_outcome(music_generation.list_projects(limit: bounded_limit(parameters["limit"], 200)), kind: "music"))
      when "music.projects.create" then domain(music_generation.create_project(required(parameters, "project")))
      when "music.projects.get" then domain(music_project_with_analysis(project_id: required(parameters, "project_id")))
      when "music.vocals.diagnostic" then domain(music_vocal_diagnostic.inspect(project_id: required(parameters, "project_id")))
      when "music.qualification" then domain(music_qualification.snapshot)
      when "music.projects.release" then domain(project_release.release(kind: "music", project_id: required(parameters, "project_id")))
      when "music.projects.restore" then domain(project_release.restore(kind: "music", project_id: required(parameters, "project_id")))
      when "music.projects.delete.preview" then domain(music_project_deletion.preview(project_id: required(parameters, "project_id")))
      when "music.projects.delete.execute" then domain(music_project_deletion.execute(project_id: required(parameters, "project_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "mix.sources.list" then domain(long_form_mix.sources(limit: bounded_limit(parameters["limit"], LongFormMixService::MAX_LIMIT)))
      when "mix.projects.list" then domain(long_form_mix.list(limit: bounded_limit(parameters["limit"], LongFormMixService::MAX_LIMIT)))
      when "mix.projects.get" then domain(long_form_mix.get(mix_id: required(parameters, "mix_id")))
      when "mix.projects.create" then domain(long_form_mix.create(plan: required(parameters, "plan")))
      when "mix.handoff.preview" then domain(long_form_mix.handoff_preview(mix_id: required(parameters, "mix_id")))
      when "mix.handoff.execute" then domain(long_form_mix.handoff_execute(mix_id: required(parameters, "mix_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "mix.render.status" then domain(long_form_mix_render.status(mix_id: required(parameters, "mix_id")))
      when "mix.render.preview" then domain(long_form_mix_render.preview(mix_id: required(parameters, "mix_id")))
      when "mix.render.execute" then domain(long_form_mix_render.execute(mix_id: required(parameters, "mix_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "mix.final.status" then domain(long_form_mix_finalization.status(mix_id: required(parameters, "mix_id")))
      when "mix.final.review" then domain(long_form_mix_finalization.record_review(mix_id: required(parameters, "mix_id"), review: required(parameters, "review")))
      when "mix.final.export.preview" then domain(long_form_mix_finalization.export_preview(mix_id: required(parameters, "mix_id")))
      when "mix.final.export.execute" then domain(long_form_mix_finalization.export_execute(mix_id: required(parameters, "mix_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "music.references.list" then domain(music_reference_library.inventory(limit: bounded_limit(parameters["limit"], 500)))
      when "music.references.get" then domain(music_reference_library.inspect(identifier: required(parameters, "reference_id")))
      when "music.references.delete.preview" then domain(music_reference_library.deletion_preview(identifier: required(parameters, "reference_id")))
      when "music.references.delete.execute" then domain(music_reference_library.delete(identifier: required(parameters, "reference_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "music.references.status" then domain(music_reference_analysis.status)
      when "music.references.analysis.preview" then domain(music_reference_analysis.preview(url: required(parameters, "url"), rights_assertion: required(parameters, "rights_assertion")))
      when "music.references.analysis.execute" then domain(music_reference_analysis.execute(url: required(parameters, "url"), rights_assertion: required(parameters, "rights_assertion"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"], progress: progress))
      when "music.references.reanalysis.preview" then domain(music_reference_analysis.reanalysis_preview(reference_id: required(parameters, "reference_id")))
      when "music.references.reanalysis.execute" then domain(music_reference_analysis.reanalyze(reference_id: required(parameters, "reference_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"], progress: progress))
      when "music.references.synthesis.draft" then domain(draft_music_reference_synthesis(reference_id: required(parameters, "reference_id"), scope: required(parameters, "scope")))
      when "music.references.synthesis.approval.preview" then domain(music_reference_synthesis.approval_preview(reference_id: required(parameters, "reference_id"), revision_id: required(parameters, "revision_id")))
      when "music.references.synthesis.approval.execute" then domain(music_reference_synthesis.approve(reference_id: required(parameters, "reference_id"), revision_id: required(parameters, "revision_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "music.references.synthesis.rejection.preview" then domain(music_reference_synthesis.rejection_preview(reference_id: required(parameters, "reference_id"), revision_id: required(parameters, "revision_id")))
      when "music.references.synthesis.rejection.execute" then domain(music_reference_synthesis.reject(reference_id: required(parameters, "reference_id"), revision_id: required(parameters, "revision_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "music.references.fusion.draft" then domain(draft_music_reference_fusion(reference_ids: required(parameters, "reference_ids")))
      when "music.resources.status" then domain(music_generation.resource_inventory)
      when "music.generation.preview" then domain(music_generation.generation_preview(project_id: required(parameters, "project_id")))
      when "music.generation.execute" then domain(music_generation.generation_execute(project_id: required(parameters, "project_id"), candidate_id: required(parameters, "candidate_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"], progress: progress))
      when "music.generation.cancel.preview" then domain(music_generation.cancel_preview(candidate_id: required(parameters, "candidate_id")))
      when "music.generation.cancel.execute" then domain(music_generation.cancel_execute(candidate_id: required(parameters, "candidate_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "music.candidates.analysis.preview" then domain(music_candidate_analysis.preview(project_id: required(parameters, "project_id"), candidate_id: required(parameters, "candidate_id")))
      when "music.candidates.analysis.execute" then domain(music_candidate_analysis.execute(project_id: required(parameters, "project_id"), candidate_id: required(parameters, "candidate_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"], progress: progress))
      when "music.candidates.revision.draft" then domain(draft_music_revision(project_id: required(parameters, "project_id"), source_candidate_id: required(parameters, "source_candidate_id")))
      when "music.candidates.revision.preview" then domain(music_generation.revision_preview(project_id: required(parameters, "project_id"), source_candidate_id: required(parameters, "source_candidate_id"), revision: required(parameters, "revision")))
      when "music.candidates.revision.execute" then domain(music_generation.revision_execute(project_id: required(parameters, "project_id"), source_candidate_id: required(parameters, "source_candidate_id"), candidate_id: required(parameters, "candidate_id"), revision: required(parameters, "revision"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"], progress: progress))
      when "music.candidates.review" then domain(music_generation.record_review(project_id: required(parameters, "project_id"), candidate_id: required(parameters, "candidate_id"), review: required(parameters, "review")))
      when "music.candidates.reject.preview" then domain(music_candidate_disposition.reject_preview(project_id: required(parameters, "project_id"), candidate_id: required(parameters, "candidate_id")))
      when "music.candidates.reject.execute" then domain(music_candidate_disposition.reject_execute(project_id: required(parameters, "project_id"), candidate_id: required(parameters, "candidate_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "music.candidates.export.preview" then domain(music_candidate_disposition.export_preview(project_id: required(parameters, "project_id"), candidate_id: required(parameters, "candidate_id")))
      when "music.candidates.export.execute" then domain(music_candidate_disposition.export_execute(project_id: required(parameters, "project_id"), candidate_id: required(parameters, "candidate_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "music.candidates.trim.preview" then domain(music_candidate_trim.preview(project_id: required(parameters, "project_id"), candidate_id: required(parameters, "candidate_id"), start_seconds: required(parameters, "start_seconds"), end_seconds: required(parameters, "end_seconds")))
      when "music.candidates.trim.execute" then domain(music_candidate_trim.execute(project_id: required(parameters, "project_id"), candidate_id: required(parameters, "candidate_id"), start_seconds: required(parameters, "start_seconds"), end_seconds: required(parameters, "end_seconds"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "music.visuals.import.preview" then domain(music_visual_companion.import_preview(project_id: required(parameters, "project_id"), candidate_id: required(parameters, "candidate_id"), asset_id: required(parameters, "asset_id")))
      when "music.visuals.import.execute" then domain(music_visual_companion.import_execute(project_id: required(parameters, "project_id"), candidate_id: required(parameters, "candidate_id"), asset_id: required(parameters, "asset_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "music.visuals.loop.preview" then domain(music_visual_companion.loop_preview(project_id: required(parameters, "project_id"), candidate_id: required(parameters, "candidate_id"), visual_id: required(parameters, "visual_id"), presentation: parameters["visual_presentation"]))
      when "music.visuals.loop.execute" then domain(music_visual_companion.loop_execute(project_id: required(parameters, "project_id"), candidate_id: required(parameters, "candidate_id"), visual_id: required(parameters, "visual_id"), presentation: parameters["visual_presentation"], confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"], progress: progress))
      when "music.visuals.final.preview" then domain(music_visual_companion.final_preview(project_id: required(parameters, "project_id"), candidate_id: required(parameters, "candidate_id"), visual_id: required(parameters, "visual_id")))
      when "music.visuals.final.execute" then domain(music_visual_companion.final_execute(project_id: required(parameters, "project_id"), candidate_id: required(parameters, "candidate_id"), visual_id: required(parameters, "visual_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"], progress: progress))
      when "music.publication.draft" then domain(music_publication_package.draft(project_id: required(parameters, "project_id"), candidate_id: required(parameters, "candidate_id"), visual_id: required(parameters, "visual_id")))
      when "music.publication.preview" then domain(music_publication_package.preview(project_id: required(parameters, "project_id"), candidate_id: required(parameters, "candidate_id"), visual_id: required(parameters, "visual_id"), description: required(parameters, "description")))
      when "music.publication.execute" then domain(music_publication_package.execute(project_id: required(parameters, "project_id"), candidate_id: required(parameters, "candidate_id"), visual_id: required(parameters, "visual_id"), description: required(parameters, "description"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "youtube.oauth.status" then domain(youtube_oauth.status)
      when "youtube.oauth.authorization.preview" then domain(youtube_oauth.preview(client_path: required(parameters, "client_path")))
      when "youtube.oauth.authorization.execute" then domain(youtube_oauth.execute(client_path: required(parameters, "client_path"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "youtube.upload.preview" then domain(youtube_authenticated_upload.preview(project_id: required(parameters, "project_id"), candidate_id: required(parameters, "candidate_id"), visual_id: required(parameters, "visual_id"), visibility: parameters.fetch("visibility", "private")))
      when "youtube.upload.execute" then domain(youtube_authenticated_upload.execute(project_id: required(parameters, "project_id"), candidate_id: required(parameters, "candidate_id"), visual_id: required(parameters, "visual_id"), visibility: parameters.fetch("visibility", "private"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"], progress: progress))
      when "visual.resources.status" then domain(visual_studio.resources)
      when "visual.motion.qualification" then domain(visual_motion_qualification.snapshot)
      when "visual.projects.list" then domain(project_release.decorate_outcome(visual_studio.list(limit: bounded_limit(parameters["limit"], 200)), kind: "visual"))
      when "visual.projects.create" then domain(visual_studio.create(required(parameters, "visual_project")))
      when "visual.projects.get" then domain(project_release.decorate_outcome(visual_studio.inspect(project_id: required(parameters, "visual_project_id")), kind: "visual"))
      when "visual.projects.release" then domain(project_release.release(kind: "visual", project_id: required(parameters, "visual_project_id")))
      when "visual.projects.restore" then domain(project_release.restore(kind: "visual", project_id: required(parameters, "visual_project_id")))
      when "visual.projects.update" then domain(visual_studio.update(project_id: required(parameters, "visual_project_id"), attributes: required(parameters, "visual_project")))
      when "visual.projects.delete.preview" then domain(visual_studio.project_delete_preview(project_id: required(parameters, "visual_project_id")))
      when "visual.projects.delete.execute" then domain(visual_studio.project_delete_execute(project_id: required(parameters, "visual_project_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "visual.generation.preview" then domain(visual_studio.generation_preview(project_id: required(parameters, "visual_project_id")))
      when "visual.generation.execute" then domain(visual_studio.generation_execute(project_id: required(parameters, "visual_project_id"), candidate_id: required(parameters, "visual_candidate_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"], progress: progress))
      when "visual.candidates.review" then domain(visual_studio.record_review(project_id: required(parameters, "visual_project_id"), candidate_id: required(parameters, "visual_candidate_id"), review: required(parameters, "visual_review")))
      when "visual.candidates.delete.preview" then domain(visual_studio.candidate_delete_preview(project_id: required(parameters, "visual_project_id"), candidate_id: required(parameters, "visual_candidate_id")))
      when "visual.candidates.delete.execute" then domain(visual_studio.candidate_delete_execute(project_id: required(parameters, "visual_project_id"), candidate_id: required(parameters, "visual_candidate_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "visual.edit.preview" then domain(visual_studio.edit_preview(project_id: required(parameters, "visual_project_id"), source_candidate_id: required(parameters, "source_visual_candidate_id"), instruction: required(parameters, "instruction"), seed: required(parameters, "seed")))
      when "visual.edit.execute" then domain(visual_studio.edit_execute(project_id: required(parameters, "visual_project_id"), source_candidate_id: required(parameters, "source_visual_candidate_id"), candidate_id: required(parameters, "visual_candidate_id"), instruction: required(parameters, "instruction"), seed: required(parameters, "seed"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"], progress: progress))
      when "visual.promotion.preview" then domain(visual_studio.promotion_preview(project_id: required(parameters, "visual_project_id"), candidate_id: required(parameters, "visual_candidate_id"), music_project_id: required(parameters, "project_id"), music_candidate_id: required(parameters, "candidate_id")))
      when "visual.promotion.execute" then domain(visual_studio.promotion_execute(project_id: required(parameters, "visual_project_id"), candidate_id: required(parameters, "visual_candidate_id"), music_project_id: required(parameters, "project_id"), music_candidate_id: required(parameters, "candidate_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "visual.motion.preview" then domain(visual_studio.motion_preview(project_id: required(parameters, "visual_project_id"), source_candidate_id: required(parameters, "source_visual_candidate_id"), instruction: required(parameters, "instruction"), seed: required(parameters, "seed")))
      when "visual.motion.execute" then domain(visual_studio.motion_execute(project_id: required(parameters, "visual_project_id"), source_candidate_id: required(parameters, "source_visual_candidate_id"), motion_id: required(parameters, "motion_candidate_id"), instruction: required(parameters, "instruction"), seed: required(parameters, "seed"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"], progress: progress))
      when "visual.native_motion.preview" then domain(visual_studio.native_motion_preview(project_id: required(parameters, "visual_project_id"), instruction: required(parameters, "instruction"), seed: required(parameters, "seed"), duration_seconds: parameters.fetch("duration_seconds", "4")))
      when "visual.native_motion.execute" then domain(visual_studio.native_motion_execute(project_id: required(parameters, "visual_project_id"), motion_id: required(parameters, "motion_candidate_id"), instruction: required(parameters, "instruction"), seed: required(parameters, "seed"), duration_seconds: parameters.fetch("duration_seconds", "4"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"], progress: progress))
      when "visual.native_motion.revision.preview" then domain(visual_studio.native_motion_revision_preview(project_id: required(parameters, "visual_project_id"), source_motion_id: required(parameters, "source_motion_candidate_id"), instruction: required(parameters, "instruction"), seed: required(parameters, "seed"), duration_seconds: required(parameters, "duration_seconds")))
      when "visual.native_motion.revision.execute" then domain(visual_studio.native_motion_revision_execute(project_id: required(parameters, "visual_project_id"), source_motion_id: required(parameters, "source_motion_candidate_id"), motion_id: required(parameters, "motion_candidate_id"), instruction: required(parameters, "instruction"), seed: required(parameters, "seed"), duration_seconds: required(parameters, "duration_seconds"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"], progress: progress))
      when "visual.motion.review" then domain(visual_studio.motion_review(project_id: required(parameters, "visual_project_id"), motion_id: required(parameters, "motion_candidate_id"), review: required(parameters, "visual_review")))
      when "visual.motion.delete.preview" then domain(visual_studio.motion_delete_preview(project_id: required(parameters, "visual_project_id"), motion_id: required(parameters, "motion_candidate_id")))
      when "visual.motion.delete.execute" then domain(visual_studio.motion_delete_execute(project_id: required(parameters, "visual_project_id"), motion_id: required(parameters, "motion_candidate_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "visual.motion.promotion.preview" then domain(visual_studio.motion_promotion_preview(project_id: required(parameters, "visual_project_id"), motion_id: required(parameters, "motion_candidate_id"), music_project_id: required(parameters, "project_id"), music_candidate_id: required(parameters, "candidate_id")))
      when "visual.motion.promotion.execute" then domain(visual_studio.motion_promotion_execute(project_id: required(parameters, "visual_project_id"), motion_id: required(parameters, "motion_candidate_id"), music_project_id: required(parameters, "project_id"), music_candidate_id: required(parameters, "candidate_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "visual.blender.resources" then domain(blender_scene.resources)
      when "visual.blender.templates" then domain(blender_scene.templates)
      when "visual.blender.list" then domain(blender_scene.list(project_id: required(parameters, "visual_project_id")))
      when "visual.blender.preview" then domain(blender_scene.preview(project_id: required(parameters, "visual_project_id"), music_project_id: required(parameters, "project_id"), music_candidate_id: required(parameters, "candidate_id"), template_id: required(parameters, "template_id"), bars: required(parameters, "bars"), direction: required(parameters, "direction"), seed: required(parameters, "seed"), quality: parameters.fetch("quality", "review"), look_profile: parameters.fetch("look_profile", "template"), temporal_mode: parameters.fetch("temporal_mode", "whole_bar_loop"), comparison_scene_ids: parameters["comparison_scene_ids"], source_scene_id: parameters["source_blender_scene_id"]))
      when "visual.blender.execute" then domain(blender_scene.execute(project_id: required(parameters, "visual_project_id"), scene_id: required(parameters, "blender_scene_id"), music_project_id: required(parameters, "project_id"), music_candidate_id: required(parameters, "candidate_id"), template_id: required(parameters, "template_id"), bars: required(parameters, "bars"), direction: required(parameters, "direction"), seed: required(parameters, "seed"), quality: parameters.fetch("quality", "review"), look_profile: parameters.fetch("look_profile", "template"), temporal_mode: parameters.fetch("temporal_mode", "whole_bar_loop"), comparison_scene_ids: parameters["comparison_scene_ids"], source_scene_id: parameters["source_blender_scene_id"], confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"], progress: progress))
      when "visual.blender.resume.preview" then domain(blender_scene.resume_preview(project_id: required(parameters, "visual_project_id"), scene_id: required(parameters, "blender_scene_id")))
      when "visual.blender.resume.execute" then domain(blender_scene.resume_execute(project_id: required(parameters, "visual_project_id"), scene_id: required(parameters, "blender_scene_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"], progress: progress))
      when "visual.blender.review" then domain(blender_scene.review(project_id: required(parameters, "visual_project_id"), scene_id: required(parameters, "blender_scene_id"), review: required(parameters, "visual_review")))
      when "visual.blender.delete.preview" then domain(blender_scene.delete_preview(project_id: required(parameters, "visual_project_id"), scene_id: required(parameters, "blender_scene_id")))
      when "visual.blender.delete.execute" then domain(blender_scene.delete_execute(project_id: required(parameters, "visual_project_id"), scene_id: required(parameters, "blender_scene_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
      when "visual.blender.promotion.preview" then domain(blender_scene.promotion_preview(project_id: required(parameters, "visual_project_id"), scene_id: required(parameters, "blender_scene_id")))
      when "visual.blender.promotion.execute" then domain(blender_scene.promotion_execute(project_id: required(parameters, "visual_project_id"), scene_id: required(parameters, "blender_scene_id"), confirmation: parameters["confirmation"], expected_digest: parameters["expected_digest"]))
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
        "product_tabs" => ["Chat", "Self Improvement", "Creative Studios", "Administration"],
        "administration_surfaces" => ["Host Stewardship", "Project Timeline", "Local Topology", "Backup & Recovery", "Guided Maintenance"],
        "creative_surfaces" => ["Music Studio", "Visual Studio", "Mix Studio"],
        "self_improvement_surfaces" => ["Skill Studio", "Self Assessment", "Self Augmentation"],
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
        "cores" => {
          "available" => true,
          "manual_only" => true,
          "status_operation" => "core.status",
          "activation_gate" => "existing_runtime_idle_check_preview_digest_and_exact_confirmation",
          "automatic_switch" => false,
          "music_studio_is_a_core" => false
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
        "music_studio" => {
          "available" => true,
          "phase" => "A3",
          "foreground_only" => true,
          "generation_gate" => "preview_digest_and_exact_confirmation",
          "automatic_model_loading" => false,
          "queue" => false
        },
        "visual_studio" => {
          "available" => true,
          "phase" => "A1",
          "still_generation" => "FLUX.2 Klein 4B via bounded AMD Vulkan foreground job",
          "motion_generation" => "qualification_required",
          "generation_gate" => "preview_digest_and_exact_confirmation",
          "automatic_model_loading" => false,
          "promotion_to_music" => "future_explicit_human_gate"
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

    def chats_send(parameters, context, request_id, progress: nil)
      chat_id = parameters["chat_id"] || context["current_chat_id"]
      return awaiting("chat_id is required") if chat_id.to_s.empty?
      return awaiting("message is required") if parameters["message"].to_s.strip.empty?

      options = {
        chat_id: chat_id,
        message: parameters["message"],
        request_id: request_id,
        interface: context.fetch("interface", "internal")
      }
      options[:progress] = progress if progress
      chat_service.send(**options)
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
          "available" => !definition["path"].to_s.empty? || !definition["internal_handler"].to_s.empty?
        }
      end
      { "records" => records, "count" => records.length, "limit" => limit, "read_only" => true }
    end

    def invocation_catalog
      @invocation_catalog_service ||= InvocationCatalogService.new(root: @root, registry: skill_registry)
    end

    def file_inspection
      @file_inspection_service ||= FileInspectionService.new(root: @root, process_env: @process_env)
    end

    def network_diagnostic
      @network_diagnostic_service ||= NetworkDiagnosticService.new(clock: @clock)
    end

    def repository_inspection
      @repository_inspection_service ||= RepositoryInspectionService.new(root: @root, process_env: @process_env, clock: @clock)
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
      @conversation_runtime ||= ConversationRuntime.new(root: @root, store: chat_store, env: resolver.effective_environment,
        memory_store: semantic_conversation_memory_context,
        creative_workflow_service: conversation_creative_workflow,
        core_workflow_service: conversation_core_workflow,
        maintenance_workflow_service: conversation_maintenance_workflow,
        security_status_service: ConversationSecurityStatusService.new(
          wazuh_status_service: wazuh_security_status,
          alert_evidence_service: wazuh_alert_evidence,
          posture_service: wazuh_compliance_posture
        ),
        fleet_observability_service: ConversationFleetObservabilityService.new(
          summary_service: fleet_observability_summary
        ),
        identity_compact_resolver: -> { %w[amd-free music].include?(core_orchestration.status.dig("data", "active_core_id")) })
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

    def host_stewardship_capabilities
      @host_stewardship_capability_registry ||= HostStewardshipCapabilityRegistry.new(
        process_env: @process_env,
        clock: @clock
      )
    end

    def file_steward
      @file_steward_service ||= FileStewardService.new(
        root: @root,
        process_env: @process_env,
        clock: @clock
      )
    end

    def software_steward
      @software_steward_service ||= SoftwareStewardService.new(clock: @clock)
    end

    def storage_steward
      @storage_steward_service ||= StorageStewardService.new(process_env: @process_env, clock: @clock)
    end

    def incident_narrator
      @incident_narrator_service ||= IncidentNarratorService.new(
        alert_source: -> { wazuh_alert_evidence.snapshot },
        security_source: -> { wazuh_security_status.snapshot },
        maintenance_device_receipt_source: -> { maintenance_device_control.retained_receipts(limit: 16) },
        maintenance_host_receipt_source: -> { maintenance_foreground_execution.retained_receipts(limit: 16) },
        backup_source: -> { backup_administration.retained_drs_status },
        observability_source: -> { fleet_observability_summary.summary },
        clock: @clock
      )
    end

    def fleet_observability_summary
      _report, resolver = resolved_configuration
      @fleet_observability_summary_service ||= FleetObservabilitySummaryService.new(
        process_env: resolver.effective_environment,
        clock: @clock
      )
    end

    def host_stewardship
      @host_stewardship_service ||= HostStewardshipService.new(
        host_source: -> { collect_system_status },
        security_source: -> { wazuh_security_status.snapshot },
        backup_source: -> { nightly_drs_deployment.status },
        capability_registry: host_stewardship_capabilities,
        file_steward: file_steward,
        clock: @clock
      )
    end

    def collect_system_status
      host = status_collector.collect
      begin
        core_envelope = core_orchestration.status
        runtime = core_envelope.fetch("data", {})
        music = music_generation.resource_inventory
        host.merge(
          "core" => {
            "mode" => runtime["core_mode"] || "unavailable",
            "label" => runtime["active_core_label"],
            "role" => runtime["core_role"] || "daily-chat",
            "chat_engine" => {
              "profile" => runtime["profile"],
              "model" => runtime["model_name"],
              "runtime" => runtime["runtime"],
              "accelerator" => runtime["accelerator"],
              "service_state" => runtime["service_state"],
              "model_resident" => runtime.dig("server", "model_resident")
            }.compact,
            "music_engine" => music.fetch("engine", {}),
            "music_lane" => runtime["music_lane"],
            "runtime_status" => core_envelope.fetch("lifecycle_state", "unknown")
          }
        )
      rescue StandardError => error
        host.merge("core" => { "mode" => "daily", "runtime_status" => "unavailable", "reason" => error.class.name })
      end
    end

    def model_runtime_control
      return @model_runtime_control_service if @model_runtime_control_service

      _report, resolver = resolved_configuration
      @model_runtime_control_service ||= ModelRuntimeControlService.new(root: @root, env: resolver.effective_environment)
    end

    def core_orchestration
      return @core_orchestration_service if @core_orchestration_service

      _report, resolver = resolved_configuration
      @core_orchestration_service ||= CoreOrchestrationService.new(
        root: @root,
        env: resolver.effective_environment,
        runtime_control: model_runtime_control,
        memory_runtime: configured_memory_embedding_runtime(resolver.effective_environment)
      )
    end

    def configured_memory_embedding_runtime(environment)
      values = %w[SOUL_MEMORY_EMBEDDING_ENDPOINT SOUL_MEMORY_EMBEDDING_PROFILE SOUL_MEMORY_EMBEDDING_DIMENSIONS].map do |key|
        environment[key].to_s.strip
      end
      values.all? { |value| !value.empty? && value != "0" } ? MemoryEmbeddingRuntimeCoordinator.new : nil
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

    def knowledge_vault
      return @knowledge_vault_service if @knowledge_vault_service

      _report, resolver = resolved_configuration
      @knowledge_vault_service ||= KnowledgeVaultService.new(
        root: @root,
        process_env: resolver.effective_environment
      )
    end

    def local_search
      return @local_search_service if @local_search_service

      _report, resolver = resolved_configuration
      @local_search_service ||= LocalSearchService.new(
        root: @root,
        process_env: resolver.effective_environment
      )
    end

    def memory_observatory
      @memory_observatory_service ||= MemoryObservatoryService.new(
        memory_store: conversation_memory,
        index_service: memory_retrieval_index,
        retrieval_service: memory_retrieval
      )
    end

    def memory_runtime_private_review
      @memory_runtime_private_review_service ||= MemoryRuntimePrivateReviewService.new(
        root: @root,
        memory_store: conversation_memory,
        retrieval_service: memory_retrieval,
        embedding_endpoint: @process_env["SOUL_MEMORY_EMBEDDING_ENDPOINT"],
        embedding_profile: @process_env["SOUL_MEMORY_EMBEDDING_PROFILE"],
        embedding_dimensions: @process_env["SOUL_MEMORY_EMBEDDING_DIMENSIONS"],
        embedding_protocol: @process_env.fetch("SOUL_MEMORY_EMBEDDING_PROTOCOL", "ollama"),
        selected_core: lambda {
          envelope = core_orchestration.status
          envelope["lifecycle_state"] == "complete" ? envelope.fetch("data", {}) : {}
        },
        clock: @clock
      )
    end

    def memory_retrieval
      @memory_retrieval_service ||= ApprovedMemoryRetrievalService.new(
        memory_store: conversation_memory,
        index_service: memory_retrieval_index,
        embedding_client: memory_embedding_client,
        query_instruction: @process_env["SOUL_MEMORY_EMBEDDING_QUERY_INSTRUCTION"],
        clock: @clock
      )
    end

    def memory_retrieval_index
      memory_paths = MemoryPaths.new(root: @root)
      @memory_retrieval_index_service ||= ApprovedMemoryIndexService.new(
        memory_store: conversation_memory,
        index_path: memory_paths.write_path("derived/approved-memory-index.json"),
        allowed_root: memory_paths.private_root,
        embedding_client: memory_embedding_client,
        clock: @clock
      )
    end

    def conversation_memory
      @conversation_memory_store ||= ConversationMemoryStore.new(root: @root, create: false, clock: @clock)
    end

    def semantic_conversation_memory_context
      @semantic_conversation_memory_context ||= SemanticConversationMemoryContext.new(
        memory_store: conversation_memory,
        retrieval_service: memory_retrieval
      )
    end

    def memory_embedding_client
      return @memory_embedding_client if defined?(@memory_embedding_client)

      endpoint = @process_env["SOUL_MEMORY_EMBEDDING_ENDPOINT"].to_s.strip
      profile = @process_env["SOUL_MEMORY_EMBEDDING_PROFILE"].to_s.strip
      dimensions = @process_env["SOUL_MEMORY_EMBEDDING_DIMENSIONS"].to_s.strip
      configured = [endpoint, profile, dimensions]
      raise RuntimeError, "memory embedding configuration is incomplete" if configured.any?(&:empty?) && !configured.all?(&:empty?)
      @memory_embedding_client = if configured.all?(&:empty?)
                                   nil
                                 else
                                   LocalLoopbackEmbeddingClient.new(
                                     endpoint: endpoint,
                                     profile: { "name" => profile, "dimensions" => Integer(dimensions) },
                                     protocol: @process_env.fetch("SOUL_MEMORY_EMBEDDING_PROTOCOL", "ollama")
                                   )
                                 end
    rescue ArgumentError => error
      raise RuntimeError, "memory embedding configuration is invalid: #{error.message}"
    end

    def skill_studio
      @skill_studio_service ||= SkillStudioService.new(root: @root, clock: @clock)
    end

    def self_improvement
      @self_improvement_service ||= SelfImprovementService.new(root: @root, clock: @clock)
    end

    def self_assessment_dev_synthesis
      @self_assessment_dev_synthesis_service ||= SelfAssessmentDevSynthesisService.new(
        root: @root,
        clock: @clock,
        assessment_source: self_improvement
      )
    end

    def maintenance_rehearsal
      @maintenance_rehearsal_service ||= MaintenanceRehearsalService.new(root: @root, clock: @clock)
    end

    def maintenance_fleet_status
      @maintenance_fleet_status_service ||= MaintenanceFleetStatusService.new(
        root: @root,
        clock: @clock,
        process_env: @process_env
      )
    end

    def fleet_operations_evidence
      @fleet_operations_evidence_service ||= FleetOperationsEvidenceService.new(
        fleet_snapshot_source: -> { maintenance_fleet_status.snapshot },
        device_receipt_source: -> { maintenance_device_control.retained_receipts(limit: FleetOperationsEvidenceService::MAX_TRANSACTIONS) },
        clock: @clock
      )
    end

    def wazuh_security_status
      @wazuh_security_status_service ||= WazuhSecurityStatusService.new(
        root: @root,
        clock: @clock,
        process_env: @process_env
      )
    end

    def wazuh_alert_evidence
      @wazuh_alert_evidence_service ||= WazuhAlertEvidenceService.new(
        root: @root,
        clock: @clock,
        process_env: @process_env
      )
    end

    def wazuh_alert_notifications
      @wazuh_alert_notification_service ||= WazuhAlertNotificationService.new(
        root: @root,
        clock: @clock,
        process_env: @process_env,
        alert_service: wazuh_alert_evidence
      )
    end

    def wazuh_compliance_posture
      @wazuh_compliance_posture_service ||= WazuhCompliancePostureService.new(
        root: @root,
        clock: @clock,
        process_env: @process_env
      )
    end

    def maintenance_fleet_discovery
      @maintenance_fleet_discovery_service ||= MaintenanceFleetDiscoveryService.new(
        root: @root,
        clock: @clock,
        process_env: @process_env
      )
    end

    def maintenance_device_control
      return @maintenance_device_control_service if @maintenance_device_control_service

      _report, resolver = resolved_configuration
      @maintenance_device_control_service ||= MaintenanceDeviceControlService.new(
        root: @root,
        clock: @clock,
        fleet_status_service: maintenance_fleet_status,
        live_execution_enabled: resolver.effective_environment["SOUL_MAINTENANCE_REMOTE_LIVE"] == "1",
        process_env: resolver.effective_environment
      )
    end

    def maintenance_foreground_execution
      return @maintenance_foreground_execution_service if @maintenance_foreground_execution_service

      _report, resolver = resolved_configuration
      @maintenance_foreground_execution_service ||= MaintenanceForegroundExecutionService.new(
        root: @root,
        clock: @clock,
        rehearsal_service: maintenance_rehearsal,
        live_execution_enabled: resolver.effective_environment["SOUL_MAINTENANCE_A2_LIVE"] == "1",
        passwordless_authority_enabled: resolver.effective_environment["SOUL_MAINTENANCE_PASSWORDLESS"] == "1"
      )
    end

    def maintenance_reboot_restore
      return @maintenance_reboot_restore_service if @maintenance_reboot_restore_service

      _report, resolver = resolved_configuration
      @maintenance_reboot_restore_service ||= MaintenanceRebootRestoreService.new(
        root: @root,
        clock: @clock,
        foreground_service: maintenance_foreground_execution,
        live_execution_enabled: resolver.effective_environment["SOUL_MAINTENANCE_A3_LIVE"] == "1"
      )
    end

    def self_augmentation
      @self_augmentation_service ||= SelfAugmentationService.new(root: @root, clock: @clock)
    end

    def self_augmentation_experiments
      @self_augmentation_experiment_service ||= SelfAugmentationExperimentService.new(root: @root, clock: @clock)
    end

    def self_augmentation_dev_critique
      @self_augmentation_dev_critique_service ||= SelfAugmentationDevCritiqueService.new(
        root: @root,
        clock: @clock,
        proposal_source: self_augmentation
      )
    end

    def self_augmentation_dev_handoff
      @self_augmentation_dev_handoff_service ||= SelfAugmentationDevHandoffService.new(
        root: @root,
        clock: @clock,
        experiment_source: self_augmentation_experiments
      )
    end

    def music_generation
      @music_generation_service ||= MusicGenerationService.new(root: @root)
    end

    def music_vocal_diagnostic
      @music_vocal_diagnostic_service ||= MusicVocalDiagnosticService.new(
        music_generation: music_generation,
        analysis_service: music_candidate_analysis
      )
    end

    def visual_studio
      @visual_studio_service ||= VisualStudioService.new(root: @root, core_status: -> { core_orchestration.status }, music_visual_companion: music_visual_companion, blender_scene_service: blender_scene)
    end

    def blender_scene
      @blender_scene_service ||= BlenderSceneService.new(root: @root, music_visual_companion: music_visual_companion)
    end

    def visual_motion_qualification
      @visual_motion_qualification_service ||= VisualMotionQualificationService.new(visual_studio: visual_studio)
    end

    def music_qualification
      @music_qualification_service ||= MusicQualificationService.new(music_generation: music_generation)
    end

    def project_tracker
      @project_tracker_service ||= ProjectTrackerService.new(root: @root, clock: @clock)
    end

    def backup_administration
      @backup_administration_service ||= BackupAdministrationService.new(
        root: @root, process_env: @process_env, clock: @clock
      )
    end

    def operator_backup_administration
      @operator_backup_administration_service ||= BackupAdministrationService.new(
        root: @root, process_env: @process_env, clock: @clock, profile_id: "operator"
      )
    end

    def nightly_drs_deployment
      @nightly_drs_deployment ||= NightlyDrsDeployment.new(
        root: @root, process_env: @process_env, clock: @clock
      )
    end

    def operator_nightly_drs_deployment
      @operator_nightly_drs_deployment ||= NightlyDrsDeployment.new(
        root: @root, process_env: @process_env, clock: @clock, profile_id: "operator"
      )
    end

    def backup_status(password:)
      result = backup_administration.status(password: password)
      return result unless result["ok"] && result["data"].is_a?(Hash)
      result["data"]["automation"] = nightly_drs_deployment.status.fetch("data", {})
      result
    rescue StandardError
      result["data"]["automation"] = {
        "ready" => false,
        "mode" => "unavailable",
        "credential_ready" => false
      } if result && result["data"].is_a?(Hash)
      result
    end

    def operator_backup_status(password:)
      result = operator_backup_administration.status(password: password)
      return result unless result["ok"] && result["data"].is_a?(Hash)
      result["data"]["automation"] = operator_nightly_drs_deployment.status.fetch("data", {})
      result
    rescue StandardError
      result["data"]["automation"] = {
        "ready" => false,
        "mode" => "unavailable",
        "credential_ready" => false
      } if result && result["data"].is_a?(Hash)
      result
    end

    def conversation_creative_workflow
      report, resolver = resolved_configuration
      raise RuntimeError, "configuration is invalid" unless report.fetch("ok")
      env = resolver.effective_environment
      @conversation_creative_workflow ||= ConversationCreativeWorkflowService.new(
        root: @root, chat_store: chat_store,
        provider_client: ConversationProviderClient.new(env: env, root: @root),
        music_generation: music_generation, visual_studio: visual_studio,
        core_orchestration: core_orchestration, music_disposition: music_candidate_disposition,
        music_visual_companion: music_visual_companion, publication_package: music_publication_package
      )
    end

    def conversation_core_workflow
      @conversation_core_workflow ||= ConversationCoreWorkflowService.new(core_orchestration: core_orchestration)
    end

    def conversation_maintenance_workflow
      @conversation_maintenance_workflow ||= ConversationMaintenanceWorkflowService.new(
        root: @root,
        fleet_status_service: maintenance_fleet_status,
        device_control_service: maintenance_device_control
      )
    end

    def music_candidate_analysis
      @music_candidate_analysis_service ||= MusicCandidateAnalysisService.new(root: @root)
    end

    def music_candidate_disposition
      @music_candidate_disposition_service ||= MusicCandidateDispositionService.new(root: @root, analysis_service: music_candidate_analysis)
    end

    def music_candidate_trim
      @music_candidate_trim_service ||= MusicCandidateTrimService.new(root: @root)
    end

    def music_visual_companion
      @music_visual_companion_service ||= MusicVisualCompanionService.new(root: @root)
    end

    def music_publication_package
      @music_publication_package_service ||= MusicPublicationPackageService.new(root: @root, visual_service: music_visual_companion)
    end

    def youtube_oauth
      @youtube_oauth_service ||= YouTubeOAuthService.new(root: @root)
    end

    def youtube_authenticated_upload
      @youtube_authenticated_upload_service ||= YouTubeAuthenticatedUploadService.new(root: @root, oauth: youtube_oauth)
    end

    def music_project_deletion
      @music_project_deletion_service ||= MusicProjectDeletionService.new(root: @root)
    end

    def long_form_mix
      @long_form_mix_service ||= LongFormMixService.new(root: @root)
    end

    def long_form_mix_render
      @long_form_mix_render_service ||= LongFormMixRenderService.new(root: @root, mix_service: long_form_mix)
    end

    def long_form_mix_finalization
      @long_form_mix_finalization_service ||= LongFormMixFinalizationService.new(
        root: @root,
        mix_service: long_form_mix,
        render_service: long_form_mix_render
      )
    end

    def project_release
      @project_release_service ||= ProjectReleaseService.new(root: @root)
    end

    def music_reference_library
      @music_reference_library_service ||= MusicReferenceLibraryService.new(root: @root)
    end

    def music_reference_analysis
      @music_reference_analysis_service ||= MusicReferenceAnalysisService.new(root: @root)
    end

    def music_reference_synthesis
      return @music_reference_synthesis_service if @music_reference_synthesis_service
      report, resolver = resolved_configuration
      raise RuntimeError, "configuration is invalid" unless report.fetch("ok")
      env = resolver.effective_environment
      @music_reference_synthesis_service = MusicReferenceSynthesisService.new(root: @root, provider_client: ConversationProviderClient.new(env: env, root: @root))
    end

    def draft_music_reference_synthesis(reference_id:, scope:)
      provider = @music_reference_synthesis_provider
      unless provider
        report, resolver = resolved_configuration
        return awaiting("configuration is invalid") unless report.fetch("ok")
        provider = ConversationProviderRegistry.new(env: resolver.effective_environment).local.find(&:configured?)
      end
      music_reference_synthesis.draft(reference_id: reference_id, scope: scope, provider: provider)
    end

    def draft_music_reference_fusion(reference_ids:)
      provider = @music_reference_synthesis_provider
      unless provider
        report, resolver = resolved_configuration
        return awaiting("configuration is invalid") unless report.fetch("ok")
        provider = ConversationProviderRegistry.new(env: resolver.effective_environment).local.find(&:configured?)
      end
      music_reference_synthesis.draft_fusion(reference_ids: reference_ids, provider: provider)
    end

    def music_project_with_analysis(project_id:)
      result = music_generation.inspect_project(project_id: project_id)
      return result unless result.fetch("ok", false)
      result.fetch("data").fetch("generations").each do |candidate|
        candidate["analysis"] = music_candidate_analysis.read(project_id: project_id, candidate_id: candidate.fetch("candidate_id"))
        candidate["visual_sources"] = music_visual_companion.available_sources(project_id: project_id, candidate_id: candidate.fetch("candidate_id"))
        candidate["visuals"] = music_visual_companion.inventory(project_id: project_id, candidate_id: candidate.fetch("candidate_id"))
      end
      project_release.decorate_outcome(result, kind: "music")
    end

    def draft_music_revision(project_id:, source_candidate_id:)
      project_result = music_generation.inspect_project(project_id: project_id)
      return project_result unless project_result.fetch("ok", false)
      data = project_result.fetch("data")
      candidate = data.fetch("generations").find { |item| item["candidate_id"] == source_candidate_id }
      return awaiting("source music candidate does not exist") unless candidate
      analysis = music_candidate_analysis.read(project_id: project_id, candidate_id: source_candidate_id)
      service, provider = music_revision_drafting
      service.draft(project: data.fetch("project"), candidate: candidate, analysis: analysis, provider: provider)
    end

    def music_revision_drafting
      return [@music_revision_draft_service, music_revision_provider] if @music_revision_draft_service
      report, resolver = resolved_configuration
      raise RuntimeError, "configuration is invalid" unless report.fetch("ok")
      env = resolver.effective_environment
      provider = ConversationProviderRegistry.new(env: env).local.find(&:configured?)
      @music_revision_draft_service = MusicRevisionDraftService.new(provider_client: ConversationProviderClient.new(env: env, root: @root))
      [@music_revision_draft_service, provider]
    end

    def music_revision_provider
      return @music_revision_provider if @music_revision_provider
      report, resolver = resolved_configuration
      return nil unless report.fetch("ok")
      ConversationProviderRegistry.new(env: resolver.effective_environment).local.find(&:configured?)
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
        errors = [{ "code" => "domain_failure", "message" => safe_message(data["reason"] || data["message"]) }] unless data.fetch("ok", false)
        mutation = data.fetch("mutation", mutation)
        data = data.fetch("data")
      elsif data.is_a?(Hash) && data.key?("lifecycle_state")
        errors = [{ "code" => "domain_failure", "message" => safe_message(data["reason"] || data["message"]) }] unless data.fetch("ok", false)
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
