#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/bounded_command_runner"
require_relative "../lib/soul_core/dashboard_http_application"
require_relative "../lib/soul_core/voice_transcription_service"

errors = []
check = lambda do |name, condition|
  puts "#{condition ? 'PASS' : 'FAIL'}: #{name}"
  errors << name unless condition
end

class VoiceFixtureRunner
  attr_accessor :duration, :failure
  attr_reader :temporary_directories
  attr_reader :commands

  def initialize
    @duration = 2.4
    @failure = nil
    @temporary_directories = []
    @commands = []
  end

  def which(name) = "/fixture/#{name}"

  def run(*command, **_options)
    argv = command.flatten.map(&:to_s)
    @commands << argv
    status = @failure && argv.first.include?(@failure) ? "failed" : "ok"
    if argv.first == "ffprobe"
      @temporary_directories << File.dirname(argv.last)
      result(status, stdout: @duration.to_s)
    elsif argv.first == "ffmpeg"
      File.binwrite(argv.last, "RIFF-voice-fixture") if status == "ok"
      result(status)
    elsif File.basename(argv.first) == "whisper-cli"
      output = argv.fetch(argv.index("--output-file") + 1)
      File.write("#{output}.json", JSON.generate("transcription" => [
        { "offsets" => { "from" => 0, "to" => 900 }, "text" => " Hello Soul. " },
        { "offsets" => { "from" => 950, "to" => 2100 }, "text" => "This remains an editable draft." }
      ])) if status == "ok"
      result(status)
    else
      result("failed")
    end
  end

  private

  def result(status, stdout: "")
    SoulCore::BoundedCommandRunner::Result.new(
      stdout: stdout, stderr: "", exit_status: status == "ok" ? 0 : 1,
      status: status, truncated: false
    )
  end
end

class VoiceFixtureAuth
  def session(token)
    return nil unless token == "session"
    { "authenticated" => true, "username" => "admin", "password_change_required" => false }
  end
end

class VoiceFixtureService
  attr_reader :calls

  def initialize = (@calls = [])
  def status
    { "schema_version" => "soul.application.v1", "lifecycle_state" => "complete", "mutation" => "none", "ok" => true, "data" => { "available" => true }, "errors" => [] }
  end
  def transcribe(audio_bytes:, content_type:)
    @calls << [audio_bytes, content_type]
    { "schema_version" => "soul.application.v1", "lifecycle_state" => "complete", "mutation" => "none", "ok" => true, "data" => { "transcript" => "fixture transcript", "source_audio_retained" => false, "automatically_sent" => false }, "errors" => [] }
  end
end

Dir.mktmpdir("soul-voice-test-") do |root|
  runtime_root = File.join(root, "runtime")
  install = File.join(runtime_root, "transcription", "fixture-v1")
  FileUtils.mkdir_p(install)
  binary = File.join(install, "whisper-cli")
  model = File.join(install, "fixture.bin")
  File.write(binary, "#!/bin/sh\nexit 0\n")
  File.chmod(0o700, binary)
  File.binwrite(model, "fixture-model")
  manifest = File.join(root, "manifest.json")
  File.write(manifest, JSON.generate({
    "schema_version" => "soul.music_transcription.models.v1",
    "runtime" => { "name" => "whisper.cpp", "release" => "fixture-v1", "binary" => "whisper-cli" },
    "models" => {
      "fixture.bin" => {
        "bytes" => File.size(model),
        "sha256" => Digest::SHA256.file(model).hexdigest,
        "language" => "en"
      }
    }
  }))

  runner = VoiceFixtureRunner.new
  service = SoulCore::VoiceTranscriptionService.new(root: root, music_root: runtime_root, manifest_path: manifest, model_name: "fixture.bin", runner: runner)
  status = service.status
  check.call("shared pinned runtime is reported ready without a resident process", status["ok"] && status.dig("data", "runtime", "cpu_only") && status.dig("data", "runtime", "resident_after_completion") == false)

  completed = service.transcribe(audio_bytes: "bounded-webm-fixture".b, content_type: "audio/webm;codecs=opus")
  check.call("bounded recording becomes an editable transcript and is never sent", completed["lifecycle_state"] == "complete" && completed.dig("data", "transcript") == "Hello Soul. This remains an editable draft." && completed.dig("data", "automatically_sent") == false)
  check.call("source and normalized audio are explicitly not retained", completed.dig("data", "source_audio_retained") == false && completed.dig("data", "normalized_audio_retained") == false)
  check.call("request-private temporary directories are removed at terminal return", runner.temporary_directories.all? { |path| !File.exist?(path) })
  normalization_index = runner.commands.index { |command| command.first == "ffmpeg" }
  probe_index = runner.commands.index { |command| command.first == "ffprobe" }
  check.call("browser containers normalize under a hard ceiling before reliable WAV duration validation", normalization_index < probe_index && runner.commands[normalization_index].include?("-t") && runner.commands[probe_index].last.end_with?("normalized.wav"))

  runner.duration = 61.0
  excessive = service.transcribe(audio_bytes: "too-long".b, content_type: "audio/mp4")
  check.call("recordings beyond sixty seconds stop at awaiting_input", excessive["lifecycle_state"] == "awaiting_input" && excessive.dig("data", "message").include?("60 seconds"))
  check.call("unsupported containers fail before invoking local tools", service.transcribe(audio_bytes: "x".b, content_type: "application/octet-stream")["lifecycle_state"] == "awaiting_input")

  voice = VoiceFixtureService.new
  app = SoulCore::DashboardHttpApplication.new(
    root: File.expand_path("..", __dir__), facade: Object.new, bind_host: "127.0.0.1", port: 4567,
    csrf_token: "voice-csrf", authentication: VoiceFixtureAuth.new, voice_transcription: voice
  )
  headers = {
    "Host" => "127.0.0.1:4567", "Origin" => "http://127.0.0.1:4567",
    "Cookie" => "soul_session=session", "Content-Type" => "audio/webm;codecs=opus", "X-Soul-CSRF" => "voice-csrf"
  }
  response = app.call(method: "POST", target: "/api/v1/voice/transcribe", headers: headers, body: "audio".b)
  check.call("dedicated authenticated route accepts exact same-origin audio", response.status == 200 && voice.calls == [["audio".b, "audio/webm;codecs=opus"]])
  check.call("microphone is allowed only for the same-origin dashboard", response.headers["Permissions-Policy"].include?("microphone=(self)") && !response.headers["Permissions-Policy"].include?("microphone=*"))
  check.call("missing CSRF blocks audio before service invocation", app.call(method: "POST", target: "/api/v1/voice/transcribe", headers: headers.reject { |key, _| key == "X-Soul-CSRF" }, body: "audio".b).status == 403 && voice.calls.length == 1)
  check.call("unsupported content type is rejected at the HTTP boundary", app.call(method: "POST", target: "/api/v1/voice/transcribe", headers: headers.merge("Content-Type" => "application/octet-stream"), body: "audio".b).status == 415)
  check.call("voice status requires an authenticated session", app.call(method: "GET", target: "/api/v1/voice/status", headers: { "Host" => "127.0.0.1:4567" }).status == 401)
end

html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
js = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
css = File.read(File.expand_path("../assets/dashboard/dashboard.css", __dir__))
server = File.read(File.expand_path("../lib/soul_core/dashboard_server.rb", __dir__))
check.call("Chat exposes one labeled push-to-talk control", html.include?('id="record-voice"') && html.include?('aria-label="Start push-to-talk recording"'))
check.call(
  "browser capture is explicit, finite, and enters the ordinary Chat submit path",
  js.include?("getUserMedia") &&
    js.include?("MediaRecorder") &&
    js.include?("elapsed >= 60") &&
    js.include?("insertVoiceTranscript") &&
    js.include?("state.voiceRoundTripPending = true") &&
    js.include?('byId("composer").requestSubmit()') &&
    js.match?(/callSoulStream\(\s*"chats\.send"/)
)
check.call(
  "only a voice-originated turn speaks its terminal assistant reply",
  js.match?(/const voiceRoundTrip = state\.voiceRoundTripPending; state\.voiceRoundTripPending = false;/) &&
    js.match?(/if \(voiceRoundTrip && state\.activeChat\?\.id === chatId\)[\s\S]{0,1000}synthesizeMessageSpeech/)
)
check.call("leaving Chat visibly cancels capture", js.include?('cancelVoiceRecording("Voice capture stopped because Chat was closed.")'))
check.call("voice UI has visible and reduced-motion-aware recording state", css.include?("voice-capture-pulse") && css.include?(".voice-button[aria-pressed=\"true\"]"))
check.call("server grants voice its exact bounded body ceiling", server.include?('when "/api/v1/voice/transcribe" then VOICE_BODY_LIMIT') && server.include?("VOICE_BODY_LIMIT = 8 * 1024 * 1024"))
check.call("no listener, daemon, service, wake word, or background polling was added", ![js, html].any? { |source| source.match?(/WebSocket|EventSource|serviceWorker|setInterval|wake.?word/i) })

abort "Voice transcription A0 verification failed: #{errors.join(', ')}" unless errors.empty?
puts "Voice transcription A0 candidate verification passed."
