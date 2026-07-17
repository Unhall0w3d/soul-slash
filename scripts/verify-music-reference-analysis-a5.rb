#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"
require_relative "../lib/soul_core/application_contract"
require_relative "../lib/soul_core/music_generation_service"
require_relative "../lib/soul_core/music_reference_analysis_service"
require_relative "../lib/soul_core/music_reference_library_store"

failures = []
check = lambda do |name, value|
  puts "- #{name}: #{value ? 'ok' : 'FAILED'}"
  failures << name unless value
end

class FakeToolRunner
  Result = Struct.new(:stdout, :stderr, :status, keyword_init: true) { def success? = status == "ok" }
  def initialize(ffmpeg) = (@ffmpeg = ffmpeg)
  def which(name) = name == "ffmpeg" ? @ffmpeg : nil
  def run(command, **_options)
    argv = Array(command)
    output = if argv.include?("import essentia; print(essentia.__version__)")
      "2.1b6.dev1438\n"
    elsif argv.include?("-version")
      "ffmpeg version fixture\n"
    else
      "2026.7.4\n"
    end
    Result.new(stdout: output, stderr: "", status: "ok")
  end
end

class FakeProcessRunner
  attr_reader :commands, :temporary_directories
  def initialize(metadata:, fail_stage: nil)
    @metadata = metadata
    @fail_stage = fail_stage
    @commands = []
    @temporary_directories = []
  end

  def run(command, env:, chdir:, **options)
    @commands << { "command" => command, "env" => env, "chdir" => chdir, "rlimit_fsize_bytes" => options[:rlimit_fsize_bytes] }
    @temporary_directories << chdir if File.basename(chdir).start_with?("soul-music-reference-")
    stage = if command.include?("--dump-single-json") then "metadata"
      elsif File.basename(command.first) == "yt-dlp" then "download"
      elsif File.basename(command.first) == "ffmpeg" then "transcode"
      else "analysis" end
    return result("failed", "", "fixture #{stage} failure") if @fail_stage == stage
    case stage
    when "metadata"
      result("ok", JSON.generate(@metadata), "")
    when "download"
      File.binwrite(File.join(chdir, "source.webm"), "source-audio")
      result("ok", "", "")
    when "transcode"
      File.binwrite(command.last, "R" * 512)
      result("ok", "", "")
    else
      evidence = {
        "schema_version" => "soul.music.reference.extractor.v1", "essentia_version" => "2.1b6.dev1438",
        "bpm" => 118.2, "bpm_alternatives" => [59.1], "rhythm_confidence" => 2.8,
        "beat_count" => 412, "median_beat_interval" => 0.5076, "key" => "D minor", "key_strength" => 0.72,
        "dynamic_complexity" => 4.1, "loudness" => -13.2, "danceability" => 1.3, "dfa" => 0.61,
        "energy_curve" => (1..8).map { |index| "segment #{index}: RMS 0.1" }
      }
      result("ok", JSON.generate(evidence), "")
    end
  end

  private

  def result(status, stdout, stderr)
    SoulCore::MusicGenerationService::ProcessResult.new(status: status, stdout: stdout, stderr: stderr, exit_status: status == "ok" ? 0 : 1, pid: 42)
  end
end

metadata = {
  "id" => "abcDEF12345", "title" => "Reference signal", "duration" => 212,
  "artists" => ["Test Artist"], "album" => "Test Album", "live_status" => "not_live"
}

Dir.mktmpdir("soul-reference-analysis-a5") do |root|
  tooling = File.join(root, "Soul", "music", "tooling", "reference-analysis", ".venv", "bin")
  FileUtils.mkdir_p(tooling)
  %w[python yt-dlp].each { |name| File.write(File.join(tooling, name), "fixture"); File.chmod(0o700, File.join(tooling, name)) }
  analyzer = File.join(root, "scripts", "soul-music-reference-analyze")
  FileUtils.mkdir_p(File.dirname(analyzer)); File.write(analyzer, "fixture")
  ffmpeg = File.join(root, "ffmpeg"); File.write(ffmpeg, "fixture"); File.chmod(0o700, ffmpeg)
  store = SoulCore::MusicReferenceLibraryStore.new(root: root, id_generator: -> { "1" * 16 }, clock: -> { Time.utc(2026, 7, 17, 12) })
  process = FakeProcessRunner.new(metadata: metadata)
  service = SoulCore::MusicReferenceAnalysisService.new(root: root, store: store, process_runner: process, runner: FakeToolRunner.new(ffmpeg))

  blocked_url = service.preview(url: "http://127.0.0.1/private", rights_assertion: "analysis_only")
  playlist_url = service.preview(url: "https://www.youtube.com/watch?v=abcDEF12345&list=private", rights_assertion: "analysis_only")
  check.call("URL boundary rejects local HTTP and playlist parameters before a process", blocked_url["lifecycle_state"] == "awaiting_input" && playlist_url["lifecycle_state"] == "awaiting_input" && process.commands.empty?)

  preview = service.preview(url: "https://youtu.be/abcDEF12345", rights_assertion: "analysis_only")
  check.call("metadata-only preview binds identity limits retention and exact confirmation", preview["lifecycle_state"] == "blocked_for_human_review" && preview.dig("data", "confirmation_phrase") == "ANALYZE_MUSIC_REFERENCE" && preview.dig("data", "preview_scope", "retention", "source_audio") == false)
  metadata_command = process.commands.first.fetch("command")
  check.call("yt-dlp ignores config plugins remote components playlists and caches", %w[--ignore-config --no-plugin-dirs --no-remote-components --no-cache-dir --no-playlist --dump-single-json --skip-download].all? { |flag| metadata_command.include?(flag) })

  wrong = service.execute(url: "https://youtu.be/abcDEF12345", rights_assertion: "analysis_only", confirmation: "yes", expected_digest: preview.dig("data", "expected_digest"))
  check.call("wrong confirmation downloads nothing", wrong["lifecycle_state"] == "blocked_for_human_review" && process.commands.length == 1)

  complete = service.execute(url: "https://youtu.be/abcDEF12345", rights_assertion: "analysis_only", confirmation: "ANALYZE_MUSIC_REFERENCE", expected_digest: preview.dig("data", "expected_digest"))
  record = complete.dig("data", "reference")
  check.call("confirmed foreground operation records derived candidate evidence", complete["lifecycle_state"] == "blocked_for_human_review" && record.dig("evidence", "bpm") == 118.2 && record.dig("provenance", "album") == "Test Album")
  check.call("stored profile contains no source audio or copied transcript field", record.dig("provenance", "rights_assertion") == "analysis_only" && (JSON.generate(record).scan(/source_audio|transcript|machine_heard/).length == 0))
  check.call("temporary audio and isolated HOME are removed at terminal completion", process.temporary_directories.uniq.all? { |path| !File.exist?(path) } && process.commands.all? { |item| item.dig("env", "HOME") == item["chdir"] })
  download_command = process.commands.find { |item| File.basename(item.fetch("command").first) == "yt-dlp" && !item.fetch("command").include?("--dump-single-json") }.fetch("command")
  download_call = process.commands.find { |item| File.basename(item.fetch("command").first) == "yt-dlp" && !item.fetch("command").include?("--dump-single-json") }
  check.call("download is one fragment one retry and 250 MiB process bounded", download_command.each_cons(2).include?(["--max-filesize", (250 * 1024 * 1024).to_s]) && download_command.each_cons(2).include?(["--concurrent-fragments", "1"]) && download_command.each_cons(2).include?(["--retries", "1"]) && download_call.fetch("rlimit_fsize_bytes") == 250 * 1024 * 1024)
end

Dir.mktmpdir("soul-reference-analysis-failure") do |root|
  tooling = File.join(root, "Soul", "music", "tooling", "reference-analysis", ".venv", "bin")
  FileUtils.mkdir_p(tooling); %w[python yt-dlp].each { |name| File.write(File.join(tooling, name), "fixture"); File.chmod(0o700, File.join(tooling, name)) }
  FileUtils.mkdir_p(File.join(root, "scripts")); File.write(File.join(root, "scripts", "soul-music-reference-analyze"), "fixture")
  ffmpeg = File.join(root, "ffmpeg"); File.write(ffmpeg, "fixture"); File.chmod(0o700, ffmpeg)
  process = FakeProcessRunner.new(metadata: metadata, fail_stage: "analysis")
  service = SoulCore::MusicReferenceAnalysisService.new(root: root, process_runner: process, runner: FakeToolRunner.new(ffmpeg))
  preview = service.preview(url: "https://youtu.be/abcDEF12345", rights_assertion: "analysis_only")
  failed = service.execute(url: "https://youtu.be/abcDEF12345", rights_assertion: "analysis_only", confirmation: "ANALYZE_MUSIC_REFERENCE", expected_digest: preview.dig("data", "expected_digest"))
  check.call("analysis failure terminates failed and removes every transient file", failed["lifecycle_state"] == "failed" && process.temporary_directories.uniq.all? { |path| !File.exist?(path) })
end

request = { "schema_version" => "soul.application.v1", "request_id" => "reference-analysis-a5-1", "operation" => "music.references.analysis.execute", "parameters" => { "url" => "https://youtu.be/abcDEF12345", "rights_assertion" => "analysis_only", "confirmation" => "ANALYZE_MUSIC_REFERENCE", "expected_digest" => "a" * 64 }, "context" => { "interface" => "dashboard" } }
check.call("typed application contract exposes preview status and execution", SoulCore::ApplicationContract.validate(request)["ok"] == true && %w[music.references.status music.references.analysis.preview music.references.analysis.execute].all? { |operation| SoulCore::ApplicationContract::OPERATIONS.key?(operation) })

plan_json, plan_error, plan_status = Open3.capture3(RbConfig.ruby, File.expand_path("soul-music-reference-tooling", __dir__), "plan", "--root", Dir.mktmpdir("soul-tooling-plan"))
plan = JSON.parse(plan_json)
check.call("optional tooling plan reuses system yt-dlp or pins a local fallback", plan_status.success? && plan_error.empty? && plan["lifecycle_state"] == "blocked_for_human_review" && %w[system local_environment].include?(plan.dig("yt_dlp", "source")) && plan.dig("packages", "essentia") == "2.1b6.dev1438" && (plan.dig("yt_dlp", "source") == "system" || plan.dig("packages", "yt-dlp") == "2026.7.4") && plan["resident_process"] == false && plan["confirmation_phrase"] == "INSTALL_MUSIC_REFERENCE_TOOLS")

http = File.read(File.expand_path("../lib/soul_core/dashboard_http_application.rb", __dir__))
html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
js = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
check.call("dashboard exposes metadata preview exact gate progress and foreground stream", %w[preview-music-reference music-reference-confirmation analyze-music-reference].all? { |id| html.include?(id) } && js.include?("music.references.analysis.preview") && js.include?("music.references.analysis.execute") && http.include?("music.references.analysis.execute"))
check.call("browser adds no queue polling or remote dependency", %w[setInterval setTimeout WebSocket EventSource serviceWorker innerHTML].none? { |needle| js.include?(needle) } && ![html, js].any? { |source| source.match?(%r{(?:src|href)=["']https?://}) })

abort "Music reference analysis A5.2 verification failed: #{failures.join(', ')}" unless failures.empty?
puts "Music reference analysis A5.2 deterministic verification passed."
