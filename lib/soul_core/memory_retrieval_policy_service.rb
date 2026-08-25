# frozen_string_literal: true

require "digest"
require "json"

module SoulCore
  class MemoryRetrievalPolicyService
    SCHEMA = "soul.memory_retrieval_policy_control.a26.v1"
    ACTIVATE_CONFIRMATION = "ACTIVATE_MEMORY_RETRIEVAL_POLICY"
    ROLLBACK_CONFIRMATION = "ROLLBACK_MEMORY_RETRIEVAL_POLICY"
    MAX_REASON_CHARACTERS = 500

    def initialize(store:)
      @store = store
    end

    def status
      complete(@store.status, mutation: "none")
    rescue StandardError => error
      failed("retrieval policy status failed safely: #{error.class}")
    end

    def preview(profile:, reason:)
      reason = validate_reason(reason)
      scope = {"action" => "activate", "profile" => profile.to_s, "reason_sha256" => Digest::SHA256.hexdigest(reason)}
      complete(scope.merge("confirmation_phrase" => ACTIVATE_CONFIRMATION, "expected_digest" => digest(scope)), mutation: "none")
    rescue StandardError => error
      failed("retrieval policy preview failed safely: #{error.class}")
    end

    def execute(profile:, reason:, confirmation:, expected_digest:)
      previewed = preview(profile: profile, reason: reason)
      return previewed unless previewed["lifecycle_state"] == "complete"
      data = previewed.fetch("data")
      return blocked("retrieval policy confirmation mismatch") unless confirmation.to_s == ACTIVATE_CONFIRMATION
      return blocked("retrieval policy preview changed") unless secure_compare(expected_digest, data.fetch("expected_digest"))
      complete(@store.activate(profile: profile, reason_sha256: data.fetch("reason_sha256")), mutation: "retrieval_policy_changed")
    rescue StandardError => error
      failed("retrieval policy activation failed safely: #{error.class}")
    end

    def rollback_preview(reason:)
      reason = validate_reason(reason)
      scope = {"action" => "rollback", "reason_sha256" => Digest::SHA256.hexdigest(reason)}
      complete(scope.merge("confirmation_phrase" => ROLLBACK_CONFIRMATION, "expected_digest" => digest(scope)), mutation: "none")
    rescue StandardError => error
      failed("retrieval policy rollback preview failed safely: #{error.class}")
    end

    def rollback_execute(reason:, confirmation:, expected_digest:)
      previewed = rollback_preview(reason: reason)
      return previewed unless previewed["lifecycle_state"] == "complete"
      data = previewed.fetch("data")
      return blocked("retrieval policy rollback confirmation mismatch") unless confirmation.to_s == ROLLBACK_CONFIRMATION
      return blocked("retrieval policy rollback preview changed") unless secure_compare(expected_digest, data.fetch("expected_digest"))
      complete(@store.rollback(reason_sha256: data.fetch("reason_sha256")), mutation: "retrieval_policy_rolled_back")
    rescue StandardError => error
      failed("retrieval policy rollback failed safely: #{error.class}")
    end

    private

    def validate_reason(value)
      text = value.to_s.strip
      raise ArgumentError, "retrieval policy reason is invalid" if text.empty? || text.length > MAX_REASON_CHARACTERS || text.match?(/[\r\n]/)
      text
    end

    def digest(value) = Digest::SHA256.hexdigest(JSON.generate(value.sort.to_h))
    def secure_compare(left, right) = left.to_s.bytesize == right.to_s.bytesize && left.to_s.bytes.zip(right.to_s.bytes).reduce(0) { |sum, pair| sum | (pair[0] ^ pair[1]) }.zero?
    def complete(data, mutation:) = {"lifecycle_state" => "complete", "schema" => SCHEMA, "data" => data, "mutation" => mutation}
    def blocked(message) = {"lifecycle_state" => "blocked_for_human_review", "schema" => SCHEMA, "message" => message, "mutation" => "none"}
    def failed(message) = {"lifecycle_state" => "failed", "schema" => SCHEMA, "message" => message, "mutation" => "none"}
  end
end
