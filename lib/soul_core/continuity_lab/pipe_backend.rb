# frozen_string_literal: true

require_relative "config"

module SoulCore
  module ContinuityLab
    class BrokerDisconnected < Error; end

    # Only the fixed isolated worker constructs this adapter. The foreground
    # parent owns its deadline and fixture response script; no URLs exist here.
    class PipeBackend
      def initialize(input: $stdin, output: $stdout)
        @input, @output = input, output
      end

      def call(call_index:, input:, preparation_digest: nil)
        request = { "operation" => "generate", "call_index" => call_index, "input" => input }
        request["preparation_digest"] = preparation_digest unless preparation_digest.nil?
        value = exchange(request)
        unless value.is_a?(Hash) && value.keys.sort == %w[ok response] && value["ok"] == true && value["response"].is_a?(String) && value["response"].bytesize <= 65_536
          raise BrokerDisconnected, "invalid broker response"
        end
        value["response"]
      end

      def prepare(call_index:, input:)
        value = exchange({ "operation" => "prepare_context", "call_index" => call_index, "input" => input })
        unless value.is_a?(Hash) && value.keys.sort == %w[ok preparation] && [true, false].include?(value["ok"]) &&
               value["preparation"].is_a?(Hash) && value["preparation"]["status"] == (value["ok"] ? "ready" : "rejected")
          raise BrokerDisconnected, "invalid preparation response"
        end
        value["preparation"]
      end

      private

      def exchange(request)
        @output.puts(ContinuityLab.encode({ "type" => "request", "request" => {
          **request
        } }))
        @output.flush
        line = @input.gets(524_289)
        raise BrokerDisconnected, "broker response missing or oversized" unless line && line.end_with?("\n") && line.bytesize <= 524_288
        ContinuityLab.parse(line)
      rescue JSON::ParserError, IOError, SystemCallError => error
        raise BrokerDisconnected, "broker channel failed: #{error.class}"
      end
    end
  end
end
