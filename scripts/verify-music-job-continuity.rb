#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "tmpdir"
require_relative "../lib/soul_core/dashboard_music_job_manager"
require_relative "../lib/soul_core/dashboard_http_application"

failures = []
check = lambda do |name, value|
  puts "- #{name}: #{value ? 'ok' : 'FAILED'}"
  failures << name unless value
end

request = {
  "schema_version" => "soul.application.v1", "request_id" => "job-continuity-1",
  "operation" => "music.generation.execute",
  "parameters" => { "project_id" => "music_#{'1' * 16}", "candidate_id" => "candidate_#{'2' * 16}",
    "confirmation" => "START_MUSIC_GENERATION", "expected_digest" => "a" * 64 },
  "context" => { "interface" => "dashboard" }
}

Dir.mktmpdir("soul-music-jobs") do |root|
  started = Queue.new
  release = Queue.new
  facade = Object.new
  facade.define_singleton_method(:call) do |incoming, progress:|
    progress.call({ "stage" => "model", "message" => "bounded generation running" })
    started << true
    release.pop
    { "schema_version" => "soul.application.v1", "request_id" => incoming.fetch("request_id"),
      "operation" => incoming.fetch("operation"), "ok" => false, "lifecycle_state" => "blocked_for_human_review",
      "data" => { "candidate" => { "candidate_id" => incoming.dig("parameters", "candidate_id") }, "reason" => "candidate ready" },
      "errors" => [], "warnings" => [], "meta" => { "mutation" => "music_candidate_created" } }
  end
  job_ids = ["3" * 16, "6" * 16]
  manager = SoulCore::DashboardMusicJobManager.new(root: root, facade: facade, id_generator: -> { job_ids.shift })
  record = manager.start(request)
  started.pop
  duplicate_request = Marshal.load(Marshal.dump(request)); duplicate_request["request_id"] = "job-continuity-reconnect"
  duplicate = manager.start(duplicate_request)
  check.call("a repeated exact approval reattaches instead of starting a duplicate", duplicate["job_id"] == record["job_id"])
  detached_stream = manager.stream(record.fetch("job_id"))
  first = JSON.parse(detached_stream.next)
  check.call("a dashboard stream can attach to the accepted bounded job", first["type"] == "progress")
  detached_stream = nil
  release << true
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
  sleep(0.01) while manager.active.any? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
  check.call("generation continues after its first dashboard stream is abandoned", manager.active.empty?)
  terminal = manager.stream(record.fetch("job_id")).to_a.map { |line| JSON.parse(line) }.last
  check.call("a later dashboard view recovers the terminal candidate result", terminal["type"] == "result" && terminal.dig("envelope", "data", "candidate", "candidate_id") == "candidate_#{'2' * 16}")
  persisted = JSON.parse(File.read(File.join(root, "Soul", "music", "jobs", "#{record.fetch('job_id')}.json")))
  check.call("job progress and result are atomically persisted with restrictive permissions", persisted["status"] == "terminal" && (File.stat(File.join(root, "Soul", "music", "jobs", "#{record.fetch('job_id')}.json")).mode & 0o777) == 0o600)
  auth = Object.new
  auth.define_singleton_method(:session) { |_token| { "password_change_required" => false } }
  app = SoulCore::DashboardHttpApplication.new(root: root, facade: facade, bind_host: "127.0.0.1", port: 4567,
    csrf_token: "job-csrf", authentication: auth, music_jobs: manager)
  headers = { "host" => "127.0.0.1:4567", "origin" => "http://127.0.0.1:4567", "content-type" => "application/json",
    "x-soul-csrf" => "job-csrf", "cookie" => "soul_session=test" }
  follow = app.call(method: "POST", target: "/api/v1/music-job-follow", headers: headers, body: JSON.generate({ "job_id" => record.fetch("job_id") }))
  check.call("authenticated HTTP follow recovers the detached terminal stream", follow.status == 200 && follow.body.to_a.join.include?("candidate_#{'2' * 16}"))
  invalid = app.call(method: "POST", target: "/api/v1/music-job-status", headers: headers, body: JSON.generate({ "project_id" => "../escape" }))
  check.call("job status rejects untyped project identities", invalid.status == 422)

  second = Marshal.load(Marshal.dump(request)); second["request_id"] = "job-continuity-2"; second["parameters"]["candidate_id"] = "candidate_#{'4' * 16}"
  blocker = Queue.new
  facade.define_singleton_method(:call) do |incoming, progress:|
    progress.call({ "stage" => "model", "message" => "second run" }); blocker.pop
    { "schema_version" => "soul.application.v1", "request_id" => incoming.fetch("request_id"), "operation" => incoming.fetch("operation"),
      "ok" => false, "lifecycle_state" => "canceled", "data" => {}, "errors" => [], "warnings" => [], "meta" => { "mutation" => "none" } }
  end
  manager.start(second)
  begin
    third = Marshal.load(Marshal.dump(request)); third["request_id"] = "job-continuity-3"; third["parameters"]["candidate_id"] = "candidate_#{'5' * 16}"
    manager.start(third)
    rejected = false
  rescue ArgumentError
    rejected = true
  end
  check.call("the persistent boundary remains a single bounded lane rather than a queue", rejected)
  blocker << true
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
  sleep(0.01) while manager.active.any? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
end

abort "Music job continuity verification failed: #{failures.join(', ')}" unless failures.empty?
puts "Music job continuity deterministic verification passed."
