# frozen_string_literal: true

require "net/http"
require "timeout"
require_relative "config"
require_relative "qwen_stream_response"

module SoulCore
  module ContinuityLab
    class BackendUnavailable < Error; end

    # Fixed local qualification transport. No environment proxy, redirect,
    # retry, credentials or operator-selected destination exists on this path.
    class QwenTransport
      READ_ROUTES = %w[/health /props /slots].freeze
      WRITE_ROUTES = %w[/apply-template /tokenize /completion].freeze
      MAX_BYTES = 524_288

      # Explicit diagnostic path only; ordinary request semantics remain unchanged.
      def stream_completion(payload, deadline:, on_progress:)
        unless payload.is_a?(Hash) && payload["stream"] == true && payload["n_predict"] == 768 && on_progress.respond_to?(:call)
          raise ValidationError, "invalid streaming request"
        end
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raise BackendUnavailable, "stream deadline exhausted" unless remaining.positive?
        body = ContinuityLab.encode(payload)
        raise ValidationError, "transport request too large" if body.bytesize > MAX_BYTES
        parser = QwenStreamResponse.new(on_progress: on_progress)
        http = Net::HTTP.new("127.0.0.1", 8082, nil)
        http.open_timeout = [remaining, 2].min
        http.read_timeout = http.write_timeout = [remaining, 60].min
        http.max_retries = 0
        request = Net::HTTP::Post.new("/completion")
        request["Content-Type"] = "application/json"
        request["Accept"] = "text/event-stream"
        request.body = body
        Timeout.timeout([remaining, 60].min) do
          http.start do |connection|
            connection.request(request) do |response|
              unless response.code == "200" && response["content-type"].to_s.split(";").first == "text/event-stream"
                raise BackendUnavailable, "unexpected streaming HTTP response"
              end
              response.read_body { |chunk| parser.feed(chunk) }
            end
          end
        end
        parser.finish
      rescue StandardError, Interrupt => error
        # A receipt callback may itself fail; never recover by returning partial text.
        if parser
          begin
            on_progress.call(parser.diagnostic.merge("interrupted" => true, "error_class" => error.class.name))
          rescue StandardError
            nil
          end
        end
        raise if error.is_a?(Interrupt)
        raise BackendUnavailable, "stream unavailable: #{error.class}"
      end

      def request(method, path, payload = nil, deadline:)
        permitted = (method == "GET" && READ_ROUTES.include?(path) && payload.nil?) ||
                    (method == "POST" && WRITE_ROUTES.include?(path) && payload.is_a?(Hash))
        raise ValidationError, "transport route denied" unless permitted
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raise BackendUnavailable, "transport deadline exhausted" unless remaining.positive?
        body = payload && ContinuityLab.encode(payload)
        raise ValidationError, "transport request too large" if body && body.bytesize > MAX_BYTES
        http = Net::HTTP.new("127.0.0.1", 8082, nil)
        http.open_timeout = [remaining, 2].min
        http.read_timeout = http.write_timeout = [remaining, 30].min
        http.max_retries = 0
        request = method == "GET" ? Net::HTTP::Get.new(path) : Net::HTTP::Post.new(path)
        request["Content-Type"] = "application/json"
        request.body = body if body
        bytes = +""
        Timeout.timeout([remaining, 30].min) do
          http.start do |connection|
            connection.request(request) do |response|
              raise BackendUnavailable, "local backend HTTP #{response.code}" unless response.code == "200"
              response.read_body do |chunk|
                bytes << chunk
                raise BackendUnavailable, "backend response too large" if bytes.bytesize > MAX_BYTES
              end
            end
          end
        end
        ContinuityLab.parse(bytes)
      rescue JSON::ParserError, Timeout::Error, IOError, SystemCallError, Net::HTTPBadResponse => error
        raise BackendUnavailable, "local backend unavailable: #{error.class}"
      end
    end
  end
end
