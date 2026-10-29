# frozen_string_literal: true

require "digest"
require_relative "roster_chat_adapter"

module SoulCore
  # One bounded attempt, composed by a trusted foreground owner. The injected
  # client must enforce its deadline, loopback destination and response byte cap;
  # admission must verify ownership/identity under the caller's runtime lease.
  # This component cannot start, switch, stop, or grant authority to a model.
  class RosterChatExchange
    class Stopped < StandardError; end

    def initialize(adapter:, client:, admission:, receipt:, cancel: -> { false },
                   clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      raise ArgumentError, "roster adapter required" unless adapter.instance_of?(RosterChatAdapter)
      @adapter, @client, @admission, @receipt, @cancel, @clock = adapter, client, admission, receipt, cancel, clock
      @used = false
    end

    def call(messages:, deadline:)
      raise Stopped, "attempt already consumed; no automatic retry" if @used
      @used = true
      unless deadline.is_a?(Numeric) && deadline.finite? && (deadline - @clock.call).between?(0.001, 180)
        raise Stopped, "finite request window of at most 180 seconds required"
      end
      check!(deadline)
      payload = @adapter.payload(messages: messages)
      template = @client.request("POST", "/apply-template",
        payload.slice("messages", "chat_template_kwargs").merge("add_generation_prompt" => true), deadline: deadline)
      prompt = template.is_a?(Hash) && template["prompt"]
      unless prompt.is_a?(String) && prompt.valid_encoding? && prompt.bytesize.between?(1, RosterChatAdapter::MAX_BYTES)
        raise RosterChatAdapter::Invalid, "invalid native template"
      end
      check!(deadline)
      tokenized = @client.request("POST", "/tokenize",
        { "content" => prompt, "add_special" => false, "parse_special" => true }, deadline: deadline)
      count = @adapter.validate_input_tokens!(tokenized.is_a?(Hash) && tokenized["tokens"])
      record = { "adapter" => @adapter.binding, "request_sha256" => Digest::SHA256.hexdigest(JSON.generate(payload)),
        "prompt_sha256" => Digest::SHA256.hexdigest(prompt), "input_tokens" => count }
      check!(deadline)
      # Intent is recorded before generation; exceptions and ambiguous transport
      # outcomes consume this attempt and must be reconciled by the journal owner.
      @receipt.call(record.merge("state" => "generation_intent"))
      check!(deadline)
      response = @client.request("POST", "/v1/chat/completions", payload, deadline: deadline)
      check!(deadline)
      result = @adapter.final_reply(response)
      unless result["usage"]["prompt_tokens"] == count
        raise RosterChatAdapter::Unavailable, "native template and generation token counts differ"
      end
      @receipt.call(record.merge("state" => "final_received", "usage" => result["usage"],
        "final_sha256" => Digest::SHA256.hexdigest(result["content"])))
      check!(deadline)
      result
    end

    private

    def check!(deadline)
      raise Stopped, "canceled or deadline exhausted" if @cancel.call || @clock.call >= deadline
      raise Stopped, "runtime admission denied" unless @admission.call == true
    end
  end
end
