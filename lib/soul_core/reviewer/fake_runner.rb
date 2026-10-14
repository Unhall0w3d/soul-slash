# frozen_string_literal: true

require_relative "store"

module SoulCore
  module Reviewer
    # No subprocess, network, model, tool dispatcher, or callback injection.
    # It exercises the workflow only, never correctness of a review judgment.
    class FakeRunner
      def self.runtime = Contract.fake_runtime

      def initialize(store:)
        raise Lab::ValidationError, "review store required" unless store.instance_of?(Store)
        @store = store
      end

      def run(review_id:, now:, available:)
        raise Lab::ValidationError, "availability must be explicit boolean" unless [true, false].include?(available)
        return @store.unavailable(review_id: review_id, now: now) unless available

        entry = @store.lease(review_id: review_id, now: now)
        attempt = entry.fetch("attempt_id")
        @store.start(review_id: review_id, attempt_id: attempt, now: now)
        response = { "review_id" => review_id, "verdict" => "insufficient_evidence", "findings" => [],
          "omissions" => ["M1 fake provider performs no semantic review and cannot satisfy independent validation."] }
        entry = @store.complete(review_id: review_id, attempt_id: attempt, response: response, runtime: self.class.runtime, now: now)
        { "status" => "completed", "review" => entry, "task_disposition" => Contract.disposition(entry["request"]) }
      rescue SignalException => signal
        begin
          @store.cancel(review_id: review_id, now: now) if attempt
        rescue Lab::Error, SystemCallError, IOError
          # Completion may already be durable, or storage may be unavailable.
          # Preserve the interruption; inspect/recover explicitly, never replay.
        end
        raise signal
      end
    end
  end
end
