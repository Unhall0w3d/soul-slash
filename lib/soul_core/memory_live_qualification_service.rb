# frozen_string_literal: true

require "digest"
require "json"
require_relative "conversation_memory_store"
require_relative "conversation_observation_store"
require_relative "memory_audit_journal_service"
require_relative "memory_lifecycle_admission_service"
require_relative "memory_local_proposal_synthesizer"
require_relative "memory_observation_derivation_service"
require_relative "memory_paths"
require_relative "memory_retrieval_index"
require_relative "memory_retrieval_service"

module SoulCore
  # Supervised, foreground-only qualification of capture through compensation.
  class MemoryLiveQualificationService
    SCHEMA = "soul.memory_live_qualification.a14.v1"
    REQUEST_PREFIX = "a14-qualification-"

    def initialize(root: Dir.pwd, env: ENV, synthesizer: nil, model_identity: nil,
                   observation_store: nil, memory_store: nil, audit_service: nil,
                   derivation_service: nil, admission_service: nil)
      @root = File.expand_path(root)
      @paths = MemoryPaths.new(root: @root)
      @observations = observation_store || ConversationObservationStore.new(root: @root)
      @memories = memory_store || ConversationMemoryStore.new(root: @root, create: false)
      @audit = audit_service || MemoryAuditJournalService.new(root: @root, memory_store: @memories)
      @synthesizer = synthesizer || MemoryLocalProposalSynthesizer.new(root: @root, env: env)
      @derivations = derivation_service || MemoryObservationDerivationService.new(
        root: @root, observation_store: @observations, synthesizer: @synthesizer,
        model_identity: model_identity || { "provider" => "local", "model" => LocalDevelopmentModelClient::MODEL, "core" => "dev" }
      )
      @admissions = admission_service || MemoryLifecycleAdmissionService.new(
        root: @root, derivation_service: @derivations, observation_store: @observations,
        memory_store: @memories, audit_service: @audit
      )
    end

    def status
      complete(
        "audit" => content_free(@audit.verify),
        "observations" => content_free(@observations.integrity),
        "derivations" => content_free(@derivations.integrity),
        "admissions" => content_free(@admissions.integrity),
        "mutation" => "none"
      )
    end

    def derive(request_id:)
      validate_request_id!(request_id)
      result = @derivations.derive(request_id: request_id)
      return failed(result["reason"]) unless result["ok"]

      complete("derivation" => content_free(result), "model" => content_free(@synthesizer.respond_to?(:last_receipt) ? @synthesizer.last_receipt : nil), "mutation" => "append_private_derivation")
    rescue ArgumentError => error
      failed(error.message)
    end

    def admit(request_id:)
      validate_request_id!(request_id)
      result = @admissions.apply(request_id: request_id)
      return failed(result["reason"]) unless result["ok"]

      complete("admission" => content_free(result), "mutation" => result["no_work"] ? "none" : "audited_canonical_memory")
    rescue ArgumentError => error
      failed(error.message)
    end

    def retrieve(query:)
      index = ApprovedMemoryIndexService.new(
        memory_store: @memories,
        index_path: @paths.write_path("derived/approved-memory-index.json"),
        allowed_root: @paths.private_root
      )
      result = ApprovedMemoryRetrievalService.new(memory_store: @memories, index_service: index).query(query: query, limit: 8)
      return failed(result["message"]) unless result["lifecycle_state"] == "complete"

      data = result.fetch("data")
      complete(
        "retrieval" => {
          "count" => data.fetch("count"), "abstained" => data.fetch("abstained"),
          "retrieval_mode" => data.fetch("retrieval_mode"),
          "memory_ids" => data.fetch("results").map { |item| item.fetch("memory_id") },
          "content_sha256s" => data.fetch("results").map { |item| Digest::SHA256.hexdigest(item.fetch("excerpt")) }
        },
        "mutation" => "none"
      )
    end

    def rollback(transaction_id:, reason: "A14 supervised qualification compensation")
      reviewed = @admissions.decision_batch(limit: 8).select do |decision|
        decision.fetch("request_id").start_with?(REQUEST_PREFIX)
      end.flat_map { |decision| decision.fetch("outcomes") }
        .filter_map { |outcome| outcome["rollback_reference"] }
      raise ArgumentError, "transaction is not part of a retained A14 qualification" unless reviewed.include?(transaction_id.to_s)
      result = @audit.rollback_transaction(
        transaction_id: transaction_id,
        reason: reason,
        audit_metadata: {
          "actor" => "operator-approved-soul-deployment",
          "trigger" => "a14_supervised_qualification",
          "policy_version" => SCHEMA,
          "rollback_reference" => transaction_id
        }
      )
      return failed(result["error"] || result["reason"]) unless result["ok"]

      complete("rollback" => content_free(result), "mutation" => "audited_compensation")
    rescue ArgumentError => error
      failed(error.message)
    end

    private

    def complete(data)
      { "ok" => true, "lifecycle_state" => "complete", "schema" => SCHEMA,
        "data" => data, "content_included" => false }
    end

    def failed(reason)
      { "ok" => false, "lifecycle_state" => "failed", "schema" => SCHEMA,
        "reason" => reason.to_s.gsub(@root, "[PROJECT_ROOT]")[0, 400], "content_included" => false }
    end

    def validate_request_id!(request_id)
      value = request_id.to_s
      raise ArgumentError, "A14 request ID is invalid" unless value.start_with?(REQUEST_PREFIX)
    end

    def content_free(value)
      return nil if value.nil?
      copy = JSON.parse(JSON.generate(value))
      redact(copy)
    end

    def redact(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, child), out|
          next if %w[text content excerpt query messages candidate structured].include?(key.to_s)
          out[key] = redact(child)
        end
      when Array then value.map { |child| redact(child) }
      else value
      end
    end
  end
end
