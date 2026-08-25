# frozen_string_literal: true

require "digest"
require "json"

module SoulCore
  class MemoryProjectionReconciler
    SCHEMA = "soul.memory_projection_reconciler.a21.v1"
    CONFIRMATION = "REBUILD_MEMORY_PROJECTION"
    NAME_PREFIX = "soul_memory_"

    def initialize(contract:, qdrant_client:, falkor_client:, selector_store:)
      @contract = contract
      @qdrant_client = qdrant_client
      @falkor_client = falkor_client
      @selector_store = selector_store
    end

    def preview
      built = build_projection
      return built unless built.fetch("ok")

      plan = public_plan(built.fetch("bundle"), built.fetch("receipt"))
      result(false, "blocked_for_human_review", "Review the exact memory projection generation plan.",
        plan.merge("confirmation_phrase" => CONFIRMATION, "expected_digest" => digest(plan)))
    rescue StandardError => error
      failed("Memory projection preview failed safely: #{error.class}: #{error.message}")
    end

    def execute(confirmation:, expected_digest:)
      built = build_projection
      return built unless built.fetch("ok")

      bundle = built.fetch("bundle")
      receipt = built.fetch("receipt")
      plan = public_plan(bundle, receipt)
      plan_digest = digest(plan)
      unless secure_compare(confirmation, CONFIRMATION) && secure_compare(expected_digest, plan_digest)
        return result(false, "blocked_for_human_review", "Memory projection confirmation or plan digest is stale.",
          plan.merge("confirmation_phrase" => CONFIRMATION, "expected_digest" => plan_digest))
      end

      created = []
      phase = "qdrant_prepare"
      qdrant_state = prepare(@qdrant_client, plan.fetch("qdrant_collection"), bundle.fetch("qdrant"))
      created << [@qdrant_client, plan.fetch("qdrant_collection")] if qdrant_state == "created"
      phase = "falkor_prepare"
      falkor_state = prepare(@falkor_client, plan.fetch("falkor_graph"), bundle.fetch("falkor"))
      created << [@falkor_client, plan.fetch("falkor_graph")] if falkor_state == "created"

      phase = "qdrant_verify"
      verify_store!(@qdrant_client, plan.fetch("qdrant_collection"), plan.fetch("qdrant_payload_digest"))
      phase = "falkor_verify"
      verify_store!(@falkor_client, plan.fetch("falkor_graph"), plan.fetch("falkor_payload_digest"))
      previous = @selector_store.active
      selector = {
        "schema" => SCHEMA,
        "generation_id" => plan.fetch("generation_id"),
        "payload_digest" => plan.fetch("payload_digest"),
        "source_digests" => plan.fetch("source_digests"),
        "qdrant_collection" => plan.fetch("qdrant_collection"),
        "falkor_graph" => plan.fetch("falkor_graph")
      }
      phase = "selector_activate"
      @selector_store.activate(selector)
      result(true, "complete", "Memory projection generation verified and selected.",
        plan.merge("previous_generation_id" => previous&.fetch("generation_id", nil), "fallback" => "local_authoritative_retrieval"),
        "projection_generation_activated")
    rescue StandardError => error
      cleanup(created || [])
      failed("Memory projection generation failed safely during #{phase || "preparation"}: #{error.class}.", "projection_generation_partial")
    end

    private

    def build_projection
      projection = @contract.build
      unless projection.is_a?(Hash) && projection["lifecycle_state"] == "complete"
        return failed("Canonical projection contract is unavailable.")
      end
      data = projection.fetch("data")
      {"ok" => true, "bundle" => data.fetch("bundle"), "receipt" => data.fetch("receipt")}
    end

    def public_plan(bundle, receipt)
      payload_digest = receipt.fetch("payload_digest")
      suffix = payload_digest[0, 20]
      {
        "schema" => SCHEMA,
        "authority" => "conversation_memory_ledger",
        "generation_id" => "generation_#{suffix}",
        "payload_digest" => payload_digest,
        "source_digests" => receipt.fetch("source_digests"),
        "qdrant_collection" => "#{NAME_PREFIX}vectors_#{suffix}",
        "falkor_graph" => "SoulMemory_#{suffix}",
        "qdrant_payload_digest" => digest(bundle.fetch("qdrant")),
        "falkor_payload_digest" => digest(bundle.fetch("falkor")),
        "qdrant" => receipt.fetch("qdrant"),
        "falkor" => receipt.fetch("falkor"),
        "content_included" => false,
        "activation" => "owner_private_local_selector_after_dual_verification",
        "fallback" => "local_authoritative_retrieval"
      }
    end

    def prepare(client, name, payload)
      state = client.prepare(name: name, payload: payload)
      raise "projection client returned invalid preparation state" unless %w[created existing].include?(state)
      state
    end

    def verify_store!(client, name, expected_digest)
      observed = client.verify(name: name)
      raise "projection verification is unavailable" unless observed.is_a?(Hash)
      raise "projection verification digest mismatched" unless secure_compare(observed.fetch("payload_digest").to_s, expected_digest)
    end

    def cleanup(created)
      created.reverse_each do |client, name|
        client.delete(name: name)
      rescue StandardError
        nil
      end
    end

    def result(ok, lifecycle, reason, data, mutation = "none")
      {"ok" => ok, "lifecycle_state" => lifecycle, "schema" => SCHEMA, "reason" => reason, "data" => data, "mutation" => mutation}
    end

    def failed(reason, mutation = "none")
      result(false, "failed", reason, {"fallback" => "local_authoritative_retrieval", "content_included" => false}, mutation)
    end

    def digest(value)
      Digest::SHA256.hexdigest(JSON.generate(canonicalize(value)))
    end

    def canonicalize(value)
      case value
      when Hash then value.keys.sort.to_h { |key| [key, canonicalize(value.fetch(key))] }
      when Array then value.map { |item| canonicalize(item) }
      else value
      end
    end

    def secure_compare(left, right)
      left = left.to_s
      right = right.to_s
      left.bytesize == right.bytesize && left.bytes.zip(right.bytes).reduce(0) { |sum, pair| sum | (pair[0] ^ pair[1]) }.zero?
    end
  end
end
