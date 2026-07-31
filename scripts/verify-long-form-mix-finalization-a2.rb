#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/application_contract"
require_relative "../lib/soul_core/application_facade"
require_relative "../lib/soul_core/long_form_mix_finalization_service"

failures = []
check = lambda do |name, value|
  puts "- #{name}: #{value ? "ok" : "FAILED"}"
  failures << name unless value
end

class FinalMixFixture
  attr_reader :mix

  def initialize
    @mix = {
      "schema_version" => "soul.music.long_form_mix.v1",
      "mix_id" => "mix_1111111111111111",
      "parent_mix_id" => nil,
      "title" => "A2 Accepted Mix",
      "intent" => "Verify a human-reviewed accepted audio package.",
      "sequence" => [{ "source_id" => "project_1111111111111111/candidate_1111111111111111" }],
      "timeline_seconds" => [{ "source_id" => "project_1111111111111111/candidate_1111111111111111", "start_seconds" => 0.0, "end_seconds" => 12.0, "duration_seconds" => 12.0 }],
      "total_duration_seconds" => 12.0,
      "created_at" => "2026-07-30T22:00:00Z",
      "updated_at" => "2026-07-30T22:00:00Z"
    }
  end

  def get(mix_id:)
    return { "ok" => false, "lifecycle_state" => "awaiting_input", "reason" => "missing", "data" => {} } unless mix_id == @mix.fetch("mix_id")
    { "ok" => true, "lifecycle_state" => "complete", "reason" => "ready", "data" => { "mix" => @mix } }
  end
end

class FinalRenderFixture
  attr_reader :render

  def initialize(root)
    @root = root
    @flac = File.join(root, "fixture-master.flac")
    @mp3 = File.join(root, "fixture-listening.mp3")
    File.write(@flac, "accepted flac bytes", mode: "wb", perm: 0o600)
    File.write(@mp3, "accepted mp3 bytes", mode: "wb", perm: 0o600)
    @render = {
      "schema_version" => "soul.music.long_form_mix_render.v1",
      "mix_id" => "mix_1111111111111111",
      "scope_digest" => "a" * 64,
      "checksums" => {
        "master.flac" => Digest::SHA256.file(@flac).hexdigest,
        "listening.mp3" => Digest::SHA256.file(@mp3).hexdigest
      }
    }
  end

  def status(mix_id:)
    return { "ok" => false, "lifecycle_state" => "awaiting_input", "reason" => "missing", "data" => {} } unless mix_id == @render.fetch("mix_id")
    { "ok" => true, "lifecycle_state" => "complete", "reason" => "ready", "data" => { "render" => @render } }
  end

  def artifact_path(mix_id:, artifact:)
    raise "wrong mix" unless mix_id == @render.fetch("mix_id")
    artifact == "flac" ? @flac : @mp3
  end

  def mutate_flac!
    File.write(@flac, "drifted flac bytes", mode: "wb", perm: 0o600)
  end
end

class FinalFacadeFixture
  attr_reader :calls

  def initialize
    @calls = []
  end

  def status(**arguments)
    response("mix.final.status", arguments)
  end

  def record_review(**arguments)
    response("mix.final.review", arguments)
  end

  def export_preview(**arguments)
    response("mix.final.export.preview", arguments)
  end

  def export_execute(**arguments)
    response("mix.final.export.execute", arguments)
  end

  private

  def response(name, arguments)
    @calls << [name, arguments]
    { "ok" => true, "lifecycle_state" => "complete", "data" => { "method" => name }, "mutation" => "none" }
  end
end

def parse_manifest(path)
  File.readlines(path).each_with_object({}) do |line, values|
    next if line.strip.empty?
    digest, name = line.strip.split(/\s+/, 2)
    values[name.to_s.sub(/^  /, "")] = digest
  end
end

Dir.mktmpdir("soul-long-form-mix-a2-") do |root|
  mix_service = FinalMixFixture.new
  render_service = FinalRenderFixture.new(root)
  export_parent = File.join(root, "Music")
  export_root = File.join(export_parent, "soul-music")
  final_root = File.join(export_root, "mixes", "finished")
  service = SoulCore::LongFormMixFinalizationService.new(
    root: root,
    mix_service: mix_service,
    render_service: render_service,
    export_parent: export_parent,
    export_root: export_root,
    final_root: final_root,
    clock: -> { Time.utc(2026, 7, 30, 22, 30, 0) }
  )
  mix_id = mix_service.mix.fetch("mix_id")

  status = service.status(mix_id: mix_id)
  check.call("status starts without a human review", status.dig("data", "review").nil?)
  blocked_without_review = service.export_preview(mix_id: mix_id)
  check.call("export waits for human listening review", blocked_without_review.fetch("lifecycle_state") == "awaiting_input")

  reject = service.record_review(mix_id: mix_id, review: {
    "sequence_cohesion" => "partial",
    "transition_quality" => "failed",
    "rating" => 2,
    "disposition" => "reject",
    "notes" => "Transition does not work."
  })
  check.call("reject review is recorded", reject.fetch("lifecycle_state") == "complete")
  check.call("reject cannot export", service.export_preview(mix_id: mix_id).fetch("lifecycle_state") == "awaiting_input")

  keep = service.record_review(mix_id: mix_id, review: {
    "sequence_cohesion" => "passed",
    "transition_quality" => "passed",
    "rating" => 4,
    "disposition" => "keep",
    "notes" => "The complete sequence and both transitions work."
  })
  check.call("corrected keep review is recorded", keep.fetch("lifecycle_state") == "complete")
  check.call("prior review history is preserved", keep.dig("data", "review_history_count") == 1)

  preview = service.export_preview(mix_id: mix_id)
  check.call("keep review reaches exact export gate", preview.fetch("lifecycle_state") == "blocked_for_human_review" && preview.fetch("ok"))
  check.call("exact export phrase is exposed", preview.dig("data", "confirmation_phrase") == SoulCore::LongFormMixFinalizationService::CONFIRMATION)
  expected = preview.dig("data", "expected_digest")

  wrong_phrase = service.export_execute(mix_id: mix_id, confirmation: "BAD", expected_digest: expected)
  check.call("wrong phrase fails closed", wrong_phrase.fetch("lifecycle_state") == "blocked_for_human_review")
  wrong_digest = service.export_execute(mix_id: mix_id, confirmation: SoulCore::LongFormMixFinalizationService::CONFIRMATION, expected_digest: "0" * 64)
  check.call("wrong digest fails closed", wrong_digest.fetch("lifecycle_state") == "blocked_for_human_review")

  execute = service.export_execute(mix_id: mix_id, confirmation: SoulCore::LongFormMixFinalizationService::CONFIRMATION, expected_digest: expected)
  check.call("exact accepted export completes", execute.fetch("lifecycle_state") == "complete")
  package = execute.dig("data", "accepted_export")
  destination = package.fetch("destination")
  check.call("accepted export stays in configured finished root", destination.start_with?("#{final_root}/"))
  check.call("accepted package is complete", SoulCore::LongFormMixFinalizationService::FINAL_FILES.all? { |name| File.file?(File.join(destination, name)) })
  manifest = parse_manifest(File.join(destination, "checksums.sha256"))
  check.call("accepted checksum inventory is exact", manifest.keys.sort == %w[listening.mp3 master.flac mix-info.md mix.json].sort)
  check.call("accepted checksums verify", manifest.all? { |name, value| Digest::SHA256.file(File.join(destination, name)).hexdigest == value })
  metadata = JSON.parse(File.read(File.join(destination, "mix.json")))
  check.call("metadata binds latest keep review", metadata.dig("review", "review_id") == keep.dig("data", "review", "review_id"))
  check.call("metadata remains honest about accepted audio", File.read(File.join(destination, "mix-info.md")).include?("not a mastered release"))

  replay = service.export_execute(mix_id: mix_id, confirmation: SoulCore::LongFormMixFinalizationService::CONFIRMATION, expected_digest: expected)
  check.call("accepted export is idempotent", replay.dig("data", "idempotent_replay") == true)

  revised = service.record_review(mix_id: mix_id, review: {
    "sequence_cohesion" => "partial",
    "transition_quality" => "partial",
    "rating" => 3,
    "disposition" => "revise",
    "notes" => "Preserve the old export, but revise the plan."
  })
  check.call("post-export correction is preserved", revised.dig("data", "review_history_count") == 2)
  corrected_status = service.status(mix_id: mix_id)
  check.call("latest revise no longer advertises accepted export", corrected_status.dig("data", "accepted_export").nil?)
  check.call("prior accepted package remains untouched", File.directory?(destination))

  second_root = File.join(root, "second")
  FileUtils.mkdir_p(second_root)
  second_render = FinalRenderFixture.new(second_root)
  second_service = SoulCore::LongFormMixFinalizationService.new(
    root: second_root,
    mix_service: mix_service,
    render_service: second_render,
    export_parent: File.join(second_root, "Music"),
    export_root: File.join(second_root, "Music", "soul-music"),
    final_root: File.join(second_root, "Music", "soul-music", "mixes", "finished")
  )
  second_service.record_review(mix_id: mix_id, review: {
    "sequence_cohesion" => "passed", "transition_quality" => "passed", "rating" => 5,
    "disposition" => "keep", "notes" => "Drift test."
  })
  drift_preview = second_service.export_preview(mix_id: mix_id)
  second_render.mutate_flac!
  drift = second_service.export_execute(
    mix_id: mix_id,
    confirmation: SoulCore::LongFormMixFinalizationService::CONFIRMATION,
    expected_digest: drift_preview.dig("data", "expected_digest")
  )
  check.call("render artifact drift blocks final copy", drift.fetch("lifecycle_state") == "blocked_for_human_review")

  third_root = File.join(root, "third")
  FileUtils.mkdir_p(third_root)
  third_render = FinalRenderFixture.new(third_root)
  third_service = SoulCore::LongFormMixFinalizationService.new(
    root: third_root,
    mix_service: mix_service,
    render_service: third_render,
    export_parent: File.join(third_root, "Music"),
    export_root: File.join(third_root, "Music", "soul-music"),
    final_root: File.join(third_root, "Music", "soul-music", "mixes", "finished")
  )
  third_service.record_review(mix_id: mix_id, review: {
    "sequence_cohesion" => "passed", "transition_quality" => "passed", "rating" => 5,
    "disposition" => "keep", "notes" => "Review identity tamper test."
  })
  review_path = File.join(third_root, "Soul", "private", "mix_reviews", "#{mix_id}.json")
  tampered_review = JSON.parse(File.read(review_path))
  tampered_review.fetch("latest")["review_id"] = "../escaped-review"
  File.write(review_path, JSON.pretty_generate(tampered_review), mode: "w", perm: 0o600)
  tampered_preview = third_service.export_preview(mix_id: mix_id)
  check.call("tampered review identity blocks export", tampered_preview.fetch("lifecycle_state") == "blocked_for_human_review")

  facade_fixture = FinalFacadeFixture.new
  facade = SoulCore::ApplicationFacade.new(root: root, long_form_mix_finalization_service: facade_fixture)
  requests = [
    ["mix.final.status", { "mix_id" => mix_id }],
    ["mix.final.review", { "mix_id" => mix_id, "review" => { "rating" => 4 } }],
    ["mix.final.export.preview", { "mix_id" => mix_id }],
    ["mix.final.export.execute", { "mix_id" => mix_id, "confirmation" => SoulCore::LongFormMixFinalizationService::CONFIRMATION, "expected_digest" => "a" * 64 }]
  ]
  requests.each do |operation, parameters|
    envelope = facade.call({
      "schema_version" => SoulCore::ApplicationContract::SCHEMA_VERSION,
      "request_id" => operation.tr(".", "-"),
      "operation" => operation,
      "parameters" => parameters,
      "context" => { "interface" => "dashboard" }
    })
    check.call("facade dispatches #{operation}", envelope.fetch("lifecycle_state") == "complete")
  end
  check.call("facade finalization dispatch order is stable", facade_fixture.calls.map(&:first) == requests.map(&:first))

  html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
  js = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
  check.call("dashboard exposes human mix review", html.include?("Human listening gate") && html.include?("mix-final-review-form"))
  check.call("dashboard exposes exact accepted export", html.include?("Export exact accepted mix"))
  check.call("dashboard wires finalization operations", %w[mix.final.status mix.final.review mix.final.export.preview mix.final.export.execute].all? { |operation| js.include?(operation) })
  check.call("dashboard states mastering and publication boundary", html.include?("does not master, publish, or assemble visuals"))
end

if failures.empty?
  puts "Long-form mix A2 finalization deterministic verification passed."
  exit 0
end

warn "Long-form mix A2 finalization verification failed: #{failures.join(", ")}"
exit 1
