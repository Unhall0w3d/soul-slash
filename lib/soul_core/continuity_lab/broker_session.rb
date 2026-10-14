# frozen_string_literal: true

require_relative "fake_backend"
require_relative "context_builder"

module SoulCore
  module ContinuityLab
    # Fixture-only dispatch. These fixed route declarations confer no HTTP or
    # real-inference authority; a later adapter needs separate qualification.
    class BrokerSession
      UPSTREAM = "http://127.0.0.1:8082"
      ROUTES = { "generate" => "/v1/chat/completions", "format" => "/apply-template", "tokenize" => "/tokenize" }.freeze
      MAX_INPUT_BYTES = 12_288
      attr_reader :requests

      def initialize(responses:)
        @backend = FakeBackend.new(responses: responses)
        @requests, @last_index = 0, -1
      end

      def calls = @backend.calls

      def dispatch(request)
        raise ValidationError, "broker request budget exhausted" if @requests >= 32
        @requests += 1
        unless request.is_a?(Hash) && request["input"].is_a?(String) && request["input"].encoding == Encoding::UTF_8 &&
               request["input"].valid_encoding? && request["input"].bytesize <= MAX_INPUT_BYTES
          raise ValidationError, "invalid broker input"
        end
        case request["operation"]
        when "generate"
          index = request["call_index"]
          unless request.keys.sort == %w[call_index input operation] && index.is_a?(Integer) && index.between?(0, 15) && index > @last_index
            raise ValidationError, "invalid generation request"
          end
          @last_index = index
          { "ok" => true, "response" => @backend.call(call_index: index, input: request["input"]) }
        when "format_count"
          raise ValidationError, "invalid count request" unless request.keys.sort == %w[input operation]
          { "ok" => true, "count" => ContextBuilder.count(request["input"]), "counter" => ContextBuilder::COUNTER }
        else
          raise ValidationError, "broker operation is not allowed"
        end
      end
    end
  end
end
