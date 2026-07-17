#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/music_candidate_analysis_service"

failures = []
check = ->(name, value) { puts "- #{name}: #{value ? 'ok' : 'FAILED'}"; failures << name unless value }

Dir.mktmpdir("soul-vocal-analysis") do |root|
  install = File.join(root, "runtime", "transcription", "v-test")
  FileUtils.mkdir_p(install)
  binary = File.join(install, "whisper-cli"); File.write(binary, "#!/bin/sh\n", mode: "wx", perm: 0o700)
  model = File.join(install, "test.en.bin"); File.binwrite(model, "pinned-model")
  manifest = File.join(root, "manifest.json")
  File.write(manifest, JSON.generate({ "runtime" => { "name" => "whisper.cpp", "release" => "v-test", "binary" => "whisper-cli" }, "models" => { "test.en.bin" => { "bytes" => File.size(model), "sha256" => Digest::SHA256.file(model).hexdigest, "language" => "en" } } }))
  store = SoulCore::MusicProjectStore.new(root: root, id_generator: -> { "1" * 16 })
  project = store.create("title"=>"Test", "intent"=>"bounded", "target_duration_seconds"=>30, "vocal_mode"=>"vocal", "rights_status"=>"original", "caption"=>"test", "lyrics"=>"[Verse]\nFirst line present\nSecond line missing", "bpm"=>100, "keyscale"=>"C minor", "timesignature"=>"4", "language"=>"en", "seed"=>1)
  candidate = "candidate_#{'2' * 16}"; candidate_dir = File.join(store.generations_path(project.fetch("project_id")), candidate); Dir.mkdir(candidate_dir)
  File.write(File.join(candidate_dir, "candidate.json"), "{}", mode: "wx"); File.binwrite(File.join(candidate_dir, "master.flac"), "audio")
  fake = Object.new
  fake.define_singleton_method(:run) do |command, **_options|
    base = command[command.index("--output-file") + 1]
    File.write("#{base}.json", JSON.generate({ "transcription" => [{ "offsets" => { "from" => 1000, "to" => 2000 }, "text" => "First line present" }] }))
    SoulCore::MusicGenerationService::ProcessResult.new(status: "ok", stdout: "progress = 100%", stderr: "", exit_status: 0, pid: 123)
  end
  service = SoulCore::MusicCandidateAnalysisService.new(root: root, music_root: File.join(root, "runtime"), manifest_path: manifest, project_store: store, process_runner: fake)
  preview = service.preview(project_id: project.fetch("project_id"), candidate_id: candidate)
  scope = preview.dig("data", "preview_scope")
  check.call("preview declares a bounded nonresident CPU operation", scope["resource_lane"] == "cpu-foreground" && scope["persistent_service"] == false && scope["automatic_retry"] == false && scope["automatic_revision"] == false)
  bad_confirmation = service.execute(project_id: project.fetch("project_id"), candidate_id: candidate, confirmation: "wrong", expected_digest: preview.dig("data", "expected_digest"))
  check.call("exact confirmation gate cannot be weakened", bad_confirmation["ok"] == false && bad_confirmation["lifecycle_state"] == "blocked_for_human_review")
  result = service.execute(project_id: project.fetch("project_id"), candidate_id: candidate, confirmation: preview.dig("data", "confirmation_phrase"), expected_digest: preview.dig("data", "expected_digest"))
  evidence = result.dig("data", "analysis")
  check.call("machine BAD routes to an Operator-triggered revision attempt", evidence["machine_route"] == "revision_recommended" && evidence["next_gate"] == "operator_triggered_revision_attempt")
  check.call("successful evidence remains blocked for human review", result["lifecycle_state"] == "blocked_for_human_review" && evidence["disclaimer"].include?("never constitutes human approval"))
  check.call("candidate-local evidence can be read without a resident model", service.read(project_id: project.fetch("project_id"), candidate_id: candidate)["machine_heard_lyrics"] == "First line present")
  check.call("machine-heard evidence is formatted as a lyric sheet", evidence["machine_heard_formatted"] == "First line present")
end

source = File.read(File.expand_path("../lib/soul_core/music_candidate_analysis_service.rb", __dir__))
check.call("runtime is CPU-only, bounded, and process-group managed", source.include?("--no-gpu") && source.include?("TIMEOUT_SECONDS = 360") && source.include?("ForegroundProcessRunner"))
installer = File.read(File.expand_path("../scripts/soul-music-transcription", __dir__))
check.call("installer retains only the foreground CLI and required libraries", installer.include?('name == "whisper-cli"') && installer.include?('name.start_with?("libwhisper")') && !installer.include?("whisper-server"))
dashboard = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
check.call("dashboard exposes exact analysis preview and comparison", dashboard.include?("ANALYZE_MUSIC_CANDIDATE") == false && dashboard.include?("music.candidates.analysis.preview") && dashboard.include?("music-lyric-compare"))
check.call("existing evidence receives formatted line and stanza breaks without re-analysis", dashboard.include?("formatMachineHeardLyrics") && dashboard.include?("machine_heard_formatted"))
check.call("BAD routing requests a Soul draft but preserves editable exact generation gates", dashboard.include?("Ask Soul to draft revision") && dashboard.include?("music.candidates.revision.draft") && dashboard.include?("music.candidates.revision.preview") && dashboard.include?("music.candidates.revision.execute") && dashboard.include?("Preview exact revision"))

abort "Music vocal-analysis verification failed: #{failures.join(', ')}" unless failures.empty?
puts "Music Studio A3 vocal-analysis deterministic verification passed."
