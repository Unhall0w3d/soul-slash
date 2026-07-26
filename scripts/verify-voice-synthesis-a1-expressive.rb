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

class ExpressiveFixtureRunner
  attr_reader :devices, :references

  def initialize
    @devices = []
    @references = []
  end

  def run(*command, **_options)
    argv = command.flatten.map(&:to_s)
    if argv.first == "nvidia-smi"
      return SoulCore::BoundedCommandRunner::Result.new(stdout: "Fixture GPU\n", stderr: "", exit_status: 0, status: "ok", truncated: false)
    end
    output = argv.fetch(argv.index("--output") + 1)
    if argv.include?("--reference")
      @devices << argv.fetch(argv.index("--device") + 1)
      @references << argv.fetch(argv.index("--reference") + 1)
    end
    File.binwrite(output, "RIFF" + ("\0" * 4) + "WAVE" + ("\0" * 64))
    SoulCore::BoundedCommandRunner::Result.new(stdout: "", stderr: "", exit_status: 0, status: "ok", truncated: false)
  end
end

class ExpressiveFixtureControl
  attr_reader :released
  attr_accessor :blocked

  def initialize
    @released = []
    @blocked = false
  end
  def status
    {
      "ok" => true,
      "data" => {
        "active_profile_id" => "nvidia-fallback",
        "profiles" => [{ "id" => "nvidia-fallback", "accelerator" => "NVIDIA CUDA" }]
      }
    }
  end

  def with_temporary_release(profile_id:, on_progress: nil)
    if blocked
      raise SoulCore::ModelRuntimeControlService::TemporaryReleaseError.new(
        "active work must complete first", lifecycle_state: "blocked_for_human_review",
        receipt: { "active_work_count" => 1 }
      )
    end
    @released << profile_id
    on_progress&.call("stage" => "releasing_chat_engine", "message" => "released")
    value = yield
    on_progress&.call("stage" => "restoring_chat_engine", "message" => "restored")
    [value, { "restored" => true, "health" => "ready" }]
  end
end

class ExpressiveFixtureAuth
  def session(token)
    token == "session" ? { "password_change_required" => false } : nil
  end
end

Dir.mktmpdir("soul-expressive-test-") do |root|
  responsive = File.join(root, "responsive")
  expressive = File.join(root, "expressive")
  [responsive, expressive].each do |runtime|
    python = File.join(runtime, ".venv", "bin", "python")
    FileUtils.mkdir_p(File.dirname(python))
    File.write(python, "#!/bin/sh\nexit 0\n")
    File.chmod(0o700, python)
  end

  responsive_asset = File.join(responsive, "supertonic-3", "fixture.onnx")
  expressive_asset = File.join(expressive, "chatterbox-original", "fixture.safetensors")
  FileUtils.mkdir_p(File.dirname(responsive_asset))
  FileUtils.mkdir_p(File.dirname(expressive_asset))
  File.binwrite(responsive_asset, "responsive")
  File.binwrite(expressive_asset, "expressive")
  responsive_manifest = File.join(root, "responsive.json")
  expressive_manifest = File.join(root, "expressive.json")
  File.write(responsive_manifest, JSON.generate(
    "schema_version" => "soul.voice_synthesis.models.v1",
    "runtime" => { "name" => "Supertonic", "release" => "3", "package_version" => "fixture", "revision" => "fixture", "cpu_only" => true },
    "defaults" => { "voice" => "F3", "language" => "en", "steps" => 10, "speed" => 1.0 },
    "voices" => { "F3" => {}, "M3" => {} },
    "assets" => { "fixture.onnx" => Digest::SHA256.file(responsive_asset).hexdigest }
  ))
  File.write(expressive_manifest, JSON.generate(
    "schema_version" => "soul.voice_expressive.models.v1",
    "runtime" => { "name" => "Chatterbox", "variant" => "Original English" },
    "defaults" => { "exaggeration" => 0.7, "cfg_weight" => 0.3 },
    "assets" => { "fixture.safetensors" => { "bytes" => File.size(expressive_asset), "sha256" => Digest::SHA256.file(expressive_asset).hexdigest } }
  ))

  runner = ExpressiveFixtureRunner.new
  control = ExpressiveFixtureControl.new
  service = SoulCore::VoiceSynthesisService.new(
    root: File.expand_path("..", __dir__), runtime_root: responsive, manifest_path: responsive_manifest,
    expressive_root: expressive, expressive_manifest_path: expressive_manifest,
    model_runtime_control: control, runner: runner
  )
  status = service.status
  check.call("status exposes responsive and expressive engines", status.dig("data", "qualities", "responsive", "available") && status.dig("data", "qualities", "expressive", "available"))
  events = []
  result = service.synthesize(text: "A measured, expressive response.", voice_name: "F3", quality: "expressive", on_progress: ->(event) { events << event })
  check.call("expressive request returns request-private WAV", result["ok"] && result["quality"] == "expressive" && result["audio"].start_with?("RIFF"))
  check.call("active NVIDIA chat engine is released and restored", control.released == ["nvidia-fallback"] && result.dig("runtime_receipt", "restored"))
  check.call("streaming stages expose preparation, render, and restore", %w[preparing_reference rendering_voice restoring_chat_engine].all? { |stage| events.any? { |event| event["stage"] == stage } })
  check.call("Chatterbox uses the private Supertonic reference on CUDA", runner.devices == ["cuda"] && runner.references.all? { |path| !File.exist?(path) })
  check.call("expressive text is independently bounded", service.synthesize(text: "x" * 601, quality: "expressive")["lifecycle_state"] == "awaiting_input")
  control.blocked = true
  fallback = service.synthesize(text: "Do not interrupt active work.", quality: "expressive")
  check.call("active NVIDIA work is preserved through CPU fallback", fallback["ok"] && fallback["device"] == "cpu" && fallback.dig("runtime_receipt", "nvidia_preserved"))
  control.blocked = false

  app = SoulCore::DashboardHttpApplication.new(
    root: File.expand_path("..", __dir__), facade: Object.new, bind_host: "127.0.0.1", port: 4567,
    csrf_token: "csrf", authentication: ExpressiveFixtureAuth.new, voice_synthesis: service
  )
  headers = { "Host" => "127.0.0.1:4567", "Origin" => "http://127.0.0.1:4567", "Cookie" => "soul_session=session", "Content-Type" => "application/json", "X-Soul-CSRF" => "csrf" }
  response = app.call(method: "POST", target: "/api/v1/voice/synthesize-stream", headers: headers, body: JSON.generate("text" => "Stream this.", "voice" => "M3", "quality" => "expressive"))
  body = response.body.to_a.join
  check.call("authenticated NDJSON streams progress and terminal audio", response.status == 200 && body.include?('"type":"progress"') && body.include?('"audio_base64"'))
  denied = app.call(method: "POST", target: "/api/v1/voice/synthesize-stream", headers: headers.reject { |key, _| key == "X-Soul-CSRF" }, body: "{}")
  check.call("CSRF is checked before expressive inference", denied.status == 403)
end

source = File.read(File.expand_path("../lib/soul_core/model_runtime_control_service.rb", __dir__))
js = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
check.call("runtime restoration is protected by ensure", source.match?(/with_temporary_release[\s\S]+ensure[\s\S]+restore_temporary_profile/))
check.call("dashboard offers explicit persisted delivery choice", js.include?("VOICE_OUTPUT_QUALITIES") && js.include?("soul.voice.output.quality"))
check.call("expressive UI consumes bounded NDJSON without polling", js.include?("/api/v1/voice/synthesize-stream") && !js.match?(/WebSocket|EventSource|setInterval/))

abort "Voice synthesis A1 verification failed: #{errors.join(', ')}" unless errors.empty?
puts "Voice synthesis A1 expressive candidate verification passed."
