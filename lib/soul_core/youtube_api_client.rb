# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module SoulCore
  class YouTubeApiClient
    API_ORIGIN = "https://www.googleapis.com"
    TOKEN_TIMEOUT = 20
    REQUEST_TIMEOUT = 30
    UPLOAD_TIMEOUT = 180
    MAX_RESPONSE_BYTES = 1024 * 1024
    UPLOAD_CHUNK_BYTES = 8 * 1024 * 1024
    TRANSIENT_STATUS = [408, 429, 500, 502, 503, 504].freeze
    MAX_ATTEMPTS = 3

    class ApiError < StandardError
      attr_reader :status, :reason

      def initialize(message, status: nil, reason: nil)
        super(message)
        @status = status
        @reason = reason
      end
    end

    def initialize(sleeper: ->(seconds) { sleep(seconds) }, http_adapter: nil)
      @sleeper = sleeper
      @http_adapter = http_adapter
    end

    def exchange_code(token_uri:, client_id:, client_secret:, code:, redirect_uri:, code_verifier:)
      form = {
        "client_id" => client_id,
        "client_secret" => client_secret,
        "code" => code,
        "code_verifier" => code_verifier,
        "grant_type" => "authorization_code",
        "redirect_uri" => redirect_uri
      }
      request_json(:post, token_uri, form: form, timeout: TOKEN_TIMEOUT)
    end

    def refresh_access_token(token_uri:, client_id:, client_secret:, refresh_token:)
      form = {
        "client_id" => client_id,
        "client_secret" => client_secret,
        "refresh_token" => refresh_token,
        "grant_type" => "refresh_token"
      }
      request_json(:post, token_uri, form: form, timeout: TOKEN_TIMEOUT)
    end

    def channel(access_token:)
      response = request_json(
        :get,
        "#{API_ORIGIN}/youtube/v3/channels?part=id,snippet&mine=true&maxResults=1",
        access_token: access_token
      )
      item = Array(response["items"]).first
      raise ApiError, "authorized Google account does not resolve to a YouTube channel" unless item

      { "id" => item.fetch("id"), "title" => item.dig("snippet", "title").to_s }
    rescue KeyError
      raise ApiError, "YouTube returned an invalid channel response"
    end

    def videos(access_token:, video_ids:)
      ids = Array(video_ids).map(&:to_s)
      raise ApiError, "YouTube video lookup requires between 1 and 50 IDs" unless ids.length.between?(1, 50)

      query = URI.encode_www_form(
        "part" => "snippet",
        "id" => ids.join(","),
        "maxResults" => ids.length.to_s
      )
      response = request_json(
        :get,
        "#{API_ORIGIN}/youtube/v3/videos?#{query}",
        access_token: access_token
      )
      Array(response["items"])
    end

    def update_video_snippet(access_token:, video_id:, snippet:)
      response, = request(
        :put,
        "#{API_ORIGIN}/youtube/v3/videos?part=snippet",
        access_token: access_token,
        body: JSON.generate("id" => video_id, "snippet" => snippet),
        headers: { "Content-Type" => "application/json; charset=UTF-8" },
        timeout: REQUEST_TIMEOUT,
        accepted: [200]
      )
      parse_json(response)
    end

    def initiate_upload(access_token:, metadata:, video_size:, mime_type:)
      _response, headers = request(
        :post,
        "#{API_ORIGIN}/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status&notifySubscribers=false",
        access_token: access_token,
        body: JSON.generate(metadata),
        headers: {
          "Content-Type" => "application/json; charset=UTF-8",
          "X-Upload-Content-Length" => video_size.to_s,
          "X-Upload-Content-Type" => mime_type
        },
        timeout: REQUEST_TIMEOUT,
        accepted: [200]
      )
      location = headers["location"].to_s
      raise ApiError, "YouTube did not return a resumable upload location" unless location.start_with?("https://")
      location
    end

    def upload_video(access_token:, upload_url:, path:, mime_type:, progress: nil)
      size = File.size(path)
      File.open(path, "rb") do |io|
        offset = 0
        while offset < size
          io.seek(offset)
          chunk = io.read([UPLOAD_CHUNK_BYTES, size - offset].min)
          raise ApiError, "local upload source ended before its recorded size" if chunk.nil? || chunk.empty?
          ending = offset + chunk.bytesize - 1
          progress&.call({
            "stage" => "upload_chunk",
            "message" => "Uploading bytes #{offset + 1}–#{ending + 1} of #{size}.",
            "offset" => offset,
            "ending" => ending,
            "total" => size
          })
          response, headers = request(
            :put,
            upload_url,
            access_token: access_token,
            body: chunk,
            headers: {
              "Content-Type" => mime_type,
              "Content-Range" => "bytes #{offset}-#{ending}/#{size}"
            },
            timeout: UPLOAD_TIMEOUT,
            accepted: [200, 201, 308]
          )
          return parse_json(response) unless response.empty?

          acknowledged = headers["range"].to_s.match(/\Abytes=0-(\d+)\z/)
          next_offset = acknowledged ? Integer(acknowledged[1]) + 1 : ending + 1
          raise ApiError, "YouTube returned an invalid resumable upload offset" unless next_offset > offset && next_offset <= size
          offset = next_offset
        end
      end
      raise ApiError, "YouTube resumable upload ended without a video resource"
    end

    def set_thumbnail(access_token:, video_id:, path:)
      File.open(path, "rb") do |io|
        response, = request(
          :post,
          "#{API_ORIGIN}/upload/youtube/v3/thumbnails/set?videoId=#{URI.encode_www_form_component(video_id)}&uploadType=media",
          access_token: access_token,
          body_stream: io,
          content_length: File.size(path),
          headers: { "Content-Type" => "image/png" },
          timeout: UPLOAD_TIMEOUT,
          accepted: [200]
        )
        parse_json(response)
      end
    end

    private

    def request_json(method, url, access_token: nil, form: nil, timeout: REQUEST_TIMEOUT)
      body = form ? URI.encode_www_form(form) : nil
      headers = form ? { "Content-Type" => "application/x-www-form-urlencoded" } : {}
      response, = request(method, url, access_token: access_token, body: body, headers: headers, timeout: timeout, accepted: [200])
      parse_json(response)
    end

    def request(method, url, access_token: nil, body: nil, body_stream: nil, content_length: nil, headers: {}, timeout:, accepted:, progress: nil)
      uri = URI.parse(url)
      raise ApiError, "YouTube request URL must use HTTPS" unless uri.is_a?(URI::HTTPS)

      attempts = 0
      begin
        attempts += 1
        request = build_request(method, uri, body: body, body_stream: body_stream, content_length: content_length)
        request["Authorization"] = "Bearer #{access_token}" if access_token
        headers.each { |key, value| request[key] = value }
        response = if @http_adapter
                     @http_adapter.call(uri, request, timeout)
                   else
                     Net::HTTP.start(
                       uri.host, uri.port, use_ssl: true,
                       open_timeout: [timeout, 10].min, read_timeout: timeout, write_timeout: timeout
                     ) { |http| http.request(request) }
                   end
        code = response.code.to_i
        return [bounded_body(response), response.to_hash.transform_values(&:first)] if accepted.include?(code)

        detail = safe_error(response)
        raise ApiError.new("YouTube API returned HTTP #{code}#{detail.empty? ? "" : ": #{detail}"}", status: code, reason: error_reason(response))
      rescue ApiError => error
        raise unless TRANSIENT_STATUS.include?(error.status) && attempts < MAX_ATTEMPTS && rewindable?(body_stream)

        body_stream.rewind if body_stream
        @sleeper.call(attempts)
        retry
      rescue IOError, EOFError, Errno::ECONNRESET, Errno::ETIMEDOUT, Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout => error
        raise ApiError, "YouTube transport failed: #{error.class}" unless attempts < MAX_ATTEMPTS && rewindable?(body_stream)

        body_stream.rewind if body_stream
        @sleeper.call(attempts)
        retry
      end
    end

    def build_request(method, uri, body:, body_stream:, content_length:)
      request_class = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put }.fetch(method)
      request = request_class.new(uri)
      if body_stream
        request.body_stream = body_stream
        request.content_length = Integer(content_length)
      elsif body
        request.body = body
      end
      request
    end

    def bounded_body(response)
      body = response.body.to_s
      raise ApiError, "YouTube response exceeds size limit" if body.bytesize > MAX_RESPONSE_BYTES

      body
    end

    def parse_json(body)
      JSON.parse(body)
    rescue JSON::ParserError
      raise ApiError, "YouTube returned invalid JSON"
    end

    def safe_error(response)
      parsed = JSON.parse(response.body.to_s.byteslice(0, MAX_RESPONSE_BYTES))
      parsed.dig("error", "message").to_s.gsub(/\s+/, " ").slice(0, 300)
    rescue JSON::ParserError
      ""
    end

    def error_reason(response)
      parsed = JSON.parse(response.body.to_s.byteslice(0, MAX_RESPONSE_BYTES))
      parsed.dig("error", "errors", 0, "reason").to_s
    rescue JSON::ParserError
      nil
    end

    def rewindable?(stream)
      stream.nil? || stream.respond_to?(:rewind)
    end
  end
end
