#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "socket"
require "tmpdir"
require_relative "../lib/soul_core/application_contract"
require_relative "../lib/soul_core/dashboard_http_application"
require_relative "../lib/soul_core/dashboard_server"
require_relative "../lib/soul_core/music_generation_service"
require_relative "../lib/soul_core/music_project_store"

failures = []
check = lambda do |name, value|
  puts "- #{name}: #{value ? 'ok' : 'FAILED'}"
  failures << name unless value
end

project_input = {
  "title" => "Bounded signal", "intent" => "verify A3", "target_duration_seconds" => 30,
  "vocal_mode" => "vocal", "rights_status" => "original", "caption" => "dark electronic pulse",
  "lyrics" => "[Verse]\nA local signal", "bpm" => 110, "keyscale" => "C minor",
  "timesignature" => "4", "language" => "en", "seed" => 42
}

request = { "schema_version" => "soul.application.v1", "request_id" => "verify-a3-0001", "operation" => "music.projects.create", "parameters" => { "project" => project_input }, "context" => { "interface" => "dashboard" } }
check.call("typed application contract accepts bounded project objects", SoulCore::ApplicationContract.validate(request)["ok"] == true)
bad = Marshal.load(Marshal.dump(request)); bad["parameters"]["project_id"] = "../escape"
bad["operation"] = "music.projects.get"; bad["parameters"].delete("project")
check.call("music identities reject traversal", SoulCore::ApplicationContract.validate(bad)["ok"] == false)

Dir.mktmpdir("soul-music-a3") do |root|
  store = SoulCore::MusicProjectStore.new(root: root, id_generator: -> { "1" * 16 })
  project = store.create(project_input)
  candidate = "candidate_#{'2' * 16}"
  candidate_dir = File.join(store.generations_path(project.fetch("project_id")), candidate)
  Dir.mkdir(candidate_dir, 0o700)
  File.write(File.join(candidate_dir, "candidate.json"), "{}", mode: "wx", perm: 0o600)
  File.write(File.join(candidate_dir, "listening.mp3"), "audio", mode: "wx", perm: 0o600)
  File.write(File.join(candidate_dir, "master.flac"), "lossless", mode: "wx", perm: 0o600)
  review = store.record_review(project_id: project.fetch("project_id"), candidate_id: candidate, attributes: {
    "rating" => 4, "disposition" => "revise", "musical_quality" => "passed", "prompt_adherence" => "partial",
    "vocal_adherence" => "failed", "lyric_adherence" => "failed", "notes" => "music present; lyrics absent"
  })
  check.call("candidate adherence review is project-local and terminal", review["lyric_adherence"] == "failed" && store.read_review(project.fetch("project_id"), candidate)["rating"] == 4)
  revised = review.slice("rating", "disposition", "musical_quality", "prompt_adherence", "vocal_adherence", "lyric_adherence", "notes").merge("rating" => 3, "notes" => "second listening pass")
  store.record_review(project_id: project.fetch("project_id"), candidate_id: candidate, attributes: revised)
  history = Dir.children(File.join(store.project_path(project.fetch("project_id")), "reviews", "history"))
  check.call("revised reviews preserve immutable prior evidence", history.length == 1 && store.read_review(project.fetch("project_id"), candidate)["rating"] == 3)
  check.call("audio resolver permits only exact project candidate artifacts", store.candidate_artifact_path(project.fetch("project_id"), candidate, "mp3").end_with?("listening.mp3"))
  begin
    store.candidate_artifact_path(project.fetch("project_id"), candidate, "../project.json")
    rejected = false
  rescue SoulCore::MusicProjectStore::ValidationError
    rejected = true
  end
  check.call("audio resolver rejects arbitrary paths", rejected)

  fake_auth = Object.new
  fake_auth.define_singleton_method(:session) { |_token| { "authenticated" => true, "username" => "operator", "password_change_required" => false } }
  fake_facade = Object.new
  fake_facade.define_singleton_method(:music_artifact_path) { |**_args| File.join(candidate_dir, "listening.mp3") }
  fake_facade.define_singleton_method(:call) do |req, progress: nil|
    progress&.call({ "stage" => "model", "message" => "bounded" })
    { "schema_version" => "soul.application.v1", "request_id" => req["request_id"], "operation" => req["operation"], "ok" => false, "lifecycle_state" => "blocked_for_human_review", "data" => {}, "errors" => [], "warnings" => [], "meta" => { "mutation" => "none" } }
  end
  app = SoulCore::DashboardHttpApplication.new(root: File.expand_path("..", __dir__), facade: fake_facade, bind_host: "127.0.0.1", port: 4567, csrf_token: "a3-csrf", authentication: fake_auth)
  base_headers = { "host" => "127.0.0.1:4567", "cookie" => "soul_session=test" }
  ranged = app.call(method: "GET", target: "/api/v1/music/audio/#{project.fetch('project_id')}/#{candidate}/mp3", headers: base_headers.merge("range" => "bytes=1-3"))
  bytes = +""; ranged.body.each { |chunk| bytes << chunk }
  check.call("authenticated audio supports bounded byte ranges", ranged.status == 206 && ranged.headers["Content-Range"] == "bytes 1-3/5" && bytes == "udi")
  stream_request = JSON.generate({ "schema_version" => "soul.application.v1", "request_id" => "verify-a3-stream", "operation" => "music.generation.execute", "parameters" => {}, "context" => { "interface" => "dashboard" } })
  stream = app.call(method: "POST", target: "/api/v1/music-stream", headers: base_headers.merge("origin" => "http://127.0.0.1:4567", "content-type" => "application/json", "x-soul-csrf" => "a3-csrf"), body: stream_request)
  events = +""; stream.body.each { |chunk| events << chunk }
  check.call("authenticated music stream emits progress and one terminal result", stream.status == 200 && events.lines.count == 2 && events.include?('"type":"progress"') && events.include?('"type":"result"'))
end

burst_server = SoulCore::DashboardServer.new(host: "127.0.0.1", port: 0, application: Object.new)
occupied_clients = Array.new(SoulCore::DashboardServer::MAX_CONCURRENT_REQUESTS) { Object.new }
occupied_clients.each { |client| raise "request fixture did not reserve" unless burst_server.send(:reserve_request, client) }
released_client = occupied_clients.shift
releaser = Thread.new do
  IO.select(nil, nil, nil, 0.05)
  burst_server.send(:release_request, released_client)
end
burst_client = Object.new
started_waiting = Process.clock_gettime(Process::CLOCK_MONOTONIC)
burst_accepted = burst_server.send(:reserve_request, burst_client)
burst_wait = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_waiting
releaser.join
check.call("transient request burst waits boundedly for a released slot", burst_accepted && burst_wait >= 0.025 && burst_wait < SoulCore::DashboardServer::REQUEST_SLOT_WAIT_SECONDS)
burst_server.send(:release_request, burst_client)
occupied_clients.each { |client| burst_server.send(:release_request, client) }

runner = SoulCore::MusicGenerationService::ForegroundProcessRunner.new
child_pid = nil
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
result = runner.run([RbConfig.ruby, "-e", '$stdout.sync=true; puts "stage"; sleep 30'], env: {}, chdir: Dir.pwd, timeout_seconds: 5, max_output_bytes: 4096,
  on_spawn: ->(pid, _pgid) { child_pid = pid }, canceled: -> { false }, progress: ->(_event) { raise IOError, "client left" })
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
dead = begin
  Process.kill(0, child_pid)
  false
rescue Errno::ESRCH
  true
end
check.call("stream abandonment terminates the exact owned process group", result.status == "failed" && elapsed < 4 && dead)

server_source = File.read(File.expand_path("../lib/soul_core/dashboard_server.rb", __dir__))
http_source = File.read(File.expand_path("../lib/soul_core/dashboard_http_application.rb", __dir__))
html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
js = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
css = File.read(File.expand_path("../assets/dashboard/dashboard.css", __dir__))
check.call("dashboard concurrency is capped with bounded burst absorption and joined", server_source.include?("MAX_CONCURRENT_REQUESTS = 48") && server_source.include?("REQUEST_SLOT_WAIT_SECONDS = 2.0") && server_source.include?("@request_available.wait") && server_source.include?("close_and_join_requests") && server_source.include?("429"))
check.call("music stream and authenticated audio routes are explicit", http_source.include?("/api/v1/music-stream") && http_source.include?("/api/v1/music/audio/"))
check.call("Music Studio exposes preview progress cancel playback and review", %w[music-panel preview-music-generation music-progress cancel-music-generation music-candidates].all? { |id| html.include?(id) } && js.include?("music.candidates.review"))
check.call("initial and revision generation share one live status treatment", html.include?("class=\"generation-progress\"") && css.include?(".generation-progress") && js.include?("createGenerationProgress") && js.include?("showGenerationProgress(progress, event)"))
check.call("Music Studio exposes only the four reviewed duration presets", html.scan(/<option value="(30|90|180|600)">/).flatten == %w[30 90 180 600] && html.include?('<option value="600">10 minutes</option>'))
check.call("candidate cards expose persisted generation timing", js.include?("generated in") && js.include?("flac_derivation_seconds") && js.include?("mp3_derivation_seconds") && js.include?("total_seconds"))
check.call("a mistaken keep can be re-marked revise with review history preserved", js.include?("Re-mark as revise") && js.include?("preserving the prior keep review") && js.include?('disposition: "revise"'))
check.call("inactive media does not eagerly consume request slots", js.scan('preload = "none"').length >= 5 && !js.include?('preload = "metadata"'))
check.call("composition archive uses the available desktop column and stays bounded on narrow screens", css.include?(".music-projects>#music-project-list { flex:1 1 auto; min-height:240px; max-height:none; }") && css.include?(".music-projects>#music-project-list { min-height:0; max-height:360px; }"))
check.call("browser adds no timer queue or remote dependency", %w[setInterval setTimeout WebSocket EventSource serviceWorker innerHTML].none? { |needle| js.include?(needle) } && ![html, js].any? { |source| source.match?(%r{https?://}) })
check.call("A3 brief explicitly excludes queues and automatic model loading", File.read(File.expand_path("../docs/soul/MUSIC_STUDIO_A3_DASHBOARD_BRIEF.md", __dir__)).include?("There is no job queue") && File.read(File.expand_path("../docs/soul/MUSIC_STUDIO_A3_DASHBOARD_BRIEF.md", __dir__)).include?("never loads, unloads"))

abort "Music Studio A3 verification failed: #{failures.join(', ')}" unless failures.empty?
puts "Music Studio A3 deterministic verification passed."
