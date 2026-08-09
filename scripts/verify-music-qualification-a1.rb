#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/soul_core/application_contract"
require_relative "../lib/soul_core/application_facade"
require_relative "../lib/soul_core/music_qualification_service"

class MusicQualificationFixture
  attr_reader :inspections

  def initialize(states: {}, missing: [], inspection_failure: nil)
    @states = states
    @missing = missing
    @inspection_failure = inspection_failure
    @inspections = 0
  end

  def list_projects(limit:)
    raise "unbounded fixture listing" unless limit == 200

    projects = SoulCore::MusicQualificationService::TARGET_DURATIONS.filter_map do |duration|
      project(duration) unless @missing.include?(duration)
    end
    projects << project(600)
    complete("projects" => projects)
  end

  def inspect_project(project_id:)
    @inspections += 1
    duration = Integer(project_id.delete_prefix("project-"))
    return { "lifecycle_state" => "failed", "ok" => false, "reason" => "fixture inspection failure" } if @inspection_failure == duration

    state = @states.fetch(duration, :keep)
    complete("project" => project(duration), "generations" => state == :none ? [] : [candidate(duration, state)])
  end

  private

  def project(duration)
    {
      "project_id" => "project-#{duration}",
      "title" => "Fixture #{duration}",
      "target_duration_seconds" => duration,
      "vocal_mode" => false
    }
  end

  def candidate(duration, state)
    disposition = { keep: "keep", revise: "revise", reject: "reject" }[state]
    artifact_duration = state == :technical_failure ? duration - 8 : duration
    {
      "candidate_id" => "candidate-#{duration}",
      "created_at" => "2026-08-08T12:00:00Z",
      "generation_kind" => "initial",
      "artifacts" => {
        "flac" => {
          "duration_seconds" => artifact_duration,
          "sample_rate" => 48_000,
          "channels" => 2,
          "codec" => "flac"
        }
      },
      "timings" => { "total_seconds" => 90.25 },
      "review" => disposition && {
        "disposition" => disposition,
        "musical_quality" => "passed",
        "prompt_adherence" => "passed",
        "overall_rating" => 4,
        "notes" => "Human fixture evidence."
      }
    }
  end

  def complete(data)
    { "lifecycle_state" => "complete", "ok" => true, "data" => data }
  end
end

checks = 0
failures = []
check = lambda do |label, condition|
  checks += 1
  failures << label unless condition
end

ready_fixture = MusicQualificationFixture.new
ready = SoulCore::MusicQualificationService.new(music_generation: ready_fixture).snapshot
check.call("five-duration evidence becomes ready only for a human decision",
           ready["lifecycle_state"] == "complete" &&
             ready.dig("data", "evidence_state") == "ready_for_human_qualification_decision" &&
             ready.dig("data", "qualification_authority") == "human" &&
             !ready.dig("data", "automatic_qualification") &&
             ready["mutation"] == "none" &&
             ready_fixture.inspections == 5)
check.call("unrelated supported durations are excluded from the qualification cohort",
           ready.dig("data", "project_count") == 5 &&
             ready.dig("data", "coverage").map { |row| row.fetch("duration_seconds") } == [43, 57, 71, 144, 248])

missing = SoulCore::MusicQualificationService.new(
  music_generation: MusicQualificationFixture.new(missing: [71])
).snapshot
check.call("missing technical duration evidence remains explicit",
           missing.dig("data", "evidence_state") == "duration_gaps" &&
             missing.dig("data", "next_review").include?("71"))

unreviewed = SoulCore::MusicQualificationService.new(
  music_generation: MusicQualificationFixture.new(states: { 57 => :unreviewed })
).snapshot
check.call("an unreviewed latest candidate blocks qualification",
           unreviewed.dig("data", "evidence_state") == "unreviewed_candidates" &&
             unreviewed.dig("data", "unreviewed_count") == 1 &&
             unreviewed.dig("data", "next_review").include?("Fixture 57"))

revision = SoulCore::MusicQualificationService.new(
  music_generation: MusicQualificationFixture.new(states: { 71 => :revise })
).snapshot
check.call("reviewed revision evidence is not mistaken for an accepted duration",
           revision.dig("data", "evidence_state") == "revision_required" &&
             revision.dig("data", "next_review").include?("71"))

bad_artifact = SoulCore::MusicQualificationService.new(
  music_generation: MusicQualificationFixture.new(states: { 144 => :technical_failure })
).snapshot
check.call("duration drift fails technical qualification even with retained evidence",
           bad_artifact.dig("data", "evidence_state") == "duration_gaps" &&
             !bad_artifact.dig("data", "coverage").find { |row| row["duration_seconds"] == 144 }.fetch("technical_evidence_present"))

failure = SoulCore::MusicQualificationService.new(
  music_generation: MusicQualificationFixture.new(inspection_failure: 248)
).snapshot
check.call("project inspection failure terminates as archive attention",
           failure.dig("data", "evidence_state") == "archive_attention" &&
             failure.dig("data", "inspection_failures").length == 1)

contract = SoulCore::ApplicationContract::OPERATIONS
facade = File.read(File.expand_path("../lib/soul_core/application_facade.rb", __dir__))
html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
javascript = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
brief = File.read(File.expand_path("../docs/soul/CREATIVE_QUALIFICATION_PROGRAM_A1_BRIEF.md", __dir__))
check.call("facade contract exposes one parameterless read-only operation",
           contract["music.qualification"] == [] &&
             facade.include?('when "music.qualification"') &&
             facade.include?("MusicQualificationService.new"))
check.call("Music Studio exposes a manual evidence refresh without a polling loop",
           html.include?('id="refresh-music-qualification"') &&
             html.include?('id="music-qualification-summary"') &&
             javascript.include?('callSoul("music.qualification"') &&
             !javascript.match?(/music.qualification.{0,160}(?:setInterval|setTimeout)/m))
check.call("brief preserves read-only and human-authority boundaries",
           brief.include?("read-only") &&
           brief.include?("Do not generate") &&
             brief.include?("Operator") &&
             brief.include?("No worker, queue, watcher") &&
             brief.include?("background polling"))

abort "Music qualification A1 verification failed: #{failures.join(', ')}" unless failures.empty?
puts "PASS: #{checks} Music qualification A1 checks"
