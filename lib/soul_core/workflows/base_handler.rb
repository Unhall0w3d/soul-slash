# frozen_string_literal: true

module SoulCore
  module Workflows
    class BaseHandler
      attr_reader :definition

      def initialize(definition:)
        @definition = definition
      end

      def intent
        definition.intent
      end

      def match_intent(_text, result_class:)
        nil
      end

      def responds_to_status?(_status)
        false
      end

      def run(parameters:, original_text:)
        raise NotImplementedError, "#{self.class} must implement #run"
      end

      def respond(state:, text:)
        raise NotImplementedError, "#{self.class} does not implement #respond for #{state['status']}"
      end
    end
  end
end
