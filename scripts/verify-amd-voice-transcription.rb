#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/bounded_command_runner"
require_relative "../lib/soul_core/amd_voice_transcription_service"

errors = []
check = lambda do |name, condition|
  puts "#{condition ? 'PASS' : 'FAIL'}: #{name}"
  errors << name unless condition
end

class AmdFixtureCoordinator
  attr_reader :calls

  def initialize(receipt: { "transaction" => "fixture", "restored" => true }, failure: nil)
    @receipt = receipt
    @failure = failure
    @calls = 0
  end

  def run
    @calls += 1
    raise @failure if @failure

    value = yield
    [value, @receipt]
  end
end

class AmdFixtureRunner
  attr_reader :commands, :options, :temporary_directories
  attr_accessor :proof, :proof_gpu, :proof_backend, :status, :pcm, :omit_output, :cancel

  def initialize
    @commands = []
    @options = []
    @temporary_directories = []
    @proof = true
    @proof_gpu = SoulCore::AmdVoiceTranscriptionService::CANDIDATE_GPU_NAME
    @proof_backend = "Vulkan0"
    @status = "ok"
    @pcm = "\x01\x00".b
    @omit_output = false
    @cancel = false
  end

  def which(name) = "/fixture/#{name}"

  def run(*command, **kwargs)
    argv = command.flatten.map(&:to_s)
    @commands << argv
    @options << kwargs
    raise Interrupt, "fixture cancellation" if @cancel && File.basename(argv.first) == "whisper-cli"

    status = @status
    if argv.first == "ffprobe"
      @temporary_directories << File.dirname(argv.last)
      result(status, stdout: "2.4")
    elsif argv.first == "ffmpeg"
      if argv.include?("-f")
        File.binwrite(argv.last, @pcm) if status == "ok"
      else
        File.binwrite(argv.last, "RIFF-fixture") if status == "ok"
      end
      result(status)
    elsif File.basename(argv.first) == "whisper-cli"
      output = argv.fetch(argv.index("--output-file") + 1)
      unless @omit_output
        File.write("#{output}.json", JSON.generate("transcription" => [{ "text" => " Move the fixture to Trash. " }])) if status == "ok"
      end
      stderr = if @proof
                  "Device 0: #{@proof_gpu}\nusing #{@proof_backend} backend\n"
                else
                  ""
                end
      result(status, stderr: stderr)
    else
      result("failed")
    end
  end

  private

  def result(status, stdout: "", stderr: "")
    SoulCore::BoundedCommandRunner::Result.new(
      stdout: stdout, stderr: stderr, exit_status: status == "ok" ? 0 : 1,
      status: status, truncated: false
    )
  end
end

class AmdFixtureService < SoulCore::AmdVoiceTranscriptionService
  # The fixture intentionally avoids fabricating the pinned 1.6 GB model and
  # real CLI/library digests. Blocker behavior is tested on the concrete adapter.
  def environment_blockers = []
end

Dir.mktmpdir("soul-amd-voice-test-") do |root|
  candidate = File.join(root, "candidate")
  bin = File.join(candidate, "bin")
  FileUtils.mkdir_p(bin)
  File.write(File.join(bin, "whisper-cli"), "fixture-cli")
  File.chmod(0o700, File.join(bin, "whisper-cli"))
  File.write(File.join(bin, "libggml-vulkan.so.0.15.1"), "fixture-vulkan")
  File.write(File.join(bin, "libwhisper.so.1.9.1"), "fixture-whisper")
  File.write(File.join(candidate, SoulCore::AmdVoiceTranscriptionService::CANDIDATE_MODEL), "fixture-model")

  manifest = File.join(root, "manifest.json")
  File.write(manifest, JSON.generate(
    "schema_version" => "soul.music_transcription.models.v1",
    "runtime" => { "name" => "whisper.cpp", "release" => "fixture-v1", "binary" => "whisper-cli" },
    "models" => { "fixture.bin" => { "bytes" => 1, "sha256" => Digest::SHA256.hexdigest("x"), "language" => "en" } }
  ))

  base_args = { root: root, music_root: root, manifest_path: manifest, runner: AmdFixtureRunner.new }

  begin
    SoulCore::AmdVoiceTranscriptionService.new(candidate_directory: "relative/candidate", coordinator: AmdFixtureCoordinator.new, **base_args)
    check.call("relative candidate directories are rejected", false)
  rescue ArgumentError => error
    check.call("relative candidate directories are rejected", error.message.include?("absolute"))
  end

  begin
    SoulCore::AmdVoiceTranscriptionService.new(candidate_directory: candidate, coordinator: nil, **base_args)
    check.call("coordinator injection is mandatory", false)
  rescue ArgumentError => error
    check.call("coordinator injection is mandatory", error.message.include?("coordinator"))
  end

  blocked = SoulCore::AmdVoiceTranscriptionService.new(candidate_directory: candidate, coordinator: AmdFixtureCoordinator.new, **base_args)
  blocked_status = blocked.status
  check.call("GPU-required native library digest and loader binding are checked", blocked_status.dig("data", "message").include?("GPU-required Whisper library digest does not match") && blocked_status.dig("data", "message").include?("Whisper loader link"))
  check.call("AMD candidate release and artifact pins are exact", SoulCore::AmdVoiceTranscriptionService::CANDIDATE_RELEASE == "whisper-v1.9.1-vulkan-rx6900xt-20260905" && SoulCore::AmdVoiceTranscriptionService::CANDIDATE_MODEL == "ggml-large-v3-turbo.bin" && SoulCore::AmdVoiceTranscriptionService::CANDIDATE_MODEL_BYTES == 1_624_555_275 && SoulCore::AmdVoiceTranscriptionService::CANDIDATE_MODEL_SHA256 == "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69" && SoulCore::AmdVoiceTranscriptionService::CANDIDATE_BINARY_SHA256 == "551c5df9f0f86eadc091ef87afa7941703f2a2e27ee9a988492249d089025a5e" && SoulCore::AmdVoiceTranscriptionService::CANDIDATE_VULKAN_LIBRARY_SHA256 == "5bf24ff73444dbf162d2f0c64ded3fd63848942898bfe6b062b240977cd2af78")
  check.call("pinned candidate hashes and model bytes are checked before use", !blocked_status["ok"] && blocked_status.dig("data", "message").include?("digest"))
  check.call("Vulkan status identifies the exact candidate GPU without starting work", blocked_status.dig("data", "runtime", "gpu") == SoulCore::AmdVoiceTranscriptionService::CANDIDATE_GPU_NAME && blocked_status.dig("data", "runtime", "resident_after_completion") == false)

  runner = AmdFixtureRunner.new
  coordinator = AmdFixtureCoordinator.new
  service = AmdFixtureService.new(candidate_directory: candidate, coordinator: coordinator, **base_args.merge(runner: runner))
  completed = service.transcribe(audio_bytes: "bounded-webm-fixture".b, content_type: "audio/webm;codecs=opus")
  check.call("coordinator wraps one bounded Vulkan recognition", completed["ok"] && coordinator.calls == 1)
  check.call("Vulkan recognition returns an editable transcript and handoff receipt", completed.dig("data", "transcript") == "Move the fixture to Trash." && completed.dig("data", "runtime", "handoff", "transaction") == "fixture")
  whisper_command = runner.commands.find { |argv| File.basename(argv.first) == "whisper-cli" }
  whisper_options = runner.options[runner.commands.index(whisper_command)]
  check.call("candidate CLI is pinned to device zero with GPU output enabled", whisper_command.include?("--device") && whisper_command.include?("0") && whisper_command.include?("--output-json-full") && !whisper_command.include?("--no-gpu") && !whisper_command.include?("--no-prints"))
  check.call("AMD Vulkan environment is isolated and conflicting ICD selection is cleared", whisper_options.dig(:env, "VK_DRIVER_FILES") == "/usr/share/vulkan/icd.d/radeon_icd.json" && whisper_options.dig(:env, "GGML_VK_VISIBLE_DEVICES") == "0" && whisper_options.dig(:env, "LD_LIBRARY_PATH") == File.join(candidate, "bin") && whisper_options.dig(:env, "VK_ICD_FILENAMES").nil?)
  check.call("recognition keeps the existing 180-second bound", whisper_options[:timeout_seconds] == SoulCore::VoiceTranscriptionService::TRANSCRIPTION_TIMEOUT_SECONDS)
  check.call("request-private audio is removed after Vulkan recognition", runner.temporary_directories.all? { |path| !File.exist?(path) })

  runner.proof = false
  before = runner.commands.count { |argv| File.basename(argv.first) == "whisper-cli" }
  unproven = service.transcribe(audio_bytes: "missing-proof".b, content_type: "audio/wav")
  check.call("missing Vulkan0 proof fails closed without CPU fallback", unproven["lifecycle_state"] == "failed" && runner.commands.count { |argv| File.basename(argv.first) == "whisper-cli" } == before + 1)
  check.call("failed Vulkan proof still removes request-private audio", runner.temporary_directories.all? { |path| !File.exist?(path) })

  runner.proof = true
  runner.proof_backend = "CUDA0"
  wrong_backend = service.transcribe(audio_bytes: "wrong-backend".b, content_type: "audio/wav")
  check.call("wrong backend proof fails closed", wrong_backend["lifecycle_state"] == "failed")
  runner.proof_backend = "Vulkan0"
  runner.proof_gpu = "AMD Radeon RX 6800 XT"
  wrong_gpu = service.transcribe(audio_bytes: "wrong-gpu".b, content_type: "audio/wav")
  check.call("wrong AMD GPU proof fails closed", wrong_gpu["lifecycle_state"] == "failed")
  runner.proof_gpu = SoulCore::AmdVoiceTranscriptionService::CANDIDATE_GPU_NAME

  runner.status = "timeout"
  timed_out = service.transcribe(audio_bytes: "timeout-fixture".b, content_type: "audio/wav")
  check.call("bounded runner timeout is surfaced as a failed lifecycle", timed_out["lifecycle_state"] == "failed")
  check.call("timeout cleanup removes request-private audio", runner.temporary_directories.all? { |path| !File.exist?(path) })
  check.call("a failed new invocation clears the prior handoff receipt", !service.status.dig("data", "runtime").key?("handoff"))

  runner.status = "ok"
  runner.omit_output = true
  missing_output = service.transcribe(audio_bytes: "missing-output".b, content_type: "audio/wav")
  check.call("missing JSON output fails safely", missing_output["lifecycle_state"] == "failed")
  check.call("output failure cleanup removes request-private audio", runner.temporary_directories.all? { |path| !File.exist?(path) })
  runner.omit_output = false

  coordinator_failure = AmdFixtureService.new(
    candidate_directory: candidate,
    coordinator: AmdFixtureCoordinator.new(failure: RuntimeError.new("coordinator fixture failure")),
    **base_args.merge(runner: runner)
  )
  failed_coordinator = coordinator_failure.transcribe(audio_bytes: "coordinator-failure".b, content_type: "audio/wav")
  check.call("coordinator failure is surfaced as a failed lifecycle", failed_coordinator["lifecycle_state"] == "failed" && failed_coordinator.dig("data", "message").include?("coordinator fixture failure"))
  check.call("coordinator failure cleanup removes request-private audio", runner.temporary_directories.all? { |path| !File.exist?(path) })

  runner.pcm = "\x00\x00".b
  previous_calls = coordinator.calls
  silent = service.transcribe(audio_bytes: "silence-fixture", content_type: "audio/wav")
  check.call("digital silence never initiates a runtime handoff", silent["lifecycle_state"] == "awaiting_input" && coordinator.calls == previous_calls)
  runner.pcm = "\x01\x00".b

  unrestored = AmdFixtureService.new(
    candidate_directory: candidate,
    coordinator: AmdFixtureCoordinator.new(receipt: { "transaction" => "fixture", "restored" => false }),
    **base_args.merge(runner: runner)
  )
  not_restored = unrestored.transcribe(audio_bytes: "unrestored-fixture".b, content_type: "audio/wav")
  check.call("an un-restored handoff cannot return a transcript", not_restored["lifecycle_state"] == "failed" && !not_restored["ok"])
  check.call("un-restored handoff cleanup removes request-private audio", runner.temporary_directories.all? { |path| !File.exist?(path) })

  runner.cancel = true
  begin
    service.transcribe(audio_bytes: "cancel-fixture".b, content_type: "audio/wav")
    check.call("cancellation is propagated from the bounded runner", false)
  rescue Interrupt => error
    check.call("cancellation is propagated from the bounded runner", error.message == "fixture cancellation")
  end
  check.call("cancellation cleanup removes request-private audio", runner.temporary_directories.all? { |path| !File.exist?(path) })

  unsafe_candidate = File.join(root, "unsafe-candidate")
  FileUtils.mkdir_p(unsafe_candidate)
  File.symlink(bin, File.join(unsafe_candidate, "bin"))
  File.write(File.join(unsafe_candidate, SoulCore::AmdVoiceTranscriptionService::CANDIDATE_MODEL), "fixture-model")
  unsafe = SoulCore::AmdVoiceTranscriptionService.new(candidate_directory: unsafe_candidate, coordinator: AmdFixtureCoordinator.new, **base_args)
  unsafe_status = unsafe.status
  check.call("symlinked candidate bin directories are rejected", !unsafe_status["ok"] && unsafe_status.dig("data", "message").include?("bin directory is missing or unsafe"))
end

abort "AMD Vulkan voice transcription verification failed: #{errors.join(', ')}" unless errors.empty?
puts "AMD Vulkan voice transcription candidate verification passed."
