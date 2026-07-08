# frozen_string_literal: true

require_relative "workflow_session"

module SoulCore
  module WorkflowSessionHandlerDispatchPatch
    def respond(text)
      state = @runner.load_session("latest")
      workflow = state["workflow"].to_s

      if WorkflowHandlerRegistry.new.include?(workflow)
        handler = WorkflowHandlerRegistry.new.handler_for(workflow)
        return handler.respond(state: state, text: text) if handler.responds_to_status?(state["status"])
      end

      super
    rescue StandardError
      super
    end
  end
end

SoulCore::WorkflowSession.prepend(SoulCore::WorkflowSessionHandlerDispatchPatch)
