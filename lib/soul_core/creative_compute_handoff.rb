# frozen_string_literal: true
require "digest"
require "json"

module SoulCore
  # Foreground only. The native service still validates the exact approval and
  # acquires its existing lease. This bridge never grants generation authority.
  class CreativeComputeHandoff
    class Unavailable < StandardError; end
    def initialize(control:)
      @control = control
      @context_key = "soul_creative_origin_#{object_id}".to_sym
    end

    def with_origin(member:, conversation_id:)
      prior = Thread.current[@context_key]
      Thread.current[@context_key] = [member, conversation_id]
      yield
    ensure
      Thread.current[@context_key] = prior
    end

    def status = @control.status

    def run(provider_id:, request_id:, project_id:, input_digest:)
      member, origin = Thread.current[@context_key] || ["studio", project_id]
      prepared = @control.prepare_handoff(provider_id: provider_id, request_id: request_id,
        conversation_id: project_id, origin_conversation_id: origin, member: member, input_digest: input_digest)
      raise Unavailable, "Creative handoff refused; no generation started" unless prepared["ok"]
      handoff = prepared.fetch("data").fetch("handoff")
      result = yield
      outcome = result.is_a?(Hash) && result["ok"] ? "complete" : (result.is_a?(Hash) && result["lifecycle_state"] == "canceled" ? "canceled" : "failed")
      digest = Digest::SHA256.hexdigest(JSON.generate(result))
      finished = @control.finish_handoff(handoff_id: handoff.fetch("handoff_id"), outcome: outcome, result_digest: digest)
      raise Unavailable, "Creative result retained; GPU release is unverified and compute remains held" unless finished["ok"]
      result
      # An exception, interruption, or lost response retains the durable hold.
      # It is not safe to infer cleanup and retry generation in an ensure block.
    end
  end
end
