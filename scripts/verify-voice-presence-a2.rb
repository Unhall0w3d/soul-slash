#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "tmpdir"
require_relative "../lib/soul_core/application_contract"
require_relative "../lib/soul_core/dashboard_http_application"
require_relative "../lib/soul_core/voice_transcription_service"
require_relative "../lib/soul_core/voice_presence_launch_service"

ROOT = File.expand_path("..", __dir__)
MANIFEST_PATH = File.join(ROOT, "config", "voice_presence_models.json")
manifest = JSON.parse(File.binread(MANIFEST_PATH, 256 * 1024))
raise "manifest schema differs" unless manifest["schema_version"] == "soul.voice_presence.models.v1"
raise "wake phrase differs" unless manifest.dig("keyword", "phrase") == "Hey Soul"
raise "reviewed wake threshold differs" unless manifest.dig("keyword", "trigger_threshold") == 0.15
raise "reviewed wake boosting differs" unless manifest.dig("keyword", "boosting_score") == 3.5
raise "wake feed is too coarse" unless manifest.dig("capture", "wake_chunk_milliseconds") == 10
raise "wake detector is not CPU bounded" unless File.binread(File.join(ROOT, "scripts", "soul-voice-presence-worker.py")).include?('provider="cpu"')
raise "capture duration is unbounded" unless manifest.dig("capture", "maximum_utterance_seconds").to_f.between?(1, 30)
raise "speech-start timeout is unbounded" unless manifest.dig("capture", "speech_start_timeout_seconds").to_f.between?(1, 4)
raise "follow-up timeout differs" unless manifest.dig("capture", "followup_speech_start_timeout_seconds").to_f == 5.0
raise "trailing silence is unbounded" unless manifest.dig("capture", "trailing_silence_seconds").to_f.between?(0.5, 2)
raise "post-wake capture delay is unbounded" unless manifest.dig("capture", "post_wake_capture_delay_seconds").to_f.between?(0.16, 0.3)

request = {
  "schema_version" => SoulCore::ApplicationContract::SCHEMA_VERSION,
  "request_id" => "voice-presence-test-1234",
  "operation" => "chats.create",
  "parameters" => { "title" => "Voice presence" },
  "context" => { "interface" => "voice_presence" }
}
raise "voice_presence is not an ordinary application interface" unless SoulCore::ApplicationContract.validate(request)["ok"]

transcription_source = File.binread(File.join(ROOT, "lib", "soul_core", "voice_transcription_service.rb"))
raise "native WAV normalization can overwrite its input" unless transcription_source.include?('File.join(temporary, "source#{extension}")') &&
  transcription_source.include?('File.join(temporary, "normalized.wav")')

Dir.mktmpdir("soul-voice-presence-launch-test-") do |state_root|
  held_lock = nil
  spawner = lambda do |_launcher, _environment|
    held_lock = File.open(File.join(state_root, "run.lock"), File::RDWR | File::CREAT, 0o600)
    raise "fixture could not hold instance lock" unless held_lock.flock(File::LOCK_EX | File::LOCK_NB)
  end
  service = SoulCore::VoicePresenceLaunchService.new(root: ROOT, state_root: state_root, spawner: spawner)
  raise "closed launch status differs" unless service.status.dig("data", "running") == false
  launched = service.launch
  raise "bounded launch did not observe visible instance lock" unless launched["ok"] && launched.dig("data", "running")
  raise "duplicate launch was not idempotent" unless service.launch.dig("data", "already_running") == true
  held_lock.flock(File::LOCK_UN)
  held_lock.close
  raise "closed instance remained reported running" unless service.status.dig("data", "running") == false

  auth = Object.new
  auth.define_singleton_method(:session) do |token|
    token == "session" ? { "authenticated" => true, "username" => "admin", "password_change_required" => false } : nil
  end
  fixture_presence = Object.new
  fixture_presence.define_singleton_method(:status) { { "lifecycle_state" => "complete", "ok" => true, "message" => "closed", "data" => { "running" => false } } }
  fixture_presence.define_singleton_method(:launch) { { "lifecycle_state" => "complete", "ok" => true, "message" => "opened", "data" => { "running" => true } } }
  application = SoulCore::DashboardHttpApplication.new(
    root: ROOT, facade: Object.new, bind_host: "127.0.0.1", port: 4567,
    csrf_token: "voice-presence-csrf", authentication: auth, voice_presence: fixture_presence
  )
  headers = {
    "Host" => "127.0.0.1:4567", "Origin" => "http://127.0.0.1:4567",
    "Cookie" => "soul_session=session", "Content-Type" => "application/json",
    "X-Soul-CSRF" => "voice-presence-csrf"
  }
  raise "dashboard presence status is not authenticated" unless application.call(method: "GET", target: "/api/v1/voice/presence/status", headers: headers).status == 200
  raise "dashboard launch is not CSRF protected" unless application.call(method: "POST", target: "/api/v1/voice/presence/launch", headers: headers.reject { |key, _| key == "X-Soul-CSRF" }, body: '{"action":"launch"}').status == 403
  raise "dashboard launch failed" unless application.call(method: "POST", target: "/api/v1/voice/presence/launch", headers: headers, body: '{"action":"launch"}').status == 200
end

Dir.mktmpdir("soul-voice-presence-test-") do |directory|
  script = <<~PYTHON
    import importlib.util, pathlib, tempfile, wave
    spec = importlib.util.spec_from_file_location("worker", #{File.join(ROOT, "scripts", "soul-voice-presence-worker.py").inspect})
    worker = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(worker)
    assert worker.rms(b"\\x00\\x00" * 100) == 0
    assert worker.rms((1000).to_bytes(2, "little", signed=True) * 100) == 1000
    path = pathlib.Path(#{directory.inspect}) / "bounded.wav"
    worker.write_wav(path, [(100).to_bytes(2, "little", signed=True) * 1600], 16000)
    with wave.open(str(path), "rb") as stream:
        assert stream.getnchannels() == 1
        assert stream.getframerate() == 16000
        assert stream.getnframes() == 1600
    assert oct(path.stat().st_mode & 0o777) == "0o600"
  PYTHON
  output, status = Open3.capture2e("python3", "-c", script)
  raise "worker primitive test failed: #{output}" unless status.success?
end

app = File.read(File.join(ROOT, "scripts", "soul-voice-presence-app.py"), encoding: "UTF-8")
raise "window close does not terminate children" unless app.include?("def closeEvent") && app.include?("process.terminate()") && app.include?("process.kill()")
raise "three-failure pause is missing" unless app.include?("self.failure_count >= 3")
raise "masked portrait state is missing" unless app.include?("self.args.masked") && app.include?("self.args.unmasked")
raise "reviewed voice selector is missing" unless app.include?('self.voice_selector.addItem("Feminine · F3", "F3")') &&
  app.include?('self.voice_selector.addItem("Masculine · M3", "M3")')
raise "voice preference is not persisted" unless app.include?('QSettings("SoulSlash", "VoicePresence")')

bridge = File.binread(File.join(ROOT, "scripts", "soul-voice-presence-bridge"))
raise "voice does not use ordinary chats.send" unless bridge.include?('request("chats.send"')
raise "voice origin bypasses interface contract" unless bridge.include?('"interface" => "voice_presence"')
raise "responsive voice is not explicit" unless bridge.include?('quality: "responsive"')
raise "presence bridge does not bound voice profiles" unless bridge.include?("%w[F3 M3].include?")

plan_output, plan_status = Open3.capture2e(
  "ruby", File.join(ROOT, "scripts", "soul-voice-presence-runtime"), "plan",
  "--root", File.join(Dir.tmpdir, "soul-voice-presence-not-installed"),
  "--manifest", MANIFEST_PATH,
  "--requirements", File.join(ROOT, "config", "voice_presence_requirements.txt")
)
raise "runtime plan failed: #{plan_output}" unless plan_status.success?
plan = JSON.parse(plan_output)
raise "runtime plan would install a service" unless plan["system_service"] == false
raise "runtime plan survives window close" unless plan["survives_window_close"] == false
raise "runtime plan lacks exact confirmation" unless plan["confirmation_phrase"] == "INSTALL_SOUL_VOICE_PRESENCE"
raise "runtime plan digest differs" unless plan["expected_digest"] == Digest::SHA256.hexdigest(JSON.generate(plan.reject { |key, _| %w[expected_digest lifecycle_state].include?(key) }))

puts JSON.pretty_generate(
  "lifecycle_state" => "complete",
  "deterministic_tests" => 34,
  "wake_phrase" => manifest.dig("keyword", "phrase"),
  "ordinary_chat_interface" => true,
  "system_service" => false,
  "window_controls_residency" => true
)
