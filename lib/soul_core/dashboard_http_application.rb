# frozen_string_literal: true

require "json"
require "base64"
require "securerandom"
require "uri"
require_relative "dashboard_authentication"
require_relative "dashboard_music_job_manager"
require_relative "voice_transcription_service"
require_relative "voice_synthesis_service"
require_relative "voice_presence_launch_service"
require_relative "picture_understanding_service"
require_relative "screen_capture_service"

module SoulCore
  class DashboardHttpApplication
    Response = Struct.new(:status, :headers, :body, keyword_init: true)

    STATIC_ROUTES = {
      "/assets/dashboard.css" => ["assets/dashboard/dashboard.css", "text/css; charset=utf-8"],
      "/assets/dashboard.js" => ["assets/dashboard/dashboard.js", "text/javascript; charset=utf-8"],
      "/brand/micro-mark.svg" => ["assets/brand/soul-slash-micro-mark.svg", "image/svg+xml"],
      "/brand/repo-header.png" => ["assets/brand/soul-slash-repo-header.png", "image/png"],
      "/brand/character/soul-full-body.png" => ["assets/brand/character/soul-full-body.png", "image/png"],
      "/brand/character/soul-portrait-unmasked.png" => ["assets/brand/character/soul-portrait-unmasked.png", "image/png"],
      "/brand/character/soul-portrait-masked.png" => ["assets/brand/character/soul-portrait-masked.png", "image/png"],
      "/notifications/cue-submit.wav" => ["assets/notifications/cue-submit.wav", "audio/wav"],
      "/notifications/cue-wake.wav" => ["assets/notifications/cue-wake.wav", "audio/wav"],
      "/notifications/cue-complete.wav" => ["assets/notifications/cue-complete.wav", "audio/wav"],
      "/notifications/cue-attention.wav" => ["assets/notifications/cue-attention.wav", "audio/wav"],
      "/notifications/f3-chat-ready.wav" => ["assets/notifications/f3-chat-ready.wav", "audio/wav"],
      "/notifications/m3-chat-ready.wav" => ["assets/notifications/m3-chat-ready.wav", "audio/wav"],
      "/notifications/f3-music-ready.wav" => ["assets/notifications/f3-music-ready.wav", "audio/wav"],
      "/notifications/m3-music-ready.wav" => ["assets/notifications/m3-music-ready.wav", "audio/wav"],
      "/notifications/f3-visual-ready.wav" => ["assets/notifications/f3-visual-ready.wav", "audio/wav"],
      "/notifications/m3-visual-ready.wav" => ["assets/notifications/m3-visual-ready.wav", "audio/wav"],
      "/notifications/f3-lyrics-ready.wav" => ["assets/notifications/f3-lyrics-ready.wav", "audio/wav"],
      "/notifications/m3-lyrics-ready.wav" => ["assets/notifications/m3-lyrics-ready.wav", "audio/wav"],
      "/notifications/f3-improvement-ready.wav" => ["assets/notifications/f3-improvement-ready.wav", "audio/wav"],
      "/notifications/m3-improvement-ready.wav" => ["assets/notifications/m3-improvement-ready.wav", "audio/wav"],
      "/notifications/f3-backup-ready.wav" => ["assets/notifications/f3-backup-ready.wav", "audio/wav"],
      "/notifications/m3-backup-ready.wav" => ["assets/notifications/m3-backup-ready.wav", "audio/wav"],
      "/notifications/f3-attention.wav" => ["assets/notifications/f3-attention.wav", "audio/wav"],
      "/notifications/m3-attention.wav" => ["assets/notifications/m3-attention.wav", "audio/wav"],
      "/notifications/f3-device-attention.wav" => ["assets/notifications/f3-device-attention.wav", "audio/wav"],
      "/notifications/m3-device-attention.wav" => ["assets/notifications/m3-device-attention.wav", "audio/wav"],
      "/notifications/f3-reboot-required.wav" => ["assets/notifications/f3-reboot-required.wav", "audio/wav"],
      "/notifications/m3-reboot-required.wav" => ["assets/notifications/m3-reboot-required.wav", "audio/wav"],
      "/notifications/f3-backup-attention.wav" => ["assets/notifications/f3-backup-attention.wav", "audio/wav"],
      "/notifications/m3-backup-attention.wav" => ["assets/notifications/m3-backup-attention.wav", "audio/wav"],
      "/notifications/f3-security-alert.wav" => ["assets/notifications/f3-security-alert.wav", "audio/wav"],
      "/notifications/m3-security-alert.wav" => ["assets/notifications/m3-security-alert.wav", "audio/wav"]
    }.freeze

    SECURITY_HEADERS = {
      "Content-Security-Policy" => "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' blob:; media-src 'self' blob:; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'",
      "X-Content-Type-Options" => "nosniff",
      "X-Frame-Options" => "DENY",
      "Referrer-Policy" => "no-referrer",
      "Permissions-Policy" => "camera=(), microphone=(self), geolocation=(), payment=(), usb=()",
      "Connection" => "close"
    }.freeze

    AUTH_ROUTES = %w[/auth/v1/session /auth/v1/login /auth/v1/change-password /auth/v1/logout].freeze
    SESSION_COOKIE = "soul_session"

    attr_reader :csrf_token, :authentication

    def initialize(root:, facade:, bind_host:, port:, csrf_token: SecureRandom.hex(32), authentication: nil, public_origin: nil, music_jobs: nil, voice_transcription: nil, voice_synthesis: nil, voice_presence: nil, picture_understanding: nil, screen_capture: nil)
      @root = File.expand_path(root)
      @facade = facade
      @bind_host = bind_host
      @port = Integer(port)
      @csrf_token = csrf_token
      @authentication = authentication || DashboardAuthentication.new(root: @root)
      @public_origin = public_origin.to_s.empty? ? nil : normalize_public_origin(public_origin)
      @music_jobs = music_jobs
      @voice_transcription = voice_transcription
      @voice_synthesis = voice_synthesis
      @voice_presence = voice_presence
      @picture_understanding = picture_understanding
      @screen_capture = screen_capture
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

      return auth_session(normalized_headers) if target == "/auth/v1/session" && method == "GET"
      return auth_post(target, normalized_headers, body) if AUTH_ROUTES.include?(target) && method == "POST"
      return response(405, "Method Not Allowed", "Allow" => target == "/auth/v1/session" ? "GET" : "POST") if AUTH_ROUTES.include?(target)

      return api_call(normalized_headers, body) if target == "/api/v1/call" && method == "POST"
      return response(405, "Method Not Allowed", "Allow" => "POST") if target == "/api/v1/call"
      return chat_stream(normalized_headers, body) if target == "/api/v1/chat-stream" && method == "POST"
      return response(405, "Method Not Allowed", "Allow" => "POST") if target == "/api/v1/chat-stream"
      return music_stream(normalized_headers, body) if target == "/api/v1/music-stream" && method == "POST"
      return response(405, "Method Not Allowed", "Allow" => "POST") if target == "/api/v1/music-stream"
      return administration_stream(normalized_headers, body) if target == "/api/v1/administration-stream" && method == "POST"
      return response(405, "Method Not Allowed", "Allow" => "POST") if target == "/api/v1/administration-stream"
      return music_job_start(normalized_headers, body) if target == "/api/v1/music-job-stream" && method == "POST"
      return response(405, "Method Not Allowed", "Allow" => "POST") if target == "/api/v1/music-job-stream"
      return music_job_start(normalized_headers, body) if target == "/api/v1/bounded-job-stream" && method == "POST"
      return response(405, "Method Not Allowed", "Allow" => "POST") if target == "/api/v1/bounded-job-stream"
      return music_job_follow(normalized_headers, body) if target == "/api/v1/music-job-follow" && method == "POST"
      return response(405, "Method Not Allowed", "Allow" => "POST") if target == "/api/v1/music-job-follow"
      return music_job_follow(normalized_headers, body) if target == "/api/v1/bounded-job-follow" && method == "POST"
      return response(405, "Method Not Allowed", "Allow" => "POST") if target == "/api/v1/bounded-job-follow"
      return music_job_status(normalized_headers, body) if target == "/api/v1/music-job-status" && method == "POST"
      return response(405, "Method Not Allowed", "Allow" => "POST") if target == "/api/v1/music-job-status"
      return bounded_job_status(normalized_headers, body) if target == "/api/v1/bounded-job-status" && method == "POST"
      return response(405, "Method Not Allowed", "Allow" => "POST") if target == "/api/v1/bounded-job-status"
      return voice_status(normalized_headers) if target == "/api/v1/voice/status" && method == "GET"
      return response(405, "Method Not Allowed", "Allow" => "GET") if target == "/api/v1/voice/status"
      return voice_transcribe(normalized_headers, body) if target == "/api/v1/voice/transcribe" && method == "POST"
      return response(405, "Method Not Allowed", "Allow" => "POST") if target == "/api/v1/voice/transcribe"
      return voice_synthesis_status(normalized_headers) if target == "/api/v1/voice/synthesis/status" && method == "GET"
      return response(405, "Method Not Allowed", "Allow" => "GET") if target == "/api/v1/voice/synthesis/status"
      return voice_synthesize(normalized_headers, body) if target == "/api/v1/voice/synthesize" && method == "POST"
      return response(405, "Method Not Allowed", "Allow" => "POST") if target == "/api/v1/voice/synthesize"
      return voice_synthesize_stream(normalized_headers, body) if target == "/api/v1/voice/synthesize-stream" && method == "POST"
      return response(405, "Method Not Allowed", "Allow" => "POST") if target == "/api/v1/voice/synthesize-stream"
      return voice_presence_status(normalized_headers) if target == "/api/v1/voice/presence/status" && method == "GET"
      return response(405, "Method Not Allowed", "Allow" => "GET") if target == "/api/v1/voice/presence/status"
      return voice_presence_launch(normalized_headers, body) if target == "/api/v1/voice/presence/launch" && method == "POST"
      return response(405, "Method Not Allowed", "Allow" => "POST") if target == "/api/v1/voice/presence/launch"
      return picture_stream(normalized_headers, body) if target == "/api/v1/perception/picture-stream" && method == "POST"
      return response(405, "Method Not Allowed", "Allow" => "POST") if target == "/api/v1/perception/picture-stream"
      return screen_capture(normalized_headers, body) if target == "/api/v1/perception/screen-capture" && method == "POST"
      return response(405, "Method Not Allowed", "Allow" => "POST") if target == "/api/v1/perception/screen-capture"
      if (match = target.match(%r{\A/api/v1/perception/image/(chat_[A-Za-z0-9_.-]+)/([0-9a-f]{64})\.(png|jpg)\z}))
        return response(405, "Method Not Allowed", "Allow" => "GET") unless method == "GET"
        return perception_image(normalized_headers, *match.captures)
      end
      if (match = target.match(%r{\A/api/v1/music/audio/(music_[a-f0-9]{16})/(candidate_[a-f0-9]{16})/(mp3|flac)\z}))
        return response(405, "Method Not Allowed", "Allow" => "GET") unless method == "GET"
        return music_audio(normalized_headers, *match.captures)
      end
      if (match = target.match(%r{\A/api/v1/mix/audio/(mix_[a-f0-9]{16})/(mp3|flac)\z}))
        return response(405, "Method Not Allowed", "Allow" => "GET") unless method == "GET"
        return mix_audio(normalized_headers, *match.captures)
      end
      if (match = target.match(%r{\A/api/v1/music/visual/(music_[a-f0-9]{16})/(candidate_[a-f0-9]{16})/(visual_[a-f0-9]{16})/(base|loop|preview)\z}))
        return response(405, "Method Not Allowed", "Allow" => "GET") unless method == "GET"
        return music_visual(normalized_headers, *match.captures)
      end
      if (match = target.match(%r{\A/api/v1/visual/image/(visual_project_[a-f0-9]{16})/(visual_candidate_[a-f0-9]{16})\z}))
        return response(405, "Method Not Allowed", "Allow" => "GET") unless method == "GET"
        return visual_image(normalized_headers, *match.captures)
      end
      if (match = target.match(%r{\A/api/v1/visual/motion/(visual_project_[a-f0-9]{16})/(motion_candidate_[a-f0-9]{16})\z}))
        return response(405, "Method Not Allowed", "Allow" => "GET") unless method == "GET"
        return visual_motion(normalized_headers, *match.captures)
      end

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
      boundary_error = mutation_boundary_error(headers, body)
      return boundary_error if boundary_error

      session = @authentication.session(session_token(headers))
      return json_response(401, error_envelope("authentication_required", "dashboard login required")) unless session
      if session.fetch("password_change_required")
        return json_response(403, error_envelope("password_change_required", "replace the bootstrap password before using the dashboard"))
      end

      request = JSON.parse(body)
      envelope = @facade.call(request)
      json_response(200, envelope)
    end

    def chat_stream(headers, body)
      boundary_error = mutation_boundary_error(headers, body)
      return boundary_error if boundary_error

      session = @authentication.session(session_token(headers))
      return json_response(401, error_envelope("authentication_required", "dashboard login required")) unless session
      if session.fetch("password_change_required")
        return json_response(403, error_envelope("password_change_required", "replace the bootstrap password before using the dashboard"))
      end

      request = JSON.parse(body)
      unless request.is_a?(Hash) && request["operation"] == "chats.send"
        return json_response(422, error_envelope("invalid_stream_operation", "chat stream accepts chats.send only"))
      end

      stream = Enumerator.new do |output|
        progress = lambda do |event|
          output << JSON.generate({ "type" => "progress", "event" => event }) + "\n"
        end
        envelope = @facade.call(request, progress: progress)
        output << JSON.generate({ "type" => "result", "envelope" => envelope }) + "\n"
      rescue StandardError => error
        output << JSON.generate({ "type" => "result", "envelope" => error_envelope("stream_failure", "chat stream failed safely: #{error.class}") }) + "\n"
      end
      response(200, stream, "Content-Type" => "application/x-ndjson; charset=utf-8", "Cache-Control" => "no-store")
    end

    def music_stream(headers, body)
      boundary_error = mutation_boundary_error(headers, body)
      return boundary_error if boundary_error
      session = @authentication.session(session_token(headers))
      return json_response(401, error_envelope("authentication_required", "dashboard login required")) unless session
      return json_response(403, error_envelope("password_change_required", "replace the bootstrap password before using the dashboard")) if session.fetch("password_change_required")
      request = JSON.parse(body)
      allowed = %w[music.generation.execute music.candidates.analysis.execute music.candidates.revision.execute music.references.analysis.execute music.visuals.loop.execute music.visuals.final.execute youtube.upload.execute visual.generation.execute visual.edit.execute visual.motion.execute visual.native_motion.execute visual.native_motion.revision.execute]
      unless request.is_a?(Hash) && allowed.include?(request["operation"])
        return json_response(422, error_envelope("invalid_stream_operation", "music stream accepts bounded music, analysis, publication, or visual rendering only"))
      end
      stream = Enumerator.new do |output|
        progress = ->(event) { output << JSON.generate({ "type" => "progress", "event" => event }) + "\n" }
        envelope = @facade.call(request, progress: progress)
        output << JSON.generate({ "type" => "result", "envelope" => envelope }) + "\n"
      rescue StandardError => error
        output << JSON.generate({ "type" => "result", "envelope" => error_envelope("stream_failure", "music stream failed safely: #{error.class}") }) + "\n"
      end
      response(200, stream, "Content-Type" => "application/x-ndjson; charset=utf-8", "Cache-Control" => "no-store")
    end

    def administration_stream(headers, body)
      boundary_error = mutation_boundary_error(headers, body)
      return boundary_error if boundary_error
      session_error = authenticated_session_error(headers)
      return session_error if session_error
      request = JSON.parse(body)
      allowed = %w[
        backup.create.execute backup.retention.execute backup.restore.execute backup.replica.execute backup.drs.execute
        operator_backup.create.execute operator_backup.retention.execute operator_backup.restore.execute
        operator_backup.replica.execute operator_backup.drs.execute maintenance.device.execute
      ]
      unless request.is_a?(Hash) && allowed.include?(request["operation"])
        return json_response(422, error_envelope("invalid_stream_operation", "administration stream accepts bounded backup, recovery, and device-maintenance execution only"))
      end
      stream = Enumerator.new do |output|
        progress = ->(event) { output << JSON.generate({ "type" => "progress", "event" => event }) + "\n" }
        envelope = @facade.call(request, progress: progress)
        output << JSON.generate({ "type" => "result", "envelope" => envelope }) + "\n"
      rescue StandardError => error
        output << JSON.generate({ "type" => "result", "envelope" => error_envelope("stream_failure", "administration stream failed safely: #{error.class}") }) + "\n"
      end
      response(200, stream, "Content-Type" => "application/x-ndjson; charset=utf-8", "Cache-Control" => "no-store")
    end

    def music_job_start(headers, body)
      boundary_error = mutation_boundary_error(headers, body)
      return boundary_error if boundary_error
      session_error = authenticated_session_error(headers)
      return session_error if session_error
      request = JSON.parse(body)
      record = music_jobs.start(request)
      music_job_stream_response(record.fetch("job_id"))
    rescue ArgumentError => error
      json_response(422, error_envelope("music_job_rejected", error.message))
    end

    def music_job_follow(headers, body)
      boundary_error = mutation_boundary_error(headers, body)
      return boundary_error if boundary_error
      session_error = authenticated_session_error(headers)
      return session_error if session_error
      request = JSON.parse(body)
      music_job_stream_response(request.fetch("job_id"))
    rescue KeyError, ArgumentError => error
      json_response(422, error_envelope("music_job_rejected", error.message))
    end

    def music_job_status(headers, body)
      boundary_error = mutation_boundary_error(headers, body)
      return boundary_error if boundary_error
      session_error = authenticated_session_error(headers)
      return session_error if session_error
      request = JSON.parse(body)
      project_id = request["project_id"]
      return json_response(422, error_envelope("music_job_rejected", "project_id is invalid")) unless project_id.to_s.match?(/\Amusic_[a-f0-9]{16}\z/)
      json_response(200, { "jobs" => music_jobs.active(project_id: project_id) })
    end

    def bounded_job_status(headers, body)
      boundary_error = mutation_boundary_error(headers, body)
      return boundary_error if boundary_error
      session_error = authenticated_session_error(headers)
      return session_error if session_error
      request = JSON.parse(body)
      operations = Array(request["operations"])
      dev_operations = DashboardMusicJobManager::OPERATIONS.grep(/\Aself_(?:improvement|augmentation)\./)
      return json_response(422, error_envelope("bounded_job_rejected", "operations are invalid")) if operations.empty? || (operations - dev_operations).any?
      json_response(200, { "jobs" => music_jobs.active(operations: operations) })
    rescue JSON::ParserError
      json_response(422, error_envelope("bounded_job_rejected", "request is invalid"))
    end

    def music_job_stream_response(job_id)
      response(200, music_jobs.stream(job_id), "Content-Type" => "application/x-ndjson; charset=utf-8", "Cache-Control" => "no-store")
    end

    def authenticated_session_error(headers)
      session = @authentication.session(session_token(headers))
      return json_response(401, error_envelope("authentication_required", "dashboard login required")) unless session
      return json_response(403, error_envelope("password_change_required", "replace the bootstrap password before using the dashboard")) if session.fetch("password_change_required")
      nil
    end

    def music_jobs
      @music_jobs ||= DashboardMusicJobManager.new(root: @root, facade: @facade)
    end

    def voice_status(headers)
      session_error = authenticated_session_error(headers)
      return session_error if session_error

      json_response(200, voice_transcription.status)
    end

    def voice_transcribe(headers, body)
      boundary_error = binary_mutation_boundary_error(headers, body)
      return boundary_error if boundary_error
      session_error = authenticated_session_error(headers)
      return session_error if session_error

      json_response(200, voice_transcription.transcribe(audio_bytes: body, content_type: headers["content-type"]))
    end

    def voice_transcription
      @voice_transcription ||= VoiceTranscriptionService.new(root: @root)
    end

    def voice_synthesis_status(headers)
      session_error = authenticated_session_error(headers)
      return session_error if session_error

      json_response(200, voice_synthesis.status)
    end

    def voice_synthesize(headers, body)
      boundary_error = mutation_boundary_error(headers, body)
      return boundary_error if boundary_error
      session_error = authenticated_session_error(headers)
      return session_error if session_error

      request = JSON.parse(body)
      options = { text: request["text"], voice_name: request["voice"], quality: request["quality"] || "responsive" }
      options[:speech_context] = request["speech_context"] unless request["speech_context"].to_s.empty?
      result = voice_synthesis.synthesize(**options)
      unless result.fetch("ok")
        status = result.fetch("lifecycle_state") == "awaiting_input" ? 422 : 503
        return json_response(status, error_envelope("voice_synthesis", result.fetch("message")))
      end

      response(
        200,
        result.fetch("audio"),
        "Content-Type" => result.fetch("content_type"),
        "Content-Disposition" => "inline; filename=\"soul-voice.wav\"",
        "Cache-Control" => "private, no-store",
        "X-Soul-Voice" => result.fetch("voice")
      )
    end

    def voice_synthesize_stream(headers, body)
      boundary_error = mutation_boundary_error(headers, body)
      return boundary_error if boundary_error
      session_error = authenticated_session_error(headers)
      return session_error if session_error
      request = JSON.parse(body)

      stream = Enumerator.new do |output|
        progress = ->(event) { output << JSON.generate({ "type" => "progress", "event" => event }) + "\n" }
        options = {
          text: request["text"], voice_name: request["voice"],
          quality: request["quality"] || "expressive", on_progress: progress
        }
        options[:speech_context] = request["speech_context"] unless request["speech_context"].to_s.empty?
        result = voice_synthesis.synthesize(**options)
        payload = if result.fetch("ok")
          result.except("audio").merge("audio_base64" => Base64.strict_encode64(result.fetch("audio")))
        else
          result
        end
        output << JSON.generate({ "type" => "result", "result" => payload }) + "\n"
      rescue StandardError => error
        output << JSON.generate({ "type" => "result", "result" => { "ok" => false, "lifecycle_state" => "failed", "message" => "voice stream failed safely: #{error.class}" } }) + "\n"
      end
      response(200, stream, "Content-Type" => "application/x-ndjson; charset=utf-8", "Cache-Control" => "private, no-store")
    end

    def voice_synthesis
      @voice_synthesis ||= VoiceSynthesisService.new(root: @root)
    end

    def voice_presence_status(headers)
      session_error = authenticated_session_error(headers)
      return session_error if session_error

      json_response(200, voice_presence.status)
    end

    def voice_presence_launch(headers, body)
      boundary_error = mutation_boundary_error(headers, body)
      return boundary_error if boundary_error
      session_error = authenticated_session_error(headers)
      return session_error if session_error

      request = JSON.parse(body)
      return json_response(422, error_envelope("voice_presence", "action must be launch")) unless request["action"] == "launch"
      result = voice_presence.launch
      json_response(result["ok"] ? 200 : 503, result)
    end

    def voice_presence
      @voice_presence ||= VoicePresenceLaunchService.new(root: @root)
    end

    def picture_stream(headers, body)
      boundary_error = picture_mutation_boundary_error(headers, body)
      return boundary_error if boundary_error
      session_error = authenticated_session_error(headers)
      return session_error if session_error
      request = JSON.parse(body)

      stream = Enumerator.new do |output|
        progress = ->(event) { output << JSON.generate({ "type" => "progress", "event" => event }) + "\n" }
        result = picture_understanding.analyze(
          chat_id: request["chat_id"], question: request["question"],
          image_base64: request["image_base64"], media_type: request["media_type"],
          filename: request["filename"], retain: request["retain"] == true,
          request_id: request["request_id"], on_progress: progress
        )
        output << JSON.generate({ "type" => "result", "result" => result }) + "\n"
      rescue StandardError => error
        output << JSON.generate({ "type" => "result", "result" => { "ok" => false, "lifecycle_state" => "failed", "reason" => "picture stream failed safely: #{error.class}", "mutation" => "none" } }) + "\n"
      end
      response(200, stream, "Content-Type" => "application/x-ndjson; charset=utf-8", "Cache-Control" => "private, no-store")
    end

    def perception_image(headers, chat_id, digest, extension)
      session_error = authenticated_session_error(headers)
      return session_error if session_error

      path = picture_understanding.retained_artifact_path(chat_id: chat_id, digest: digest, extension: extension)
      response(
        200, File.binread(path),
        "Content-Type" => extension == "png" ? "image/png" : "image/jpeg",
        "Content-Disposition" => "inline; filename=\"#{digest}.#{extension}\"",
        "Cache-Control" => "private, no-store"
      )
    rescue Errno::ENOENT, ArgumentError
      response(404, "Not Found")
    end

    def picture_understanding
      @picture_understanding ||= PictureUnderstandingService.new(root: @root)
    end

    def screen_capture(headers, body)
      boundary_error = mutation_boundary_error(headers, body)
      return boundary_error if boundary_error
      session_error = authenticated_session_error(headers)
      return session_error if session_error

      request = JSON.parse(body)
      result = screen_capture_service.capture(mode: request["mode"])
      json_response(result["ok"] ? 200 : 422, result)
    rescue JSON::ParserError
      json_response(400, error_envelope("invalid_json", "screen capture request must be valid JSON"))
    end

    def screen_capture_service
      @screen_capture ||= ScreenCaptureService.new(root: @root)
    end

    def music_audio(headers, project_id, candidate_id, artifact)
      session = @authentication.session(session_token(headers))
      return json_response(401, error_envelope("authentication_required", "dashboard login required")) unless session
      return json_response(403, error_envelope("password_change_required", "replace the bootstrap password before using the dashboard")) if session.fetch("password_change_required")
      path = @facade.music_artifact_path(project_id: project_id, candidate_id: candidate_id, artifact: artifact)
      content_type = artifact == "mp3" ? "audio/mpeg" : "audio/flac"
      size = File.size(path)
      range = audio_range(headers["range"], size)
      return response(416, "Range Not Satisfiable", "Content-Range" => "bytes */#{size}") if headers["range"] && !range
      offset, length = range || [0, size]
      extra = { "Content-Type" => content_type, "Content-Length" => length.to_s, "Content-Disposition" => "inline; filename=\"#{File.basename(path)}\"", "Cache-Control" => "private, no-store", "Accept-Ranges" => "bytes" }
      extra["Content-Range"] = "bytes #{offset}-#{offset + length - 1}/#{size}" if range
      response(range ? 206 : 200, FileStream.new(path, offset: offset, length: length), extra)
    rescue MusicProjectStore::ValidationError, MusicProjectStore::IntegrityError
      response(404, "Not Found")
    end

    def mix_audio(headers, mix_id, artifact)
      session = @authentication.session(session_token(headers))
      return json_response(401, error_envelope("authentication_required", "dashboard login required")) unless session
      return json_response(403, error_envelope("password_change_required", "replace the bootstrap password before using the dashboard")) if session.fetch("password_change_required")
      path = @facade.mix_artifact_path(mix_id: mix_id, artifact: artifact)
      raise LongFormMixRenderService::ValidationError, "mix artifact path is unavailable" if path.to_s.empty?
      content_type = artifact == "mp3" ? "audio/mpeg" : "audio/flac"
      size = File.size(path)
      range = audio_range(headers["range"], size)
      return response(416, "Range Not Satisfiable", "Content-Range" => "bytes */#{size}") if headers["range"] && !range
      offset, length = range || [0, size]
      extra = { "Content-Type" => content_type, "Content-Length" => length.to_s, "Content-Disposition" => "inline; filename=\"#{File.basename(path)}\"", "Cache-Control" => "private, no-store", "Accept-Ranges" => "bytes" }
      extra["Content-Range"] = "bytes #{offset}-#{offset + length - 1}/#{size}" if range
      response(range ? 206 : 200, FileStream.new(path, offset: offset, length: length), extra)
    rescue LongFormMixRenderService::ValidationError, LongFormMixRenderService::IntegrityError, ArgumentError
      response(404, "Not Found")
    rescue Errno::ENOENT
      response(404, "Not Found")
    end

    def music_visual(headers, project_id, candidate_id, visual_id, artifact)
      session = @authentication.session(session_token(headers))
      return json_response(401, error_envelope("authentication_required", "dashboard login required")) unless session
      return json_response(403, error_envelope("password_change_required", "replace the bootstrap password before using the dashboard")) if session.fetch("password_change_required")
      path = @facade.music_visual_artifact_path(project_id: project_id, candidate_id: candidate_id, visual_id: visual_id, artifact: artifact)
      content_type = if artifact == "base"
        "image/png"
      elsif File.extname(path) == ".webm"
        "video/webm"
      else
        "video/mp4"
      end
      size = File.size(path)
      range = audio_range(headers["range"], size)
      return response(416, "Range Not Satisfiable", "Content-Range" => "bytes */#{size}") if headers["range"] && !range
      offset, length = range || [0, size]
      extra = { "Content-Type" => content_type, "Content-Length" => length.to_s, "Content-Disposition" => "inline; filename=\"#{File.basename(path)}\"", "Cache-Control" => "private, no-store", "Accept-Ranges" => "bytes" }
      extra["Content-Range"] = "bytes #{offset}-#{offset + length - 1}/#{size}" if range
      response(range ? 206 : 200, FileStream.new(path, offset: offset, length: length), extra)
    rescue MusicProjectStore::ValidationError, MusicProjectStore::IntegrityError
      response(404, "Not Found")
    end

    def visual_image(headers, project_id, candidate_id)
      session = @authentication.session(session_token(headers))
      return json_response(401, error_envelope("authentication_required", "dashboard login required")) unless session
      return json_response(403, error_envelope("password_change_required", "replace the bootstrap password before using the dashboard")) if session.fetch("password_change_required")
      path = @facade.visual_artifact_path(project_id: project_id, candidate_id: candidate_id)
      response(200, FileStream.new(path), "Content-Type" => "image/png", "Content-Length" => File.size(path).to_s, "Content-Disposition" => "inline; filename=\"#{File.basename(path)}\"", "Cache-Control" => "private, no-store")
    rescue ArgumentError
      response(404, "Not Found")
    end

    def visual_motion(headers, project_id, motion_id)
      session = @authentication.session(session_token(headers))
      return json_response(401, error_envelope("authentication_required", "dashboard login required")) unless session
      return json_response(403, error_envelope("password_change_required", "replace the bootstrap password before using the dashboard")) if session.fetch("password_change_required")
      path = @facade.visual_motion_artifact_path(project_id: project_id, motion_id: motion_id)
      size = File.size(path)
      range = audio_range(headers["range"], size)
      return response(416, "Range Not Satisfiable", "Content-Range" => "bytes */#{size}") if headers["range"] && !range
      offset, length = range || [0, size]
      extra = { "Content-Type" => "video/webm", "Content-Length" => length.to_s, "Content-Disposition" => "inline; filename=\"#{File.basename(path)}\"", "Cache-Control" => "private, no-store", "Accept-Ranges" => "bytes" }
      extra["Content-Range"] = "bytes #{offset}-#{offset + length - 1}/#{size}" if range
      response(range ? 206 : 200, FileStream.new(path, offset: offset, length: length), extra)
    rescue ArgumentError
      response(404, "Not Found")
    end

    class FileStream
      def initialize(path, offset: 0, length: File.size(path)) = (@path, @offset, @length = path, offset, length)
      def each
        File.open(@path, "rb") do |file|
          file.seek(@offset)
          remaining = @length
          while remaining.positive?
            chunk = file.read([64 * 1024, remaining].min)
            break unless chunk
            remaining -= chunk.bytesize
            yield chunk
          end
        end
      end
    end

    def audio_range(header, size)
      return nil if header.to_s.empty?
      match = header.match(/\Abytes=(\d*)-(\d*)\z/)
      return nil unless match && (!match[1].empty? || !match[2].empty?)
      if match[1].empty?
        length = [Integer(match[2]), size].min
        return nil unless length.positive?
        [size - length, length]
      else
        first = Integer(match[1]); last = match[2].empty? ? size - 1 : [Integer(match[2]), size - 1].min
        return nil if first >= size || last < first
        [first, last - first + 1]
      end
    rescue ArgumentError
      nil
    end

    def auth_session(headers)
      session = @authentication.session(session_token(headers))
      json_response(200, auth_payload(session || { "authenticated" => false, "password_change_required" => false }))
    end

    def auth_post(target, headers, body)
      boundary_error = mutation_boundary_error(headers, body)
      return boundary_error if boundary_error

      request = JSON.parse(body)
      return json_response(400, auth_error("invalid_request", "request body must be a JSON object")) unless request.is_a?(Hash)

      case target
      when "/auth/v1/login"
        login(headers, request)
      when "/auth/v1/change-password"
        change_password(headers, request)
      when "/auth/v1/logout"
        logout(headers)
      end
    end

    def login(headers, request)
      result = @authentication.authenticate(username: request["username"], password: request["password"])
      return auth_failure(result) unless result.ok

      json_response(200, auth_payload(result.session), "Set-Cookie" => session_cookie(result.token, secure: secure_request?(headers)))
    end

    def change_password(headers, request)
      result = @authentication.change_password(
        token: session_token(headers),
        current_password: request["current_password"],
        new_password: request["new_password"],
        confirmation: request["confirmation"]
      )
      return auth_failure(result) unless result.ok

      json_response(200, auth_payload(result.session), "Set-Cookie" => session_cookie(result.token, secure: secure_request?(headers)))
    end

    def logout(headers)
      @authentication.logout(session_token(headers))
      json_response(200, auth_payload({ "authenticated" => false, "password_change_required" => false }), "Set-Cookie" => expired_session_cookie(secure: secure_request?(headers)))
    end

    def auth_failure(result)
      headers = result.retry_after ? { "Retry-After" => result.retry_after.to_s } : {}
      json_response(result.status, auth_error(result.code, result.reason), headers)
    end

    def mutation_boundary_error(headers, body)
      return json_response(415, auth_error("content_type", "Content-Type must be application/json")) unless headers["content-type"].to_s.split(";", 2).first.strip.downcase == "application/json"
      return json_response(403, auth_error("origin", "same-origin request required")) unless valid_origin?(headers["origin"])
      return json_response(403, auth_error("csrf", "valid CSRF token required")) unless secure_compare(headers["x-soul-csrf"], @csrf_token)
      return json_response(413, auth_error("body_too_large", "request body exceeds 128 KiB")) if body.bytesize > 128 * 1024

      nil
    end

    def binary_mutation_boundary_error(headers, body)
      media_type = headers["content-type"].to_s.split(";", 2).first.strip.downcase
      unless VoiceTranscriptionService::CONTENT_TYPES.key?(media_type)
        return json_response(415, auth_error("content_type", "Content-Type must be a supported audio recording"))
      end
      return json_response(403, auth_error("origin", "same-origin request required")) unless valid_origin?(headers["origin"])
      return json_response(403, auth_error("csrf", "valid CSRF token required")) unless secure_compare(headers["x-soul-csrf"], @csrf_token)
      if body.bytesize > VoiceTranscriptionService::MAX_UPLOAD_BYTES
        return json_response(413, auth_error("body_too_large", "recording exceeds the bounded upload limit"))
      end

      nil
    end

    def picture_mutation_boundary_error(headers, body)
      return json_response(415, auth_error("content_type", "Content-Type must be application/json")) unless headers["content-type"].to_s.split(";", 2).first.strip.downcase == "application/json"
      return json_response(403, auth_error("origin", "same-origin request required")) unless valid_origin?(headers["origin"])
      return json_response(403, auth_error("csrf", "valid CSRF token required")) unless secure_compare(headers["x-soul-csrf"], @csrf_token)
      return json_response(413, auth_error("body_too_large", "picture request exceeds the bounded upload limit")) if body.bytesize > PictureUnderstandingService::MAX_REQUEST_BODY_BYTES

      nil
    end

    def valid_host?(host)
      allowed_authorities.include?(host.to_s.downcase)
    end

    def valid_origin?(origin)
      allowed_origins.include?(origin.to_s.downcase)
    end

    def allowed_authorities
      @allowed_authorities ||= begin
        hosts = [@bind_host, "127.0.0.1", "localhost", "[::1]"]
        authorities = hosts.map { |host| "#{host}:#{@port}" }
        authorities << public_authority if @public_origin
        authorities.uniq.freeze
      end
    end

    def allowed_origins
      @allowed_origins ||= begin
        origins = [@bind_host, "127.0.0.1", "localhost", "[::1]"].map { |host| "http://#{host}:#{@port}" }
        origins << @public_origin if @public_origin
        origins.map(&:downcase).uniq.freeze
      end
    end

    def normalize_public_origin(value)
      uri = URI.parse(value.to_s)
      valid_path = uri.path.to_s.empty? || uri.path == "/"
      raise ArgumentError, "dashboard public origin must be exact HTTPS" unless uri.scheme == "https" && !uri.host.to_s.empty? && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? && valid_path
      host = uri.host.include?(":") ? "[#{uri.host}]" : uri.host
      "https://#{host}#{uri.port == 443 ? '' : ":#{uri.port}"}".downcase
    rescue URI::InvalidURIError
      raise ArgumentError, "dashboard public origin must be exact HTTPS"
    end

    def public_authority
      @public_origin.delete_prefix("https://")
    end

    def secure_request?(headers)
      @public_origin && headers["origin"].to_s.downcase == @public_origin && headers["host"].to_s.downcase == public_authority
    end

    def secure_compare(left, right)
      return false unless left.is_a?(String) && left.bytesize == right.bytesize

      left.bytes.zip(right.bytes).reduce(0) { |memo, (a, b)| memo | (a ^ b) }.zero?
    end

    def session_token(headers)
      values = headers["cookie"].to_s.split(";").filter_map do |part|
        key, value = part.strip.split("=", 2)
        value if key == SESSION_COOKIE
      end
      values.length == 1 ? values.first : nil
    end

    def session_cookie(token, secure:)
      attributes = ["#{SESSION_COOKIE}=#{token}", "Path=/", "Max-Age=#{DashboardAuthentication::SESSION_ABSOLUTE_SECONDS}", "HttpOnly", "SameSite=Strict"]
      attributes << "Secure" if secure
      attributes.join("; ")
    end

    def expired_session_cookie(secure:)
      attributes = ["#{SESSION_COOKIE}=", "Path=/", "Max-Age=0", "HttpOnly", "SameSite=Strict"]
      attributes << "Secure" if secure
      attributes.join("; ")
    end

    def json_response(status, value, extra_headers = {})
      response(status, JSON.generate(value), { "Content-Type" => "application/json; charset=utf-8", "Cache-Control" => "no-store" }.merge(extra_headers))
    end

    def auth_payload(session)
      {
        "schema_version" => "soul.dashboard.auth.v1",
        "ok" => true,
        "authenticated" => session.fetch("authenticated"),
        "username" => session["username"],
        "password_change_required" => session.fetch("password_change_required")
      }
    end

    def auth_error(code, reason)
      {
        "schema_version" => "soul.dashboard.auth.v1",
        "ok" => false,
        "error" => { "code" => code, "reason" => reason }
      }
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
