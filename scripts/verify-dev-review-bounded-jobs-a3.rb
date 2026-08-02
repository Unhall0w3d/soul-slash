#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "tmpdir"
require_relative "../lib/soul_core/application_facade"
require_relative "../lib/soul_core/dashboard_music_job_manager"
require_relative "../lib/soul_core/dashboard_http_application"

failures = []
check = lambda do |name, value|
  puts "- #{name}: #{value ? 'ok' : 'FAILED'}"
  failures << name unless value
end

operations = {
  "self_improvement.dev_synthesis.execute" => { "scope" => "environment" },
  "self_augmentation.dev_critique.execute" => { "proposal_id" => "aug_#{'1' * 16}" },
  "self_augmentation.dev_handoff.execute" => { "experiment_id" => "exp_#{'2' * 16}" }
}

Dir.mktmpdir("soul-dev-review-jobs") do |root|
  calls = []
  facade = Object.new
  facade.define_singleton_method(:call) do |request, progress:|
    calls << request.fetch("operation")
    progress.call({ "stage" => "model", "message" => "bounded Dev review running" })
    { "schema_version" => "soul.application.v1", "request_id" => request.fetch("request_id"),
      "operation" => request.fetch("operation"), "ok" => true, "lifecycle_state" => "complete",
      "data" => { "review" => { "ready" => true } }, "errors" => [], "warnings" => [], "meta" => { "mutation" => "review_created" } }
  end
  ids = %w[3 4 5].map { |digit| digit * 16 }
  manager = SoulCore::DashboardMusicJobManager.new(root: root, facade: facade, id_generator: -> { ids.shift })

  records = operations.map do |operation, parameters|
    request = { "schema_version" => "soul.application.v1", "request_id" => "verify-#{operation}", "operation" => operation,
      "parameters" => parameters.merge("confirmation" => "EXACT", "expected_digest" => "a" * 64), "context" => { "interface" => "dashboard" } }
    record = manager.start(request)
    manager.stream(record.fetch("job_id")).to_a
    record
  end
  check.call("all three Dev review operations execute through the bounded lane", calls.sort == operations.keys.sort)
  persisted = records.map { |record| JSON.parse(File.read(File.join(root, "Soul", "music", "jobs", "#{record.fetch('job_id')}.json"))) }
  check.call("typed Dev subject identities are persisted", persisted.map { |item| [item["scope"], item["proposal_id"], item["experiment_id"]].compact }.flatten.sort == ["environment", "aug_#{'1' * 16}", "exp_#{'2' * 16}"].sort)
  check.call("terminal envelopes and progress are owner-private", persisted.all? { |item| item["status"] == "terminal" && item.dig("result", "lifecycle_state") == "complete" && (File.stat(File.join(root, "Soul", "music", "jobs", "#{item.fetch('job_id')}.json")).mode & 0o777) == 0o600 })

  invalid = {
    "self_improvement.dev_synthesis.execute" => { "scope" => "arbitrary" },
    "self_augmentation.dev_critique.execute" => { "proposal_id" => "../proposal" },
    "self_augmentation.dev_handoff.execute" => { "experiment_id" => "not-an-experiment" }
  }
  rejected = invalid.all? do |operation, parameters|
    manager.start({ "request_id" => "invalid", "operation" => operation, "parameters" => parameters, "context" => {} })
    false
  rescue ArgumentError
    true
  end
  check.call("malformed Dev subject identities fail before execution", rejected)

  auth = Object.new
  auth.define_singleton_method(:session) { |_token| { "password_change_required" => false } }
  app = SoulCore::DashboardHttpApplication.new(root: root, facade: facade, bind_host: "127.0.0.1", port: 4567,
    csrf_token: "job-csrf", authentication: auth, music_jobs: manager)
  headers = { "host" => "127.0.0.1:4567", "origin" => "http://127.0.0.1:4567", "content-type" => "application/json",
    "x-soul-csrf" => "job-csrf", "cookie" => "soul_session=test" }
  follow = app.call(method: "POST", target: "/api/v1/bounded-job-follow", headers: headers, body: JSON.generate({ "job_id" => records.first.fetch("job_id") }))
  check.call("neutral authenticated follow endpoint returns the retained result", follow.status == 200 && follow.body.to_a.join.include?('"ready":true'))
  status = app.call(method: "POST", target: "/api/v1/bounded-job-status", headers: headers, body: JSON.generate({ "operations" => operations.keys }))
  check.call("neutral status endpoint exposes only active requested Dev operations", status.status == 200 && JSON.parse(status.body).fetch("jobs") == [])
  disallowed = app.call(method: "POST", target: "/api/v1/bounded-job-status", headers: headers, body: JSON.generate({ "operations" => ["music.generation.execute"] }))
  check.call("neutral Dev status rejects unrelated operations", disallowed.status == 422)

  interrupted = {
    "schema_version" => "soul.dashboard.music_job.v1", "job_id" => "job_#{'9' * 16}", "operation" => "self_augmentation.dev_handoff.execute",
    "experiment_id" => "exp_#{'8' * 16}", "request_digest" => "b" * 64, "status" => "running", "lifecycle_state" => "awaiting_input",
    "latest_progress" => { "stage" => "model", "message" => "running" }, "created_at" => Time.now.iso8601, "updated_at" => Time.now.iso8601, "result" => nil
  }
  path = File.join(root, "Soul", "music", "jobs", "#{interrupted.fetch('job_id')}.json")
  File.write(path, JSON.pretty_generate(interrupted), mode: "w", perm: 0o600)
  recovered = SoulCore::DashboardMusicJobManager.new(root: root, facade: facade)
  receipt = recovered.stream(interrupted.fetch("job_id")).to_a.map { |line| JSON.parse(line) }.last
  check.call("dashboard restart marks interrupted work failed without re-executing it", receipt.dig("envelope", "lifecycle_state") == "failed" && calls.length == 3)
end

javascript = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
check.call("Dashboard starts and resumes Dev review work through neutral bounded endpoints",
  javascript.include?('callNdjson("/api/v1/bounded-job-stream", "self_improvement.dev_synthesis.execute"') &&
  javascript.include?('callNdjson("/api/v1/bounded-job-stream", "self_augmentation.dev_critique.execute"') &&
  javascript.include?('callNdjson("/api/v1/bounded-job-stream", "self_augmentation.dev_handoff.execute"') &&
  javascript.include?("resumeBoundedDevJobs"))

failure_service = Object.new
failure_service.define_singleton_method(:execute) do |**_arguments|
  { "schema_version" => "soul.dev_worker.result.v1", "ok" => false, "lifecycle_state" => "blocked_for_human_review",
    "message" => "model runtime control is disabled", "data" => {}, "mutation" => "none" }
end
failure_facade = SoulCore::ApplicationFacade.new(root: Dir.pwd, self_assessment_dev_synthesis_service: failure_service)
failure = failure_facade.call({ "schema_version" => "soul.application.v1", "request_id" => "bounded-message",
  "operation" => "self_improvement.dev_synthesis.execute", "parameters" => { "scope" => "environment" }, "context" => { "interface" => "dashboard_test" } })
check.call("provider failures retain their safe domain message in the application envelope",
  failure.dig("errors", 0, "message") == "model runtime control is disabled")

abort "Dev review bounded jobs A3 verification failed: #{failures.join(', ')}" unless failures.empty?
puts "Dev review bounded jobs A3 deterministic verification passed."
