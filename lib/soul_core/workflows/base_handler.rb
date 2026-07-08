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

      def run(parameters:, original_text:)
        raise NotImplementedError, "#{self.class} must implement #run"
      end

      def respond(_state:, _text:)
        raise NotImplementedError, "#{self.class} does not implement #respond yet"
      end
    end
  end
end
