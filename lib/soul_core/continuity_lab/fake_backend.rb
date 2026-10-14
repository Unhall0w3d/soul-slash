# frozen_string_literal: true

require_relative "config"

module SoulCore
  module ContinuityLab
    # Scripted data, not an injectable executable provider. No input is evaluated.
    class FakeBackend
      attr_reader :calls

      def initialize(responses:)
        unless responses.is_a?(Array) && responses.length.between?(1, 16) &&
               responses.all? { |value| value.is_a?(String) && value.encoding == Encoding::UTF_8 && value.valid_encoding? && value.bytesize <= 65_536 }
          raise ValidationError, "fake responses must be bounded strings"
        end
        @responses = responses.map { |value| value.dup.freeze }.freeze
        @calls = 0
        @inputs = []
      end

      def inputs = @inputs.map(&:dup)

      def call(call_index:, input:)
        @calls += 1
        @inputs << input.dup.freeze
        @responses.fetch(call_index).dup
      rescue IndexError
        raise ValidationError, "fake response script exhausted"
      end
    end
  end
end
