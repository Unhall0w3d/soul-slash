#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require "time"

require_relative "../lib/soul_core/application_facade"
require_relative "../lib/soul_core/backup_administration_service"
require_relative "../lib/soul_core/backup_manifest_policy"

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

class ManifestReconciliationNoCommandRunner
  attr_reader :calls

  def initialize
    @calls = []
  end

  def which(_name)
    nil
  end

  def run(*command, **_options)
    @calls << command
    raise "manifest reconciliation must not invoke an external command"
  end
end

Dir.mktmpdir("soul-backup-manifest-reconciliation-") do |root|
  private_root = File.join(root, "Soul", "private")
  backup_root = File.join(private_root, "backup")
  FileUtils.mkdir_p(backup_root, mode: 0o700)
  File.chmod(0o700, private_root)

  [
    File.join(root, ".env"),
    File.join(root, "Soul", "runtime", "creative_flows", "state.json"),
    File.join(root, "Soul", "runtime", "youtube_auth", "state.json"),
    File.join(root, "Soul", "runtime", "youtube_description_sync", "state.json"),
    File.join(root, "Knowledge", "soul-vault", "README.md")
  ].each do |path|
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "{}\n")
  end

  policy = SoulCore::BackupManifestPolicy.new(root: root, home: root)
  new_sources = %w[creative_flows youtube_auth youtube_description_sync].map { |name| File.join(root, "Soul", "runtime", name) }
  initial_sources = policy.sources - new_sources
  dynamic_exclusions = policy.exclusions.select { |line| line.start_with?(root) } -
    ["#{File.join(root, "Soul", "private", "backup", "restores")}/**"]
  initial_exclusions = policy.exclusions - dynamic_exclusions
  sources_path = File.join(backup_root, "sources.txt")
  excludes_path = File.join(backup_root, "excludes.txt")
  source_header = "# operator sources remain\n\n"
  exclusion_header = "# operator exclusions remain\n"
  File.write(sources_path, source_header + initial_sources.join("\n") + "\n", mode: "w", perm: 0o600)
  File.write(excludes_path, exclusion_header + initial_exclusions.join("\n") + "\n", mode: "w", perm: 0o600)

  runner = ManifestReconciliationNoCommandRunner.new
  service = SoulCore::BackupAdministrationService.new(
    root: root,
    home: root,
    process_env: {},
    runner: runner,
    clock: -> { Time.utc(2026, 7, 29, 20, 30, 0) },
    id_generator: -> { "0123456789abcdef" }
  )

  preview = service.manifest_reconciliation_preview
  check.call("preview binds only missing portable-policy entries",
               preview["ok"] &&
               preview.dig("data", "source_additions").length == 3 &&
               preview.dig("data", "exclusion_additions").sort == dynamic_exclusions.map { |line| line.gsub(root, "[PROJECT_ROOT]") }.sort &&
               preview.dig("data", "source_removals").empty? &&
               preview.dig("data", "exclusion_removals").empty?)
  check.call("preview declares no password Restic retry or replacement",
             preview.dig("data", "password_required") == false &&
               preview.dig("data", "restic_operation") == false &&
               preview.dig("data", "automatic_retry") == false &&
               preview.dig("data", "replace_existing") == false)

  source_before = File.binread(sources_path)
  exclusions_before = File.binread(excludes_path)
  wrong = service.manifest_reconciliation_execute(
    confirmation: "NO",
    expected_digest: preview.dig("data", "expected_digest")
  )
  check.call("wrong confirmation changes no manifest",
             wrong["lifecycle_state"] == "awaiting_input" &&
               File.binread(sources_path) == source_before &&
               File.binread(excludes_path) == exclusions_before)

  File.open(sources_path, "a", 0o600) { |file| file.write("# reviewed local note\n") }
  stale = service.manifest_reconciliation_execute(
    confirmation: preview.dig("data", "confirmation_phrase"),
    expected_digest: preview.dig("data", "expected_digest")
  )
  check.call("manifest drift invalidates the reviewed digest",
             stale["lifecycle_state"] == "blocked_for_human_review" &&
               !File.binread(sources_path).include?(new_sources.first))

  current = service.manifest_reconciliation_preview
  source_hold = "#{new_sources.first}.held"
  File.rename(new_sources.first, source_hold)
  source_drift = service.manifest_reconciliation_execute(
    confirmation: current.dig("data", "confirmation_phrase"),
    expected_digest: current.dig("data", "expected_digest")
  )
  File.rename(source_hold, new_sources.first)
  check.call("portable source drift invalidates the reviewed scope",
             source_drift["lifecycle_state"] == "blocked_for_human_review" &&
               !File.binread(sources_path).include?(new_sources.first))
  current = service.manifest_reconciliation_preview

  lock_path = File.join(backup_root, "operation.lock")
  File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
    lock.flock(File::LOCK_EX | File::LOCK_NB)
    busy = service.manifest_reconciliation_execute(
      confirmation: current.dig("data", "confirmation_phrase"),
      expected_digest: current.dig("data", "expected_digest")
    )
    check.call("shared backup operation lock blocks concurrent reconciliation",
               busy["lifecycle_state"] == "blocked_for_human_review")
  end

  exact = service.manifest_reconciliation_execute(
    confirmation: current.dig("data", "confirmation_phrase"),
    expected_digest: current.dig("data", "expected_digest")
  )
  final_sources = File.readlines(sources_path, chomp: true)
  final_exclusions = File.readlines(excludes_path, chomp: true)
  check.call("exact execution appends all and only reviewed policy entries",
             exact["ok"] &&
               exact["mutation"] == "backup_manifests_reconciled" &&
               exact.dig("data", "source_addition_count") == 3 &&
               exact.dig("data", "exclusion_addition_count") == dynamic_exclusions.length &&
               new_sources.all? { |line| final_sources.include?(line) } &&
               dynamic_exclusions.all? { |line| final_exclusions.include?(line) })
  check.call("existing owner entries comments and blank lines are preserved",
             File.binread(sources_path).start_with?(source_header) &&
               File.binread(sources_path).include?("# reviewed local note\n") &&
               File.binread(excludes_path).start_with?(exclusion_header) &&
               initial_sources.all? { |line| final_sources.include?(line) } &&
               initial_exclusions.all? { |line| final_exclusions.include?(line) })
  check.call("reconciled manifests and private receipt remain owner-only",
             (File.stat(sources_path).mode & 0o077).zero? &&
               (File.stat(excludes_path).mode & 0o077).zero? &&
               Dir.glob(File.join(backup_root, "receipts", "manifest_reconciliation_*.json")).one? &&
               Dir.glob(File.join(backup_root, "receipts", "*.json")).all? { |path| (File.stat(path).mode & 0o077).zero? })
  check.call("reconciliation receipt stores counts and hashes but no source paths",
             begin
               receipt = JSON.parse(File.read(Dir.glob(File.join(backup_root, "receipts", "*.json")).first))
               receipt["source_addition_count"] == 3 &&
                 receipt["snapshot_verification_required"] == true &&
                 !receipt.to_s.include?("creative_flows")
             end)

  second = service.manifest_reconciliation_preview
  check.call("second preview is terminal and idempotent",
             second["ok"] &&
               second.dig("data", "changes_required") == false &&
               second.dig("data", "source_additions").empty? &&
               second.dig("data", "exclusion_additions").empty?)
  check.call("no password or external command path is touched", runner.calls.empty?)

  facade = SoulCore::ApplicationFacade.new(root: root, backup_administration_service: service)
  envelope = facade.call({
    "schema_version" => "soul.application.v1",
    "request_id" => "req_backup_manifest_preview",
    "operation" => "backup.manifests.reconcile.preview",
    "parameters" => {},
    "context" => { "interface" => "dashboard_test" }
  })
  check.call("application facade exposes the bounded reconciliation preview",
             envelope["ok"] && envelope.dig("data", "changes_required") == false)

  real_excludes = File.join(backup_root, "real-excludes.txt")
  File.rename(excludes_path, real_excludes)
  File.symlink(real_excludes, excludes_path)
  symlinked = service.manifest_reconciliation_preview
  check.call("symlinked owner manifest fails closed without mutation",
             symlinked["lifecycle_state"] == "awaiting_input" &&
               File.symlink?(excludes_path) &&
               File.file?(real_excludes))
end

javascript = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
brief = File.read(File.expand_path("../docs/soul/BACKUP_MANIFEST_RECONCILIATION_A0_BRIEF.md", __dir__))
config_script = File.read(File.expand_path("soul-backup-config", __dir__))
check.call("Dashboard exposes preview then exact add-only execution",
           html.include?('id="preview-backup-manifests"') &&
             html.include?('id="execute-backup-manifests"') &&
             javascript.index('"backup.manifests.reconcile.preview"') < javascript.index('"backup.manifests.reconcile.execute"') &&
             html.include?("A fresh verified backup remains a separate gate"))
check.call("initial setup and reconciliation share one portable policy",
           config_script.include?('require_relative "../lib/soul_core/backup_manifest_policy"') &&
             config_script.include?("policy.sources") &&
             config_script.include?("policy.exclusions"))
check.call("approved brief prohibits replacement Restic and background behavior",
           brief.include?("add-only") &&
             brief.include?("It must never start Restic") &&
             brief.include?("no retry, scheduler, timer, watcher, daemon, or background"))

abort "Backup Manifest Reconciliation A0 verification failed: #{errors.join(', ')}" unless errors.empty?
puts "Backup Manifest Reconciliation A0 is candidate-ready for human review."
