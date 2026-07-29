#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require "time"

require_relative "../lib/soul_core/application_contract"
require_relative "../lib/soul_core/application_facade"
require_relative "../lib/soul_core/self_improvement_service"
require_relative "../lib/soul_core/storage_retention_assessor"

Result = Struct.new(:status, :stdout, :stderr, :exit_status, keyword_init: true) do
  def success? = status == "ok"
end

class CleanupRunner
  def run(*argv, **_options)
    if argv.first == "du"
      path = argv.last
      bytes = if File.file?(path)
        File.size(path)
      elsif File.directory?(path)
        Dir.glob(File.join(path, "**", "*"), File::FNM_DOTMATCH).sum do |entry|
          File.file?(entry) && !File.symlink?(entry) ? File.size(entry) : 0
        end
      else
        0
      end
      Result.new(status: "ok", stdout: "#{bytes}\t#{path}\n", stderr: "", exit_status: 0)
    elsif argv.first == "systemctl"
      Result.new(status: "ok", stdout: "MemoryCurrent=1\nMemoryPeak=2\nActiveState=active\nSubState=running\n", stderr: "", exit_status: 0)
    else
      Result.new(status: "failed", stdout: "", stderr: "unexpected command", exit_status: 1)
    end
  end
end

class PartialFailureCleanupAssessor < SoulCore::StorageRetentionAssessor
  private

  def remove_staged_candidate!(candidate)
    @remove_count = @remove_count.to_i + 1
    return super if @remove_count == 1
    raise Errno::EIO, candidate.fetch("staging_path")
  end
end

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

touch_tree = lambda do |path, at|
  entries = Dir.glob(File.join(path, "**", "*"), File::FNM_DOTMATCH)
  entries.select { |entry| File.file?(entry) && !File.symlink?(entry) }.each { |entry| File.utime(at, at, entry) }
  entries.select { |entry| File.directory?(entry) && !File.symlink?(entry) }.sort_by { |entry| -entry.length }.each { |entry| File.utime(at, at, entry) }
  File.utime(at, at, path)
end

make_assessor = lambda do |root, home, temp, now, klass = SoulCore::StorageRetentionAssessor|
  klass.new(root: root, home: home, temp_root: temp, runner: CleanupRunner.new, clock: -> { now })
end

puts "Bounded Storage Cleanup A3 verification:"

Dir.mktmpdir("soul-storage-cleanup-a3-") do |sandbox|
  root = File.join(sandbox, "repo")
  home = File.join(sandbox, "home")
  temp = File.join(sandbox, "tmp")
  [root, home, temp].each { |path| FileUtils.mkdir_p(path) }
  now = Time.utc(2026, 7, 29, 22, 0, 0)
  old_temp = now - (2 * 24 * 60 * 60)
  old_log = now - (31 * 24 * 60 * 60)

  known = File.join(temp, "soul-whisper-old")
  FileUtils.mkdir_p(File.join(known, "nested"))
  File.write(File.join(known, "nested", "trace.json"), "review residue")
  touch_tree.call(known, old_temp)
  unknown = File.join(temp, "soul-unknown-owner-state")
  FileUtils.mkdir_p(unknown)
  File.write(File.join(unknown, "state"), "protected")
  touch_tree.call(unknown, old_temp)
  recent = File.join(temp, "soul-character-recent")
  FileUtils.mkdir_p(recent)
  File.write(File.join(recent, "trace"), "recent")

  logs = File.join(root, "Soul", "logs", "tasks")
  FileUtils.mkdir_p(logs)
  expired_log = File.join(logs, "expired.json")
  current_log = File.join(logs, "current.json")
  keep_file = File.join(logs, ".keep")
  File.write(expired_log, "expired evidence")
  File.write(current_log, "current evidence")
  File.write(keep_file, "")
  File.utime(old_log, old_log, expired_log)
  File.utime(old_log, old_log, keep_file)

  generations = File.join(root, "Soul", "music", "projects", "music_aaaaaaaaaaaaaaaa", "generations")
  quarantine = File.join(generations, ".candidate_bbbbbbbbbbbbbbbb.partial")
  accepted = File.join(generations, "candidate_cccccccccccccccc")
  FileUtils.mkdir_p(quarantine)
  FileUtils.mkdir_p(accepted)
  File.write(File.join(quarantine, "failure.json"), "failed")
  File.write(File.join(accepted, "candidate.json"), "accepted")
  touch_tree.call(quarantine, old_temp)
  touch_tree.call(accepted, old_temp)

  assessor = make_assessor.call(root, home, temp, now)
  preview = assessor.preview(category: "temp_review_artifacts")
  check.call("preview binds one known old owner-local tree with executable authority",
    preview["ok"] &&
      preview.dig("data", "entry_count") == 1 &&
      preview.dig("data", "entries", 0, "path") == known &&
      preview.dig("data", "entries", 0, "identity_digest").match?(/\A[a-f0-9]{64}\z/) &&
      preview.dig("data", "confirmation_phrase") == SoulCore::StorageRetentionAssessor::CLEANUP_CONFIRMATION &&
      preview.dig("data", "execution_available") == true)

  wrong = assessor.execute(
    category: "temp_review_artifacts",
    confirmation: "yes",
    expected_digest: preview.dig("data", "expected_digest")
  )
  check.call("wrong confirmation removes nothing",
    wrong["lifecycle_state"] == "awaiting_input" &&
      File.directory?(known) &&
      File.directory?(unknown) &&
      File.directory?(recent))

  File.write(File.join(known, "nested", "trace.json"), "changed after preview")
  drift = assessor.execute(
    category: "temp_review_artifacts",
    confirmation: preview.dig("data", "confirmation_phrase"),
    expected_digest: preview.dig("data", "expected_digest")
  )
  check.call("candidate drift invalidates the exact digest before staging",
    drift["lifecycle_state"] == "blocked_for_human_review" && File.directory?(known))
  File.write(File.join(known, "nested", "trace.json"), "review residue")
  touch_tree.call(known, old_temp)

  fresh_preview = assessor.preview(category: "temp_review_artifacts")
  exact = assessor.execute(
    category: "temp_review_artifacts",
    confirmation: fresh_preview.dig("data", "confirmation_phrase"),
    expected_digest: fresh_preview.dig("data", "expected_digest")
  )
  check.call("exact temporary cleanup removes only the reviewed candidate",
    exact["ok"] &&
      exact["mutation"] == "storage_retention_cleanup_completed" &&
      exact.dig("data", "removed_count") == 1 &&
      exact.dig("data", "receipt_id").start_with?("storage_cleanup_") &&
      !File.exist?(known) &&
      File.read(File.join(unknown, "state")) == "protected" &&
      File.read(File.join(recent, "trace")) == "recent")
  receipt_path = File.join(root, "Soul", "logs", "storage_cleanup", "#{exact.dig('data', 'receipt_id')}.json")
  receipt = JSON.parse(File.read(receipt_path))
  check.call("owner-only cleanup receipt stores hashes and lifecycle evidence but no raw path",
    (File.stat(receipt_path).mode & 0o777) == 0o600 &&
      receipt["lifecycle_state"] == "complete" &&
      receipt["removed_entry_digests"].all? { |value| value.match?(/\A[a-f0-9]{64}\z/) } &&
      !File.read(receipt_path).include?(known))
  empty = assessor.preview(category: "temp_review_artifacts")
  check.call("second preview is empty and has no execute authority",
    empty["ok"] && empty.dig("data", "entry_count").zero? && empty.dig("data", "execution_available") == false)

  log_preview = assessor.preview(category: "expired_project_logs")
  log_result = assessor.execute(
    category: "expired_project_logs",
    confirmation: log_preview.dig("data", "confirmation_phrase"),
    expected_digest: log_preview.dig("data", "expected_digest")
  )
  check.call("log cleanup removes only old regular non-dot files",
    log_result["ok"] &&
      !File.exist?(expired_log) &&
      File.read(current_log) == "current evidence" &&
      File.file?(keep_file))

  music_preview = assessor.preview(category: "failed_music_quarantine")
  lease_root = File.join(root, "Soul", "runtime", "music")
  FileUtils.mkdir_p(lease_root)
  File.write(File.join(lease_root, "amd-music.json"), "{}")
  lease_block = assessor.execute(
    category: "failed_music_quarantine",
    confirmation: music_preview.dig("data", "confirmation_phrase"),
    expected_digest: music_preview.dig("data", "expected_digest")
  )
  check.call("a Music lease appearing after preview blocks quarantine cleanup",
    lease_block["lifecycle_state"] == "blocked_for_human_review" &&
      File.directory?(quarantine) &&
      File.directory?(accepted))
  File.delete(File.join(lease_root, "amd-music.json"))
  music_preview = assessor.preview(category: "failed_music_quarantine")
  music_result = assessor.execute(
    category: "failed_music_quarantine",
    confirmation: music_preview.dig("data", "confirmation_phrase"),
    expected_digest: music_preview.dig("data", "expected_digest")
  )
  check.call("quarantine cleanup removes only old failed partial candidates",
    music_result["ok"] &&
      !File.exist?(quarantine) &&
      File.read(File.join(accepted, "candidate.json")) == "accepted")

  lock = assessor.instance_variable_get(:@cleanup_mutex)
  lock.lock
  concurrent = assessor.execute(
    category: "temp_review_artifacts",
    confirmation: SoulCore::StorageRetentionAssessor::CLEANUP_CONFIRMATION,
    expected_digest: "0" * 64
  )
  lock.unlock
  check.call("concurrent cleanup fails immediately without waiting",
    concurrent["lifecycle_state"] == "blocked_for_human_review" &&
      concurrent["reason"].include?("another storage cleanup operation"))

  service = SoulCore::SelfImprovementService.new(
    root: root,
    storage_assessor: assessor,
    environment_assessor: Object.new,
    assessment_timeout_seconds: 2
  )
  facade = SoulCore::ApplicationFacade.new(root: root, self_improvement_service: service)
  facade_candidate = File.join(temp, "soul-tooling-plan-facade")
  File.write(facade_candidate, "facade fixture")
  File.utime(old_temp, old_temp, facade_candidate)
  facade_preview = facade.call({
    "schema_version" => "soul.application.v1",
    "request_id" => "storage-cleanup-preview-a3",
    "operation" => "storage_retention.cleanup.preview",
    "parameters" => { "category" => "temp_review_artifacts" },
    "context" => { "interface" => "dashboard_test" }
  })
  facade_scope = facade_preview.fetch("data")
  facade_execute = facade.call({
    "schema_version" => "soul.application.v1",
    "request_id" => "storage-cleanup-execute-a3",
    "operation" => "storage_retention.cleanup.execute",
    "parameters" => {
      "category" => "temp_review_artifacts",
      "confirmation" => facade_scope.fetch("confirmation_phrase"),
      "expected_digest" => facade_scope.fetch("expected_digest")
    },
    "context" => { "interface" => "dashboard_test" }
  })
  check.call("application facade executes the exact gate through terminal lifecycle evidence",
      facade_preview["lifecycle_state"] == "complete" &&
      facade_execute["lifecycle_state"] == "complete" &&
      !File.exist?(facade_candidate) &&
      facade_execute.dig("meta", "mutation") == "storage_retention_cleanup_completed" &&
      SoulCore::ApplicationContract::OPERATIONS.key?("storage_retention.cleanup.execute"))
end

Dir.mktmpdir("soul-storage-cleanup-unsafe-a3-") do |sandbox|
  root = File.join(sandbox, "repo")
  home = File.join(sandbox, "home")
  temp = File.join(sandbox, "tmp")
  [root, home, temp].each { |path| FileUtils.mkdir_p(path) }
  now = Time.utc(2026, 7, 29, 22, 0, 0)
  old = now - (2 * 24 * 60 * 60)
  candidate = File.join(temp, "soul-character-unsafe")
  FileUtils.mkdir_p(candidate)
  target = File.join(temp, "outside")
  File.write(target, "protected")
  File.symlink(target, File.join(candidate, "link"))
  File.utime(old, old, candidate)
  assessor = make_assessor.call(root, home, temp, now)
  result = assessor.preview(category: "temp_review_artifacts")
  check.call("a symlink anywhere in a candidate tree blocks the whole scope",
    result["lifecycle_state"] == "blocked_for_human_review" &&
      File.read(target) == "protected" &&
      File.symlink?(File.join(candidate, "link")))
end

Dir.mktmpdir("soul-storage-cleanup-bound-a3-") do |sandbox|
  root = File.join(sandbox, "repo")
  home = File.join(sandbox, "home")
  temp = File.join(sandbox, "tmp")
  [root, home, temp].each { |path| FileUtils.mkdir_p(path) }
  now = Time.utc(2026, 7, 29, 22, 0, 0)
  old = now - (2 * 24 * 60 * 60)
  257.times do |index|
    path = File.join(temp, format("soul-whisper-%03d", index))
    File.write(path, "x")
    File.utime(old, old, path)
  end
  assessor = make_assessor.call(root, home, temp, now)
  result = assessor.preview(category: "temp_review_artifacts")
  check.call("an oversized candidate set blocks instead of silently truncating",
    result["lifecycle_state"] == "blocked_for_human_review" &&
      Dir.children(temp).length == 257)
end

Dir.mktmpdir("soul-storage-cleanup-rollback-a3-") do |sandbox|
  root = File.join(sandbox, "repo")
  home = File.join(sandbox, "home")
  temp = File.join(sandbox, "tmp")
  [root, home, temp].each { |path| FileUtils.mkdir_p(path) }
  now = Time.utc(2026, 7, 29, 22, 0, 0)
  old = now - (2 * 24 * 60 * 60)
  first = File.join(temp, "soul-whisper-first")
  second = File.join(temp, "soul-whisper-second")
  [first, second].each { |path| File.write(path, File.basename(path)); File.utime(old, old, path) }
  assessor = make_assessor.call(root, home, temp, now, PartialFailureCleanupAssessor)
  preview = assessor.preview(category: "temp_review_artifacts")
  result = assessor.execute(
    category: "temp_review_artifacts",
    confirmation: preview.dig("data", "confirmation_phrase"),
    expected_digest: preview.dig("data", "expected_digest")
  )
  check.call("partial failure is terminal, disclosed, and restores still-staged entries",
    result["lifecycle_state"] == "failed" &&
      result.dig("data", "removed_count") == 1 &&
      [File.exist?(first), File.exist?(second)].count(true) == 1 &&
      Dir.children(temp).none? { |name| name.start_with?(".soul-cleanup-stage-") })
end

source = File.read(File.join(__dir__, "../lib/soul_core/storage_retention_assessor.rb"))
html = File.read(File.join(__dir__, "../assets/dashboard/index.html"))
javascript = File.read(File.join(__dir__, "../assets/dashboard/dashboard.js"))
brief = File.read(File.join(__dir__, "../docs/soul/BOUNDED_STORAGE_CLEANUP_A3_BRIEF.md"))
check.call("Dashboard separates preview from one explicit destructive click",
  html.include?('id="preview-storage-cleanup"') &&
    html.include?('id="execute-storage-cleanup"') &&
    javascript.include?("storage_retention.cleanup.execute") &&
    javascript.include?("preview.confirmation_phrase"))
check.call("production cleanup contains no shell deletion or persistence primitive",
  !source.match?(/system\s*\(|spawn\s*\(|Open3|`.*rm|rm_rf/) &&
    !source.match?(/setInterval|cron|systemd|Thread\.new/) &&
    brief.include?("No cleanup runs automatically"))

abort(errors.map { |error| "- #{error}" }.join("\n")) unless errors.empty?
puts "Bounded Storage Cleanup A3 is candidate-ready for human review."
