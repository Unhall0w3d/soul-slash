#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "fileutils"
require "tmpdir"
require "time"

require_relative "../lib/soul_core/application_contract"
require_relative "../lib/soul_core/application_facade"
require_relative "../lib/soul_core/self_improvement_service"
require_relative "../lib/soul_core/storage_retention_assessor"

Result = Struct.new(:status, :stdout, :stderr, :exit_status, keyword_init: true) do
  def success? = status == "ok"
end

class StorageRunner
  def run(*argv, **_options)
    if argv.first == "du"
      path = argv.last
      bytes = if File.file?(path)
        File.size(path)
      elsif File.directory?(path)
        Dir.glob(File.join(path, "**", "*"), File::FNM_DOTMATCH).sum { |item| File.file?(item) && !File.symlink?(item) ? File.size(item) : 0 }
      else
        0
      end
      Result.new(status: "ok", stdout: "#{bytes}\t#{path}\n", stderr: "", exit_status: 0)
    elsif argv.first == "systemctl"
      Result.new(status: "ok", stdout: "MemoryCurrent=104857600\nMemoryPeak=209715200\nActiveState=active\nSubState=running\n", stderr: "", exit_status: 0)
    else
      Result.new(status: "failed", stdout: "", stderr: "unexpected command", exit_status: 1)
    end
  end
end

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

Dir.mktmpdir("soul-storage-a1-") do |sandbox|
  root = File.join(sandbox, "repo")
  home = File.join(sandbox, "home")
  temp = File.join(sandbox, "tmp")
  [root, home, temp].each { |path| Dir.mkdir(path) }
  now = Time.utc(2026, 7, 18, 18, 0, 0)
  old = now - (31 * 24 * 60 * 60)

  private_music = File.join(root, "Soul", "music")
  logs = File.join(root, "Soul", "logs")
  quarantine = File.join(private_music, "projects", "music_aaaaaaaaaaaaaaaa", "generations", ".candidate_bbbbbbbbbbbbbbbb.partial")
  memory = File.join(root, "Soul", "memory")
  production = File.join(home, ".local", "share", "soul", "music", "acestep-cpp")
  [private_music, logs, quarantine, memory, production].each { |path| FileUtils.mkdir_p(path) }
  File.write(File.join(private_music, "project.json"), "private")
  File.write(File.join(memory, "context.yaml"), "shared")
  File.write(File.join(production, "model.gguf"), "model")
  old_log = File.join(logs, "old.json"); File.write(old_log, "old log"); File.utime(old, old, old_log)
  File.write(File.join(logs, "current.json"), "current log")
  failure = File.join(quarantine, "failure.json"); File.write(failure, "failure"); File.utime(old, old, quarantine)

  known = File.join(temp, "soul-acestep-cpp-review-old"); Dir.mkdir(known); File.write(File.join(known, "trace"), "trace"); File.utime(old, old, known)
  recent = File.join(temp, "soul-whisper-recent"); Dir.mkdir(recent); File.write(File.join(recent, "trace"), "trace")
  unknown = File.join(temp, "soul-mystery-state"); Dir.mkdir(unknown); File.write(File.join(unknown, "state"), "state"); File.utime(old, old, unknown)

  assessor = SoulCore::StorageRetentionAssessor.new(root: root, home: home, temp_root: temp, runner: StorageRunner.new, clock: -> { now })
  inventory = assessor.inventory
  temp_category = inventory.fetch("categories").find { |item| item["id"] == "temporary_soul_residue" }
  protected = inventory.fetch("categories").select { |item| item["retention"] == "protected" }.map { |item| item["id"] }
  check.call("inventory is metadata-only and terminal", inventory["status"] == "ok" && inventory["read_only"] && inventory.dig("verification", "files_changed") == false)
  check.call("private projects models memory and exports remain protected", %w[private_music_projects production_music_runtime music_pilot_evidence transcription_runtime finished_music_exports shared_memory].all? { |id| protected.include?(id) })
  check.call("unknown Soul temporary residue is visible but protected", temp_category["blocked"] == "unknown Soul-prefixed residue is protected")
  check.call("dashboard memory is point-in-time with no sampler", inventory.dig("dashboard_memory", "current_bytes") == 104_857_600 && inventory.dig("dashboard_memory", "peak_bytes") == 209_715_200 && inventory.dig("dashboard_memory", "background_sampling") == false)

  temp_preview = assessor.preview(category: "temp_review_artifacts")
  temp_entries = temp_preview.dig("data", "entries")
  check.call("temporary preview includes only owned allowlisted aged entries", temp_preview["lifecycle_state"] == "complete" && temp_entries.length == 1 && temp_entries.first["path"].end_with?("soul-acestep-cpp-review-old"))
  check.call("preview binds exact scope but exposes no execution", temp_preview.dig("data", "expected_digest").match?(/\A[a-f0-9]{64}\z/) && temp_preview.dig("data", "execution_available") == false)

  log_preview = assessor.preview(category: "expired_project_logs")
  check.call("log preview includes old regular files but not current logs", log_preview.dig("data", "entries").length == 1 && log_preview.dig("data", "entries", 0, "path").end_with?("old.json"))
  quarantine_preview = assessor.preview(category: "failed_music_quarantine")
  check.call("quarantine preview is path-shaped and age-bounded", quarantine_preview.dig("data", "entries").length == 1 && quarantine_preview.dig("data", "entries", 0, "type") == "directory")

  lease_root = File.join(root, "Soul", "runtime", "music"); FileUtils.mkdir_p(lease_root); File.write(File.join(lease_root, "amd-music.json"), "{}")
  blocked = assessor.preview(category: "failed_music_quarantine")
  check.call("active music lease blocks quarantine preview", blocked["lifecycle_state"] == "blocked_for_human_review")
  File.delete(File.join(lease_root, "amd-music.json"))
  check.call("unknown cleanup category awaits bounded input", assessor.preview(category: "everything")["lifecycle_state"] == "awaiting_input")

  service = SoulCore::SelfImprovementService.new(root: root, storage_assessor: assessor, environment_assessor: Object.new, assessment_timeout_seconds: 2)
  storage = service.refresh(scope: "storage")
  check.call("Self Assessment exposes Storage as an explicit foreground scope", SoulCore::SelfImprovementService::SCOPES.include?("storage") && storage["lifecycle_state"] == "complete" && storage.dig("data", "assessment_scope") == "storage")
  check.call("application contract exposes preview without execute", SoulCore::ApplicationContract::OPERATIONS.key?("storage_retention.cleanup.preview") && !SoulCore::ApplicationContract::OPERATIONS.key?("storage_retention.cleanup.execute"))
  facade = SoulCore::ApplicationFacade.new(root: root, self_improvement_service: service)
  envelope = facade.call({ "schema_version" => "soul.application.v1", "request_id" => "storage-preview-fixture", "operation" => "storage_retention.cleanup.preview", "parameters" => { "category" => "temp_review_artifacts" }, "context" => { "interface" => "dashboard_test" } })
  check.call("application facade dispatches the read-only preview contract", envelope["lifecycle_state"] == "complete" && envelope.dig("data", "execution_available") == false)

  check.call("read-only assessment and previews changed no fixture content", File.read(old_log) == "old log" && File.read(failure) == "failure" && File.directory?(known) && File.directory?(quarantine))
end

html = File.read(File.join(__dir__, "../assets/dashboard/index.html"))
js = File.read(File.join(__dir__, "../assets/dashboard/dashboard.js"))
brief = File.read(File.join(__dir__, "../docs/soul/STORAGE_AND_RETENTION_A1_BRIEF.md"))
check.call("dashboard exposes Storage inventory and preview-only category control", html.include?('data-assessment-scope="storage"') && html.include?('id="preview-storage-cleanup"') && js.include?("storage_retention.cleanup.preview"))
check.call("dashboard storage inspection remains manual and timer-free", !js.match?(/setInterval|setTimeout|requestAnimationFrame/) && js.include?("point-in-time only"))
check.call("approved brief prohibits automatic or destructive cleanup", brief.include?("A1 registers no cleanup execute operation") && brief.include?("scheduled cleanup") && brief.include?("never followed"))

abort(errors.map { |error| "- #{error}" }.join("\n")) unless errors.empty?
puts "Storage and Retention A1 is candidate-ready for human review."
