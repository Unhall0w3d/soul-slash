#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/bounded_command_runner"
require_relative "../lib/soul_core/cuda_voice_transcription_service"

errors = []
check = lambda do |name, condition|
  puts "#{condition ? 'PASS' : 'FAIL'}: #{name}"
  errors << name unless condition
end

class CudaFixtureCoordinator
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

class CudaFixtureRunner
  attr_reader :commands, :options, :temporary_directories
  attr_accessor :proof, :status, :pcm

  def initialize
    @commands = []
    @options = []
    @temporary_directories = []
    @proof = true
    @status = "ok"
    @pcm = "\x01\x00".b
  end

  def which(name) = "/fixture/#{name}"

  def run(*command, **kwargs)
    argv = command.flatten.map(&:to_s)
    @commands << argv
    @options << kwargs
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
      File.write("#{output}.json", JSON.generate("transcription" => [{ "text" => " Move the fixture to Trash. " }])) if status == "ok"
      stderr = @proof ? "Device 0: NVIDIA GeForce GTX 1070, compute capability 6.1\nusing CUDA0 backend\n" : ""
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

class CudaFixtureService < SoulCore::CudaVoiceTranscriptionService
  # The fixture intentionally avoids fabricating the pinned 1.6 GB model and
  # real CLI digest. Blocker behavior is tested on the concrete adapter below.
  def environment_blockers = []
end

Dir.mktmpdir("soul-cuda-voice-test-") do |root|
  candidate = File.join(root, "candidate")
  bin = File.join(candidate, "bin")
  FileUtils.mkdir_p(bin)
  File.write(File.join(bin, "whisper-cli"), "fixture-cli")
  File.chmod(0o700, File.join(bin, "whisper-cli"))
  File.write(File.join(bin, "libggml-cuda.so.0.15.1"), "fixture-cuda")
  File.write(File.join(candidate, SoulCore::CudaVoiceTranscriptionService::CANDIDATE_MODEL), "fixture-model")

  manifest = File.join(root, "manifest.json")
  File.write(manifest, JSON.generate(
    "schema_version" => "soul.music_transcription.models.v1",
    "runtime" => { "name" => "whisper.cpp", "release" => "fixture-v1", "binary" => "whisper-cli" },
    "models" => { "fixture.bin" => { "bytes" => 1, "sha256" => Digest::SHA256.hexdigest("x"), "language" => "en" } }
  ))

  uuid = "GPU-92d94102-e241-1a40-62c5-832d60874aab"
  base_args = { root: root, music_root: root, manifest_path: manifest, runner: CudaFixtureRunner.new }

  begin
    SoulCore::CudaVoiceTranscriptionService.new(candidate_directory: "relative/candidate", gpu_uuid: uuid, coordinator: CudaFixtureCoordinator.new, **base_args)
    check.call("relative candidate directories are rejected", false)
  rescue ArgumentError => error
    check.call("relative candidate directories are rejected", error.message.include?("absolute"))
  end

  begin
    SoulCore::CudaVoiceTranscriptionService.new(candidate_directory: candidate, gpu_uuid: uuid, coordinator: nil, **base_args)
    check.call("coordinator injection is mandatory", false)
  rescue ArgumentError => error
    check.call("coordinator injection is mandatory", error.message.include?("coordinator"))
  end

  blocked = SoulCore::CudaVoiceTranscriptionService.new(candidate_directory: candidate, gpu_uuid: uuid, coordinator: CudaFixtureCoordinator.new, **base_args)
  blocked_status = blocked.status
  check.call("pinned candidate hashes and model bytes are checked before use", !blocked_status["ok"] && blocked_status.dig("data", "message").include?("digest"))
  check.call("CUDA status identifies the exact candidate GPU without starting work", blocked_status.dig("data", "runtime", "gpu_uuid") == uuid && blocked_status.dig("data", "runtime", "resident_after_completion") == false)

  runner = CudaFixtureRunner.new
  coordinator = CudaFixtureCoordinator.new
  service = CudaFixtureService.new(candidate_directory: candidate, gpu_uuid: uuid, coordinator: coordinator, **base_args.merge(runner: runner))
  completed = service.transcribe(audio_bytes: "bounded-webm-fixture".b, content_type: "audio/webm;codecs=opus")
  check.call("coordinator wraps one bounded CUDA recognition", completed["ok"] && coordinator.calls == 1)
  check.call("CUDA recognition returns an editable transcript and handoff receipt", completed.dig("data", "transcript") == "Move the fixture to Trash." && completed.dig("data", "runtime", "handoff", "transaction") == "fixture")
  whisper_command = runner.commands.find { |argv| File.basename(argv.first) == "whisper-cli" }
  whisper_options = runner.options[runner.commands.index(whisper_command)]
  check.call("candidate CLI is pinned to device zero with flash attention disabled", whisper_command.include?("--device") && whisper_command.include?("0") && whisper_command.include?("--no-flash-attn") && whisper_command.include?("--output-json-full") && !whisper_command.include?("--no-prints"))
  check.call("CUDA UUID and candidate libraries are isolated in the child environment", whisper_options.dig(:env, "CUDA_VISIBLE_DEVICES") == uuid && whisper_options.dig(:env, "LD_LIBRARY_PATH") == File.join(candidate, "bin"))
  check.call("recognition keeps the existing 180-second bound", whisper_options[:timeout_seconds] == SoulCore::VoiceTranscriptionService::TRANSCRIPTION_TIMEOUT_SECONDS)
  check.call("request-private audio is removed after CUDA recognition", runner.temporary_directories.all? { |path| !File.exist?(path) })

  runner.proof = false
  before = runner.commands.count { |argv| File.basename(argv.first) == "whisper-cli" }
  unproven = service.transcribe(audio_bytes: "missing-proof".b, content_type: "audio/wav")
  check.call("missing CUDA0 and GTX 1070 proof fails closed without CPU fallback", unproven["lifecycle_state"] == "failed" && runner.commands.count { |argv| File.basename(argv.first) == "whisper-cli" } == before + 1)
  check.call("failed CUDA proof still removes request-private audio", runner.temporary_directories.all? { |path| !File.exist?(path) })

  runner.proof = true
  runner.status = "timeout"
  timed_out = service.transcribe(audio_bytes: "timeout-fixture".b, content_type: "audio/wav")
  check.call("bounded runner timeout is surfaced as a failed lifecycle", timed_out["lifecycle_state"] == "failed")
  check.call("timeout cleanup removes request-private audio", runner.temporary_directories.all? { |path| !File.exist?(path) })
  check.call("a failed new invocation clears the prior handoff receipt", !service.status.dig("data", "runtime").key?("handoff"))

  runner.status = "ok"
  runner.pcm = "\x00\x00".b
  previous_calls = coordinator.calls
  silent = service.transcribe(audio_bytes: "silence-fixture", content_type: "audio/wav")
  check.call("digital silence never initiates a runtime handoff", silent["lifecycle_state"] == "awaiting_input" && coordinator.calls == previous_calls)
  runner.pcm = "\x01\x00".b
  unrestored = CudaFixtureService.new(
    candidate_directory: candidate, gpu_uuid: uuid,
    coordinator: CudaFixtureCoordinator.new(receipt: { "transaction" => "fixture", "restored" => false }),
    **base_args.merge(runner: runner)
  )
  not_restored = unrestored.transcribe(audio_bytes: "unrestored-fixture".b, content_type: "audio/wav")
  check.call("an un-restored handoff cannot return a transcript", not_restored["lifecycle_state"] == "failed" && !not_restored["ok"])
  check.call("un-restored handoff cleanup removes request-private audio", runner.temporary_directories.all? { |path| !File.exist?(path) })

  unsafe_candidate = File.join(root, "unsafe-candidate")
  FileUtils.mkdir_p(unsafe_candidate)
  File.symlink(bin, File.join(unsafe_candidate, "bin"))
  File.write(File.join(unsafe_candidate, SoulCore::CudaVoiceTranscriptionService::CANDIDATE_MODEL), "fixture-model")
  unsafe = SoulCore::CudaVoiceTranscriptionService.new(candidate_directory: unsafe_candidate, gpu_uuid: uuid, coordinator: CudaFixtureCoordinator.new, **base_args)
  unsafe_status = unsafe.status
  check.call("symlinked candidate bin directories are rejected", !unsafe_status["ok"] && unsafe_status.dig("data", "message").include?("bin directory is missing or unsafe"))
end

abort "CUDA voice transcription verification failed: #{errors.join(', ')}" unless errors.empty?
puts "CUDA voice transcription candidate verification passed."
