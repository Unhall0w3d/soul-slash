# frozen_string_literal: true

require_relative "intent_router"
require_relative "workflow_handler_registry"

module SoulCore
  module WorkflowIntentHandlerDispatchPatch
    def route(text)
      result_class = self.class.const_get(:Result)
      matched = WorkflowHandlerRegistry.new.match_intent(text, result_class: result_class)
      return matched if matched

      super
    end
  end
end

SoulCore::IntentRouter.prepend(SoulCore::WorkflowIntentHandlerDispatchPatch)
