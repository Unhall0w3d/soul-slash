#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"
load File.expand_path("soul-music-vulkan-pilot", __dir__)
require_relative "../lib/soul_core/music_vulkan_generation_backend"

ROOT = File.expand_path("..", __dir__)
errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

manifest = JSON.parse(File.read(File.join(ROOT, "config/music_vulkan_models.json")))
script = File.read(File.join(ROOT, "scripts/soul-music-vulkan-pilot"))
core = File.read(File.join(ROOT, "lib/soul_core/core_orchestration_service.rb"))
backend = File.read(File.join(ROOT, "lib/soul_core/music_vulkan_generation_backend.rb"))
generation = File.read(File.join(ROOT, "lib/soul_core/music_generation_service.rb"))
brief = File.read(File.join(ROOT, "docs/soul/MUSIC_CORE_VULKAN_FEASIBILITY_BRIEF.md"))
makefile = File.read(File.join(ROOT, "Makefile"))
dashboard = File.read(File.join(ROOT, "assets/dashboard/dashboard.js"))

puts "Music Core Vulkan feasibility verification:"

check.call("runtime and GGML source revisions are exact", manifest.dig("runtime", "revision") == "7eb27775fd110a8b2503ac089aedcc02416caa0a" && manifest.dig("runtime", "submodules", "ggml") == "9e2947f17583acc2f657a77c29b6593ca0fbc6c4")
check.call("manifest is the production Vulkan contract", manifest["schema_version"] == "soul.music_vulkan.models.v1")
check.call("model repository revision is immutable", manifest.dig("models", "revision") == "9b3707625776cc4cf775e9b12ab82f9fe48335ff")
check.call("candidate set is exact 4B LM 2B Turbo Q8 and BF16 VAE", manifest.dig("models", "files").map { |item| item["filename"] } == %w[Qwen3-Embedding-0.6B-Q8_0.gguf acestep-5Hz-lm-4B-Q8_0.gguf acestep-v15-turbo-Q8_0.gguf vae-BF16.gguf] && manifest.dig("models", "files").all? { |item| item["bytes"].is_a?(Integer) && item["bytes"].positive? && item["sha256"].match?(/\A[a-f0-9]{64}\z/) })
check.call("profile keeps production at reviewed durations and isolates the 210-second qualification", manifest.dig("profile", "accelerator") == "AMD Vulkan" && manifest.dig("profile", "offload") == false && manifest.dig("profile", "durations") == [30, 90, 180] && manifest.dig("profile", "qualification_durations") == [210])
check.call("LM collapse recovery is capped at three total attempts", manifest.dig("profile", "max_lm_attempts") == 3 && script.include?("max_lm_attempts.times") && script.include?("three consecutive LM audio-code plans degenerated"))
check.call("production backend enforces the accepted collapse guard before synthesis", backend.include?("audio_code_health") && backend.index("audio_code_health") < backend.index('binary("ace-synth")') && backend.include?("three consecutive LM audio-code plans degenerated"))
check.call("production generation publishes FLAC and MP3 then removes the WAV intermediate", generation.include?("run_lossless_transcode") && generation.include?("FileUtils.rm_f(wav_path)") && generation.include?("listening.mp3"))
check.call("collapsed production attempts retain bounded diagnostic evidence", generation.include?('payload["lm_attempts"]') && generation.include?('payload["code_health"]') && generation.include?("music_candidate_quarantined"))
check.call("VAE uses reference-sized tiles after the 1024-frame AMD timeout", manifest.dig("profile", "vae_chunk") == 256 && script.include?('"--vae-chunk", vae_chunk.to_s'))
check.call("setup builds only foreground LM and synth targets", script.include?('"--target", "ace-lm", "ace-synth"') && !script.include?('"ace-server"') && !script.include?("server.sh"))
check.call("all mutations require exact digest and confirmation", %w[INSTALL_MUSIC_VULKAN_RUNTIME DOWNLOAD_MUSIC_VULKAN_MODELS RUN_MUSIC_VULKAN_PILOT].all? { |token| script.include?(token) } && script.include?("scope changed; preview again"))
check.call("downloads use HTTPS-only redirects and verified partial files", script.include?('"--proto-redir", "=https"') && script.include?(".partial-") && script.include?("size or digest verification"))
check.call("foreground commands use owned process groups and bounded termination", script.include?("pgroup: true") && script.include?('Process.kill("TERM", -wait.pid)') && script.include?('Process.kill("KILL", -wait.pid)') && script.include?("MAX_LOG_BYTES"))
check.call("pinned binaries resolve only their local GGML shared libraries", script.include?('"LD_LIBRARY_PATH" => runtime_library_path') && script.include?('File.join(@install_dir, "build")'))
check.call("pilot allows only one batch and separates production from qualification durations", script.include?("PRODUCTION_DURATIONS = [30, 90, 180]") && script.include?('210 => "duration_210_v1"') && script.include?('"batch_size" => 1') && script.include?('"inference_steps" => 8'))
check.call("pilot can pin the accepted LM seed for comparison", script.include?('%w[lm_seed qualification]') && script.include?('Integer(data["lm_seed"])'))
check.call("pilot requests an upstream-supported lossless WAV format", script.include?('"output_format" => "wav16"'))
check.call("failed pilots retain bounded UTF-8-safe diagnostic logs", script.include?("pilot.failed.log") && script.include?("MAX_LOG_BYTES") && script.include?(".scrub"))
check.call("degenerate LM plans stop before synthesis", script.index("audio_code_health") < script.index('synth = run!') && script.include?("synthesis was not started"))
check.call("bounded LM retries derive new seeds inside the confirmed run", script.include?("next_lm_seed(lm_seed, attempt_number)") && script.include?("automatic_attempts_exhausted") && script.include?("max_lm_attempts"))
check.call("production LM planning begins from the project seed", backend.include?('input.fetch("lm_seed", input.fetch("seed", -1))'))
check.call("production maps Soul's language and trained instrumental token into the pinned request", backend.include?('input.except("language")') && backend.include?('input.fetch("lyrics") == "[Instrumental]" ? "unknown" : input.fetch("language")'))
check.call("Music Core is a distinct intent over reserve chat without duplicate services", core.include?('role == "music-chat" && members.empty?') && core.include?('core_id == "music" && profile.fetch("core_role") == "reserve-chat"') && core.include?('"active_core_id" => target_core_id'))
check.call("AMD-Free and Music require an exact idle-safe intent gate when sharing Qwen", core.include?('"ACTIVATE_#{core_id.upcase.tr(\'-\', \'_\')}_CORE"') && core.include?('"service_mutation_required" => false') && core.include?("Core intent state changed; preview again"))
check.call("brief excludes XL offload ROCm listeners and automatic switching", %w[XL offload ROCm listener automatic].all? { |word| brief.include?(word) } && brief.include?("No service, systemd unit, daemon, watcher"))
check.call("Makefile exposes separate plan-gated setup download and run", %w[music-vulkan-setup-plan music-vulkan-download-plan music-vulkan-run-plan].all? { |target| makefile.include?(target) })
check.call("dashboard uses the selected Core lane rather than the retired NVIDIA-only status", dashboard.include?("data.can_acquire_music === true") && dashboard.include?("Starting the bounded Music Core revision pass") && !dashboard.include?("AMD conversation remains online; the NVIDIA lane"))

stdout, status = Open3.capture2("ruby", File.join(ROOT, "scripts/soul-music-vulkan-pilot"), "plan", "--action", "setup", "--manifest", File.join(ROOT, "config/music_vulkan_models.json"), "--root", File.join(Dir.home, ".local", "share", "soul", "music"))
plan = JSON.parse(stdout)
check.call("setup plan terminates at human review with an exact digest", status.success? && plan["lifecycle_state"] == "blocked_for_human_review" && plan["confirmation_phrase"] == "INSTALL_MUSIC_VULKAN_RUNTIME" && plan["expected_digest"].match?(/\A[a-f0-9]{64}\z/))

pilot = MusicVulkanPilot.new(manifest: File.join(ROOT, "config/music_vulkan_models.json"), root: File.join(Dir.home, ".local", "share", "soul", "music"), action: "run")
collapsed = pilot.send(:audio_code_health, Array.new(450, 44_537).join(","), 90)
diverse = pilot.send(:audio_code_health, (0...900).map { |index| index % 65_536 }.join(","), 180)
cohesive_with_outro = pilot.send(:audio_code_health, ((0...832).to_a + Array.new(68, 35_847)).join(","), 180)
check.call("deterministic code-health fixtures reject collapse", collapsed["degenerate"] && collapsed["adjacent_repeat_ratio"] > 0.99)
check.call("deterministic code-health fixtures preserve diverse and localized-outro plans", !diverse["degenerate"] && !cohesive_with_outro["degenerate"])

Dir.mktmpdir("soul-vulkan-duration-qualification") do |temporary|
  base_request = {
    "caption" => "Original high-energy ensemble instrumental with brass, reeds, electric bass, drums, percussion, piano, and guitar.",
    "lyrics" => "[Instrumental Intro]\n[Ensemble Development]\n[Final Ensemble Stop]",
    "bpm" => 152, "keyscale" => "C minor", "timesignature" => "4", "language" => "en",
    "duration" => 210, "seed" => 2_104_199_811
  }
  request_path = File.join(temporary, "request.json")
  File.write(request_path, JSON.generate(base_request.merge("qualification" => "duration_210_v1")))
  stdout, status = Open3.capture2("ruby", File.join(ROOT, "scripts/soul-music-vulkan-pilot"), "plan", "--action", "run", "--request", request_path, "--manifest", File.join(ROOT, "config/music_vulkan_models.json"), "--root", File.join(Dir.home, ".local", "share", "soul", "music"))
  qualified = JSON.parse(stdout)
  check.call("210-second pilot requires and digests an explicit qualification marker", status.success? && qualified["lifecycle_state"] == "blocked_for_human_review" && qualified.dig("preview_scope", "qualification") == "duration_210_v1")

  File.write(request_path, JSON.generate(base_request))
  stdout, status = Open3.capture2e("ruby", File.join(ROOT, "scripts/soul-music-vulkan-pilot"), "plan", "--action", "run", "--request", request_path, "--manifest", File.join(ROOT, "config/music_vulkan_models.json"), "--root", File.join(Dir.home, ".local", "share", "soul", "music"))
  unqualified = JSON.parse(stdout)
  check.call("unmarked 210-second requests stop before authorization", !status.success? && unqualified["lifecycle_state"] == "awaiting_input" && unqualified["reason"].include?("duration_210_v1"))

  File.write(request_path, JSON.generate(base_request.merge("duration" => 180, "qualification" => "duration_210_v1")))
  stdout, status = Open3.capture2e("ruby", File.join(ROOT, "scripts/soul-music-vulkan-pilot"), "plan", "--action", "run", "--request", request_path, "--manifest", File.join(ROOT, "config/music_vulkan_models.json"), "--root", File.join(Dir.home, ".local", "share", "soul", "music"))
  marked_production = JSON.parse(stdout)
  check.call("qualification markers cannot broaden production requests", !status.success? && marked_production["lifecycle_state"] == "awaiting_input" && marked_production["reason"].include?("must not carry"))
end

abort(errors.map { |error| "- #{error}" }.join("\n")) unless errors.empty?
puts "Music Core Vulkan feasibility boundary is candidate-ready."
