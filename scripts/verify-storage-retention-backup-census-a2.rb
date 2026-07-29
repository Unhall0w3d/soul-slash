#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "time"

require_relative "../lib/soul_core/application_contract"
require_relative "../lib/soul_core/artifact_retention_census"
require_relative "../lib/soul_core/storage_retention_assessor"

Result = Struct.new(:status, :stdout, :stderr, :exit_status, keyword_init: true) do
  def success? = status == "ok"
end

class CensusRunner
  def run(*argv, **_options)
    return Result.new(status: "failed", stdout: "", stderr: "unexpected command", exit_status: 1) unless argv.first == "du"
    path = argv.last
    bytes = if File.file?(path)
      File.size(path)
    elsif File.directory?(path)
      Dir.glob(File.join(path, "**", "*"), File::FNM_DOTMATCH).sum { |entry| File.file?(entry) && !File.symlink?(entry) ? File.size(entry) : 0 }
    else
      0
    end
    Result.new(status: "ok", stdout: "#{bytes}\t#{path}\n", stderr: "", exit_status: 0)
  end
end

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

puts "Storage, Retention, and Backup Census A2 verification:"

Dir.mktmpdir("soul-retention-census-a2-") do |sandbox|
  root = File.join(sandbox, "repo")
  home = File.join(sandbox, "home")
  temp = File.join(sandbox, "tmp")
  backup = File.join(root, "Soul", "private", "backup")
  manifests = File.join(backup, "manifests")
  vault = File.join(home, "Knowledge", "soul-vault")
  paths = {
    private: File.join(root, "Soul", "private"),
    chats: File.join(root, "Soul", "runtime", "chats"),
    creative_flows: File.join(root, "Soul", "runtime", "creative_flows"),
    music: File.join(root, "Soul", "music", "projects"),
    visual: File.join(root, "Soul", "visual", "projects"),
    exports: File.join(home, "Music", "soul-music"),
    sessions: File.join(root, "Soul", "runtime", "dashboard_auth", "sessions"),
    approvals: File.join(root, "Soul", "runtime", "approvals"),
    leases: File.join(root, "Soul", "runtime", "model_runtime", "leases")
  }
  ([root, home, temp, manifests, vault, File.join(vault, ".git")] + paths.values).each { |path| FileUtils.mkdir_p(path) }
  File.write(File.join(paths.fetch(:chats), "chat.jsonl"), "private fixture")
  File.write(File.join(vault, "README.md"), "private fixture")

  sources = [paths.fetch(:private), paths.fetch(:chats), paths.fetch(:creative_flows), paths.fetch(:music), paths.fetch(:visual), paths.fetch(:exports), vault]
  exclusions = [
    "#{File.join(root, "Soul", "private", "creative-inspection")}/**",
    "#{File.join(root, "Soul", "private", "host_maintenance", "checkupdates_db")}/**",
    "#{File.join(root, "Soul", "private", "perception", "screen_capture")}/**",
    "#{File.join(root, "Soul", "private", "perception", "staging")}/**",
    "#{paths.fetch(:sessions)}/**",
    "#{paths.fetch(:approvals)}/**",
    "#{paths.fetch(:leases)}/**"
  ]
  File.write(File.join(backup, "sources.txt"), sources.join("\n") + "\n")
  File.write(File.join(backup, "excludes.txt"), exclusions.join("\n") + "\n")
  snapshot_id = "a" * 64
  File.write(File.join(manifests, "#{snapshot_id}.json"), JSON.pretty_generate(
    "schema_version" => "soul.backup_snapshot_manifest.v1",
    "snapshot_id" => snapshot_id,
    "verified_at" => "2026-07-29T18:00:00Z",
    "repository_id" => "b" * 64,
    "source_roots" => sources,
    "paths" => sources + [File.join(paths.fetch(:chats), "chat.jsonl"), File.join(vault, "README.md")],
    "verification" => { "check_mode" => "metadata", "result" => "passed" }
  ))

  before = Dir.glob(File.join(sandbox, "**", "*"), File::FNM_DOTMATCH).sort
  report = SoulCore::ArtifactRetentionCensus.new(root: root, home: home, temp_root: temp, runner: CensusRunner.new).inventory
  records = report.fetch("artifact_classes")
  by_id = records.to_h { |record| [record.fetch("id"), record] }

  check.call("census defines a broad metadata-only artifact registry",
             records.length >= 40 &&
               report["metadata_only"] &&
               records.all? { |record| %w[id owner path retention deletion_boundary backup_expectation backup].all? { |key| record.key?(key) } })
  check.call("core owner-local projects chats and exports require encrypted backup",
             %w[owner_private_state chat_transcripts music_projects visual_projects finished_music_exports].all? do |id|
               by_id.dig(id, "backup", "expectation") == "required"
             end)
  check.call("latest manifest proves the local Knowledge Vault and private Git remains supplementary",
             by_id.dig("knowledge_vault", "backup", "status") == "snapshot_verified" &&
               by_id.dig("knowledge_vault", "independent_replication", "local_repository") == true &&
               by_id.dig("knowledge_vault", "independent_replication", "remote_privacy_inferred") == false &&
               by_id.dig("knowledge_vault", "independent_replication", "restic_remains_required") == true)
  check.call("ephemeral sessions approvals leases and private staging are explicitly excluded",
             %w[dashboard_sessions approval_tokens model_leases perception_staging screen_capture_staging creative_inspection_staging].all? do |id|
               %w[excluded not_configured].include?(by_id.dig(id, "backup", "status"))
             end)
  check.call("reproducible models and tooling are never presented as missing durable backup",
             %w[production_music_models transcription_runtime music_reference_tooling].all? do |id|
               by_id.dig(id, "backup", "expectation") == "reproducible" &&
                 by_id.dig(id, "backup", "status") == "not_configured_by_design"
             end)
  check.call("census reports bounded backup summary without password or content collection",
             report.dig("backup_coverage", "required_class_count").positive? &&
               report.dig("backup_coverage", "latest_manifest", "snapshot_id") == snapshot_id[0, 12] &&
               report.dig("verification", "content_read") == false &&
               report.dig("verification", "backup_password_requested") == false &&
               report.dig("verification", "backup_operation_started") == false)
  after = Dir.glob(File.join(sandbox, "**", "*"), File::FNM_DOTMATCH).sort
  check.call("metadata-only census changes no fixture paths", before == after)
end

Dir.mktmpdir("soul-backup-defaults-a2-") do |sandbox|
  root = File.join(sandbox, "repo")
  home = File.join(sandbox, "home")
  required_paths = [
    File.join(root, "Soul", "private", "project_tracker"),
    File.join(root, "Soul", "runtime", "creative_flows"),
    File.join(root, "Soul", "runtime", "youtube_auth"),
    File.join(root, "Soul", "runtime", "youtube_description_sync"),
    File.join(root, "Soul", "music", "projects"),
    File.join(root, "Soul", "visual", "projects"),
    File.join(home, "Music", "soul-music"),
    File.join(home, "Knowledge", "soul-vault")
  ]
  required_paths.each { |path| FileUtils.mkdir_p(path) }
  script = File.expand_path("soul-backup-config", __dir__)
  stdout, stderr, status = Open3.capture3("ruby", script, "plan", "--root", root, "--home", home)
  plan = JSON.parse(stdout) if status.success?
  planned_sources = plan.to_h.dig("data", "sources").to_a
  planned_exclusions = plan.to_h.dig("data", "excludes").to_a
  check.call("portable backup defaults include Vault projects and newer continuity state",
             status.success? && stderr.empty? &&
               required_paths.all? { |path| planned_sources.any? { |source| path == source || path.start_with?("#{source}/") } })
  check.call("portable backup defaults exclude staging sessions approvals leases and maintenance cache",
             %w[
               Soul/private/creative-inspection
               Soul/private/host_maintenance/checkupdates_db
               Soul/private/perception/screen_capture
               Soul/private/perception/staging
               Soul/runtime/approvals
               Soul/runtime/dashboard_auth/sessions
               Soul/runtime/model_runtime/leases
               Soul/runtime/music
             ].all? { |relative| planned_exclusions.include?("#{File.join(root, relative)}/**") })
end

Dir.mktmpdir("soul-repo-hygiene-check-a2-") do |sandbox|
  File.write(File.join(sandbox, "README_PUBLIC_CANDIDATE.md"), "candidate")
  script = File.expand_path("repo-public-hygiene-cleanup.sh", __dir__)
  stdout, _stderr, status = Open3.capture3(script, "--check", chdir: sandbox)
  check.call("repo hygiene check reports pending work without moving or deleting it",
             !status.success? &&
               stdout.include?("Would move README_PUBLIC_CANDIDATE.md") &&
               File.file?(File.join(sandbox, "README_PUBLIC_CANDIDATE.md")) &&
               !File.exist?(File.join(sandbox, "docs", "overlays", "archive", "README_PUBLIC_CANDIDATE.md")))
end

html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
javascript = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
brief = File.read(File.expand_path("../docs/soul/STORAGE_RETENTION_AND_BACKUP_CENSUS_A2_BRIEF.md", __dir__))
check.call("Dashboard exposes artifact-class and backup coverage without cleanup execution",
           html.include?("Read-only census") &&
             javascript.include?("artifact_classes") &&
             javascript.include?("snapshot_verified_count") &&
             !SoulCore::ApplicationContract::OPERATIONS.key?("storage_retention.cleanup.execute"))
check.call("approved A2 brief preserves non-destructive foreground boundaries",
           brief.include?("No cleanup execute operation is added") &&
             brief.include?("No backup, restore, replication, retention, or Git network operation runs") &&
             brief.include?("Automatic edits to an existing owner backup manifest"))

abort(errors.map { |error| "- #{error}" }.join("\n")) unless errors.empty?
puts "Storage, Retention, and Backup Census A2 is candidate-ready for human review."
