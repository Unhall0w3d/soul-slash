#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/application_contract"
require_relative "../lib/soul_core/music_project_deletion_service"
require_relative "../lib/soul_core/music_project_store"

failures = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'FAILED'}"
  failures << label unless condition
end

class DeletionCoordinatorFixture
  attr_accessor :active
  def initialize(active = false) = (@active = active)
  def active_project?(_project_id) = @active
end

def project_input(title = "Deletion fixture")
  {
    "title" => title, "intent" => "Verify bounded archive deletion.", "target_duration_seconds" => 30,
    "vocal_mode" => "instrumental", "rights_status" => "original", "caption" => "Sparse test signal.",
    "lyrics" => "", "bpm" => 90, "keyscale" => "C minor", "timesignature" => "4", "language" => "en", "seed" => 17
  }
end

Dir.mktmpdir("soul-project-delete-") do |root|
  store = SoulCore::MusicProjectStore.new(root: root, id_generator: -> { "1" * 16 }, clock: -> { Time.utc(2026, 7, 17, 12) })
  project = store.create(project_input)
  project_path = store.project_path(project.fetch("project_id"))
  external = File.join(root, "Music", "soul-music", "deletion-fixture")
  FileUtils.mkdir_p(external); File.write(File.join(external, "master.flac"), "retained")
  File.write(File.join(project_path, "exports", "candidate_2222222222222222.json"), JSON.generate("destination" => external))
  FileUtils.mkdir_p(File.join(project_path, "generations", "candidate_2222222222222222"))
  File.write(File.join(project_path, "generations", "candidate_2222222222222222", "listening.mp3"), "archive audio")
  coordinator = DeletionCoordinatorFixture.new
  service = SoulCore::MusicProjectDeletionService.new(root: root, project_store: store, coordinator: coordinator)

  preview = service.preview(project_id: project.fetch("project_id"))
  wrong = service.execute(project_id: project.fetch("project_id"), confirmation: "yes", expected_digest: preview.dig("data", "expected_digest"))
  check.call("project deletion previews an exact bounded inventory and retained export", preview["lifecycle_state"] == "blocked_for_human_review" && preview.dig("data", "confirmation_phrase") == "DELETE_MUSIC_PROJECT" && preview.dig("data", "preview_scope", "retained_finished_exports") == [external])
  check.call("wrong deletion confirmation preserves project and external export", wrong["lifecycle_state"] == "blocked_for_human_review" && File.directory?(project_path) && File.file?(File.join(external, "master.flac")))

  File.write(File.join(project_path, "inputs", "late.json"), "{}")
  stale = service.execute(project_id: project.fetch("project_id"), confirmation: "DELETE_MUSIC_PROJECT", expected_digest: preview.dig("data", "expected_digest"))
  check.call("project mutation invalidates deletion preview", stale["lifecycle_state"] == "blocked_for_human_review" && File.directory?(project_path))
  preview = service.preview(project_id: project.fetch("project_id"))
  coordinator.active = true
  busy = service.execute(project_id: project.fetch("project_id"), confirmation: "DELETE_MUSIC_PROJECT", expected_digest: preview.dig("data", "expected_digest"))
  check.call("active foreground work blocks project deletion", busy["lifecycle_state"] == "blocked_for_human_review" && File.directory?(project_path))
  coordinator.active = false
  deleted = service.execute(project_id: project.fetch("project_id"), confirmation: "DELETE_MUSIC_PROJECT", expected_digest: preview.dig("data", "expected_digest"))
  check.call("exact deletion removes archive project and retains finished export", deleted["lifecycle_state"] == "complete" && !File.exist?(project_path) && File.read(File.join(external, "master.flac")) == "retained")
end

Dir.mktmpdir("soul-project-delete-symlink-") do |root|
  store = SoulCore::MusicProjectStore.new(root: root, id_generator: -> { "3" * 16 })
  project = store.create(project_input("Symlink fixture")); outside = Dir.mktmpdir("soul-project-delete-outside-")
  File.symlink(outside, File.join(store.project_path(project.fetch("project_id")), "inputs", "escape"))
  preview = SoulCore::MusicProjectDeletionService.new(root: root, project_store: store, coordinator: DeletionCoordinatorFixture.new).preview(project_id: project.fetch("project_id"))
  check.call("project inventory rejects symlink traversal", preview["lifecycle_state"] == "blocked_for_human_review" && File.directory?(outside))
  FileUtils.remove_entry_secure(outside)
end

check.call("typed contract exposes exact project deletion gates", %w[music.projects.delete.preview music.projects.delete.execute].all? { |operation| SoulCore::ApplicationContract::OPERATIONS.key?(operation) })
html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__)); js = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
check.call("Music Studio exposes bounded project deletion review", %w[music-project-delete-card preview-music-project-delete music-project-delete-confirmation execute-music-project-delete].all? { |id| html.include?(id) } && js.include?("music.projects.delete.preview") && js.include?("music.projects.delete.execute"))

abort "Music project deletion verification failed: #{failures.join(', ')}" unless failures.empty?
puts "Music project deletion deterministic verification passed."
