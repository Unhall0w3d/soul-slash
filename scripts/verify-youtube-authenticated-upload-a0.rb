#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "socket"
require "tmpdir"
require "time"
require "uri"
require_relative "../lib/soul_core/music_publication_package_service"
require_relative "../lib/soul_core/youtube_authenticated_upload_service"

Result = Struct.new(:ok) do
  def success? = ok
end

HttpResponseFixture = Struct.new(:code, :body, :headers) do
  def to_hash = headers || {}
end

class OAuthApiFixture
  attr_reader :calls
  attr_accessor :reject_refresh

  def initialize(channel_id: SoulCore::YouTubeOAuthService::EXPECTED_CHANNEL_ID)
    @channel_id = channel_id
    @calls = []
    @reject_refresh = false
  end

  def exchange_code(**arguments)
    @calls << ["exchange_code", arguments.keys.sort]
    {
      "access_token" => "ya29.fixture-access-never-output",
      "refresh_token" => "1//fixture-refresh-never-output",
      "scope" => SoulCore::YouTubeOAuthService::SCOPES.join(" ")
    }
  end

  def refresh_access_token(**arguments)
    @calls << ["refresh_access_token", arguments.keys.sort]
    if @reject_refresh
      raise SoulCore::YouTubeApiClient::ApiError.new(
        "YouTube API returned HTTP 400: invalid_grant", status: 400
      )
    end
    { "access_token" => "ya29.fixture-refreshed-never-output" }
  end

  def channel(access_token:)
    @calls << ["channel", !access_token.to_s.empty?]
    { "id" => @channel_id, "title" => "Soul Slash Synthesis" }
  end
end

class OAuthCallbackRunner
  def initialize(state: :valid, probe_first: false)
    @state = state
    @probe_first = probe_first
  end

  def run(*command, **_options)
    uri = URI.parse(command.last)
    query = URI.decode_www_form(uri.query).to_h
    unless @state == :none
      callback = URI.parse(query.fetch("redirect_uri"))
      state = @state == :valid ? query.fetch("state") : "wrong-state"
      Thread.new do
        if @probe_first
          probe = TCPSocket.new(callback.host, callback.port)
          probe.close
        end
        socket = TCPSocket.new(callback.host, callback.port)
        target = "#{callback.path}?#{URI.encode_www_form("state" => state, "code" => "fixture-code")}"
        socket.write("GET #{target} HTTP/1.1\r\nHost: #{callback.host}\r\nConnection: close\r\n\r\n")
        socket.read
        socket.close
      end
    end
    Result.new(true)
  end
end

class PackageVisualFixture
  def initialize(record, base, preview)
    @record = record
    @paths = { "base" => base, "preview" => preview }
  end

  def inventory(project_id:, candidate_id:)
    @record.values_at("project_id", "candidate_id") == [project_id, candidate_id] ? [@record] : []
  end

  def artifact_path(project_id:, candidate_id:, visual_id:, artifact:)
    raise "identity mismatch" unless @record.values_at("project_id", "candidate_id", "visual_id") == [project_id, candidate_id, visual_id]
    @paths.fetch(artifact)
  end
end

class UploadOAuthFixture
  def initialize(channel_id: SoulCore::YouTubeOAuthService::EXPECTED_CHANNEL_ID)
    @channel_id = channel_id
  end

  def access_context
    {
      "access_token" => "ya29.upload-fixture-never-output",
      "channel_id" => @channel_id,
      "channel_title" => "Soul Slash Synthesis",
      "project_id" => SoulCore::YouTubeOAuthService::PROJECT_ID
    }
  end
end

class UploadApiFixture
  attr_reader :calls
  attr_accessor :thumbnail_failure, :thumbnail_interrupt, :actual_privacy

  def initialize
    @calls = []
    @thumbnail_failure = false
    @thumbnail_interrupt = false
    @actual_privacy = "private"
  end

  def initiate_upload(**arguments)
    @calls << ["initiate", arguments.reject { |key, _| key == :access_token }]
    "https://upload.youtube.test/session/fixture"
  end

  def upload_video(**arguments)
    @calls << ["upload", arguments.reject { |key, _| key == :access_token || key == :progress }]
    {
      "id" => "SoulA0video1",
      "snippet" => { "channelId" => SoulCore::YouTubeOAuthService::EXPECTED_CHANNEL_ID },
      "status" => { "privacyStatus" => @actual_privacy }
    }
  end

  def set_thumbnail(**arguments)
    @calls << ["thumbnail", arguments.reject { |key, _| key == :access_token }]
    raise Interrupt if @thumbnail_interrupt
    raise SoulCore::YouTubeApiClient::ApiError, "fixture thumbnail failure" if @thumbnail_failure
    { "items" => [] }
  end
end

failures = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'FAILED'}"
  failures << label unless condition
end

Dir.mktmpdir("soul-youtube-a0-") do |root|
  client_path = File.join(root, "desktop-client.json")
  client_secret = "fixture-client-secret-never-output"
  File.write(client_path, JSON.generate(
    "installed" => {
      "client_id" => "fixture.apps.googleusercontent.com",
      "project_id" => SoulCore::YouTubeOAuthService::PROJECT_ID,
      "auth_uri" => "https://accounts.google.com/o/oauth2/auth",
      "token_uri" => "https://oauth2.googleapis.com/token",
      "client_secret" => client_secret,
      "redirect_uris" => ["http://localhost"]
    }
  ), mode: "wx", perm: 0o600)

  oauth_api = OAuthApiFixture.new
  oauth = SoulCore::YouTubeOAuthService.new(
    root: root, api: oauth_api, runner: OAuthCallbackRunner.new,
    clock: -> { Time.utc(2026, 7, 27, 20) }, callback_timeout: 1
  )
  auth_preview = oauth.preview(client_path: client_path)
  wrong_auth = oauth.execute(
    client_path: client_path, confirmation: "WRONG",
    expected_digest: auth_preview.dig("data", "expected_digest")
  )
  credential_path = File.join(root, "Soul", "runtime", "youtube_auth", "oauth.json")
  check.call("wrong authorization gate writes no credential", wrong_auth["lifecycle_state"] == "blocked_for_human_review" && !File.exist?(credential_path))

  authorized = oauth.execute(
    client_path: client_path, confirmation: "AUTHORIZE_YOUTUBE",
    expected_digest: auth_preview.dig("data", "expected_digest")
  )
  serialized_authorized = JSON.generate(authorized)
  check.call("valid callback stores owner-only OAuth for exact channel",
             authorized["lifecycle_state"] == "complete" &&
             File.file?(credential_path) &&
             (File.stat(credential_path).mode & 0o077).zero? &&
             authorized.dig("data", "channel_id") == SoulCore::YouTubeOAuthService::EXPECTED_CHANNEL_ID)
  check.call("OAuth result exposes no client or token secret",
             !serialized_authorized.include?(client_secret) &&
             !serialized_authorized.include?("fixture-access") &&
             !serialized_authorized.include?("fixture-refresh"))
  access = oauth.access_context
  check.call("stored credential refresh re-verifies channel without returning refresh material",
             access["channel_id"] == SoulCore::YouTubeOAuthService::EXPECTED_CHANNEL_ID &&
             !JSON.generate(access.reject { |key, _| key == "access_token" }).include?("fixture-refresh"))
  oauth_api.reject_refresh = true
  rejected_refresh = begin
    oauth.access_context
    nil
  rescue SoulCore::YouTubeOAuthService::CredentialError => error
    error
  end
  check.call("rejected stored authorization gives bounded reauthorization guidance",
             rejected_refresh&.message&.include?("authorize YouTube again") &&
             rejected_refresh.message.include?("Testing") &&
             !rejected_refresh.message.include?("invalid_grant"))
  oauth_api.reject_refresh = false

  probe_root = File.join(root, "probe-first")
  probe_oauth = SoulCore::YouTubeOAuthService.new(
    root: probe_root, api: OAuthApiFixture.new, runner: OAuthCallbackRunner.new(probe_first: true),
    callback_timeout: 1
  )
  probe_preview = probe_oauth.preview(client_path: client_path)
  probe_result = probe_oauth.execute(
    client_path: client_path, confirmation: "AUTHORIZE_YOUTUBE",
    expected_digest: probe_preview.dig("data", "expected_digest")
  )
  check.call("empty browser preconnect cannot consume the real OAuth callback",
             probe_result["lifecycle_state"] == "complete" &&
             File.file?(File.join(probe_root, "Soul", "runtime", "youtube_auth", "oauth.json")))

  wrong_state_root = File.join(root, "wrong-state")
  wrong_state = SoulCore::YouTubeOAuthService.new(
    root: wrong_state_root, api: OAuthApiFixture.new, runner: OAuthCallbackRunner.new(state: :wrong),
    callback_timeout: 1
  )
  wrong_state_preview = wrong_state.preview(client_path: client_path)
  wrong_state_result = wrong_state.execute(
    client_path: client_path, confirmation: "AUTHORIZE_YOUTUBE",
    expected_digest: wrong_state_preview.dig("data", "expected_digest")
  )
  check.call("wrong OAuth callback state terminates without credentials",
             wrong_state_result["lifecycle_state"] == "blocked_for_human_review" &&
             !File.exist?(File.join(wrong_state_root, "Soul", "runtime", "youtube_auth", "oauth.json")))

  timeout_root = File.join(root, "timeout")
  timeout_oauth = SoulCore::YouTubeOAuthService.new(
    root: timeout_root, api: OAuthApiFixture.new, runner: OAuthCallbackRunner.new(state: :none),
    callback_timeout: 0.01
  )
  timeout_preview = timeout_oauth.preview(client_path: client_path)
  timeout_result = timeout_oauth.execute(
    client_path: client_path, confirmation: "AUTHORIZE_YOUTUBE",
    expected_digest: timeout_preview.dig("data", "expected_digest")
  )
  check.call("OAuth callback timeout terminates without credentials",
             timeout_result["lifecycle_state"] == "blocked_for_human_review" &&
             !File.exist?(File.join(timeout_root, "Soul", "runtime", "youtube_auth", "oauth.json")))

  export_root = File.join(root, "Music", "soul-music")
  store = SoulCore::MusicProjectStore.new(root: root, id_generator: -> { "1" * 16 }, clock: -> { Time.utc(2026, 7, 27, 20, 1) })
  project = store.create(
    "title" => "Bounded Upload Fixture", "intent" => "Verify one exact private draft.", "target_duration_seconds" => 180,
    "vocal_mode" => "instrumental", "rights_status" => "original", "caption" => "Nocturnal liquid drum and bass with measured synthetic texture.",
    "lyrics" => "", "bpm" => 172, "keyscale" => "F minor", "timesignature" => "4", "language" => "en", "seed" => 27
  )
  project_id = project.fetch("project_id")
  candidate_id = "candidate_#{'2' * 16}"
  candidate_dir = File.join(store.generations_path(project_id), candidate_id)
  Dir.mkdir(candidate_dir, 0o700)
  File.write(File.join(candidate_dir, "input.json"), JSON.generate(store.input_payload(project)))
  destination = File.join(export_root, "bounded-upload-fixture")
  FileUtils.mkdir_p(destination)
  %w[master.flac listening.mp3 song.json song-info.md].each { |name| File.binwrite(File.join(destination, name), "fixture #{name}") }
  File.write(File.join(store.project_path(project_id), "exports", "#{candidate_id}.json"), JSON.generate(
    "schema_version" => "soul.music.finished_export.v1", "project_id" => project_id,
    "candidate_id" => candidate_id, "destination" => destination, "scope_digest" => "a" * 64
  ))
  visual_id = "visual_#{'3' * 16}"
  base = File.join(root, "base.png")
  video = File.join(root, "preview.mp4")
  File.binwrite(base, "png fixture")
  File.binwrite(video, "mp4 fixture")
  visual = {
    "project_id" => project_id, "candidate_id" => candidate_id, "visual_id" => visual_id, "stage" => "preview_ready",
    "artifacts" => {
      "base" => { "sha256" => Digest::SHA256.file(base).hexdigest },
      "preview" => { "sha256" => Digest::SHA256.file(video).hexdigest }
    }
  }
  package_service = SoulCore::MusicPublicationPackageService.new(
    root: root, export_root: export_root, project_store: store,
    visual_service: PackageVisualFixture.new(visual, base, video),
    clock: -> { Time.utc(2026, 7, 27, 20, 2) }
  )
  description = package_service.draft(project_id: project_id, candidate_id: candidate_id, visual_id: visual_id).dig("data", "description")
  package_preview = package_service.preview(project_id: project_id, candidate_id: candidate_id, visual_id: visual_id, description: description)
  package_service.execute(
    project_id: project_id, candidate_id: candidate_id, visual_id: visual_id, description: description,
    confirmation: "EXPORT_YOUTUBE_PACKAGE", expected_digest: package_preview.dig("data", "expected_digest")
  )

  upload_api = UploadApiFixture.new
  uploader = SoulCore::YouTubeAuthenticatedUploadService.new(
    root: root, export_root: export_root, project_store: store,
    oauth: UploadOAuthFixture.new, api: upload_api,
    clock: -> { Time.utc(2026, 7, 27, 20, 3) }
  )
  preview = uploader.preview(project_id: project_id, candidate_id: candidate_id, visual_id: visual_id)
  check.call("upload preview defaults private and binds exact package and channel",
             preview["lifecycle_state"] == "blocked_for_human_review" &&
             preview.dig("data", "preview_scope", "visibility") == "private" &&
             preview.dig("data", "preview_scope", "channel_id") == SoulCore::YouTubeOAuthService::EXPECTED_CHANNEL_ID &&
             preview.dig("data", "preview_scope", "file_sha256").keys.sort == SoulCore::YouTubeAuthenticatedUploadService::REQUIRED_FILES.sort)
  wrong_upload = uploader.execute(
    project_id: project_id, candidate_id: candidate_id, visual_id: visual_id,
    confirmation: "WRONG", expected_digest: preview.dig("data", "expected_digest")
  )
  check.call("wrong upload gate performs no API mutation", wrong_upload["lifecycle_state"] == "blocked_for_human_review" && upload_api.calls.empty?)

  complete = uploader.execute(
    project_id: project_id, candidate_id: candidate_id, visual_id: visual_id,
    confirmation: "UPLOAD_YOUTUBE_VIDEO", expected_digest: preview.dig("data", "expected_digest")
  )
  output = JSON.generate(complete)
  check.call("exact upload calls video then thumbnail and records returned private draft",
             complete["lifecycle_state"] == "complete" &&
             upload_api.calls.map(&:first) == %w[initiate upload thumbnail] &&
             complete.dig("data", "upload", "video_id") == "SoulA0video1" &&
             complete.dig("data", "upload", "actual_privacy") == "private")
  check.call("upload result and receipt contain no OAuth tokens",
             !output.include?("ya29.") &&
             !File.binread(File.join(store.project_path(project_id), "publications", "#{candidate_id}-#{visual_id}-youtube-upload.json")).include?("ya29."))
  replay = uploader.preview(project_id: project_id, candidate_id: candidate_id, visual_id: visual_id)
  check.call("successful receipt replay is idempotent without another API call",
             replay.dig("data", "idempotent_replay") == true && upload_api.calls.length == 3)

  partial_visual_id = "visual_#{'4' * 16}"
  package_dir = File.join(destination, "youtube")
  original_receipt = JSON.parse(File.binread(File.join(store.project_path(project_id), "publications", "#{candidate_id}-#{visual_id}.json")))
  partial_receipt = original_receipt.merge("visual_id" => partial_visual_id)
  File.write(File.join(store.project_path(project_id), "publications", "#{candidate_id}-#{partial_visual_id}.json"), JSON.generate(partial_receipt))
  upload_api.thumbnail_failure = true
  partial_preview = uploader.preview(project_id: project_id, candidate_id: candidate_id, visual_id: partial_visual_id)
  partial = uploader.execute(
    project_id: project_id, candidate_id: candidate_id, visual_id: partial_visual_id,
    confirmation: "UPLOAD_YOUTUBE_VIDEO", expected_digest: partial_preview.dig("data", "expected_digest")
  )
  check.call("thumbnail failure records partial remote video and blocks blind retry",
             partial["lifecycle_state"] == "blocked_for_human_review" &&
             partial.dig("data", "upload", "state") == "partial" &&
             partial.dig("data", "upload", "thumbnail_applied") == false)

  canceled_visual_id = "visual_#{'5' * 16}"
  canceled_receipt = original_receipt.merge("visual_id" => canceled_visual_id)
  File.write(File.join(store.project_path(project_id), "publications", "#{candidate_id}-#{canceled_visual_id}.json"), JSON.generate(canceled_receipt))
  canceled_api = UploadApiFixture.new
  canceled_api.thumbnail_interrupt = true
  canceled_uploader = SoulCore::YouTubeAuthenticatedUploadService.new(
    root: root, export_root: export_root, project_store: store,
    oauth: UploadOAuthFixture.new, api: canceled_api,
    clock: -> { Time.utc(2026, 7, 27, 20, 4) }
  )
  canceled_preview = canceled_uploader.preview(project_id: project_id, candidate_id: candidate_id, visual_id: canceled_visual_id)
  canceled = canceled_uploader.execute(
    project_id: project_id, candidate_id: candidate_id, visual_id: canceled_visual_id,
    confirmation: "UPLOAD_YOUTUBE_VIDEO", expected_digest: canceled_preview.dig("data", "expected_digest")
  )
  check.call("cancellation after remote creation records the video and terminates",
             canceled["lifecycle_state"] == "canceled" &&
             canceled.dig("data", "upload", "state") == "canceled" &&
             canceled.dig("data", "upload", "video_id") == "SoulA0video1")

  changed = File.join(package_dir, "youtube-description.txt")
  File.open(changed, "a") { |file| file.write("changed") }
  changed_result = uploader.preview(project_id: project_id, candidate_id: candidate_id, visual_id: "visual_#{'6' * 16}")
  check.call("changed or unreceipted package cannot reach the API",
             changed_result["ok"] == false && changed_result["lifecycle_state"] != "complete")
end

retry_calls = 0
retry_sleeps = []
retry_responses = [
  HttpResponseFixture.new("503", JSON.generate("error" => { "message" => "temporary" }), {}),
  HttpResponseFixture.new("500", JSON.generate("error" => { "message" => "temporary" }), {}),
  HttpResponseFixture.new("200", JSON.generate("access_token" => "ya29.retry-fixture"), {})
]
retry_client = SoulCore::YouTubeApiClient.new(
  sleeper: ->(seconds) { retry_sleeps << seconds },
  http_adapter: lambda do |_uri, _request, timeout|
    retry_calls += 1
    raise "timeout is not bounded" unless timeout == SoulCore::YouTubeApiClient::TOKEN_TIMEOUT
    retry_responses.shift
  end
)
retry_token = retry_client.refresh_access_token(
  token_uri: "https://oauth2.googleapis.com/token",
  client_id: "fixture",
  client_secret: "fixture",
  refresh_token: "fixture"
)
check.call("transient API failures retry only to the fixed attempt bound",
           retry_token["access_token"] == "ya29.retry-fixture" &&
           retry_calls == SoulCore::YouTubeApiClient::MAX_ATTEMPTS &&
           retry_sleeps == [1, 2])

string_error_client = SoulCore::YouTubeApiClient.new(
  http_adapter: ->(_uri, _request, _timeout) { HttpResponseFixture.new("400", JSON.generate("invalid_grant"), {}) }
)
string_error = begin
  string_error_client.refresh_access_token(
    token_uri: "https://oauth2.googleapis.com/token",
    client_id: "fixture",
    client_secret: "fixture",
    refresh_token: "fixture"
  )
  nil
rescue SoulCore::YouTubeApiClient::ApiError => error
  error
end
check.call("scalar JSON API failures remain bounded actionable errors",
           string_error&.message&.include?("HTTP 400: invalid_grant") && string_error.reason.nil?)

Dir.mktmpdir("soul-youtube-chunks-") do |root|
  video_path = File.join(root, "video.mp4")
  File.binwrite(video_path, "v" * (SoulCore::YouTubeApiClient::UPLOAD_CHUNK_BYTES + 3))
  ranges = []
  chunk_responses = [
    HttpResponseFixture.new("308", "", { "range" => ["bytes=0-#{SoulCore::YouTubeApiClient::UPLOAD_CHUNK_BYTES - 1}"] }),
    HttpResponseFixture.new("200", JSON.generate(
      "id" => "SoulA0chunks",
      "snippet" => { "channelId" => SoulCore::YouTubeOAuthService::EXPECTED_CHANNEL_ID },
      "status" => { "privacyStatus" => "private" }
    ), {})
  ]
  chunk_client = SoulCore::YouTubeApiClient.new(
    sleeper: ->(_seconds) {},
    http_adapter: lambda do |_uri, request, _timeout|
      ranges << [request["Content-Range"], request.body.bytesize]
      chunk_responses.shift
    end
  )
  progress_events = []
  chunk_video = chunk_client.upload_video(
    access_token: "ya29.chunk-fixture", upload_url: "https://upload.youtube.test/session",
    path: video_path, mime_type: "video/mp4",
    progress: ->(event) { progress_events << event }
  )
  check.call("resumable upload sends bounded acknowledged chunks",
             chunk_video["id"] == "SoulA0chunks" &&
             ranges == [
               ["bytes 0-#{SoulCore::YouTubeApiClient::UPLOAD_CHUNK_BYTES - 1}/#{SoulCore::YouTubeApiClient::UPLOAD_CHUNK_BYTES + 3}", SoulCore::YouTubeApiClient::UPLOAD_CHUNK_BYTES],
               ["bytes #{SoulCore::YouTubeApiClient::UPLOAD_CHUNK_BYTES}-#{SoulCore::YouTubeApiClient::UPLOAD_CHUNK_BYTES + 2}/#{SoulCore::YouTubeApiClient::UPLOAD_CHUNK_BYTES + 3}", 3]
             ])
  check.call("resumable upload emits one dashboard-compatible event per chunk",
             progress_events.length == 2 &&
             progress_events.all? { |event| event.is_a?(Hash) && event["stage"] == "upload_chunk" && event["message"].to_s.include?("Uploading bytes") } &&
             progress_events.map { |event| event["offset"] } == [0, SoulCore::YouTubeApiClient::UPLOAD_CHUNK_BYTES] &&
             progress_events.all? { |event| event["total"] == SoulCore::YouTubeApiClient::UPLOAD_CHUNK_BYTES + 3 })
end

source = File.binread(File.expand_path("../lib/soul_core/youtube_api_client.rb", __dir__))
brief = File.binread(File.expand_path("../docs/soul/YOUTUBE_AUTHENTICATED_UPLOAD_A0_BRIEF.md", __dir__))
check.call("live transport is bounded and brief forbids background publication",
           source.include?("MAX_ATTEMPTS = 3") &&
           source.include?("open_timeout") &&
           source.include?("read_timeout") &&
           source.include?("notifySubscribers=false") &&
           brief.include?("No daemon, watcher, scheduled task") &&
           brief.match?(/Soul never chooses\s+to publish/))

abort "authenticated YouTube upload A0 verification failed: #{failures.join(', ')}" unless failures.empty?
puts "Authenticated YouTube upload A0 deterministic verification passed."
