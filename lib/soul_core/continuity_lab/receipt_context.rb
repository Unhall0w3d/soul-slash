# frozen_string_literal: true

require_relative "config"

module SoulCore
  module ContinuityLab
    # A deterministic projection of recorded results, not a progress summary or
    # notebook. Reconstruction from the journal remains the integrity authority.
    module ReceiptContext
      POLICY = Config::RECEIPT_POLICY
      SOURCE_FIELDS = %w[lineage_id collection id revision content_digest provenance span].freeze
      ARGUMENT_FIELDS = %w[lineage_id collection id revision start length query limit note_id expected_revision].freeze

      def self.enabled?(envelope) = envelope["context_policy"] == POLICY

      def self.receipt(group)
        result = group.fetch("tool_result")
        compact = result.slice("ok", "reason", "note_id", "revision", "truncated")
        compact["source"] = result.fetch("source").slice(*SOURCE_FIELDS) if result.key?("source")
        compact["hits"] = result.fetch("hits").map { |source| source.slice(*SOURCE_FIELDS) } if result.key?("hits")
        value = { "call_index" => group.fetch("call_index"), "tool_result" => compact }
        if result["reason"] == "invalid_action"
          value["invalid_response_sha256"] = Digest::SHA256.hexdigest(group.fetch("model_output"))
        else
          action = ContinuityLab.parse(group.fetch("model_output"))
          unless action.is_a?(Hash) && action["action"] == "tool" && action["arguments"].is_a?(Hash)
            raise ValidationError, "receipt requires a recorded tool action or rejection"
          end
          value["action"] = action.slice("action", "tool").merge("arguments" => action.fetch("arguments").slice(*ARGUMENT_FIELDS))
        end
        value
      end

      # Shared by the worker's byte pass, host token pass and journal replay.
      # Receipts themselves are essential; never silently evict their prefix.
      def self.omit_oldest!(envelope)
        raise ContextBudgetExceeded, "essential input exceeds context budget" if envelope.fetch("tool_groups").length <= 1
        removed = envelope.fetch("tool_groups").first
        if enabled?(envelope)
          receipts = envelope.fetch("execution_receipts")
          raise ValidationError, "receipt count exceeds fixed profile" if receipts.length >= 5
          receipts << receipt(removed)
        end
        envelope.fetch("tool_groups").shift
      end

      def self.validate_envelope!(envelope, call_index:)
        unless enabled?(envelope) && envelope["execution_receipts"].is_a?(Array) &&
               envelope["execution_receipts"].length <= 5 && envelope["tool_groups"].is_a?(Array)
          raise ValidationError, "invalid receipt envelope"
        end
        pairs = envelope["execution_receipts"] + envelope["tool_groups"]
        unless pairs.all? { |pair| pair.is_a?(Hash) && pair["call_index"].is_a?(Integer) } &&
               pairs.map { |pair| pair["call_index"] } == (0...call_index).to_a &&
               (call_index.zero? || !envelope["tool_groups"].empty?)
          raise ValidationError, "receipt prefix does not match current event attempts"
        end
      end
    end
  end
end
