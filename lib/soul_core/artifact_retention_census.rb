# frozen_string_literal: true

require "json"
require "time"

require_relative "bounded_command_runner"

module SoulCore
  class ArtifactRetentionCensus
    MAX_MANIFEST_BYTES = 16 * 1024 * 1024
    MAX_MANIFEST_PATHS = 100_000
    MAX_MANIFEST_LINES = 256
    BACKUP_EXPECTATIONS = %w[required excluded reproducible manual_review not_applicable].freeze
    RETENTION_CLASSES = %w[protected lifecycle_owned age_review capacity_bounded disposable reproducible manual_review].freeze

    def initialize(root:, home:, temp_root:, runner: BoundedCommandRunner.new)
      @root = File.expand_path(root)
      @home = File.expand_path(home)
      @temp_root = File.expand_path(temp_root)
      @runner = runner
      @backup_root = File.join(@root, "Soul", "private", "backup")
    end

    def inventory
      sources = manifest_lines(File.join(@backup_root, "sources.txt"))
      exclusions = manifest_lines(File.join(@backup_root, "excludes.txt"), normalize: false)
      latest = latest_backup_manifest
      records = definitions.map { |definition| inspect_definition(definition, sources, exclusions, latest) }
      required = records.select { |record| record["backup_expectation"] == "required" }
      {
        "schema_version" => "soul.artifact_retention_census.v1",
        "metadata_only" => true,
        "artifact_classes" => records,
        "backup_coverage" => {
          "source_manifest_present" => File.file?(File.join(@backup_root, "sources.txt")),
          "exclusion_manifest_present" => File.file?(File.join(@backup_root, "excludes.txt")),
          "configured_source_count" => sources.length,
          "configured_exclusion_count" => exclusions.length,
          "latest_manifest" => latest && {
            "snapshot_id" => latest.fetch("snapshot_id")[0, 12],
            "verified_at" => latest["verified_at"],
            "path_count" => latest.fetch("paths").length
          },
          "required_class_count" => required.length,
          "snapshot_verified_count" => required.count { |record| record.dig("backup", "status") == "snapshot_verified" },
          "configured_not_verified_count" => required.count { |record| record.dig("backup", "status") == "configured_not_verified" },
          "uncovered_count" => required.count { |record| record.dig("backup", "status") == "uncovered" },
          "excluded_conflict_count" => required.count { |record| record.dig("backup", "status") == "excluded_conflict" },
          "exclusion_gap_count" => records.count { |record| record.dig("backup", "status") == "exclusion_missing" },
          "knowledge_vault" => records.find { |record| record["id"] == "knowledge_vault" }.to_h.slice("backup", "independent_replication")
        },
        "verification" => {
          "content_read" => false,
          "symlinks_followed" => false,
          "backup_password_requested" => false,
          "backup_operation_started" => false,
          "files_changed" => false
        }
      }
    end

    private

    def definitions
      soul = File.join(@root, "Soul")
      runtime = File.join(soul, "runtime")
      private_root = File.join(soul, "private")
      music_runtime = File.join(@home, ".local", "share", "soul", "music")
      [
        artifact("owner_private_state", "Shared owner state", private_root, "protected", "Only the owning subsystem may mutate its bounded record.", "required"),
        artifact("shared_memory", "Memory", File.join(private_root, "memory"), "protected", "Explicit remember, forget, migration, or restore controls only.", "required"),
        artifact("project_timeline", "Project Timeline", File.join(private_root, "project_tracker"), "lifecycle_owned", "Explicit Timeline edits; no generic cleanup.", "required"),
        artifact("backup_evidence", "Backup Administration", File.join(private_root, "backup"), "protected", "Backup retention and staged-restore controls only.", "required"),
        artifact("maintenance_evidence", "Maintenance", File.join(private_root, "host_maintenance"), "capacity_bounded", "Owning receipt caps and reviewed maintenance lifecycle only.", "required"),
        artifact("maintenance_package_cache", "Maintenance", File.join(private_root, "host_maintenance", "checkupdates_db"), "reproducible", "May be rebuilt by a future exact cache-cleanup operation.", "excluded"),
        artifact("perception_staging", "Perception", File.join(private_root, "perception", "staging"), "disposable", "Request-private cleanup at terminal return.", "excluded"),
        artifact("screen_capture_staging", "Perception", File.join(private_root, "perception", "screen_capture"), "disposable", "Request-private cleanup at terminal return.", "excluded"),
        artifact("creative_inspection_staging", "Creative inspection", File.join(private_root, "creative-inspection"), "disposable", "Request-private cleanup at terminal return.", "excluded"),
        artifact("chat_transcripts", "Chat", File.join(runtime, "chats"), "lifecycle_owned", "Explicit conversation forget removes the owned transcript.", "required"),
        artifact("conversation_evidence", "Chat evidence", File.join(runtime, "conversation_evidence"), "lifecycle_owned", "Explicit conversation forget removes linked evidence.", "required"),
        artifact("conversation_state", "Chat orchestration", File.join(runtime, "conversation_state"), "lifecycle_owned", "Owning conversation or terminal-flow lifecycle only.", "required"),
        artifact("creative_flow_state", "Conversational workflows", File.join(runtime, "creative_flows"), "lifecycle_owned", "Owning chat workflow completion, cancellation, or forget.", "required"),
        artifact("application_receipts", "Application API", File.join(runtime, "application"), "capacity_bounded", "Bounded receipt-store compaction only.", "required"),
        artifact("artifact_inbox", "Shared workspace", File.join(runtime, "artifact_inbox"), "lifecycle_owned", "Explicit inbox and artifact lifecycle controls.", "required"),
        artifact("execution_history", "Chat execution history", File.join(runtime, "executions"), "capacity_bounded", "Confirmed export-before-prune control only.", "required"),
        artifact("runtime_exports", "Execution history", File.join(runtime, "exports"), "lifecycle_owned", "Explicit reviewed history/export pruning only.", "required"),
        artifact("dashboard_credentials", "Dashboard authentication", File.join(runtime, "dashboard_auth", "credentials.json"), "protected", "Credential rotation or dashboard reset only.", "required"),
        artifact("dashboard_sessions", "Dashboard authentication", File.join(runtime, "dashboard_auth", "sessions"), "disposable", "Session expiry or logout.", "excluded"),
        artifact("approval_tokens", "Application approval gates", File.join(runtime, "approvals"), "disposable", "Single-use expiry or terminal return.", "excluded"),
        artifact("model_leases", "Core orchestration", File.join(runtime, "model_runtime", "leases"), "disposable", "Owning model transition releases the lease.", "excluded"),
        artifact("music_runtime_leases", "Music runtime", File.join(runtime, "music"), "disposable", "Owning Music job releases the lease and control state.", "excluded"),
        artifact("youtube_auth_state", "YouTube integration", File.join(runtime, "youtube_auth"), "protected", "Explicit credential revocation or replacement only.", "required"),
        artifact("youtube_description_state", "YouTube description synchronization", File.join(runtime, "youtube_description_sync"), "lifecycle_owned", "Owning synchronization and reviewed receipt lifecycle.", "required"),
        artifact("workspace_artifacts", "Shared workspace", File.join(soul, "artifacts"), "lifecycle_owned", "Explicit artifact archive or owning workflow deletion.", "required"),
        artifact("skill_proposals", "Skill Studio", File.join(soul, "proposals"), "lifecycle_owned", "Explicit close, rejection, or linked production promotion.", "required"),
        artifact("self_improvement_proposals", "Self Assessment", File.join(soul, "improvement"), "lifecycle_owned", "Explicit proposal review and closeout.", "required"),
        artifact("augmentation_candidates", "Self Augmentation", File.join(soul, "augmentation"), "lifecycle_owned", "Explicit experiment cleanup or proposal closeout.", "required"),
        artifact("host_improvement_plans", "Host improvement", File.join(soul, "host_improvement"), "lifecycle_owned", "Explicit reviewed plan lifecycle.", "required"),
        artifact("reflection_state", "Knowledge reflection", File.join(soul, "reflection"), "lifecycle_owned", "Explicit reflection approval, rejection, or forget.", "required"),
        artifact("workflow_state", "Workflow runtime", File.join(soul, "workflows"), "lifecycle_owned", "Owning foreground workflow lifecycle.", "required"),
        artifact("project_logs", "Diagnostics", File.join(soul, "logs"), "age_review", "Exact review of regular files older than the documented threshold.", "required"),
        artifact("music_jobs", "Music Studio", File.join(soul, "music", "jobs"), "lifecycle_owned", "Owning generation reaches terminal state; job evidence remains bounded.", "required"),
        artifact("music_projects", "Music Studio", File.join(soul, "music", "projects"), "protected", "Exact project or candidate deletion through Music Studio only.", "required", ["finished_music_exports"]),
        artifact("music_references", "Music reference library", File.join(soul, "music", "references"), "lifecycle_owned", "Exact reviewed reference-profile deletion only.", "required"),
        artifact("visual_projects", "Visual Studio", File.join(soul, "visual", "projects"), "protected", "Exact project, candidate, or motion deletion through Visual Studio only.", "required"),
        artifact("finished_music_exports", "Operator exports", File.join(@home, "Music", "soul-music"), "protected", "Operator-managed outside project deletion.", "required"),
        artifact("knowledge_vault", "Knowledge Vault", File.join(@home, "Knowledge", "soul-vault"), "protected", "Reviewed Vault edits and independent Git history; never generic cleanup.", "required", [], "local_git"),
        artifact("soul_user_configuration", "Deployment", File.join(@home, ".config", "soul"), "protected", "Explicit configuration changes only.", "required"),
        artifact("dashboard_proxy_state", "Dashboard proxy", File.join(@home, ".local", "share", "caddy"), "protected", "Proxy reconfiguration or reviewed deployment teardown.", "required"),
        artifact("production_music_models", "Music runtime", File.join(music_runtime, "acestep-cpp"), "reproducible", "Pinned model/runtime reinstall; separate manual removal.", "reproducible"),
        artifact("legacy_music_runtime", "Legacy Music runtime", File.join(music_runtime, "ace-step"), "manual_review", "Separate exact runtime retirement review.", "manual_review"),
        artifact("transcription_runtime", "Music transcription", File.join(music_runtime, "transcription"), "reproducible", "Pinned runtime reinstall; separate manual removal.", "reproducible"),
        artifact("music_reference_tooling", "Music reference tooling", File.join(soul, "music", "tooling"), "reproducible", "Makefile-managed environment reinstall; separate manual removal.", "reproducible"),
        artifact("temporary_soul_residue", "Cross-workflow diagnostics", @temp_root, "disposable", "Only owned allowlisted aged entries through a later exact cleanup gate.", "not_applicable")
      ]
    end

    def artifact(id, owner, path, retention, deletion_boundary, backup_expectation, preserved_descendants = [], independent_replication = nil)
      raise ArgumentError, "retention class is invalid" unless RETENTION_CLASSES.include?(retention)
      raise ArgumentError, "backup expectation is invalid" unless BACKUP_EXPECTATIONS.include?(backup_expectation)
      {
        "id" => id,
        "owner" => owner,
        "path" => File.expand_path(path),
        "retention" => retention,
        "deletion_boundary" => deletion_boundary,
        "backup_expectation" => backup_expectation,
        "preserved_descendants" => preserved_descendants,
        "independent_replication" => independent_replication
      }
    end

    def inspect_definition(definition, sources, exclusions, latest)
      path = definition.fetch("path")
      observation = observe_path(path)
      definition.reject { |key, _| key == "path" || key == "independent_replication" }.merge(
        "path" => display_path(path),
        "exists" => observation.fetch("exists"),
        "bytes" => observation.fetch("bytes"),
        "entry_count" => observation.fetch("entry_count"),
        "blocked" => observation["blocked"],
        "backup" => backup_state(definition, sources, exclusions, latest),
        "independent_replication" => independent_replication(definition, observation)
      ).compact
    end

    def observe_path(path)
      return { "exists" => false, "bytes" => 0, "entry_count" => 0 } unless File.exist?(path) || File.symlink?(path)
      stat = File.lstat(path)
      return { "exists" => true, "bytes" => 0, "entry_count" => 1, "blocked" => "symlink is not followed" } if stat.symlink?
      count = stat.directory? ? Dir.children(path).length : 1
      {
        "exists" => true,
        "bytes" => disk_usage(path),
        "entry_count" => count
      }
    rescue Errno::EACCES, Errno::ENOENT => error
      { "exists" => true, "bytes" => 0, "entry_count" => 0, "blocked" => error.class.name }
    end

    def backup_state(definition, sources, exclusions, latest)
      path = definition.fetch("path")
      expectation = definition.fetch("backup_expectation")
      configured = sources.any? { |source| path == source || path.start_with?("#{source}/") }
      exact_excluded = exclusions.any? { |pattern| path_matches?(pattern, path) }
      excluded_descendant = exclusions.any? { |pattern| path_matches?(pattern, File.join(path, "__soul_probe__")) || pattern.start_with?("#{path}/") }
      verified = latest && latest.fetch("paths").any? { |entry| entry == path || entry.start_with?("#{path}/") }
      status = case expectation
      when "required"
        if exact_excluded
          "excluded_conflict"
        elsif verified
          "snapshot_verified"
        elsif configured
          "configured_not_verified"
        else
          "uncovered"
        end
      when "excluded"
        excluded_descendant ? "excluded" : (configured ? "exclusion_missing" : "not_configured")
      when "reproducible"
        configured ? "captured_for_review" : "not_configured_by_design"
      when "manual_review"
        verified ? "snapshot_verified" : (configured ? "configured_not_verified" : "manual_review")
      else
        "not_applicable"
      end
      {
        "expectation" => expectation,
        "status" => status,
        "configured" => configured,
        "latest_snapshot_verified" => !!verified
      }
    end

    def independent_replication(definition, observation)
      return nil unless definition["independent_replication"] == "local_git"
      git = File.join(definition.fetch("path"), ".git")
      {
        "kind" => "git",
        "local_repository" => observation.fetch("exists") && File.directory?(git) && !File.symlink?(git),
        "remote_privacy_inferred" => false,
        "restic_remains_required" => true
      }
    end

    def latest_backup_manifest
      root = File.join(@backup_root, "manifests")
      return nil unless File.directory?(root) && !File.symlink?(root)
      path = Dir.glob(File.join(root, "*.json")).select { |candidate| File.file?(candidate) && !File.symlink?(candidate) }.max_by { |candidate| File.mtime(candidate) }
      return nil unless path && File.size(path) <= MAX_MANIFEST_BYTES
      parsed = JSON.parse(File.binread(path, MAX_MANIFEST_BYTES))
      paths = Array(parsed["paths"])
      snapshot_id = parsed["snapshot_id"].to_s
      return nil unless snapshot_id.match?(/\A[a-f0-9]{64}\z/) && paths.length <= MAX_MANIFEST_PATHS
      normalized = paths.filter_map do |entry|
        text = entry.to_s
        File.expand_path(text) if text.start_with?("/")
      end.uniq
      { "snapshot_id" => snapshot_id, "verified_at" => parsed["verified_at"], "paths" => normalized }
    rescue JSON::ParserError, Errno::EACCES, Errno::ENOENT
      nil
    end

    def manifest_lines(path, normalize: true)
      return [] unless File.file?(path) && !File.symlink?(path) && File.size(path) <= 256 * 1024
      lines = File.readlines(path, chomp: true).map(&:strip).reject { |line| line.empty? || line.start_with?("#") }.first(MAX_MANIFEST_LINES)
      normalize ? lines.map { |line| File.expand_path(line) }.uniq : lines.uniq
    rescue Errno::EACCES, Errno::ENOENT
      []
    end

    def path_matches?(pattern, path)
      File.fnmatch?(pattern, path, File::FNM_PATHNAME | File::FNM_EXTGLOB)
    rescue ArgumentError
      false
    end

    def disk_usage(path)
      result = @runner.run("du", "-s", "-B1", "--", path, timeout_seconds: 12, max_output_bytes: 4 * 1024)
      return 0 unless result.success?
      Integer(result.stdout.to_s.split.first)
    rescue ArgumentError
      0
    end

    def display_path(path)
      expanded = File.expand_path(path)
      return "~#{expanded.delete_prefix(@home)}" if expanded == @home || expanded.start_with?(@home + File::SEPARATOR)
      return expanded.delete_prefix(@root + File::SEPARATOR) if expanded.start_with?(@root + File::SEPARATOR)
      expanded
    end
  end
end
