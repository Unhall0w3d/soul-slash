#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/application_contract"
require_relative "../lib/soul_core/project_release_service"

failures = []
check = lambda do |label, condition|
  puts "#{condition ? 'PASS' : 'FAIL'}: #{label}"
  failures << label unless condition
end

Dir.mktmpdir("soul-project-release-") do |root|
  music_id = "music_#{'a' * 16}"
  visual_id = "visual_project_#{'b' * 16}"
  music = File.join(root, "Soul", "music", "projects", music_id)
  visual = File.join(root, "Soul", "visual", "projects", visual_id)
  [music, visual].each { |path| FileUtils.mkdir_p(path) }
  candidate = File.join(music, "candidate.bin")
  binding = File.join(root, "Soul", "bindings.json")
  FileUtils.mkdir_p(File.dirname(binding))
  File.binwrite(candidate, "immutable candidate")
  File.write(binding, JSON.generate("music_project_id" => music_id, "visual_project_id" => visual_id))
  before = [Digest::SHA256.file(candidate).hexdigest, Digest::SHA256.file(binding).hexdigest]

  service = SoulCore::ProjectReleaseService.new(root: root, clock: -> { Time.utc(2026, 7, 26, 20) })
  music_release = service.release(kind: "music", project_id: music_id)
  visual_release = service.release(kind: "visual", project_id: visual_id)
  decorated = service.decorate_outcome({ "ok" => true, "data" => { "projects" => [{ "project_id" => music_id }] } }, kind: "music")
  after_release = [Digest::SHA256.file(candidate).hexdigest, Digest::SHA256.file(binding).hexdigest]
  check.call("music and visual projects enter Released without changing identity", music_release.dig("data", "project_id") == music_id && visual_release.dig("data", "project_id") == visual_id && decorated.dig("data", "projects", 0, "release_state") == "released")
  check.call("release leaves candidates and cross-studio bindings byte-identical", before == after_release)

  restored = service.restore(kind: "music", project_id: music_id)
  active = service.decorate_outcome({ "ok" => true, "data" => { "project" => { "project_id" => music_id } } }, kind: "music")
  check.call("restore returns the same project to Active", restored["lifecycle_state"] == "complete" && active.dig("data", "project", "release_state") == "active")
  check.call("restore is idempotent and preserves binding bytes", service.restore(kind: "music", project_id: music_id)["ok"] && before.last == Digest::SHA256.file(binding).hexdigest)

  outside = Dir.mktmpdir("soul-project-release-outside-")
  bad_id = "music_#{'c' * 16}"
  File.symlink(outside, File.join(root, "Soul", "music", "projects", bad_id))
  rejected = service.release(kind: "music", project_id: bad_id)
  check.call("symlink project roots fail safely", rejected["lifecycle_state"] == "awaiting_input" && Dir.empty?(outside))
  FileUtils.remove_entry_secure(outside)
end

operations = %w[music.projects.release music.projects.restore visual.projects.release visual.projects.restore]
check.call("typed application contract exposes reversible release operations", operations.all? { |operation| SoulCore::ApplicationContract::OPERATIONS.key?(operation) })
html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
javascript = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
check.call("both studios expose Active and Released folders", %w[music-folder-active music-folder-released visual-folder-active visual-folder-released].all? { |id| html.include?(id) })
check.call("both studios expose release and restore actions", operations.all? { |operation| javascript.include?(operation) })

abort "Project release folder verification failed: #{failures.join(', ')}" unless failures.empty?
puts "Project release folder deterministic verification passed."
