#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"
require "fileutils"

require_relative "../lib/soul_core/application_contract"
require_relative "../lib/soul_core/application_facade"

ROOT = File.expand_path("..", __dir__)

def check(label, condition, failures)
  puts "- #{label}: #{condition ? "ok" : "FAILED"}"
  failures << label unless condition
end

def read_text_file(path)
  File.read(path, encoding: "UTF-8")
rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
  File.binread(path).encode("UTF-8", invalid: :replace, undef: :replace)
end

def request_payload_factory
  counter = 0
  lambda do |operation, parameters = {}|
    counter += 1
    {
      "schema_version" => SoulCore::ApplicationContract::SCHEMA_VERSION,
      "request_id" => "youtube-dashboard-a1-#{counter.to_s.rjust(8, "0")}",
      "operation" => operation,
      "parameters" => parameters,
      "context" => { "interface" => "internal" }
    }
  end
end

class DashboardVerifierOAuthFixture
  attr_reader :calls

  def initialize
    @calls = []
  end

  def status
    @calls << ["status"]
    {
      "ok" => true, "lifecycle_state" => "complete", "data" => {
        "configured" => false,
        "project_id" => SoulCore::YouTubeOAuthService::PROJECT_ID,
        "expected_channel_id" => SoulCore::YouTubeOAuthService::EXPECTED_CHANNEL_ID
      }
    }
  end

  def preview(client_path:)
    @calls << ["preview", client_path]
    {
      "ok" => true, "lifecycle_state" => "awaiting_input", "data" => {
        "confirmation_phrase" => SoulCore::YouTubeOAuthService::CONFIRMATION,
        "expected_digest" => "a" * 64,
        "preview_scope" => { "client_path" => client_path }
      }
    }
  end

  def execute(client_path:, confirmation:, expected_digest:)
    @calls << ["execute", client_path, confirmation, expected_digest]
    {
      "ok" => true,
      "lifecycle_state" => "complete",
      "data" => {
        "configured" => true,
        "project_id" => SoulCore::YouTubeOAuthService::PROJECT_ID,
        "channel_id" => SoulCore::YouTubeOAuthService::EXPECTED_CHANNEL_ID,
        "channel_title" => "Soul Slash Synthesis"
      }
    }
  end
end

class DashboardVerifierUploadFixture
  attr_reader :calls

  def initialize
    @calls = []
  end

  def preview(project_id:, candidate_id:, visual_id:, visibility:)
    @calls << ["preview", project_id, candidate_id, visual_id, visibility]
    {
      "ok" => true,
      "lifecycle_state" => "blocked_for_human_review",
      "data" => {
        "confirmation_phrase" => SoulCore::YouTubeAuthenticatedUploadService::CONFIRMATION,
        "expected_digest" => "b" * 64,
        "preview_scope" => { "visibility" => visibility },
        "upload" => nil
      }
    }
  end

  def execute(project_id:, candidate_id:, visual_id:, visibility:, confirmation:, expected_digest:, progress: nil)
    @calls << ["execute", project_id, candidate_id, visual_id, visibility, confirmation, expected_digest, progress]
    progress&.call({ "stage" => "upload", "message" => "fixture upload path" })
    {
      "ok" => true,
      "lifecycle_state" => "complete",
      "data" => {
        "upload" => {
          "state" => "complete",
          "video_id" => "fixture-video-id",
          "actual_privacy" => visibility,
          "thumbnail_applied" => true,
          "studio_url" => "https://studio.youtube.com/video/fixture-video-id"
        }
      }
    }
  end
end

failures = []

Dir.mktmpdir("soul-youtube-client-discovery") do |root|
  downloads = File.join(root, "Downloads")
  FileUtils.mkdir_p(downloads)
  client_document = lambda do |project_id: SoulCore::YouTubeOAuthService::PROJECT_ID|
    {
      "installed" => {
        "client_id" => "fixture-client.apps.googleusercontent.com",
        "client_secret" => "fixture-client-secret-must-not-leak",
        "auth_uri" => "https://accounts.google.com/o/oauth2/auth",
        "token_uri" => "https://oauth2.googleapis.com/token",
        "project_id" => project_id
      }
    }
  end
  write_client = lambda do |name, document, mode|
    path = File.join(downloads, name)
    File.write(path, JSON.generate(document))
    File.chmod(mode, path)
    path
  end

  valid_path = write_client.call(
    "client_secret_valid.apps.googleusercontent.com.json",
    client_document.call,
    0o600
  )
  write_client.call(
    "client_secret_wrong-project.apps.googleusercontent.com.json",
    client_document.call(project_id: "some-other-project"),
    0o600
  )
  unsafe_path = write_client.call(
    "client_secret_unsafe.apps.googleusercontent.com.json",
    client_document.call,
    0o644
  )
  symlink_path = File.join(downloads, "client_secret_symlink.apps.googleusercontent.com.json")
  File.symlink(valid_path, symlink_path)

  discovery = SoulCore::YouTubeOAuthService.new(
    root: root,
    discovery_directories: [downloads]
  ).status
  candidates = discovery.dig("data", "client_candidates")
  serialized = JSON.generate(discovery)
  check("OAuth status discovers only the exact valid owner-only Desktop client",
    candidates == [{
      "path" => valid_path,
      "filename" => File.basename(valid_path),
      "project_id" => SoulCore::YouTubeOAuthService::PROJECT_ID,
      "application_type" => "desktop"
    }], failures)
  check("OAuth discovery rejects unsafe permissions and symlinks",
    candidates.none? { |candidate| [unsafe_path, symlink_path].include?(candidate["path"]) }, failures)
  check("OAuth discovery returns no client secret or client identifier",
    !serialized.include?("fixture-client-secret") &&
      !serialized.include?("fixture-client.apps.googleusercontent.com"), failures)
end

operations = SoulCore::ApplicationContract::OPERATIONS
youtube_operations = operations.select { |operation, _| operation.start_with?("youtube.") }

check("application contract contains exact YouTube A1 operations", youtube_operations.keys.sort == [
  "youtube.oauth.authorization.execute",
  "youtube.oauth.authorization.preview",
  "youtube.oauth.status",
  "youtube.upload.execute",
  "youtube.upload.preview"
].sort, failures)

check("YouTube operation schemas are exact", youtube_operations["youtube.oauth.status"] == [] &&
  youtube_operations["youtube.oauth.authorization.preview"] == ["client_path"] &&
  youtube_operations["youtube.oauth.authorization.execute"] == %w[client_path confirmation expected_digest] &&
  youtube_operations["youtube.upload.preview"] == %w[project_id candidate_id visual_id visibility] &&
  youtube_operations["youtube.upload.execute"] == %w[project_id candidate_id visual_id visibility confirmation expected_digest], failures)

oauth_fixture = DashboardVerifierOAuthFixture.new
upload_fixture = DashboardVerifierUploadFixture.new
request_payload = request_payload_factory

Dir.mktmpdir("soul-youtube-dashboard-a1") do |root|
  facade = SoulCore::ApplicationFacade.new(
    root: root,
    youtube_oauth_service: oauth_fixture,
    youtube_authenticated_upload_service: upload_fixture
  )

  status_result = facade.call(request_payload.call("youtube.oauth.status"))
  status_call = oauth_fixture.calls.find { |call| call[0] == "status" }
  check("facade delegates YouTube OAuth status to injected service", status_call == ["status"] && status_result["lifecycle_state"] == "complete", failures)

  auth_preview_result = facade.call(request_payload.call("youtube.oauth.authorization.preview", "client_path" => "~/Downloads/client_secret_fixture.json"))
  auth_preview_call = oauth_fixture.calls.find do |call|
    call[0] == "preview"
  end
  check("facade delegates OAuth preview with exact client path", auth_preview_call == ["preview", "~/Downloads/client_secret_fixture.json"] && auth_preview_result["lifecycle_state"] == "awaiting_input", failures)

  auth_execute_result = facade.call(request_payload.call("youtube.oauth.authorization.execute", {
    "client_path" => "/tmp/fixture-google-desktop-client.json",
    "confirmation" => SoulCore::YouTubeOAuthService::CONFIRMATION,
    "expected_digest" => auth_preview_result.dig("data", "expected_digest")
  }))
  auth_execute_call = oauth_fixture.calls.find do |call|
    call[0] == "execute"
  end
  check("facade delegates OAuth execute with exact params", auth_execute_call == [
    "execute",
    "/tmp/fixture-google-desktop-client.json",
    SoulCore::YouTubeOAuthService::CONFIRMATION,
    "a" * 64
  ] && auth_execute_result["lifecycle_state"] == "complete", failures)

  upload_preview_result = facade.call(request_payload.call("youtube.upload.preview", {
    "project_id" => "music_" + "a" * 16,
    "candidate_id" => "candidate_1234567890abcdef",
    "visual_id" => "visual_1234567890abcdef"
  }))
  upload_preview_call = upload_fixture.calls.find { |call| call[0] == "preview" }
  check("facade delegates upload preview with default visibility private", upload_preview_call == [
    "preview", "music_" + "a" * 16, "candidate_1234567890abcdef", "visual_1234567890abcdef", "private"
  ] && upload_preview_result["lifecycle_state"] == "blocked_for_human_review", failures)

  progress_events = []
  upload_progress = ->(event) { progress_events << event }
  upload_execute_result = facade.call(
    request_payload.call("youtube.upload.execute", {
      "project_id" => "music_" + "a" * 16,
      "candidate_id" => "candidate_1234567890abcdef",
      "visual_id" => "visual_1234567890abcdef",
      "confirmation" => SoulCore::YouTubeAuthenticatedUploadService::CONFIRMATION,
      "expected_digest" => upload_preview_result.dig("data", "expected_digest")
    }),
    progress: upload_progress
  )
  upload_execute_call = upload_fixture.calls.find { |call| call[0] == "execute" }
  check("facade delegates upload execute with default visibility private", upload_execute_call == [
    "execute", "music_" + "a" * 16, "candidate_1234567890abcdef", "visual_1234567890abcdef", "private",
    SoulCore::YouTubeAuthenticatedUploadService::CONFIRMATION, "b" * 64, upload_progress
  ] && upload_execute_result["lifecycle_state"] == "complete", failures)
  check("facade passes progress callback through to upload execute", progress_events == [{ "stage" => "upload", "message" => "fixture upload path" }], failures)
  check("upload execute does not drop exact params and visibility when caller omits visibility", upload_execute_call && upload_execute_call[4] == "private", failures)

end

contract_source = read_text_file(File.join(ROOT, "lib/soul_core/application_contract.rb"))
facade_source = read_text_file(File.join(ROOT, "lib/soul_core/application_facade.rb"))
dashboard_http_source = read_text_file(File.join(ROOT, "lib/soul_core/dashboard_http_application.rb"))
javascript = read_text_file(File.join(ROOT, "assets/dashboard/dashboard.js"))
dashboard_brief = read_text_file(File.join(ROOT, "docs/soul/YOUTUBE_DASHBOARD_UPLOAD_A1_BRIEF.md"))
dashboard_css = read_text_file(File.join(ROOT, "assets/dashboard/dashboard.css"))
check("dashboard contract/facade evidence aligns with added operations", %w[youtube.oauth.status youtube.oauth.authorization.preview youtube.oauth.authorization.execute youtube.upload.preview youtube.upload.execute].all? do |operation|
  contract_source.include?(operation) && facade_source.include?(operation)
end, failures)

check("YouTube dashboard UI renders OAuth/status/upload after exact package is ready", javascript.include?('if (envelope.lifecycle_state === "complete" && data.package)') && javascript.include?("renderYouTubeAuthenticatedUpload"), failures)
check("YouTube OAuth status + preview + execute flows are present", javascript.include?('callSoul("youtube.oauth.status"') && javascript.include?('callSoul("youtube.oauth.authorization.preview"') && javascript.include?('callSoul("youtube.oauth.authorization.execute"'), failures)
check("YouTube OAuth UI prefills a validated detected client while retaining manual entry",
  javascript.include?("Detected valid Desktop OAuth client") &&
    javascript.include?("oauth.client_candidates") &&
    javascript.include?("path.value = detected.value"), failures)
check("YouTube upload preview + bounded stream execute are present", javascript.include?('callSoul("youtube.upload.preview"') && javascript.include?('callNdjson("/api/v1/music-stream", "youtube.upload.execute"'), failures)
check("configured YouTube authorization can be replaced without deleting local credentials", javascript.include?("Reauthorize YouTube") && javascript.include?("renderYouTubeAuthorization(identity, panel, status, status, oauth)"), failures)
check("upload visibility gate is explicit with private default and all three choices", javascript.include?('visibility.value = "private"') &&
  javascript.include?('["private","Private · recommended draft"]') &&
  javascript.include?('["unlisted","Unlisted · explicit publication choice"]') &&
  javascript.include?('["public","Public · explicit publication choice"]'), failures)
check("upload receipt points to YouTube Studio", javascript.include?("Open exact video in YouTube Studio"), failures)
check("dashboard upload render surfaces studio receipt metadata", javascript.include?("thumbnail_applied"), failures)
check("dashboard source contains no token-like literals", !javascript.match?(/ya29\.[A-Za-z0-9_-]+/) && !javascript.include?("fixture-access") && !javascript.include?("fixture-refresh"), failures)

check("dashboard CSS includes dedicated YouTube upload control styles", dashboard_css.include?(".youtube-upload-control"), failures)

music_stream_start = dashboard_http_source.index("def music_stream(headers, body)")
music_stream_end = music_stream_start && dashboard_http_source.index("\n    def administration_stream(headers, body)", music_stream_start)
music_stream_segment = dashboard_http_source[music_stream_start...music_stream_end.to_i]
check("music stream gate includes mutation boundary and auth checks", music_stream_segment.include?("boundary_error = mutation_boundary_error(headers, body)") &&
  music_stream_segment.include?("session = @authentication.session(session_token(headers))") &&
  music_stream_segment.include?("error_envelope(\"invalid_stream_operation\""), failures)
check("music stream allows only YouTube upload execute among new YouTube mutations", music_stream_segment&.include?("youtube.upload.execute") &&
  !music_stream_segment&.include?("youtube.oauth"), failures)
check("music stream preserves CSRF/auth boundaries through existing guards", music_stream_segment.include?("boundary_error = mutation_boundary_error(headers, body)") &&
  music_stream_segment.include?("session = @authentication.session(session_token(headers))") &&
  music_stream_segment.include?("password_change_required"), failures)

check("brief exists and explicitly prohibits background execution paths", dashboard_brief.include?("Foreground invocation only.") &&
  dashboard_brief.include?("No worker, queue, daemon, watcher, service, timer") &&
  dashboard_brief.include?("automatic retry beyond A0's") &&
  dashboard_brief.include?("automatic upload is added"), failures)

check("brief records exactly the five application operations", dashboard_brief.include?("youtube.oauth.status") &&
  dashboard_brief.include?("youtube.oauth.authorization.preview") &&
  dashboard_brief.include?("youtube.oauth.authorization.execute") &&
  dashboard_brief.include?("youtube.upload.preview") &&
  dashboard_brief.include?("youtube.upload.execute"), failures)

a0_stdout, a0_stderr, a0_status = Open3.capture3("ruby", "scripts/verify-youtube-authenticated-upload-a0.rb", chdir: ROOT)
check("existing authenticated upload A0 verifier stays green", a0_status.success? && a0_stdout.include?("Authenticated YouTube upload A0 deterministic verification passed"), failures)
unless a0_status.success?
  warn a0_stderr unless a0_stderr.empty?
  warn a0_stdout unless a0_stdout.empty?
end

if failures.empty?
  puts "YouTube dashboard upload A1 verifier passed."
else
  warn "YouTube dashboard upload A1 verifier failed: #{failures.join(", ")}"
  exit 1
end
