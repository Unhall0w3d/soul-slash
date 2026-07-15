# frozen_string_literal: true

require "json"
require "securerandom"

module SoulCore
  class DashboardHttpApplication
    Response = Struct.new(:status, :headers, :body, keyword_init: true)

    STATIC_ROUTES = {
      "/assets/dashboard.css" => ["assets/dashboard/dashboard.css", "text/css; charset=utf-8"],
      "/assets/dashboard.js" => ["assets/dashboard/dashboard.js", "text/javascript; charset=utf-8"],
      "/brand/primary-mark.png" => ["assets/brand/soul-slash-primary-mark.png", "image/png"],
      "/brand/repo-header.png" => ["assets/brand/soul-slash-repo-header.png", "image/png"],
      "/brand/supporting-scene.png" => ["assets/brand/soul-slash-supporting-scene.png", "image/png"]
    }.freeze

    SECURITY_HEADERS = {
      "Content-Security-Policy" => "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'",
      "X-Content-Type-Options" => "nosniff",
      "X-Frame-Options" => "DENY",
      "Referrer-Policy" => "no-referrer",
      "Permissions-Policy" => "camera=(), microphone=(), geolocation=(), payment=(), usb=()",
      "Connection" => "close"
    }.freeze

    attr_reader :csrf_token

    def initialize(root:, facade:, bind_host:, port:, csrf_token: SecureRandom.hex(32))
      @root = File.expand_path(root)
      @facade = facade
      @bind_host = bind_host
      @port = Integer(port)
      @csrf_token = csrf_token
    end

    def call(method:, target:, headers: {}, body: "")
      method = method.to_s.upcase
      normalized_headers = headers.each_with_object({}) { |(key, value), memo| memo[key.to_s.downcase] = value.to_s }
      return response(400, "Bad Request") unless valid_host?(normalized_headers["host"])
      return response(404, "Not Found") unless target.is_a?(String) && target.start_with?("/") && !target.include?("?") && !target.include?("#")

      if target == "/"
        return response(405, "Method Not Allowed", "Allow" => "GET, HEAD") unless %w[GET HEAD].include?(method)

        html = File.binread(File.join(@root, "assets/dashboard/index.html")).sub("__SOUL_CSRF_TOKEN__", @csrf_token)
        html = "" if method == "HEAD"
        return response(200, html, "Content-Type" => "text/html; charset=utf-8", "Cache-Control" => "no-store")
      end

      if STATIC_ROUTES.key?(target)
        return response(405, "Method Not Allowed", "Allow" => "GET") unless method == "GET"

        relative_path, content_type = STATIC_ROUTES.fetch(target)
        return response(200, File.binread(File.join(@root, relative_path)), "Content-Type" => content_type, "Cache-Control" => "no-store")
      end

      return api_call(normalized_headers, body) if target == "/api/v1/call" && method == "POST"
      return response(405, "Method Not Allowed", "Allow" => "POST") if target == "/api/v1/call"

      response(404, "Not Found")
    rescue JSON::ParserError
      json_response(400, error_envelope("malformed_json", "request body must be valid JSON"))
    rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
      json_response(400, error_envelope("invalid_encoding", "request body must be valid UTF-8"))
    rescue StandardError => error
      json_response(500, error_envelope("transport_failure", "dashboard request failed safely: #{error.class}"))
    end

    private

    def api_call(headers, body)
      return json_response(415, error_envelope("content_type", "Content-Type must be application/json")) unless headers["content-type"].to_s.split(";", 2).first.strip.downcase == "application/json"
      return json_response(403, error_envelope("origin", "same-origin request required")) unless valid_origin?(headers["origin"])
      return json_response(403, error_envelope("csrf", "valid CSRF token required")) unless secure_compare(headers["x-soul-csrf"], @csrf_token)
      return json_response(413, error_envelope("body_too_large", "request body exceeds 128 KiB")) if body.bytesize > 128 * 1024

      request = JSON.parse(body)
      envelope = @facade.call(request)
      json_response(200, envelope)
    end

    def valid_host?(host)
      allowed_authorities.include?(host.to_s.downcase)
    end

    def valid_origin?(origin)
      allowed_authorities.any? { |authority| origin.to_s.downcase == "http://#{authority}" }
    end

    def allowed_authorities
      @allowed_authorities ||= begin
        hosts = [@bind_host, "127.0.0.1", "localhost", "[::1]"]
        hosts.map { |host| "#{host}:#{@port}" }.uniq.freeze
      end
    end

    def secure_compare(left, right)
      return false unless left.is_a?(String) && left.bytesize == right.bytesize

      left.bytes.zip(right.bytes).reduce(0) { |memo, (a, b)| memo | (a ^ b) }.zero?
    end

    def json_response(status, value)
      response(status, JSON.generate(value), "Content-Type" => "application/json; charset=utf-8", "Cache-Control" => "no-store")
    end

    def error_envelope(code, reason)
      {
        "schema_version" => "soul.application.v1",
        "lifecycle_state" => "failed",
        "mutation" => "none",
        "error" => { "code" => code, "reason" => reason }
      }
    end

    def response(status, body, extra_headers = {})
      Response.new(status: status, headers: SECURITY_HEADERS.merge(extra_headers), body: body)
    end
  end
end
