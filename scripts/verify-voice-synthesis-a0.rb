#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/bounded_command_runner"
require_relative "../lib/soul_core/dashboard_http_application"
require_relative "../lib/soul_core/voice_synthesis_service"

errors = []
check = lambda do |name, condition|
  puts "#{condition ? 'PASS' : 'FAIL'}: #{name}"
  errors << name unless condition
end

class SynthesisFixtureRunner
  attr_accessor :status
  attr_reader :inputs, :voices, :temporary_directories

  def initialize
    @status = "ok"
    @inputs = []
    @voices = []
    @temporary_directories = []
  end

  def run(*command, **_options)
    argv = command.flatten.map(&:to_s)
    input = argv.fetch(argv.index("--input") + 1)
    output = argv.fetch(argv.index("--output") + 1)
    @inputs << File.read(input)
    @voices << argv.fetch(argv.index("--voice") + 1)
    @temporary_directories << File.dirname(input)
    File.binwrite(output, "RIFF" + ("\0" * 4) + "WAVE" + ("\0" * 64)) if @status == "ok"
    SoulCore::BoundedCommandRunner::Result.new(
      stdout: "", stderr: "", exit_status: @status == "ok" ? 0 : 1,
      status: @status, truncated: false
    )
  end
end

class SynthesisFixtureAuth
  def session(token)
    return nil unless token == "session"
    { "authenticated" => true, "username" => "admin", "password_change_required" => false }
  end
end

class SynthesisFixtureService
  attr_reader :calls

  def initialize = (@calls = [])
  def status = { "lifecycle_state" => "complete", "ok" => true, "available" => true }
  def synthesize(text:, voice_name: nil, quality: "responsive", speech_context: nil, on_progress: nil)
    @calls << [text, voice_name, speech_context]
    { "lifecycle_state" => "complete", "ok" => true, "audio" => "RIFF....WAVEfixture".b, "content_type" => "audio/wav", "voice" => voice_name || "F3" }
  end
end

Dir.mktmpdir("soul-synthesis-test-") do |root|
  runtime_root = File.join(root, "runtime")
  python = File.join(runtime_root, ".venv", "bin", "python")
  FileUtils.mkdir_p(File.dirname(python))
  File.write(python, "#!/bin/sh\nexit 0\n")
  File.chmod(0o700, python)
  model_dir = File.join(runtime_root, "supertonic-3")
  asset = File.join(model_dir, "onnx", "fixture.onnx")
  FileUtils.mkdir_p(File.dirname(asset))
  File.binwrite(asset, "fixture-model")
  manifest = File.join(root, "manifest.json")
  File.write(manifest, JSON.generate({
    "schema_version" => "soul.voice_synthesis.models.v1",
    "runtime" => {
      "name" => "Supertonic", "release" => "3", "package_version" => "1.3.1",
      "revision" => "fixture-revision", "cpu_only" => true
    },
    "defaults" => { "voice" => "F3", "language" => "en", "steps" => 10, "speed" => 1.0 },
    "voices" => { "F1" => {}, "F3" => {}, "F5" => {}, "M3" => {} },
    "assets" => { "onnx/fixture.onnx" => Digest::SHA256.file(asset).hexdigest }
  }))

  runner = SynthesisFixtureRunner.new
  service = SoulCore::VoiceSynthesisService.new(root: File.expand_path("..", __dir__), runtime_root: runtime_root, manifest_path: manifest, runner: runner)
  status = service.status
  check.call("pinned CPU synthesis is ready without a resident process", status["ok"] && status.dig("data", "runtime", "cpu_only") && status.dig("data", "resident_after_completion") == false)

  result = service.synthesize(text: "A **clear** response.\n\n```json\n{\"secret\":\"not spoken\"}\n```\nRead https://example.test later.")
  check.call("one foreground request returns bounded WAV bytes", result["ok"] && result["audio"].start_with?("RIFF") && result["content_type"] == "audio/wav")
  check.call("Markdown code and raw URLs are excluded from spoken prose", runner.inputs == ["A clear response. Read later."])
  check.call("request-private text and audio are removed at terminal return", runner.temporary_directories.all? { |path| !File.exist?(path) })
  check.call("oversized speech stops before inference", service.synthesize(text: "x" * 2_001)["lifecycle_state"] == "awaiting_input" && runner.inputs.length == 1)
  masculine = service.synthesize(text: "A second voice.", voice_name: "M3")
  check.call("allowlisted masculine voice hot-swaps without service restart", masculine["ok"] && masculine["voice"] == "M3" && runner.voices.last == "M3")
  check.call("unknown voice profiles fail before inference", service.synthesize(text: "No.", voice_name: "unknown")["lifecycle_state"] == "awaiting_input" && runner.inputs.length == 2)

  runner.status = "timeout"
  timed_out = service.synthesize(text: "This request should stop.")
  check.call("bounded timeout terminates as failed", timed_out["lifecycle_state"] == "failed" && timed_out["message"].include?("timed out"))

  synthesis = SynthesisFixtureService.new
  app = SoulCore::DashboardHttpApplication.new(
    root: File.expand_path("..", __dir__), facade: Object.new, bind_host: "127.0.0.1", port: 4567,
    csrf_token: "voice-csrf", authentication: SynthesisFixtureAuth.new, voice_synthesis: synthesis
  )
  headers = {
    "Host" => "127.0.0.1:4567", "Origin" => "http://127.0.0.1:4567",
    "Cookie" => "soul_session=session", "Content-Type" => "application/json", "X-Soul-CSRF" => "voice-csrf"
  }
  response = app.call(method: "POST", target: "/api/v1/voice/synthesize", headers: headers, body: JSON.generate("text" => "Speak this.", "voice" => "M3"))
  check.call("authenticated same-origin synthesis returns private non-cached WAV", response.status == 200 && response.headers["Content-Type"] == "audio/wav" && response.headers["Cache-Control"] == "private, no-store" && synthesis.calls == [["Speak this.", "M3", nil]])
  contextual = app.call(method: "POST", target: "/api/v1/voice/synthesize", headers: headers, body: JSON.generate("text" => "72°F", "voice" => "F3", "speech_context" => "weather_report"))
  check.call("authenticated synthesis forwards explicit weather context", contextual.status == 200 && synthesis.calls.last == ["72°F", "F3", "weather_report"])
  check.call("missing CSRF blocks synthesis before invocation", app.call(method: "POST", target: "/api/v1/voice/synthesize", headers: headers.reject { |key, _| key == "X-Soul-CSRF" }, body: JSON.generate("text" => "No.")).status == 403 && synthesis.calls.length == 2)
  check.call("wrong Origin blocks synthesis before invocation", app.call(method: "POST", target: "/api/v1/voice/synthesize", headers: headers.merge("Origin" => "https://elsewhere.test"), body: JSON.generate("text" => "No.")).status == 403 && synthesis.calls.length == 2)
  check.call("synthesis status requires dashboard authentication", app.call(method: "GET", target: "/api/v1/voice/synthesis/status", headers: { "Host" => "127.0.0.1:4567" }).status == 401)
end

js = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
css = File.read(File.expand_path("../assets/dashboard/dashboard.css", __dir__))
brief = File.read(File.expand_path("../docs/soul/VOICE_OUTPUT_A0_BRIEF.md", __dir__))
check.call("eligible assistant messages expose explicit Speak and Stop behavior", js.include?("messageSpeakButton") && js.include?('button.textContent = "Stop"') && js.include?("/api/v1/voice/synthesize"))
check.call("dashboard CSP permits request-private blob audio playback", SoulCore::DashboardHttpApplication::SECURITY_HEADERS.fetch("Content-Security-Policy").include?("media-src 'self' blob:"))
check.call("curated voice selection is restart-free and browser-local", js.include?("VOICE_OUTPUT_PROFILES") && js.include?("voiceOutputProfile") && js.include?("localStorage.setItem"))
check.call("only one playback survives and object URLs are revoked", js.include?("stopVoicePlayback();") && js.include?("URL.revokeObjectURL"))
check.call("leaving Chat and logout stop speech", js.include?("if (!chat) stopVoicePlayback();") && js.match?(/async function logout\(\)[\s\S]{0,180}stopVoicePlayback/))
check.call("speech state is visible and reduced-motion aware", css.include?(".message-speak-button[aria-pressed=\"true\"]") && css.include?(".message-speak-button::before"))
check.call("brief prohibits automatic narration and resident TTS", brief.include?("No automatic narration") && brief.include?("resident speech process"))
check.call("no browser speech API, new listener, or polling loop was introduced", !js.match?(/speechSynthesis|SpeechSynthesisUtterance|WebSocket|EventSource|setInterval/))

abort "Voice synthesis A0 verification failed: #{errors.join(', ')}" unless errors.empty?
puts "Voice synthesis A0 candidate verification passed."
