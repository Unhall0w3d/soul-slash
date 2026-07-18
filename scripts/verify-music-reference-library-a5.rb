#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/application_contract"
require_relative "../lib/soul_core/application_facade"
require_relative "../lib/soul_core/music_reference_library_service"
require_relative "../lib/soul_core/music_reference_library_store"

failures = []
check = lambda do |name, value|
  puts "- #{name}: #{value ? 'ok' : 'FAILED'}"
  failures << name unless value
end

def provenance(source_id:, title:, artists:, album: nil)
  {
    "canonical_url" => "https://youtu.be/#{source_id}", "platform" => "youtube", "source_id" => source_id,
    "title" => title, "artists" => artists, "album" => album, "duration_seconds" => 212,
    "rights_assertion" => "analysis_only", "captured_at" => "2026-07-17T12:00:00Z",
    "musicbrainz" => {}, "tools" => { "metadata" => "fixture" }
  }
end

def evidence(bpm:, key: nil)
  {
    "status" => "reviewed", "bpm" => bpm, "bpm_alternatives" => [], "key" => key,
    "key_alternatives" => [], "meter" => "4/4", "sections" => ["intro", "verse", "chorus"],
    "instrumentation" => ["electric guitar", "drums"], "production_traits" => ["tight transient control"],
    "energy_curve" => ["restrained opening", "chorus lift"], "vocal_traits" => ["conversational verse"],
    "lyrical_traits" => ["internal rhyme", "compact phrases"], "confidence_notes" => ["fixture evidence"],
    "extractor_receipt" => { "kind" => "fixture" }
  }
end

Dir.mktmpdir("soul-music-reference-a5") do |root|
  ids = %w[1111111111111111 2222222222222222 3333333333333333 4444444444444444 5555555555555555]
  store = SoulCore::MusicReferenceLibraryStore.new(root: root, clock: -> { Time.utc(2026, 7, 17, 12) }, id_generator: -> { ids.shift })
  first = store.write_track({
    "status" => "approved", "provenance" => provenance(source_id: "abcDEF12345", title: "First signal", artists: ["Test Artist"], album: "Test Album"),
    "evidence" => evidence(bpm: 116, key: "D minor")
  })
  second = store.write_track({
    "status" => "candidate", "provenance" => provenance(source_id: "xyzXYZ98765", title: "Second signal", artists: ["Test Artist", "Guest Artist"]),
    "evidence" => evidence(bpm: 102)
  })
  fusion = store.write_fusion({
    "status" => "candidate", "title" => "Unified current", "source_reference_ids" => [first.fetch("reference_id"), second.fetch("reference_id")],
    "roles" => [
      { "reference_id" => first.fetch("reference_id"), "role" => "rhythmic language", "weight" => 0.55 },
      { "reference_id" => second.fetch("reference_id"), "role" => "song architecture", "weight" => 0.45 }
    ],
    "synthesis" => { "status" => "pending", "selected_revision_id" => nil, "revisions" => [] }
  })
  removable = store.write_track({
    "status" => "candidate", "provenance" => provenance(source_id: "delDEL45678", title: "Temporary profile", artists: ["Temporary Artist"]),
    "evidence" => evidence(bpm: 88, key: "A minor")
  })

  inventory = store.list
  artist = inventory.fetch("artists").find { |item| item["name"] == "Test Artist" }
  check.call("private records use exact schemas and stable identities", first["schema_version"] == "soul.music.reference.track.v1" && fusion["schema_version"] == "soul.music.reference.fusion.v1")
  check.call("inventory groups reviewed metadata without inventing an album", artist.fetch("albums").map { |item| item["title"] }.sort == ["Test Album", "Unresolved release"])
  check.call("multi-artist tracks appear in each credited artist profile", inventory.fetch("artists").find { |item| item["name"] == "Guest Artist" }.fetch("albums").first.fetch("tracks").first.fetch("reference_id") == second.fetch("reference_id"))
  check.call("fusion scope is constrained to two through five references", fusion.fetch("source_reference_ids").length == 2)
  check.call("single reference inspection is bounded", store.read(first.fetch("reference_id")).fetch("provenance").fetch("title") == "First signal")

  begin
    store.write_track({ "provenance" => provenance(source_id: "bad12345678", title: "Bad", artists: ["Test"]).merge("canonical_url" => "http://127.0.0.1/private") })
    bad_url_rejected = false
  rescue SoulCore::MusicReferenceLibraryStore::ValidationError
    bad_url_rejected = true
  end
  check.call("non-HTTPS and local-network source URLs are rejected", bad_url_rejected)

  service = SoulCore::MusicReferenceLibraryService.new(root: root, store: store)
  facade = SoulCore::ApplicationFacade.new(root: root, music_reference_library_service: service)
  request = {
    "schema_version" => "soul.application.v1", "request_id" => "music-reference-a5-0001",
    "operation" => "music.references.list", "parameters" => { "limit" => 25 }, "context" => { "interface" => "dashboard" }
  }
  result = facade.call(request)
  check.call("typed read-only application operation returns terminal inventory", SoulCore::ApplicationContract.validate(request)["ok"] == true && result["lifecycle_state"] == "complete" && result.dig("meta", "mutation") == "none")

  dependent = service.deletion_preview(identifier: first.fetch("reference_id"))
  preview = service.deletion_preview(identifier: removable.fetch("reference_id"))
  wrong = service.delete(identifier: removable.fetch("reference_id"), confirmation: "yes", expected_digest: preview.dig("data", "expected_digest"))
  check.call("fusion dependencies block reference deletion", dependent["lifecycle_state"] == "blocked_for_human_review" && dependent.dig("data", "dependent_fusion_ids") == [fusion.fetch("fusion_id")])
  check.call("reference deletion previews exact provenance evidence and synthesis scope", preview.dig("data", "confirmation_phrase") == "DELETE_MUSIC_REFERENCE" && preview.dig("data", "preview_scope", "title") == "Temporary profile")
  check.call("wrong reference deletion confirmation preserves profile", wrong["lifecycle_state"] == "blocked_for_human_review" && store.read(removable.fetch("reference_id"))["reference_id"] == removable.fetch("reference_id"))
  deleted = service.delete(identifier: removable.fetch("reference_id"), confirmation: "DELETE_MUSIC_REFERENCE", expected_digest: preview.dig("data", "expected_digest"))
  inventory_after_delete = store.list
  check.call("exact reference deletion removes profile and derived artist grouping", deleted["lifecycle_state"] == "complete" && inventory_after_delete.fetch("tracks").none? { |item| item["reference_id"] == removable.fetch("reference_id") } && inventory_after_delete.fetch("artists").none? { |item| item["name"] == "Temporary Artist" })
end

Dir.mktmpdir("soul-music-reference-symlink") do |root|
  FileUtils.mkdir_p(File.join(root, "Soul", "music"))
  File.symlink(Dir.tmpdir, File.join(root, "Soul", "music", "references"))
  begin
    SoulCore::MusicReferenceLibraryStore.new(root: root).list
    symlink_rejected = false
  rescue SoulCore::MusicReferenceLibraryStore::IntegrityError
    symlink_rejected = true
  end
  check.call("reference storage rejects symlink traversal", symlink_rejected)
end

html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
css = File.read(File.expand_path("../assets/dashboard/dashboard.css", __dir__))
js = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
brief = File.read(File.expand_path("../docs/soul/MUSIC_REFERENCE_LIBRARY_AND_URL_INGESTION_DESIGN.md", __dir__))
check.call("Music Studio exposes Artist Album Track and Fusion inventory", %w[music-reference-library music-reference-list music-fusion-list].all? { |needle| html.include?(needle) } && js.include?("music.references.list"))
check.call("reference foundation exposes the separately gated URL intake seam", html.include?('id="music-reference-url"') && html.include?('id="preview-music-reference"') && html.include?("ANALYZE_MUSIC_REFERENCE"))
check.call("track profiles expose exact permanent deletion", %w[preview-music-reference-delete music-reference-delete-confirmation delete-music-reference].all? { |needle| html.include?(needle) } && js.include?("music.references.delete.preview") && js.include?("music.references.delete.execute"))
check.call("reference library moves beneath the workbench at narrow widths", css.include?(".music-reference-library { grid-column:1/-1"))
check.call("A5.1 adds no browser polling or remote dependency", %w[setInterval setTimeout WebSocket EventSource serviceWorker innerHTML].none? { |needle| js.include?(needle) } && ![html, js].any? { |source| source.match?(%r{(?:src|href)=["']https?://}) })
check.call("brief keeps URL analysis foreground and transient", brief.include?("ANALYZE_MUSIC_REFERENCE") && brief.include?("raw source transcription are removed") && brief.include?("There is no queue"))

abort "Music reference library A5 verification failed: #{failures.join(', ')}" unless failures.empty?
puts "Music reference library A5.1 deterministic verification passed."
