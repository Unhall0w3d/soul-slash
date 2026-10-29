# frozen_string_literal: true
require_relative "continuity_lab/chat_application"
require_relative "roster_conversation_gateway"
require_relative "roster_admission_busy"

module SoulCore
  # Transport only; model controls are owned by the qualified adapter, not UI
  # defaults. Content-addressed request IDs make identical HTTP retries replay.
  class RosterChatApplication < ContinuityLab::ChatApplication
    def initialize(backend:, bearer_token:, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, isolated_models: [])
      unless isolated_models.is_a?(Array) && isolated_models.uniq==isolated_models &&
          (isolated_models-RosterChatAdapter::ISOLATED_MODELS).empty?
        raise ArgumentError,"unknown isolated candidate"
      end
      @isolated_models=isolated_models.map { |id| id.dup.freeze }.freeze
      super(backend: backend, bearer_token: bearer_token)
      @clock = clock
    end

    private

    def error_response(status, code, message)
      if status == 429 && code == "busy"
        # Active-job conflict, not a rate/quota error; LibreChat preserves this message.
        return json_response(409, {"error"=>{"code"=>"roster_busy", "type"=>"busy",
          "message"=>RosterAdmissionBusy::MESSAGE, "request_admitted"=>false}})
      end
      super
    end

    def supported_models = RosterChatAdapter::MODELS + @isolated_models
    def completion_model(result) = result.fetch("model")
    def generation_parameters = { "max_tokens" => 2048, "temperature" => 1.0, "top_p" => 0.95 }
    # JavaScript serializes 1.0 as 1; both denote the same fixed native control.
    def valid_temperature?(value) = (value.instance_of?(Integer) || value.instance_of?(Float)) && value == 1

    def backend_complete(conversation_id, request, messages, cancel)
      model=request.fetch("model")
      adapter = RosterChatAdapter.new(model:model,isolated:@isolated_models.include?(model))
      request_id = RosterConversationGateway.digest({ "conversation" => conversation_id,
        "adapter" => adapter.binding, "messages" => messages })
      result = @backend.complete(conversation_id: conversation_id, request_id: request_id,
        adapter: adapter, messages: messages, deadline: @clock.call + 179, cancel: cancel)
      unless result["model"] == adapter.model && result["request_id"] == request_id &&
             result["conversation_id"] == conversation_id && result["adapter"] == adapter.binding
        raise ContinuityLab::Error, "backend attribution mismatch"
      end
      { "id" => "chatcmpl-#{request_id}", "created" => Time.now.to_i,
        "model" => result.fetch("model"), "content" => result.fetch("content"),
        "soul" => result.slice("conversation_id", "request_id", "lineage", "model", "adapter",
          "replayed", "history_policy", "usage", "execution").merge("timestamp_scope" => "HTTP response, not journal creation") }
    rescue RosterAdmissionBusy
      raise ContinuityLab::Busy, RosterAdmissionBusy::MESSAGE
    rescue RosterConversationGateway::Refused
      raise ContinuityLab::Conflict, "journal refused request"
    rescue RosterRuntimeOwner::Unavailable, RosterChatExchange::Stopped, RosterChatAdapter::Unavailable
      raise ContinuityLab::Error, "runtime unavailable; inspect retained state"
    rescue RosterChatAdapter::Invalid
      raise ContinuityLab::ValidationError, "adapter request invalid"
    end
  end
end
