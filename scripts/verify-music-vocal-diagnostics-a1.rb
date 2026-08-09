#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/soul_core/application_contract"
require_relative "../lib/soul_core/application_facade"
require_relative "../lib/soul_core/music_vocal_diagnostic_service"

class VocalDiagnosticGenerationFixture
  def initialize(project:, candidates: [])
    @project = project
    @candidates = candidates
  end

  def inspect_project(project_id:)
    raise "unexpected project" unless project_id == @project.fetch("project_id")
    { "lifecycle_state" => "complete", "ok" => true, "data" => { "project" => @project, "generations" => @candidates } }
  end
end

class VocalDiagnosticAnalysisFixture
  def initialize(analyses = {}) = @analyses = analyses
  def read(project_id:, candidate_id:) = @analyses[[project_id, candidate_id]]
end

def project(mode: "vocal", caption: "Clear close vocal over restrained drums.", lyrics: "[Verse - whispered]\nThe signal bends but does not break")
  { "project_id" => "music_#{'1' * 16}", "title" => "Fixture", "vocal_mode" => mode, "caption" => caption, "lyrics" => lyrics }
end

def candidate(id, adherence: nil, generated_lyrics: nil)
  record = { "candidate_id" => id, "created_at" => "2026-08-08T12:00:00Z" }
  record["review"] = { "lyric_adherence" => adherence } if adherence
  record["generation_input"] = { "lyrics" => generated_lyrics } if generated_lyrics
  record
end

checks = 0
failures = []
check = lambda do |label, condition|
  checks += 1
  failures << label unless condition
end

clear_project = project
clear = SoulCore::MusicVocalDiagnosticService.new(
  music_generation: VocalDiagnosticGenerationFixture.new(project: clear_project),
  analysis_service: VocalDiagnosticAnalysisFixture.new
).inspect(project_id: clear_project.fetch("project_id"))
check.call("anchored whispered section is not misclassified as an unanchored pseudo-section",
           clear.dig("data", "preflight", "tags", 0, "classification") == "anchored_structure_with_modifier" &&
             !clear.dig("data", "preflight", "risks").any? { |risk| risk["code"] == "unanchored_performance_sections" })
check.call("diagnostic remains advisory and does not block generation",
           clear.dig("data", "authority") == {
             "classification" => "advisory_read_only", "human_review_required" => true,
             "blocks_generation" => false, "automatic_rewrite" => false, "automatic_generation" => false
           })

risky_project = project(
  caption: "Chopped whispers moving between near and impossible distance.",
  lyrics: "[Whisper]\nNot here.\n\n[Broken transmission]\nTurn around.\n\n[Almost inaudible]\nIt remembers."
)
candidates = [
  candidate("candidate_#{'2' * 16}"),
  candidate("candidate_#{'3' * 16}", adherence: "failed"),
  candidate("candidate_#{'4' * 16}", adherence: "failed"),
  candidate("candidate_#{'5' * 16}", adherence: "passed", generated_lyrics: "[Instrumental]")
]
analysis = {
  [risky_project.fetch("project_id"), "candidate_#{'3' * 16}"] => {
    "alignment" => { "sequence_recall" => 0.2 }, "machine_route" => "revision_recommended"
  }
}
risky = SoulCore::MusicVocalDiagnosticService.new(
  music_generation: VocalDiagnosticGenerationFixture.new(project: risky_project, candidates: candidates),
  analysis_service: VocalDiagnosticAnalysisFixture.new(analysis)
).inspect(project_id: risky_project.fetch("project_id"))
codes = risky.dig("data", "preflight", "risks").map { |risk| risk.fetch("code") }
check.call("masking, fragmentation, pacing, and unanchored tags are explicit",
           %w[line_pacing unanchored_performance_sections obscured_intelligibility sparse_fragmentation].all? { |code| codes.include?(code) })
check.call("structured failures exclude the unreviewed candidate",
           risky.dig("data", "state") == "repeated_adherence_failure" &&
             risky.dig("data", "attempts", "candidate_count") == 4 &&
             risky.dig("data", "attempts", "vocal_candidate_count") == 3 &&
             risky.dig("data", "attempts", "excluded_instrumental_candidate_count") == 1 &&
             risky.dig("data", "attempts", "reviewed_count") == 2 &&
             risky.dig("data", "attempts", "unreviewed_count") == 1 &&
             risky.dig("data", "attempts", "lyric_failed_reviews") == 2)
check.call("machine evidence reports measured recall without converting prose notes into facts",
           risky.dig("data", "attempts", "analysis_count") == 1 &&
             risky.dig("data", "attempts", "best_sequence_recall") == 0.2)

instrumental_project = project(mode: "instrumental", lyrics: "[Instrumental]")
instrumental = SoulCore::MusicVocalDiagnosticService.new(
  music_generation: VocalDiagnosticGenerationFixture.new(project: instrumental_project),
  analysis_service: VocalDiagnosticAnalysisFixture.new
).inspect(project_id: instrumental_project.fetch("project_id"))
check.call("instrumental projects terminate cleanly without false vocal warnings",
           instrumental.dig("data", "state") == "not_applicable" &&
             instrumental.dig("data", "preflight", "risks") == [])

contract = SoulCore::ApplicationContract::OPERATIONS
facade = File.read(File.expand_path("../lib/soul_core/application_facade.rb", __dir__))
html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
javascript = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
brief = File.read(File.expand_path("../docs/soul/MUSIC_VOCAL_FEASIBILITY_AND_FAILURE_DIAGNOSTICS_A1_BRIEF.md", __dir__))
check.call("one project-scoped read-only facade operation is exposed",
           contract["music.vocals.diagnostic"] == ["project_id"] &&
             facade.include?('when "music.vocals.diagnostic"') &&
             facade.include?("MusicVocalDiagnosticService.new"))
facade_fixture = Object.new
facade_fixture.define_singleton_method(:inspect) do |project_id:|
  { "lifecycle_state" => "complete", "ok" => true, "message" => "fixture", "data" => { "project_id" => project_id, "state" => "preflight_clear" } }
end
envelope = SoulCore::ApplicationFacade.new(root: Dir.pwd, music_vocal_diagnostic_service: facade_fixture).call({
  "schema_version" => SoulCore::ApplicationContract::SCHEMA_VERSION,
  "request_id" => "vocal-diagnostic-test-0001",
  "operation" => "music.vocals.diagnostic",
  "parameters" => { "project_id" => clear_project.fetch("project_id") },
  "context" => { "interface" => "dashboard_test" }
})
check.call("facade dispatch remains read-only and terminal",
           envelope["lifecycle_state"] == "complete" &&
             envelope.dig("data", "project_id") == clear_project.fetch("project_id") &&
             envelope.dig("meta", "mutation") == "none")
check.call("Music Studio renders diagnostic evidence without polling or mutation controls",
           html.include?('id="music-vocal-diagnostic-card"') &&
             javascript.include?('callSoul("music.vocals.diagnostic"') &&
             !javascript.match?(/music\.vocals\.diagnostic.{0,200}(?:setInterval|setTimeout)/m))
check.call("brief preserves human authority and nonblocking behavior",
           brief.include?("Warnings are advisory") && brief.include?("does not rewrite") && brief.include?("No new memory store"))

abort "Music vocal diagnostic A1 verification failed: #{failures.join(', ')}" unless failures.empty?
puts "PASS: #{checks} music vocal diagnostic A1 checks"
