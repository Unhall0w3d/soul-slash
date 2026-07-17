# frozen_string_literal: true

require "json"

module SoulCore
  module ApplicationContract
    SCHEMA_VERSION = "soul.application.v1"
    MAX_REQUEST_BYTES = 128 * 1024
    MAX_STRING_BYTES = 64 * 1024
    MAX_KEYS = 64
    MAX_DEPTH = 8
    REQUEST_ID = /\A[A-Za-z0-9_.:-]{8,128}\z/
    CHAT_ID = /\Achat_[A-Za-z0-9_.-]+\z/
    ARTIFACT_ID = /\Aart_[A-Za-z0-9_.-]+\z/
    DELIVERY_ID = /\Adel_[A-Za-z0-9_.-]+\z/
    PROPOSAL_ID = /\A[A-Za-z0-9][A-Za-z0-9_.-]{0,199}\z/
    BETA_ID = /\A[A-Za-z0-9][A-Za-z0-9_.-]{0,199}\z/
    HOST_PLAN_ID = /\Ahip_[a-f0-9]{16}\z/
    EXPERIMENT_ID = /\Aexp_[a-f0-9]{16}\z/
    MUSIC_PROJECT_ID = /\Amusic_[a-f0-9]{16}\z/
    MUSIC_CANDIDATE_ID = /\Acandidate_[a-f0-9]{16}\z/
    SKILL_ID = /\A[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+\z/
    INTERFACES = %w[cli dashboard_test internal dashboard].freeze

    OPERATIONS = {
      "application.bootstrap" => [],
      "application.cancel" => [],
      "chats.list" => %w[limit],
      "chats.get" => %w[chat_id],
      "chats.messages" => %w[chat_id limit],
      "chats.create" => %w[title],
      "chats.send" => %w[chat_id message],
      "chats.pin" => %w[chat_id],
      "chats.unpin" => %w[chat_id],
      "chats.clear.preview" => %w[mode title chat_ids],
      "chats.clear.execute" => %w[mode title chat_ids confirmation expected_digest],
      "chats.forget.preview" => %w[chat_id],
      "chats.forget.execute" => %w[chat_id confirmation expected_digest],
      "chats.forget_many.preview" => %w[mode title chat_ids],
      "chats.forget_many.execute" => %w[mode title chat_ids confirmation expected_digest],
      "workspace.list" => %w[kind lifecycle privacy delivery_state limit],
      "workspace.chat" => %w[chat_id kind lifecycle privacy delivery_state limit],
      "workspace.detail" => %w[artifact_id],
      "inbox.list" => %w[chat_id state limit],
      "inbox.deliver" => %w[chat_id artifact_id],
      "inbox.mark_seen" => %w[chat_id delivery_id],
      "inbox.dismiss" => %w[chat_id delivery_id],
      "system_status.refresh" => [],
      "model_runtime.status" => [],
      "model_runtime.load.preview" => %w[profile_id],
      "model_runtime.load.execute" => %w[profile_id confirmation expected_digest],
      "model_runtime.unload.preview" => %w[profile_id],
      "model_runtime.unload.execute" => %w[profile_id confirmation expected_digest],
      "model_runtime.switch.preview" => %w[profile_id],
      "model_runtime.switch.execute" => %w[profile_id confirmation expected_digest],
      "configuration.show" => [],
      "configuration.explain" => %w[key],
      "configuration.validate" => [],
      "skills.list" => %w[limit],
      "skill_studio.proposals.list" => %w[limit],
      "skill_studio.proposals.get" => %w[proposal_id],
      "skill_studio.proposals.approval.preview" => %w[proposal_id],
      "skill_studio.proposals.approval.execute" => %w[proposal_id confirmation expected_digest],
      "skill_studio.proposals.beta_build.preview" => %w[proposal_id skill_id],
      "skill_studio.proposals.beta_build.execute" => %w[proposal_id skill_id confirmation expected_digest],
      "skill_studio.proposals.close.preview" => %w[proposal_id],
      "skill_studio.proposals.close.execute" => %w[proposal_id confirmation expected_digest],
      "skill_studio.betas.list" => %w[limit],
      "skill_studio.betas.get" => %w[beta_id],
      "skill_studio.betas.run.preview" => %w[beta_id args],
      "skill_studio.betas.run.execute" => %w[beta_id args confirmation expected_digest],
      "skill_studio.betas.promotion.preview" => %w[beta_id],
      "skill_studio.betas.promotion.approve" => %w[beta_id confirmation expected_digest],
      "skill_studio.betas.production.preview" => %w[beta_id],
      "skill_studio.betas.production.execute" => %w[beta_id confirmation expected_digest],
      "self_improvement.snapshot" => [],
      "self_improvement.refresh" => %w[scope],
      "self_improvement.proposals.preview" => [],
      "self_improvement.proposals.execute" => %w[confirmation expected_digest],
      "host_improvement.plans.list" => %w[limit],
      "host_improvement.arch_upgrade.preview" => [],
      "host_improvement.arch_upgrade.handoff" => %w[confirmation expected_digest],
      "host_improvement.plans.verify" => %w[plan_id],
      "self_augmentation.census" => [],
      "self_augmentation.proposals.list" => %w[limit],
      "self_augmentation.proposals.preview" => %w[objective why_not_skill],
      "self_augmentation.proposals.execute" => %w[objective why_not_skill confirmation expected_digest],
      "self_augmentation.experiments.list" => %w[limit],
      "self_augmentation.experiments.gate_a1.preview" => %w[proposal_id allowed_files],
      "self_augmentation.experiments.gate_a1.execute" => %w[proposal_id allowed_files confirmation expected_digest],
      "self_augmentation.reviews.generate" => %w[experiment_id],
      "self_augmentation.reviews.gate_a2.preview" => %w[experiment_id],
      "self_augmentation.reviews.gate_a2.execute" => %w[experiment_id confirmation expected_digest],
      "self_augmentation.model_qualification.preview" => %w[experiment_id suite_id model_profile result evidence_digest],
      "self_augmentation.model_qualification.execute" => %w[experiment_id suite_id model_profile result evidence_digest confirmation expected_digest],
      "self_augmentation.experiments.cleanup.preview" => %w[experiment_id],
      "self_augmentation.experiments.cleanup.execute" => %w[experiment_id confirmation expected_digest],
      "music.projects.list" => %w[limit],
      "music.projects.create" => %w[project],
      "music.projects.get" => %w[project_id],
      "music.resources.status" => [],
      "music.generation.preview" => %w[project_id],
      "music.generation.execute" => %w[project_id candidate_id confirmation expected_digest],
      "music.generation.cancel.preview" => %w[candidate_id],
      "music.generation.cancel.execute" => %w[candidate_id confirmation expected_digest],
      "music.candidates.analysis.preview" => %w[project_id candidate_id],
      "music.candidates.analysis.execute" => %w[project_id candidate_id confirmation expected_digest],
      "music.candidates.revision.draft" => %w[project_id source_candidate_id],
      "music.candidates.revision.preview" => %w[project_id source_candidate_id revision],
      "music.candidates.revision.execute" => %w[project_id source_candidate_id candidate_id revision confirmation expected_digest],
      "music.candidates.review" => %w[project_id candidate_id review],
      "music.candidates.reject.preview" => %w[project_id candidate_id],
      "music.candidates.reject.execute" => %w[project_id candidate_id confirmation expected_digest],
      "music.candidates.export.preview" => %w[project_id candidate_id],
      "music.candidates.export.execute" => %w[project_id candidate_id confirmation expected_digest],
      "approvals.pending" => %w[limit],
      "activities.recent" => %w[limit filters]
    }.freeze

    module_function

    def validate(request)
      return error("request must be an object") unless request.is_a?(Hash)
      return error("request keys must be strings") unless string_keys?(request)

      unknown = request.keys - %w[schema_version request_id operation parameters context]
      return error("request contains unknown fields") unless unknown.empty?

      schema = request["schema_version"]
      return error("schema_version is required", lifecycle: "awaiting_input") if schema.to_s.empty?
      return error("unsupported schema_version") unless schema == SCHEMA_VERSION

      request_id = request["request_id"].to_s
      return error("request_id is required", lifecycle: "awaiting_input") if request_id.empty?
      return error("request_id is invalid") unless request_id.match?(REQUEST_ID)

      operation = request["operation"].to_s
      return error("operation is required", lifecycle: "awaiting_input") if operation.empty?
      allowed_parameters = OPERATIONS[operation]
      return error("unknown application operation") unless allowed_parameters

      parameters = request.fetch("parameters", {})
      return error("parameters must be an object") unless parameters.is_a?(Hash) && string_keys?(parameters)
      unknown_parameters = parameters.keys - allowed_parameters
      return error("parameters contain unknown fields for #{operation}") unless unknown_parameters.empty?

      context = request.fetch("context", {})
      return error("context must be an object") unless context.is_a?(Hash) && string_keys?(context)
      unknown_context = context.keys - %w[interface current_chat_id]
      return error("context contains unknown fields") unless unknown_context.empty?
      interface = context.fetch("interface", "internal").to_s
      return error("context interface is invalid") unless INTERFACES.include?(interface)

      shape_error = validate_shape(request)
      return error(shape_error) if shape_error

      type_error = validate_parameter_types(parameters, context)
      return error(type_error) if type_error

      identity_error = validate_identities(parameters, context)
      return error(identity_error) if identity_error

      { "ok" => true, "request" => request, "interface" => interface }
    rescue JSON::GeneratorError, Encoding::UndefinedConversionError
      error("request must contain valid UTF-8 JSON values")
    end

    def validate_shape(value, depth = 0, counts = { keys: 0 })
      return "request nesting exceeds #{MAX_DEPTH}" if depth > MAX_DEPTH

      case value
      when Hash
        counts[:keys] += value.length
        return "request contains more than #{MAX_KEYS} keys" if counts[:keys] > MAX_KEYS
        value.each do |key, child|
          return "request keys must be strings" unless key.is_a?(String)
          failure = validate_shape(child, depth + 1, counts)
          return failure if failure
        end
      when Array
        value.each do |child|
          failure = validate_shape(child, depth + 1, counts)
          return failure if failure
        end
      when String
        return "request strings must be valid UTF-8" unless value.valid_encoding?
        return "request string exceeds #{MAX_STRING_BYTES} bytes" if value.bytesize > MAX_STRING_BYTES
      when NilClass, TrueClass, FalseClass, Integer, Float
        return "request numbers must be finite" if value.is_a?(Float) && !value.finite?
      else
        return "request contains unsupported value type"
      end
      return "request exceeds #{MAX_REQUEST_BYTES} bytes" if depth.zero? && JSON.generate(value).bytesize > MAX_REQUEST_BYTES

      nil
    end

    def validate_identities(parameters, context)
      chat_id = parameters["chat_id"] || context["current_chat_id"]
      return "chat_id is invalid" if chat_id && !chat_id.to_s.match?(CHAT_ID)
      artifact_id = parameters["artifact_id"]
      return "artifact_id is invalid" if artifact_id && !artifact_id.to_s.match?(ARTIFACT_ID)
      delivery_id = parameters["delivery_id"]
      return "delivery_id is invalid" if delivery_id && !delivery_id.to_s.match?(DELIVERY_ID)
      proposal_id = parameters["proposal_id"]
      return "proposal_id is invalid" if proposal_id && !proposal_id.to_s.match?(PROPOSAL_ID)
      beta_id = parameters["beta_id"]
      return "beta_id is invalid" if beta_id && !beta_id.to_s.match?(BETA_ID)
      plan_id = parameters["plan_id"]
      return "plan_id is invalid" if plan_id && !plan_id.to_s.match?(HOST_PLAN_ID)
      experiment_id = parameters["experiment_id"]
      return "experiment_id is invalid" if experiment_id && !experiment_id.to_s.match?(EXPERIMENT_ID)
      skill_id = parameters["skill_id"]
      return "skill_id is invalid" if skill_id && !skill_id.to_s.match?(SKILL_ID)
      project_id = parameters["project_id"]
      return "project_id is invalid" if project_id && !project_id.to_s.match?(MUSIC_PROJECT_ID)
      candidate_id = parameters["candidate_id"]
      return "candidate_id is invalid" if candidate_id && !candidate_id.to_s.match?(MUSIC_CANDIDATE_ID)
      source_candidate_id = parameters["source_candidate_id"]
      return "source_candidate_id is invalid" if source_candidate_id && !source_candidate_id.to_s.match?(MUSIC_CANDIDATE_ID)
      chat_ids = parameters["chat_ids"]
      return "chat_ids contains an invalid chat ID" if chat_ids.is_a?(Array) && chat_ids.any? { |chat_id| !chat_id.to_s.match?(CHAT_ID) }

      nil
    end

    def validate_parameter_types(parameters, context)
      parameters.each do |key, value|
        if key == "limit"
          return "limit must be an integer" unless value.is_a?(Integer)
        elsif key == "filters" || key == "project" || key == "review" || key == "revision"
          return "#{key} must be an object" unless value.is_a?(Hash) && string_keys?(value)
        elsif key == "args" || key == "chat_ids" || key == "allowed_files"
          return "#{key} must be an array of strings" unless value.is_a?(Array) && value.all? { |item| item.is_a?(String) }
        else
          return "#{key} must be a string" unless value.is_a?(String)
        end
      end
      if context.key?("interface") && !context["interface"].is_a?(String)
        return "context interface must be a string"
      end
      if context.key?("current_chat_id") && !context["current_chat_id"].is_a?(String)
        return "current_chat_id must be a string"
      end

      nil
    end

    def string_keys?(hash)
      hash.keys.all? { |key| key.is_a?(String) }
    end

    def error(reason, lifecycle: "failed")
      { "ok" => false, "lifecycle_state" => lifecycle, "reason" => reason }
    end
  end
end
