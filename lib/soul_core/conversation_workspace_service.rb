# frozen_string_literal: true

require_relative "conversation_artifact_contract"
require_relative "conversation_artifact_inbox_store"
require_relative "conversation_artifact_store"

module SoulCore
  class ConversationWorkspaceService
    MAX_RECORDS = 50
    CONTEXT_RECORDS = 5

    def initialize(root:, artifact_store: nil, inbox_store: nil)
      @root = File.expand_path(root)
      @artifact_store = artifact_store || ConversationArtifactStore.new(root: @root)
      @inbox_store = inbox_store || ConversationArtifactInboxStore.new(root: @root)
    end

    attr_reader :artifact_store, :inbox_store

    def list(chat_id: nil, kind: nil, lifecycle: nil, privacy: nil, delivery_state: nil, limit: MAX_RECORDS, provider_privacy_class: nil)
      deliveries = @inbox_store.list(chat_id: chat_id, state: delivery_state, limit: MAX_RECORDS)
      delivery_by_artifact = deliveries.group_by { |record| record.fetch("artifact_id") }
      records = @artifact_store.list
      if provider_privacy_class.to_s.empty?
        known_artifact_ids = records.map { |record| record.fetch("artifact_id") }
        orphaned_delivery_ids = delivery_by_artifact.keys - known_artifact_ids
        unless orphaned_delivery_ids.empty?
          raise RuntimeError, "inbox deliveries reference unknown artifacts: #{orphaned_delivery_ids.sort.join(', ')}"
        end
      end
      unless chat_id.to_s.strip.empty?
        normalized_chat = chat_id.to_s.strip
        records = records.select do |record|
          Array(record["attached_chat_ids"]).include?(normalized_chat) || delivery_by_artifact.key?(record.fetch("artifact_id"))
        end
      end
      records = records.select { |record| record["kind"] == kind.to_s } unless kind.to_s.empty?
      records = records.select { |record| record["lifecycle"] == lifecycle.to_s } unless lifecycle.to_s.empty?
      records = records.select { |record| record["privacy"] == privacy.to_s } unless privacy.to_s.empty?
      if delivery_state && chat_id.to_s.strip.empty?
        delivered_ids = deliveries.map { |record| record.fetch("artifact_id") }.uniq
        records = records.select { |record| delivered_ids.include?(record.fetch("artifact_id")) }
      elsif delivery_state
        records = records.select { |record| delivery_by_artifact.key?(record.fetch("artifact_id")) }
      end
      blocked = []
      unless provider_privacy_class.to_s.empty?
        records, blocked = records.partition do |record|
          ConversationArtifactContract.provider_allowed?(record.fetch("privacy"), provider_privacy_class)
        end
      end

      projected = records.map do |record|
        artifact_deliveries = Array(delivery_by_artifact[record.fetch("artifact_id")])
        validate_revision!(record)
        artifact_deliveries.each { |delivery| validate_provenance!(record, delivery) }
        project(record, artifact_deliveries)
      end
      projected = projected.sort_by { |record| [record.fetch("workspace_updated_at"), record.fetch("artifact_id")] }.reverse
      projected = projected.first(normalize_limit(limit))
      {
        "ok" => true,
        "lifecycle_state" => "complete",
        "records" => projected,
        "count" => projected.length,
        "limit" => normalize_limit(limit),
        "privacy_blocked_artifact_ids" => blocked.map { |record| record.fetch("artifact_id") },
        "metadata_only" => true,
        "content_read" => false,
        "file_mutated" => false
      }
    rescue ArgumentError => error
      failure(error.message)
    rescue RuntimeError => error
      blocked(error.message)
    end

    def inbox(chat_id:, state: nil, limit: MAX_RECORDS, provider_privacy_class: nil)
      deliveries = @inbox_store.list(chat_id: require_chat_id(chat_id), state: state, limit: limit)
      records = deliveries.filter_map do |delivery|
        if !provider_privacy_class.to_s.empty? &&
           !ConversationArtifactContract.provider_allowed?(delivery.fetch("privacy"), provider_privacy_class)
          next
        end

        artifact = @artifact_store.find(delivery.fetch("artifact_id"))
        raise RuntimeError, "inbox delivery references unknown artifact #{delivery.fetch('artifact_id')}" unless artifact
        next unless provider_privacy_class.to_s.empty? || ConversationArtifactContract.provider_allowed?(artifact.fetch("privacy"), provider_privacy_class)

        validate_revision!(artifact)
        validate_provenance!(artifact, delivery)
        project(artifact, [delivery])
      end
      {
        "ok" => true,
        "lifecycle_state" => "complete",
        "records" => records,
        "count" => records.length,
        "metadata_only" => true,
        "content_read" => false,
        "file_mutated" => false
      }
    rescue ArgumentError => error
      failure(error.message)
    rescue RuntimeError => error
      blocked(error.message)
    end

    def detail(artifact_id:, provider_privacy_class: nil)
      artifact = @artifact_store.find(artifact_id)
      return awaiting("unknown artifact ID: #{artifact_id}") unless artifact
      if !provider_privacy_class.to_s.empty? && !ConversationArtifactContract.provider_allowed?(artifact.fetch("privacy"), provider_privacy_class)
        return blocked("artifact privacy is incompatible with provider context")
      end

      deliveries = @inbox_store.records.values.select { |record| record["artifact_id"] == artifact.fetch("artifact_id") }
      deliveries.each { |delivery| validate_provenance!(artifact, delivery) }
      validate_revision!(artifact)
      {
        "ok" => true,
        "lifecycle_state" => "complete",
        "record" => project(artifact, deliveries),
        "metadata_only" => true,
        "content_read" => false,
        "file_mutated" => false
      }
    rescue ArgumentError => error
      failure(error.message)
    rescue RuntimeError => error
      blocked(error.message)
    end

    def deliver(artifact_id:, chat_id:, reason: "explicit_chat_delivery")
      artifact = @artifact_store.find(artifact_id)
      return awaiting("unknown artifact ID: #{artifact_id}") unless artifact
      return blocked("artifact is not active") unless artifact["lifecycle"] == "active"
      normalized_chat = require_chat_id(chat_id)
      unless Array(artifact["attached_chat_ids"]).include?(normalized_chat)
        return awaiting("artifact must be attached to the current chat before delivery")
      end

      validate_revision!(artifact)
      delivery = @inbox_store.deliver(
        artifact: artifact,
        originating_chat_id: artifact.dig("source", "chat_id") || normalized_chat,
        recipient_chat_id: normalized_chat,
        reason: reason
      )
      {
        "ok" => true,
        "lifecycle_state" => "complete",
        "delivery" => delivery,
        "artifact_id" => artifact.fetch("artifact_id"),
        "delivery_state" => delivery.fetch("latest_delivery_state"),
        "file_mutated" => false
      }
    rescue ArgumentError => error
      failure(error.message)
    rescue RuntimeError => error
      blocked(error.message)
    rescue StandardError => error
      failure("inbox delivery failed safely: #{error.class}: #{error.message}")
    end

    def change_state(delivery_id:, chat_id:, state:)
      delivery = @inbox_store.change_state(delivery_id, chat_id: chat_id, state: state)
      {
        "ok" => true,
        "lifecycle_state" => "complete",
        "delivery" => delivery,
        "delivery_state" => delivery.fetch("latest_delivery_state"),
        "file_mutated" => false
      }
    rescue ArgumentError => error
      failure(error.message)
    rescue RuntimeError => error
      blocked(error.message)
    rescue StandardError => error
      failure("inbox state change failed safely: #{error.class}: #{error.message}")
    end

    def context_for(chat_id:, provider_privacy_class:, limit: CONTEXT_RECORDS)
      result = inbox(
        chat_id: chat_id,
        limit: [limit.to_i, CONTEXT_RECORDS].select(&:positive?).min || CONTEXT_RECORDS,
        provider_privacy_class: provider_privacy_class
      )
      records = result["ok"] ? result.fetch("records") : []
      {
        "records" => records,
        "artifact_ids" => records.map { |record| record.fetch("artifact_id") },
        "count" => records.length,
        "metadata_only" => true,
        "content_read" => false,
        "rendered" => render_context(records),
        "lifecycle_state" => result.fetch("lifecycle_state"),
        "reason" => result["reason"]
      }
    end

    private

    def project(artifact, deliveries)
      newest_delivery = deliveries.max_by { |record| record.fetch("latest_state_at").to_s }
      {
        "artifact_id" => artifact.fetch("artifact_id"),
        "title" => artifact.fetch("title"),
        "kind" => artifact.fetch("kind"),
        "lifecycle" => artifact.fetch("lifecycle"),
        "privacy" => artifact.fetch("privacy"),
        "relative_path" => artifact.fetch("relative_path"),
        "media_type" => artifact.fetch("media_type"),
        "size_bytes" => artifact.fetch("size_bytes"),
        "sha256" => artifact.fetch("sha256"),
        "source" => artifact.fetch("source"),
        "revision_of_artifact_id" => artifact["revision_of_artifact_id"],
        "attached_chat_ids" => Array(artifact["attached_chat_ids"]),
        "artifact_created_at" => artifact.fetch("created_at"),
        "artifact_updated_at" => artifact.fetch("updated_at"),
        "delivery_id" => newest_delivery&.fetch("delivery_id"),
        "delivery_state" => newest_delivery&.fetch("latest_delivery_state"),
        "delivery_reason" => newest_delivery&.fetch("delivery_reason"),
        "delivered_at" => newest_delivery&.fetch("created_at"),
        "workspace_updated_at" => [artifact.fetch("updated_at").to_s, newest_delivery&.fetch("latest_state_at").to_s].max,
        "metadata_only" => true,
        "content_read" => false
      }
    end

    def validate_revision!(artifact)
      source_id = artifact["revision_of_artifact_id"].to_s
      return true if source_id.empty?

      raise RuntimeError, "revision references unknown source artifact #{source_id}" unless @artifact_store.find(source_id)
      true
    end

    def validate_provenance!(artifact, delivery)
      unless delivery.fetch("artifact_id") == artifact.fetch("artifact_id") &&
             delivery.fetch("sha256") == artifact.fetch("sha256") &&
             delivery.fetch("size_bytes").to_i == artifact.fetch("size_bytes").to_i &&
             delivery.fetch("privacy") == artifact.fetch("privacy")
        raise RuntimeError, "inbox delivery provenance does not match canonical artifact metadata"
      end
      true
    end

    def render_context(records)
      records.map do |record|
        [
          "- #{record['artifact_id']}: #{record['title']}",
          "kind=#{record['kind']}",
          "lifecycle=#{record['lifecycle']}",
          "privacy=#{record['privacy']}",
          "delivery=#{record['delivery_state'] || 'none'}",
          "sha256=#{record['sha256']}"
        ].join("; ")
      end.join("\n")
    end

    def normalize_limit(value)
      number = value.to_i
      number = MAX_RECORDS unless number.positive?
      [number, MAX_RECORDS].min
    end

    def require_chat_id(chat_id)
      value = chat_id.to_s.strip
      raise ArgumentError, "A current chat ID is required" if value.empty?

      value
    end

    def awaiting(reason)
      { "ok" => false, "lifecycle_state" => "awaiting_input", "reason" => reason, "file_mutated" => false }
    end

    def blocked(reason)
      { "ok" => false, "lifecycle_state" => "blocked_for_human_review", "reason" => reason, "file_mutated" => false }
    end

    def failure(reason)
      { "ok" => false, "lifecycle_state" => "failed", "reason" => reason, "file_mutated" => false }
    end
  end

  class NullConversationWorkspaceService
    def context_for(chat_id:, provider_privacy_class:, limit: ConversationWorkspaceService::CONTEXT_RECORDS)
      _unused = [chat_id, provider_privacy_class, limit]
      {
        "records" => [],
        "artifact_ids" => [],
        "count" => 0,
        "metadata_only" => true,
        "content_read" => false,
        "rendered" => "",
        "lifecycle_state" => "complete"
      }
    end
  end
end
