# frozen_string_literal: true

require_relative "store"
require_relative "fake_backend"
require_relative "pipe_backend"

module SoulCore
  module ContinuityLab
    class Runtime
      def initialize(store:, backend:)
        allowed = (backend.instance_of?(FakeBackend) && store.config["backend"] == "fake") ||
                  (backend.instance_of?(PipeBackend) && %w[fixture_pipe qwen_pipe].include?(store.config["backend"]) && store.config["context_mode"] == "explicit_v1")
        raise ValidationError, "backend must match the selected experimental profile" unless allowed
        @store, @backend, @config = store, backend, store.config
      end

      def submit(event_id:, content:)
        validate_id!(event_id)
        unless content.is_a?(String) && content.encoding == Encoding::UTF_8 && content.valid_encoding? && content.bytesize <= @config["max_event_bytes"]
          raise ValidationError, "invalid event content"
        end
        receipt = @store.synchronize do |state|
          existing = state["events"][event_id]
          if existing
            raise Conflict, "event ID content conflict" unless existing["content"] == content
          else
            guard_admission!(state)
            @store.append("accepted", { "event_id" => event_id, "content" => content, "content_digest" => Digest::SHA256.hexdigest(content) })
          end
          run(state, event_id)
        end
        yield receipt if block_given?
        receipt
      end

      def resume(event_id:)
        validate_id!(event_id)
        receipt = @store.synchronize do |state|
          raise ValidationError, "unknown event" unless state["events"].key?(event_id)
          run(state, event_id)
        end
        yield receipt if block_given?
        receipt
      end

      private

      def validate_id!(id)
        raise ValidationError, "invalid event ID" unless Actions.valid_id?(id)
      end

      def guard_admission!(state)
        raise Busy, "pending event must be resumed first" if state["events"].values.any? { |event| event["state"] == "pending" }
        if state["events"].values.any? { |event| event["state"] == "blocked_for_human_review" }
          raise Busy, "lineage requires human review"
        end
      end

      def run(state, id)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @config["max_seconds"]
        loop do
          event = state["events"].fetch(id)
          return receipt(event) if Store::TERMINAL.include?(event["state"])
          return finish(id, "failed", "context_budget_exceeded") if event["context_rejection"]
          return finish(id, "failed", "repeated_failed_action") if Actions.repeated_failure?(event, @config)
          return finish(id, "failed", "deadline_exceeded") if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          return finish(id, "failed", "invalid_action_budget") if event["invalid_count"] > @config["max_invalid_actions"]
          call = event["calls"].last
          index = event["calls"].length - 1
          if call && call["response"].nil?
            return finish(id, "blocked_for_human_review", "unresolved_model_intent")
          end
          if call.nil? || call["result"]
            return finish(id, "failed", "model_call_budget") if event["calls"].length >= @config["max_model_calls"]
            index = event["calls"].length
            intent = { "event_id" => id, "call_index" => index }
            if @config.tokenized_context?
              begin
                candidate = TokenContext.initial(state: state, event_id: id, config: @config)
              rescue ContextBudgetExceeded
                return finish(id, "failed", "context_budget_exceeded")
              end
              preparation = @backend.prepare(call_index: index, input: candidate)
              if preparation["status"] == "rejected"
                context = TokenContext.finalize(state: state, event_id: id, config: @config, preparation: preparation, rejected: true)
                @store.append("context_rejected", { "event_id" => id, "context" => context })
                return finish(id, "failed", "context_budget_exceeded")
              end
              intent["context"] = TokenContext.finalize(state: state, event_id: id, config: @config, preparation: preparation)
            elsif @config["context_mode"] == "explicit_v1"
              begin
                intent["context"] = ContextBuilder.build(state: state, event_id: id, config: @config)
              rescue ContextBudgetExceeded
                return finish(id, "failed", "context_budget_exceeded")
              end
            end
            @store.append("model_intent", intent)
            begin
              input = intent["context"] ? intent["context"].fetch("formatted") : event.fetch("content")
              args = { call_index: index, input: input }
              args[:preparation_digest] = intent.dig("context", "manifest", "preparation_digest") if @config.tokenized_context?
              response = @backend.call(**args)
            rescue ValidationError
              return finish(id, "failed", "fake_backend_exhausted")
            end
            @store.append("model_response", { "event_id" => id, "call_index" => index, "response" => response })
            call = state["events"][id]["calls"][index]
          end
          action = Actions.parse(call.fetch("response"), @config)
          case action["action"]
          when "reply" then return finish(id, "complete", "reply", action.fetch("content"))
          when "wait" then return finish(id, "complete", "wait")
          when "tool"
            return finish(id, "failed", "tool_call_budget") if event["tool_count"] >= @config["max_tool_calls"]
            perform_tool(state, id, index, action)
          else
            @store.append("action_result", {
              "event_id" => id, "call_index" => index, "operation_id" => operation_id(id, index),
              "invalid" => true, "tool_attempt" => false,
              "result" => { "ok" => false, "reason" => "invalid_action" }
            })
          end
        end
      end

      def perform_tool(state, id, index, action)
        payload = { "event_id" => id, "call_index" => index, "operation_id" => operation_id(id, index),
                    "invalid" => false, "tool_attempt" => true }
        payload.merge!(Actions.tool_result(state, action, @config, id))
        @store.append("action_result", payload)
      end

      def operation_id(id, index)
        ContinuityLab.digest({ "event_id" => id, "call_index" => index })
      end

      def finish(id, state, reason, reply = nil)
        payload = { "event_id" => id, "state" => state, "reason" => reason }
        payload["reply"] = reply unless reply.nil?
        @store.append("terminal", payload)
        payload
      end

      def receipt(event)
        event.select { |key, _| %w[event_id state reason reply].include?(key) }
      end
    end
  end
end
