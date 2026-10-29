# frozen_string_literal: true
require_relative "roster_chat_application"
require_relative "telemetry_diagnostic"

module SoulCore
  class RosterServiceApplication < RosterChatApplication
    CONTROL_ROUTES = { "/v1/soul/requests/cancel" => :cancel_request,
      "/v1/soul/requests/status" => :request_status }.freeze
    COMPUTE_ROUTES = {"/v1/soul/compute/status"=>[:compute_status,[]],
      "/v1/soul/compute/telemetry"=>[:creative_telemetry,%w[handoff_id]],
      "/v1/soul/compute/preview"=>[:compute_preview,%w[policy]],
      "/v1/soul/compute/execute"=>[:compute_execute,%w[confirmation expected_digest policy]],
      "/v1/soul/compute/handoff/prepare"=>[:prepare_handoff,%w[conversation_id input_digest member origin_conversation_id provider_id request_id]],
      "/v1/soul/compute/handoff/finish"=>[:finish_handoff,%w[handoff_id outcome result_digest]],
      "/v1/soul/compute/handoff/recover"=>[:recover_prepared_handoff,%w[confirmation expected_digest handoff_id result_digest]]}.freeze

    def call(method:, target:, headers:, body: nil, cancel: -> { false })
      return super unless CONTROL_ROUTES.key?(target) || COMPUTE_ROUTES.key?(target)

      normalized = normalize_headers(headers)
      return error_response(403, "origin_forbidden", "Cross-origin requests are not supported.") if normalized.key?("origin")
      return error_response(401, "unauthorized", "A valid bearer token is required.") unless authenticated?(normalized["authorization"])
      return error_response(405, "method_not_allowed", "POST required.") unless method == "POST"
      raise ArgumentError unless body.is_a?(String) && body.bytesize.between?(1, 1024)
      request = ContinuityLab.parse(body)
      if COMPUTE_ROUTES.key?(target)
        operation,keys=COMPUTE_ROUTES.fetch(target)
        raise ArgumentError unless request.is_a?(Hash) && request.keys.sort==keys
        return json_response(200,@backend.public_send(operation,**request.transform_keys(&:to_sym)))
      end
      raise ArgumentError unless request.is_a?(Hash) && request.keys.sort == %w[conversation_id request_id]
      result = @backend.public_send(CONTROL_ROUTES.fetch(target),
        conversation_id: request.fetch("conversation_id"), request_id: request.fetch("request_id"))
      json_response(200, result)
    rescue ArgumentError, JSON::ParserError, ContinuityLab::ValidationError
      error_response(422, "invalid_request", "Bounded exact request identity required.")
    rescue StandardError => error
      if target == "/v1/soul/compute/telemetry"
        return error_response(503, TelemetryDiagnostic.code(error), "Telemetry unavailable; no retry was started.")
      end
      error_response(503, "control_unavailable", "Request state is unavailable; do not assume cleanup.")
    end

    private

    def health_response
      status = @backend.status
      scope = status["memory_policy"] == "approved_shared_and_member_scoped_v1" ?
        "text-only roster; approved scoped memory; no tools" : "text-only roster; no memory projection or tools"
      scope = "roster; approved scoped memory; explicit bounded read-only commands; no autonomous tools" if status["read_only_skills"]
      json_response(200, status.merge("scope" => scope))
    end
  end
end
