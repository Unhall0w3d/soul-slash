#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/music_generation_service"

failures = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'FAILED'}"
  failures << label unless condition
end

FakeResult = Struct.new(:stdout, :stderr, :exit_status, :status, :truncated, keyword_init: true) do
  def success? = status == "ok"
end

class A2Runner
  attr_accessor :fallback_state, :compute_processes
  attr_reader :commands

  def initialize(duration: 30)
    @duration = duration
    @fallback_state = "inactive"
    @compute_processes = ""
    @commands = []
  end

  def which(name) = "/usr/bin/#{name}"

  def run(*command, **_options)
    @commands << command
    case command.join(" ")
    when /systemctl --user is-active/
      result(@fallback_state, @fallback_state == "active" ? "ok" : "failed")
    when /nvidia-smi --query-gpu=memory.free/
      result("7900\n")
    when /nvidia-smi --query-compute-apps/
      result(@compute_processes)
    when /curl .*health/
      result('{"status":"ok"}')
    when /git rev-parse HEAD/
      result("#{'d' * 40}\n")
    when /ffprobe/
      codec = command.last.end_with?(".mp3") ? "mp3" : "flac"
      result(JSON.generate("streams" => [{ "codec_name" => codec, "sample_rate" => "48000", "channels" => 2 }], "format" => { "duration" => @duration.to_f.to_s }))
    when /volumedetect/
      FakeResult.new(stdout: "", stderr: "mean_volume: -15.0 dB\nmax_volume: -1.0 dB\n", exit_status: 0, status: "ok", truncated: false)
    else
      result("")
    end
  end

  private

  def result(stdout, status = "ok")
    FakeResult.new(stdout: stdout, stderr: "", exit_status: status == "ok" ? 0 : 3, status: status, truncated: false)
  end
end

class A2Coordinator
  attr_reader :attached, :released

  def inventory
    { "schema_version" => "soul.music.resource_inventory.v1", "lifecycle_state" => "complete", "blockers" => [], "can_acquire_nvidia_music" => true }
  end

  def acquire(project_id:, candidate_id:, input_digest:, ttl_seconds:)
    @lease = { "lease_id" => "music_lease_1111111111111111", "project_id" => project_id, "candidate_id" => candidate_id, "input_digest" => input_digest, "ttl" => ttl_seconds }
  end

  def attach_child(lease_id:, child_pid:, process_group_id:)
    @attached ||= []
    @attached << [lease_id, child_pid, process_group_id]
  end

  def cancellation_requested?(_lease_id) = false
  def release(lease_id) = (@released = lease_id)
  def cancel_preview(candidate_id:) = { "ok" => true, "lifecycle_state" => "blocked_for_human_review", "data" => { "candidate_id" => candidate_id } }
  def cancel_execute(candidate_id:, confirmation:, expected_digest:) = { "ok" => true, "lifecycle_state" => "canceled", "data" => { "candidate_id" => candidate_id, "confirmation" => confirmation, "expected_digest" => expected_digest } }
end

class A2ProcessRunner
  attr_reader :calls

  def initialize
    @calls = []
  end

  def run(command, env:, chdir:, timeout_seconds:, max_output_bytes:, on_spawn:, canceled:)
    @calls << { command: command, env: env, chdir: chdir, timeout: timeout_seconds, max: max_output_bytes }
    pid = 41_000 + @calls.length
    on_spawn.call(pid, pid)
    if command.first.end_with?("python")
      output = File.join(env.fetch("TMPDIR"), "acestep_profile_fixture")
      FileUtils.mkdir_p(output)
      File.binwrite(File.join(output, "generated.flac"), "fixture flac audio")
      SoulCore::MusicGenerationService::ProcessResult.new(status: "ok", stdout: "Success! Generated 1 audio(s)\n", stderr: "", exit_status: 0, pid: pid)
    else
      File.binwrite(command.last, "fixture mp3 audio")
      SoulCore::MusicGenerationService::ProcessResult.new(status: canceled.call ? "canceled" : "ok", stdout: "", stderr: "", exit_status: 0, pid: pid)
    end
  end
end

class A2FailProcessRunner
  attr_reader :calls

  def initialize = (@calls = [])

  def run(command, env:, chdir:, timeout_seconds:, max_output_bytes:, on_spawn:, canceled:)
    @calls << { command: command, env: env, chdir: chdir, timeout: timeout_seconds, max: max_output_bytes }
    on_spawn.call(43_001, 43_001)
    SoulCore::MusicGenerationService::ProcessResult.new(status: canceled.call ? "canceled" : "failed", stdout: "", stderr: "fixture generation failure", exit_status: 1, pid: 43_001)
  end
end

def project_input
  {
    "title" => "A2 fixture",
    "intent" => "Validate a bounded Soul-native project.",
    "target_duration_seconds" => 30,
    "vocal_mode" => "vocal",
    "rights_status" => "original",
    "caption" => "Energetic melodic rock with clear drums and guitars.",
    "lyrics" => "[Verse]\nA new signal wakes",
    "bpm" => 120,
    "keyscale" => "E minor",
    "timesignature" => "4",
    "language" => "en",
    "seed" => 1701
  }
end

Dir.mktmpdir("soul-music-a2-") do |root|
  music_root = File.join(root, "installed-music")
  source = File.join(music_root, "ace-step", "v0.1.8")
  FileUtils.mkdir_p(File.join(source, ".git"))
  FileUtils.mkdir_p(File.join(source, ".venv", "bin"))
  FileUtils.mkdir_p(File.join(source, "acestep", "core", "generation", "handler"))
  python = File.join(source, ".venv", "bin", "python")
  File.write(python, "#!/bin/sh\nexit 0\n")
  File.chmod(0o700, python)
  File.write(File.join(source, "acestep", "core", "generation", "handler", "init_service_orchestrator.py"), "SOUL_PASCAL_FP32_OVERLAY_V1\n")
  File.write(File.join(source, "acestep", "core", "generation", "handler", "init_service_downloads.py"), "SOUL_STRICT_OFFLINE_OVERLAY_V1\n")
  File.write(File.join(source, "profile_inference.py"), "SOUL_RETAIN_OUTPUT_OVERLAY_V2\n")
  dit_bytes = "dit fixture"
  lm_bytes = "lm fixture"
  FileUtils.mkdir_p(File.join(source, "checkpoints", "acestep-5Hz-lm-0.6B"))
  File.binwrite(File.join(source, "checkpoints", "dit.bin"), dit_bytes)
  File.binwrite(File.join(source, "checkpoints", "acestep-5Hz-lm-0.6B", "lm.bin"), lm_bytes)
  manifest = {
    "source" => { "release" => "v0.1.8", "revision" => "d" * 40 },
    "dit_models" => { "acestep-v15-turbo" => { "files" => [["dit.bin", dit_bytes.bytesize, Digest::SHA256.hexdigest(dit_bytes)]] } },
    "lm_models" => { "acestep-5Hz-lm-0.6B" => { "files" => [["lm.bin", lm_bytes.bytesize, Digest::SHA256.hexdigest(lm_bytes)]] } }
  }
  manifest_path = File.join(root, "manifest.json")
  File.write(manifest_path, JSON.generate(manifest))
  runner = A2Runner.new
  coordinator = A2Coordinator.new
  process_runner = A2ProcessRunner.new
  ids = %w[1111111111111111 2222222222222222 3333333333333333 4444444444444444]
  store = SoulCore::MusicProjectStore.new(root: root, id_generator: -> { ids.shift || "5555555555555555" }, clock: -> { Time.utc(2026, 7, 17, 20, 0, 0) })
  service = SoulCore::MusicGenerationService.new(root: root, music_root: music_root, manifest_path: manifest_path, project_store: store, coordinator: coordinator, process_runner: process_runner, runner: runner, clock: -> { Time.utc(2026, 7, 17, 20, 0, 0) })

  missing_rights = service.create_project(project_input.except("rights_status"))
  unknown = service.create_project(project_input.merge("surprise" => true))
  unsupported_duration = service.create_project(project_input.merge("target_duration_seconds" => 45))
  embedded_metadata = service.create_project(project_input.merge("caption" => "Energetic melodic rock at 110 BPM in D minor and 4/4 time with clear drums and guitars."))
  check.call("project schema rejects missing rights, unknown fields, unsupported duration, and embedded caption metadata without writes", missing_rights["lifecycle_state"] == "awaiting_input" && unknown["lifecycle_state"] == "awaiting_input" && unsupported_duration["lifecycle_state"] == "awaiting_input" && unsupported_duration["reason"].include?("30, 90, or 180") && embedded_metadata["lifecycle_state"] == "awaiting_input" && embedded_metadata["reason"].include?("dedicated field") && !File.exist?(File.join(root, "Soul", "music", "projects")))

  created = service.create_project(project_input)
  project = created.dig("data", "project")
  project_id = project.fetch("project_id")
  record_path = File.join(root, "Soul", "music", "projects", project_id, "project.json")
  check.call("project creation is owner-private, typed, and terminal", created["lifecycle_state"] == "complete" && project["schema_version"] == "soul.music.project.v1" && (File.stat(File.dirname(record_path)).mode & 0o777) == 0o700 && (File.stat(record_path).mode & 0o777) == 0o600)

  preview = service.generation_preview(project_id: project_id)
  candidate_id = preview.dig("data", "candidate_id")
  check.call("generation preview is read-only and exact-confirmation gated", preview["lifecycle_state"] == "blocked_for_human_review" && preview.dig("data", "confirmation_phrase") == "START_MUSIC_GENERATION" && preview.dig("data", "expected_digest").match?(/\A[a-f0-9]{64}\z/) && process_runner.calls.empty?)

  wrong = service.generation_execute(project_id: project_id, candidate_id: candidate_id, confirmation: "yes", expected_digest: preview.dig("data", "expected_digest"))
  check.call("wrong generation confirmation starts no process and creates no staging", wrong["lifecycle_state"] == "blocked_for_human_review" && process_runner.calls.empty? && Dir.children(store.generations_path(project_id)).empty?)

  generated = service.generation_execute(project_id: project_id, candidate_id: candidate_id, confirmation: "START_MUSIC_GENERATION", expected_digest: preview.dig("data", "expected_digest"))
  receipt = generated.dig("data", "candidate")
  candidate_path = generated.dig("data", "candidate_path")
  check.call("one foreground model run derives linked FLAC and MP3 artifacts", generated["lifecycle_state"] == "blocked_for_human_review" && process_runner.calls.length == 2 && receipt.dig("artifacts", "flac", "codec") == "flac" && receipt.dig("artifacts", "mp3", "codec") == "mp3" && receipt.dig("artifacts", "mp3", "derived_from_sha256") == receipt.dig("artifacts", "flac", "sha256"))
  check.call("candidate receipt is atomic, review-gated, and lease is released", File.file?(File.join(candidate_path, "candidate.json")) && !File.exist?(File.join(store.generations_path(project_id), ".#{candidate_id}.partial")) && receipt["human_review_required"] && coordinator.released == "music_lease_1111111111111111")
  check.call("generation uses strict offline project input and LAME V2", process_runner.calls.first.dig(:env, "HF_HUB_OFFLINE") == "1" && process_runner.calls.first[:command].include?(File.join(candidate_path.sub(candidate_id, ".#{candidate_id}.partial"), "input.json")) && process_runner.calls.last[:command].each_cons(2).any? { |a, b| a == "-q:a" && b == "2" })

  inspected = service.inspect_project(project_id: project_id)
  check.call("project inspection exposes only published candidates", inspected["lifecycle_state"] == "complete" && inspected.dig("data", "generations").map { |item| item["candidate_id"] } == [candidate_id])

  source_input = inspected.dig("data", "generations", 0, "generation_input")
  seed_only = service.revision_preview(project_id: project_id, source_candidate_id: candidate_id, revision: {
    "caption" => source_input.fetch("caption"), "lyrics" => source_input.fetch("lyrics"), "bpm" => source_input.fetch("bpm"),
    "keyscale" => source_input.fetch("keyscale"), "timesignature" => source_input.fetch("timesignature"), "seed" => source_input.fetch("seed") + 1
  })
  check.call("revision cannot be a seed-only retry", seed_only["lifecycle_state"] == "awaiting_input" && seed_only["reason"].include?("materially change") && process_runner.calls.length == 2)
  timed_caption = service.revision_preview(project_id: project_id, source_candidate_id: candidate_id, revision: {
    "caption" => "Verse 1 (30 sec) begins with clear drums and tightly separated vocal lines before the guitar widens.", "lyrics" => source_input.fetch("lyrics"), "bpm" => source_input.fetch("bpm"),
    "keyscale" => source_input.fetch("keyscale"), "timesignature" => source_input.fetch("timesignature"), "seed" => source_input.fetch("seed") + 2
  })
  check.call("revision rejects exact section timing from Sound and Structure", timed_caption["lifecycle_state"] == "awaiting_input" && timed_caption["reason"].include?("temporal section changes") && process_runner.calls.length == 2)

  revision = {
    "caption" => "Energetic melodic rock with an immediate two-bar vocal pickup, sparse verse one, and clearly separated lead vocal.",
    "lyrics" => source_input.fetch("lyrics"), "bpm" => 116, "keyscale" => source_input.fetch("keyscale"),
    "timesignature" => source_input.fetch("timesignature"), "seed" => 1702
  }
  revision_preview = service.revision_preview(project_id: project_id, source_candidate_id: candidate_id, revision: revision)
  revision_candidate = revision_preview.dig("data", "candidate_id")
  revision_wrong = service.revision_execute(project_id: project_id, source_candidate_id: candidate_id, candidate_id: revision_candidate, revision: revision, confirmation: "START_MUSIC_GENERATION", expected_digest: revision_preview.dig("data", "expected_digest"))
  check.call("revision preview binds changed sound and structure without starting work", revision_preview["lifecycle_state"] == "blocked_for_human_review" && revision_preview.dig("data", "confirmation_phrase") == "START_MUSIC_REVISION" && revision_preview.dig("data", "preview_scope", "changed_fields").sort == %w[bpm caption seed] && process_runner.calls.length == 2)
  check.call("revision requires its distinct exact confirmation", revision_wrong["lifecycle_state"] == "blocked_for_human_review" && process_runner.calls.length == 2)

  revised = service.revision_execute(project_id: project_id, source_candidate_id: candidate_id, candidate_id: revision_candidate, revision: revision, confirmation: "START_MUSIC_REVISION", expected_digest: revision_preview.dig("data", "expected_digest"))
  revised_receipt = revised.dig("data", "candidate")
  revised_input = store.candidate_input(project_id, revision_candidate)
  check.call("confirmed revision creates a linked candidate from the exact edited input", revised["lifecycle_state"] == "blocked_for_human_review" && process_runner.calls.length == 4 && revised_receipt["generation_kind"] == "revision" && revised_receipt["source_candidate_id"] == candidate_id && revised_input["caption"] == revision["caption"] && revised_input["bpm"] == 116)
  revised_inspection = service.inspect_project(project_id: project_id)
  check.call("revision preserves the source and candidates are newest-first", revised_inspection.dig("data", "generations").map { |item| item["candidate_id"] } == [revision_candidate, candidate_id])

  failed_runner = A2FailProcessRunner.new
  failed_service = SoulCore::MusicGenerationService.new(root: root, music_root: music_root, manifest_path: manifest_path, project_store: store, coordinator: coordinator, process_runner: failed_runner, runner: runner, clock: -> { Time.utc(2026, 7, 17, 20, 1, 0) })
  failed_preview = failed_service.generation_preview(project_id: project_id)
  failed_candidate = failed_preview.dig("data", "candidate_id")
  stale = failed_service.generation_execute(project_id: project_id, candidate_id: failed_candidate, confirmation: "START_MUSIC_GENERATION", expected_digest: "0" * 64)
  stale_no_process = failed_runner.calls.empty?
  failed = failed_service.generation_execute(project_id: project_id, candidate_id: failed_candidate, confirmation: "START_MUSIC_GENERATION", expected_digest: failed_preview.dig("data", "expected_digest"))
  quarantine = File.join(store.generations_path(project_id), ".#{failed_candidate}.partial")
  check.call("stale generation digest starts no process", stale["lifecycle_state"] == "blocked_for_human_review" && stale_no_process)
  check.call("failed foreground generation is terminal and quarantined", failed["lifecycle_state"] == "failed" && File.file?(File.join(quarantine, "failure.json")) && !File.exist?(File.join(store.generations_path(project_id), failed_candidate)) && coordinator.released == "music_lease_1111111111111111")
end

Dir.mktmpdir("soul-music-a2-legacy-duration-") do |root|
  ids = %w[7777777777777777 8888888888888888 9999999999999999]
  store = SoulCore::MusicProjectStore.new(root: root, id_generator: -> { ids.shift }, clock: -> { Time.utc(2026, 7, 17, 20, 0, 0) })
  projects = [30, 90, 180].map { |duration| store.create(project_input.merge("target_duration_seconds" => duration)) }
  check.call("all three supported duration presets create projects", projects.map { |item| item.fetch("target_duration_seconds") } == [30, 90, 180])
  project = projects.first
  record_path = File.join(store.project_path(project.fetch("project_id")), "project.json")
  legacy = JSON.parse(File.read(record_path)).merge("target_duration_seconds" => 45)
  File.write(record_path, JSON.generate(legacy))
  check.call("bounded legacy non-preset projects remain readable", store.read(project.fetch("project_id")).fetch("target_duration_seconds") == 45)
end

Dir.mktmpdir("soul-music-a2-path-") do |root|
  FileUtils.mkdir_p(File.join(root, "Soul"))
  outside = Dir.mktmpdir("soul-music-outside-")
  File.symlink(outside, File.join(root, "Soul", "music"))
  store = SoulCore::MusicProjectStore.new(root: root, id_generator: -> { "aaaaaaaaaaaaaaaa" })
  begin
    store.create(project_input)
    blocked = false
  rescue SoulCore::MusicProjectStore::IntegrityError
    blocked = true
  end
  check.call("symlinked project storage fails closed", blocked && Dir.children(outside).empty?)
ensure
  FileUtils.rm_rf(outside) if outside
end

Dir.mktmpdir("soul-music-a2-lease-") do |root|
  runner = A2Runner.new
  starts = Hash.new { |_hash, pid| "start-#{pid}" }
  signals = []
  coordinator = SoulCore::MusicResourceCoordinator.new(root: root, runner: runner, id_generator: -> { "aaaaaaaaaaaaaaaa" }, process_start: ->(pid) { starts[pid] }, signaler: ->(signal, target) { signals << [signal, target] }, sleeper: ->(_seconds) {})
  inventory = coordinator.inventory
  inventory_write_free = !File.exist?(File.join(root, "Soul", "runtime", "music"))
  lease = coordinator.acquire(project_id: "music_1111111111111111", candidate_id: "candidate_2222222222222222", input_digest: "a" * 64)
  cross_runtime = SoulCore::ModelRuntimeLeaseStore.new(root: root).active_leases
  begin
    coordinator.acquire(project_id: "music_1111111111111111", candidate_id: "candidate_3333333333333333", input_digest: "b" * 64)
    conflict = false
  rescue SoulCore::MusicResourceCoordinator::Busy
    conflict = true
  end
  coordinator.attach_child(lease_id: lease.fetch("lease_id"), child_pid: 42_424, process_group_id: 42_424)
  uncertain_observer = SoulCore::MusicResourceCoordinator.new(root: root, runner: runner, process_start: ->(_pid) { raise Errno::ESRCH })
  uncertain_inventory = uncertain_observer.inventory
  cancel = coordinator.cancel_preview(candidate_id: "candidate_2222222222222222")
  wrong = coordinator.cancel_execute(candidate_id: "candidate_2222222222222222", confirmation: "yes", expected_digest: cancel.dig("data", "expected_digest"))
  exact = coordinator.cancel_execute(candidate_id: "candidate_2222222222222222", confirmation: "CANCEL_MUSIC_GENERATION", expected_digest: cancel.dig("data", "expected_digest"))
  check.call("resource inventory is write-free and named-lane bounded", inventory["lifecycle_state"] == "complete" && inventory["can_acquire_nvidia_music"] && inventory.dig("lanes", "amd-conversation", "health") == "ok" && inventory_write_free)
  check.call("one-owner lease rejects a concurrent NVIDIA claimant", conflict)
  check.call("music lease is visible to model-runtime switching", cross_runtime.one? && cross_runtime.first["provider_id"] == "nvidia-music" && cross_runtime.first["request_id"] == "candidate_2222222222222222")
  check.call("read-only uncertain inspection cannot revoke active foreground work", uncertain_inventory.dig("lanes", "nvidia-music", "lease", "lease_id") == lease.fetch("lease_id") && SoulCore::ModelRuntimeLeaseStore.new(root: root).active_leases.one?)
  check.call("cancellation requires exact preview and signals only recorded group", wrong["lifecycle_state"] == "blocked_for_human_review" && exact["lifecycle_state"] == "canceled" && signals == [["TERM", -42_424], ["KILL", -42_424]])
  coordinator.release(lease.fetch("lease_id"))
  check.call("music release clears its cross-runtime lease", SoulCore::ModelRuntimeLeaseStore.new(root: root).active_leases.empty?)

  runner.fallback_state = "active"
  blocked_inventory = SoulCore::MusicResourceCoordinator.new(root: root, directory: File.join("Soul", "runtime", "music-blocked"), runner: runner, process_start: ->(pid) { starts[pid] }).inventory
  check.call("active NVIDIA fallback blocks music without stopping it", !blocked_inventory["can_acquire_nvidia_music"] && blocked_inventory["blockers"].include?("NVIDIA fallback service is active"))
end

source = File.read(File.join(__dir__, "soul-music-studio"))
makefile = File.read(File.join(__dir__, "..", "Makefile"))
brief = File.read(File.join(__dir__, "..", "docs", "soul", "MUSIC_STUDIO_A2_PROJECT_AND_RESOURCE_BRIEF.md"))
check.call("CLI and Make targets expose no listener, service, or queue", source.include?("generate preview") && makefile.include?("music-generate-execute") && !source.match?(/uvicorn|WEBrick|listen|daemon/) && brief.include?("No queue"))
runtime_control = File.read(File.join(__dir__, "..", "lib", "soul_core", "model_runtime_control_service.rb"))
check.call("unloaded model runtime cannot claim NVIDIA across active work", runtime_control.match?(/when "load".*active_work_count.*zero\?/m))

abort "#{failures.length} Music A2 verification(s) failed: #{failures.join(', ')}" unless failures.empty?
puts "Music Studio A2 deterministic verification passed."
