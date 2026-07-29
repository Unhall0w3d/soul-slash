# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require "socket"
require "time"

require_relative "backup_retention_ledger"
require_relative "bounded_command_runner"

module SoulCore
  class BackupAdministrationService
    BACKUP_CONFIRMATION = "CREATE_VERIFIED_BACKUP"
    RETENTION_CONFIRMATION = "FORGET_SELECTED_BACKUP_SNAPSHOTS"
    RESTORE_CONFIRMATION = "STAGE_BACKUP_RESTORE"
    REPLICA_CONFIRMATION = "COPY_VERIFIED_BACKUP_TO_CRUCIBLE"
    SNAPSHOT_ID = /\A[a-f0-9]{64}\z/
    MAX_PASSWORD_BYTES = 1024
    MAX_SNAPSHOTS = 100
    MAX_RETENTION_SELECTION = 50
    MAX_RESTORE_PATHS = 20
    MAX_INVENTORY_PATHS = BackupRetentionLedger::MAX_PATHS
    BACKUP_TIMEOUT = 3600
    CHECK_TIMEOUT = 1200
    RETENTION_TIMEOUT = 3600
    RESTORE_TIMEOUT = 3600
    REPLICA_TIMEOUT = 3600
    REPLICA_CHECK_TIMEOUT = 1800

    def initialize(root: Dir.pwd, home: Dir.home, process_env: ENV, runner: BoundedCommandRunner.new, clock: -> { Time.now.utc }, id_generator: -> { SecureRandom.hex(8) })
      @root = File.expand_path(root)
      @home = File.expand_path(home)
      @env = process_env.to_h
      @runner = runner
      @clock = clock
      @id_generator = id_generator
      @repository = File.expand_path(@env.fetch("SOUL_BACKUP_REPOSITORY", "/mnt/soul-backup/restic"))
      @mount = File.expand_path(@env.fetch("SOUL_BACKUP_MOUNT", File.dirname(@repository)))
      @state_root = File.join(@root, "Soul", "private", "backup")
      @sources_path = File.join(@state_root, "sources.txt")
      @excludes_path = File.join(@state_root, "excludes.txt")
      @ledger_path = File.join(@state_root, "retention-ledger.json")
      @manifest_root = File.join(@state_root, "manifests")
      @receipt_root = File.join(@state_root, "receipts")
      @restore_root = File.join(@state_root, "restores")
      @operation_lock_path = File.join(@state_root, "operation.lock")
      @replica_repository = @env.fetch("SOUL_BACKUP_REPLICA_REPOSITORY", "sftp:crucible-maintenance:/srv/soul-backup/restic").to_s
      @replica_ssh_alias = @env.fetch("SOUL_BACKUP_REPLICA_SSH_ALIAS", "crucible-maintenance").to_s
      @replica_target_path = @env.fetch("SOUL_BACKUP_REPLICA_TARGET_PATH", "/srv/soul-backup/restic").to_s
      @replica_owner = @env.fetch("SOUL_BACKUP_REPLICA_OWNER", "souladmin").to_s
      @replica_ssh_config = File.expand_path(@env.fetch("SOUL_BACKUP_REPLICA_SSH_CONFIG", File.join(@home, ".ssh", "config")).to_s)
      @ledger = BackupRetentionLedger.new(ledger_path: @ledger_path, clock: @clock)
      raise ArgumentError, "backup state must remain inside the project root" unless within?(@state_root, @root)
      validate_private_state_root!
    end

    def status(password: nil)
      mount = mount_status
      sources = safe_manifest_lines(@sources_path, required: false)
      validated_password = password.to_s.empty? ? nil : validate_password(password)
      snapshots = validated_password ? snapshot_inventory(validated_password) : []
      {
        "ok" => true, "lifecycle_state" => "complete", "mutation" => "none",
        "data" => {
          "available" => !@runner.which("restic").nil?,
          "repository" => display_path(@repository),
          "mount" => mount,
          "configured" => File.file?(@sources_path) && File.file?(@excludes_path),
          "source_count" => sources.length,
          "ledger_present" => regular_file?(@ledger_path),
          "snapshot_access" => password.to_s.empty? ? "locked" : "unlocked",
          "snapshots" => snapshots,
          "receipt_count" => regular_json_count(@receipt_root),
          "restore_count" => regular_directory_count(@restore_root),
          "replica" => replica_status(validated_password),
          "manual_only" => true,
          "password_retained" => false
        }
      }
    rescue ArgumentError => error
      awaiting(error.message)
    rescue StandardError => error
      blocked("backup status failed safely: #{safe_error(error)}")
    ensure
      validated_password&.replace("\0" * validated_password.bytesize)
    end

    def replica_preview(password:)
      password = validate_password(password)
      preflight = replica_preflight(password)
      scope = {
        "operation" => "backup_replica_copy",
        "source_repository_fingerprint" => repository_fingerprint,
        "target_repository" => @replica_repository,
        "target_state" => preflight.fetch("target_state"),
        "initialize_target" => preflight.fetch("target_state") == "uninitialized",
        "source_snapshot_ids" => preflight.fetch("source_ids"),
        "source_snapshot_lineage_ids" => preflight.fetch("source_lineage_ids"),
        "target_snapshot_ids" => preflight.fetch("target_ids"),
        "target_snapshot_lineage_ids" => preflight.fetch("target_lineage_ids"),
        "missing_snapshot_ids" => preflight.fetch("missing_source_ids"),
        "verification" => "target metadata and exact original-snapshot lineage coverage",
        "remote_deletion" => false,
        "automatic_retry" => false,
        "password_retained" => false
      }
      complete("exact Crucible second-copy transaction prepared", scope.merge(
        "expected_digest" => digest(scope), "confirmation_phrase" => REPLICA_CONFIRMATION
      ))
    rescue ArgumentError => error
      awaiting(error.message)
    rescue StandardError => error
      blocked("Crucible copy preview failed safely: #{safe_error(error)}")
    ensure
      password&.replace("\0" * password.bytesize) if password.is_a?(String) && !password.frozen?
    end

    def replica_execute(password:, confirmation:, expected_digest:, progress: nil)
      password = validate_password(password)
      return awaiting("exact Crucible copy confirmation is required") unless confirmation.to_s == REPLICA_CONFIRMATION
      operation_lock = acquire_operation_lock
      return blocked("another backup administration operation is already active") unless operation_lock
      preview = replica_preview(password: password)
      return preview unless preview["ok"]
      return blocked("Crucible copy preview digest is stale or invalid") unless secure_equal?(expected_digest, preview.dig("data", "expected_digest"))

      progress&.call("stage" => "source_verify", "message" => "Verifying local repository metadata before transmission…")
      source_check = restic(password, "check", timeout: CHECK_TIMEOUT, output: 1024 * 1024)
      raise "local repository verification failed#{restic_failure_suffix(source_check)}" unless source_check.success?
      if preview.dig("data", "initialize_target")
        progress&.call("stage" => "initialize", "message" => "Initializing the exact encrypted Crucible repository…")
        initialized = replica_restic(password, "init", timeout: 120)
        raise "Crucible repository initialization failed#{restic_failure_suffix(initialized)}" unless initialized.success?
      end
      progress&.call("stage" => "copy", "message" => "Copying missing Soul snapshots to Crucible…")
      copied = replica_restic(
        password, "copy", "--from-repo", @repository, "--tag", "soul-state",
        timeout: REPLICA_TIMEOUT, output: 2 * 1024 * 1024,
        extra_env: { "RESTIC_FROM_PASSWORD" => password }
      )
      raise "Crucible snapshot copy failed#{restic_failure_suffix(copied)}" unless copied.success?
      progress&.call("stage" => "verify", "message" => "Verifying Crucible repository metadata and snapshot coverage…")
      checked = replica_restic(password, "check", timeout: REPLICA_CHECK_TIMEOUT, output: 1024 * 1024)
      raise "Crucible repository verification failed#{restic_failure_suffix(checked)}" unless checked.success?
      target = replica_inventory(password)
      missing = preview.dig("data", "source_snapshot_lineage_ids") - target.fetch("lineage_ids")
      raise "Crucible verification found missing source snapshots" unless missing.empty?
      receipt = write_receipt("replica", {
        "target_repository" => @replica_repository,
        "target_repository_id" => target["repository_id"],
        "source_snapshot_ids" => preview.dig("data", "source_snapshot_ids"),
        "source_snapshot_lineage_ids" => preview.dig("data", "source_snapshot_lineage_ids"),
        "copied_source_snapshot_ids" => preview.dig("data", "missing_snapshot_ids"),
        "destination_snapshot_ids" => target.fetch("ids"),
        "destination_snapshot_lineage_ids" => target.fetch("lineage_ids"),
        "target_snapshot_count" => target.fetch("ids").length,
        "remote_deletion" => false,
        "verification" => "source and target metadata passed; original-snapshot lineage coverage is exact"
      })
      progress&.call("stage" => "complete", "message" => "Crucible second copy verified.")
      complete("Crucible second copy completed and verified", receipt, "backup_replica_verified")
    rescue ArgumentError => error
      awaiting(error.message)
    rescue StandardError => error
      failed("Crucible copy failed safely: #{safe_error(error)}")
    ensure
      release_operation_lock(operation_lock)
      password&.replace("\0" * password.bytesize) if password.is_a?(String) && !password.frozen?
    end

    def backup_preview(password:)
      password = validate_password(password)
      preflight = backup_preflight(password)
      scope = {
        "operation" => "backup_create",
        "repository_fingerprint" => repository_fingerprint,
        "source_manifest_digest" => Digest::SHA256.file(@sources_path).hexdigest,
        "exclusion_manifest_digest" => Digest::SHA256.file(@excludes_path).hexdigest,
        "source_count" => preflight.fetch("sources").length,
        "sources" => preflight.fetch("sources").map { |path| display_path(path) },
        "estimated_bytes" => preflight.fetch("estimated_bytes"),
        "prior_snapshot_id" => preflight["prior_snapshot_id"],
        "retention_days" => BackupRetentionLedger::RETENTION_DAYS,
        "verification" => "metadata",
        "automatic_retry" => false
      }
      complete("exact backup transaction prepared", scope.merge(
        "expected_digest" => digest(scope), "confirmation_phrase" => BACKUP_CONFIRMATION,
        "password_retained" => false
      ))
    rescue ArgumentError => error
      awaiting(error.message)
    rescue StandardError => error
      blocked("backup preview failed safely: #{safe_error(error)}")
    ensure
      password&.replace("\0" * password.bytesize) if password.is_a?(String) && !password.frozen?
    end

    def backup_execute(password:, confirmation:, expected_digest:, progress: nil)
      password = validate_password(password)
      return awaiting("exact backup confirmation is required") unless confirmation.to_s == BACKUP_CONFIRMATION
      operation_lock = acquire_operation_lock
      return blocked("another backup administration operation is already active") unless operation_lock
      preview = backup_preview(password: password)
      return preview unless preview["ok"]
      return blocked("backup preview digest is stale or invalid") unless secure_equal?(expected_digest, preview.dig("data", "expected_digest"))

      progress&.call("stage" => "capture", "message" => "Capturing the approved owner-state sources…")
      result = restic(password, "backup", "--json", "--files-from", @sources_path, "--exclude-file", @excludes_path, "--tag", "soul-state", "--host", Socket.gethostname, timeout: BACKUP_TIMEOUT, output: 2 * 1024 * 1024)
      raise "restic backup failed#{restic_failure_suffix(result)}" unless result.success?
      summary = json_lines(result.stdout).reverse.find { |item| item["message_type"] == "summary" }
      snapshot_id = summary.to_h["snapshot_id"].to_s
      raise "restic did not return one full snapshot ID" unless snapshot_id.match?(SNAPSHOT_ID)

      progress&.call("stage" => "verify", "message" => "Verifying repository metadata before recording deletion evidence…")
      verify_repository!(password)
      manifest = build_snapshot_manifest(password, snapshot_id)
      FileUtils.mkdir_p(@manifest_root, mode: 0o700)
      manifest_path = File.join(@manifest_root, "#{snapshot_id}.json")
      atomic_json(manifest_path, manifest)
      observation = @ledger.observe_preview(manifest: manifest)
      raise observation["reason"] unless observation["ok"]
      recorded = @ledger.observe_execute(
        manifest: manifest,
        confirmation: BackupRetentionLedger::OBSERVE_CONFIRMATION,
        expected_digest: observation.dig("data", "expected_digest")
      )
      raise recorded["reason"] unless recorded["ok"]
      receipt = write_receipt("backup", {
        "snapshot_id" => snapshot_id,
        "manifest_sha256" => Digest::SHA256.file(manifest_path).hexdigest,
        "ledger_digest" => recorded.dig("data", "ledger_digest"),
        "new_deletion_count" => recorded.dig("data", "new_deletion_count"),
        "verification" => "passed"
      })
      progress&.call("stage" => "complete", "message" => "Verified snapshot and retention evidence recorded.")
      complete("verified backup completed", receipt.merge("snapshot_id" => snapshot_id), "backup_snapshot_created")
    rescue ArgumentError => error
      awaiting(error.message)
    rescue StandardError => error
      failed("backup failed safely: #{safe_error(error)}")
    ensure
      release_operation_lock(operation_lock)
      password&.replace("\0" * password.bytesize) if password.is_a?(String) && !password.frozen?
    end

    def retention_preview(password:, snapshot_ids:)
      password = validate_password(password)
      selected = normalize_snapshot_ids(snapshot_ids, maximum: MAX_RETENTION_SELECTION)
      raise ArgumentError, "select at least one snapshot" if selected.empty?
      snapshots = snapshot_inventory(password)
      known = snapshots.map { |item| item.fetch("id") }
      unknown = selected - known
      raise ArgumentError, "selection contains an unknown snapshot" unless unknown.empty?
      raise ArgumentError, "the newest snapshot cannot be forgotten" if selected.include?(known.first)
      raise ArgumentError, "retention must leave at least two snapshots" if known.length - selected.length < 2
      holds = @ledger.retention_preview(candidate_snapshot_ids: selected)
      raise holds["reason"] unless holds["ok"]
      protected_ids = holds.dig("data", "protected_candidate_snapshot_ids")
      raise ArgumentError, "selection contains a snapshot protected by an active deletion hold" unless protected_ids.empty?
      dry_run = restic(password, "forget", "--json", "--dry-run", "--prune", "--max-repack-size", max_repack_size, *selected, timeout: CHECK_TIMEOUT)
      raise "restic retention dry-run failed#{restic_failure_suffix(dry_run)}" unless dry_run.success?
      scope = {
        "operation" => "backup_retention",
        "repository_fingerprint" => repository_fingerprint,
        "ledger_digest" => holds.dig("data", "ledger_digest"),
        "snapshot_inventory_digest" => digest(snapshots),
        "selected_snapshot_ids" => selected,
        "remaining_snapshot_count" => known.length - selected.length,
        "max_repack_size" => max_repack_size,
        "post_operation_check" => "metadata",
        "automatic_retry" => false
      }
      complete("exact forget and bounded prune transaction prepared", scope.merge(
        "expected_digest" => digest(scope), "confirmation_phrase" => RETENTION_CONFIRMATION,
        "password_retained" => false
      ))
    rescue ArgumentError => error
      awaiting(error.message)
    rescue StandardError => error
      blocked("retention preview failed safely: #{safe_error(error)}")
    ensure
      password&.replace("\0" * password.bytesize) if password.is_a?(String) && !password.frozen?
    end

    def retention_execute(password:, snapshot_ids:, confirmation:, expected_digest:, progress: nil)
      password = validate_password(password)
      return awaiting("exact retention confirmation is required") unless confirmation.to_s == RETENTION_CONFIRMATION
      operation_lock = acquire_operation_lock
      return blocked("another backup administration operation is already active") unless operation_lock
      preview = retention_preview(password: password, snapshot_ids: snapshot_ids)
      return preview unless preview["ok"]
      return blocked("retention preview digest is stale or invalid") unless secure_equal?(expected_digest, preview.dig("data", "expected_digest"))
      selected = preview.dig("data", "selected_snapshot_ids")
      progress&.call("stage" => "forget", "message" => "Removing only the approved hold-clear snapshot references…")
      result = restic(password, "forget", "--json", "--prune", "--max-repack-size", max_repack_size, *selected, timeout: RETENTION_TIMEOUT, output: 2 * 1024 * 1024)
      raise "restic retention failed#{restic_failure_suffix(result)}" unless result.success?
      progress&.call("stage" => "verify", "message" => "Verifying repository metadata after retention…")
      verify_repository!(password)
      receipt = write_receipt("retention", {
        "forgotten_snapshot_ids" => selected,
        "max_repack_size" => max_repack_size,
        "verification" => "passed"
      })
      complete("approved retention completed and repository verified", receipt, "backup_snapshots_forgotten")
    rescue ArgumentError => error
      awaiting(error.message)
    rescue StandardError => error
      failed("retention failed safely: #{safe_error(error)}")
    ensure
      release_operation_lock(operation_lock)
      password&.replace("\0" * password.bytesize) if password.is_a?(String) && !password.frozen?
    end

    def restore_preview(password:, snapshot_id:, paths: [])
      password = validate_password(password)
      id = snapshot_id.to_s
      raise ArgumentError, "snapshot ID is invalid" unless id.match?(SNAPSHOT_ID)
      snapshots = snapshot_inventory(password)
      raise ArgumentError, "snapshot was not found" unless snapshots.any? { |item| item["id"] == id }
      includes = normalize_restore_paths(paths)
      inventory = snapshot_paths(password, id)
      missing = includes.reject { |path| inventory.any? { |candidate| candidate == path || candidate.start_with?("#{path}/") } }
      raise ArgumentError, "restore path is absent from the snapshot" unless missing.empty?
      scope = {
        "operation" => "backup_staged_restore",
        "repository_fingerprint" => repository_fingerprint,
        "snapshot_id" => id,
        "includes" => includes,
        "scope" => includes.empty? ? "full_snapshot" : "selected_paths",
        "target_root" => display_path(@restore_root),
        "verify_restored_files" => true,
        "live_tree_mutation" => false,
        "automatic_retry" => false
      }
      complete("exact staged restore prepared", scope.merge(
        "expected_digest" => digest(scope), "confirmation_phrase" => RESTORE_CONFIRMATION,
        "password_retained" => false
      ))
    rescue ArgumentError => error
      awaiting(error.message)
    rescue StandardError => error
      blocked("restore preview failed safely: #{safe_error(error)}")
    ensure
      password&.replace("\0" * password.bytesize) if password.is_a?(String) && !password.frozen?
    end

    def restore_execute(password:, snapshot_id:, paths: [], confirmation:, expected_digest:, progress: nil)
      password = validate_password(password)
      return awaiting("exact staged-restore confirmation is required") unless confirmation.to_s == RESTORE_CONFIRMATION
      operation_lock = acquire_operation_lock
      return blocked("another backup administration operation is already active") unless operation_lock
      preview = restore_preview(password: password, snapshot_id: snapshot_id, paths: paths)
      return preview unless preview["ok"]
      return blocked("restore preview digest is stale or invalid") unless secure_equal?(expected_digest, preview.dig("data", "expected_digest"))
      restore_id = "restore_#{@id_generator.call}"
      raise "restore ID is invalid" unless restore_id.match?(/\Arestore_[a-f0-9]{16}\z/)
      target = File.join(@restore_root, restore_id)
      FileUtils.mkdir_p(@restore_root, mode: 0o700)
      raise "restore target already exists" if File.exist?(target) || File.symlink?(target)
      FileUtils.mkdir(target, mode: 0o700)
      args = ["restore", preview.dig("data", "snapshot_id"), "--target", target, "--verify"]
      preview.dig("data", "includes").each { |path| args.concat(["--include", path]) }
      progress&.call("stage" => "restore", "message" => "Restoring the approved snapshot into isolated staging…")
      result = restic(password, *args, timeout: RESTORE_TIMEOUT, output: 2 * 1024 * 1024)
      raise "restic restore failed#{restic_failure_suffix(result)}" unless result.success?
      evidence = staged_inventory(target)
      receipt = write_receipt("restore", {
        "restore_id" => restore_id,
        "snapshot_id" => preview.dig("data", "snapshot_id"),
        "includes" => preview.dig("data", "includes"),
        "staged_path" => display_path(target),
        "file_count" => evidence.fetch("file_count"),
        "total_bytes" => evidence.fetch("total_bytes"),
        "inventory_digest" => evidence.fetch("inventory_digest"),
        "live_tree_mutation" => false
      })
      {
        "ok" => false, "lifecycle_state" => "blocked_for_human_review",
        "reason" => "staged restore verified; inspect before any external live promotion",
        "data" => receipt, "mutation" => "backup_restore_staged"
      }
    rescue ArgumentError => error
      awaiting(error.message)
    rescue StandardError => error
      failed("restore failed safely: #{safe_error(error)}")
    ensure
      release_operation_lock(operation_lock)
      password&.replace("\0" * password.bytesize) if password.is_a?(String) && !password.frozen?
    end

    private

    def replica_status(password)
      validate_replica_configuration!
      target = replica_target_status
      return {
        "configured" => true, "target" => @replica_repository, "transport" => "SFTP over fixed SSH alias",
        "state" => "locked", "target_ready" => target["ready"], "password_retained" => false,
        "automatic_copy" => false, "remote_deletion" => false
      } unless password
      inventory = replica_inventory(password)
      {
        "configured" => true, "target" => @replica_repository, "transport" => "SFTP over fixed SSH alias",
        "state" => inventory.fetch("state"), "target_ready" => target["ready"],
        "snapshot_count" => inventory.fetch("ids").length, "repository_id" => inventory["repository_id"],
        "password_retained" => false, "automatic_copy" => false, "remote_deletion" => false
      }
    rescue StandardError => error
      {
        "configured" => false, "target" => @replica_repository, "state" => "unavailable",
        "reason" => safe_error(error), "password_retained" => false,
        "automatic_copy" => false, "remote_deletion" => false
      }
    end

    def replica_preflight(password)
      raise ArgumentError, "restic is unavailable" unless @runner.which("restic")
      validate_replica_configuration!
      mount = mount_status
      raise ArgumentError, "local backup target is not mounted" unless mount["mounted"] && mount["expected_target"]
      raise ArgumentError, "local backup repository is unavailable" unless File.directory?(@repository) && !File.symlink?(@repository)
      target = replica_target_status
      raise ArgumentError, "Crucible backup target identity is invalid" unless target["ready"]
      source = snapshot_inventory(password)
      raise ArgumentError, "local backup repository contains no Soul snapshots" if source.empty?
      remote = replica_inventory(password)
      target_lineage_ids = remote.fetch("lineage_ids")
      {
        "source_ids" => source.map { |item| item.fetch("id") }.sort,
        "source_lineage_ids" => source.map { |item| item.fetch("lineage_id") }.uniq.sort,
        "target_ids" => remote.fetch("ids"),
        "target_lineage_ids" => target_lineage_ids,
        "missing_source_ids" => source.reject { |item| target_lineage_ids.include?(item.fetch("lineage_id")) }.map { |item| item.fetch("id") }.sort,
        "target_state" => remote.fetch("state")
      }
    end

    def validate_replica_configuration!
      raise ArgumentError, "Crucible SSH alias is invalid" unless @replica_ssh_alias.match?(/\A[A-Za-z0-9][A-Za-z0-9_.-]{0,127}\z/)
      raise ArgumentError, "Crucible target owner is invalid" unless @replica_owner.match?(/\A[a-z_][a-z0-9_-]{0,31}\z/)
      raise ArgumentError, "Crucible target path is invalid" unless @replica_target_path.start_with?("/") && File.expand_path(@replica_target_path) == @replica_target_path
      raise ArgumentError, "Crucible SSH config is unavailable" unless regular_file?(@replica_ssh_config) && File.readable?(@replica_ssh_config)
      raise ArgumentError, "Crucible SSH config permissions are unsafe" unless (File.stat(@replica_ssh_config).mode & 0o022).zero?
      expected = "sftp:#{@replica_ssh_alias}:#{@replica_target_path}"
      raise ArgumentError, "Crucible repository must match its fixed SSH alias and target path" unless @replica_repository == expected
    end

    def replica_target_status
      raise ArgumentError, "ssh is unavailable" unless @runner.which("ssh")
      result = @runner.run(
        "ssh", "-F", @replica_ssh_config, "-o", "BatchMode=yes", "-o", "PasswordAuthentication=no", "-o", "ConnectTimeout=5",
        @replica_ssh_alias, "--", "/usr/bin/stat", "--format=%F,%U,%a", @replica_target_path,
        timeout_seconds: 10, max_output_bytes: 4096
      )
      raise "Crucible backup target is unreachable" unless result.success?
      kind, owner, mode = result.stdout.strip.split(",", 3)
      { "ready" => kind == "directory" && owner == @replica_owner && mode == "700", "kind" => kind, "owner" => owner, "mode" => mode }
    end

    def replica_inventory(password)
      result = replica_restic(password, "snapshots", "--json", "--tag", "soul-state", timeout: 60, output: 1024 * 1024)
      return { "state" => "uninitialized", "ids" => [], "lineage_ids" => [], "repository_id" => nil } if result.exit_status == 10
      raise ArgumentError, "Crucible repository password was rejected" if result.exit_status == 12
      raise "Crucible snapshot inventory failed#{restic_failure_suffix(result)}" unless result.success?
      snapshots = JSON.parse(result.stdout)
      raise "Crucible snapshot inventory is invalid" unless snapshots.is_a?(Array) && snapshots.length <= MAX_SNAPSHOTS
      identities = snapshots.map { |item| snapshot_identity(item, "Crucible") }
      ids = identities.map { |item| item.fetch("id") }
      raise "Crucible snapshot inventory contains an invalid ID" unless ids.all? { |id| id.match?(SNAPSHOT_ID) } && ids.uniq.length == ids.length
      config = replica_restic(password, "cat", "config", timeout: 60, output: 1024 * 1024)
      raise "Crucible repository identity failed#{restic_failure_suffix(config)}" unless config.success?
      repository_id = JSON.parse(config.stdout).fetch("id").to_s
      raise "Crucible repository identity is invalid" unless repository_id.match?(SNAPSHOT_ID)
      {
        "state" => "ready",
        "ids" => ids.sort,
        "lineage_ids" => identities.map { |item| item.fetch("lineage_id") }.uniq.sort,
        "repository_id" => repository_id
      }
    rescue JSON::ParserError, KeyError
      raise "Crucible repository inventory is invalid"
    end

    def replica_restic(password, *args, timeout:, output: 256 * 1024, extra_env: {})
      @runner.run(
        "restic", "-o", "sftp.command=ssh -F #{@replica_ssh_config} #{@replica_ssh_alias} -s sftp", "--repo", @replica_repository, *args,
        timeout_seconds: timeout, max_output_bytes: output,
        env: { "RESTIC_PASSWORD" => password }.merge(extra_env)
      )
    end

    def backup_preflight(password)
      raise ArgumentError, "restic is unavailable" unless @runner.which("restic")
      mount = mount_status
      raise ArgumentError, "backup target is not mounted" unless mount["mounted"]
      raise ArgumentError, "backup repository is not on the configured recovery mount" unless mount["expected_target"]
      raise ArgumentError, "backup target is read-only" unless mount["writable"]
      raise ArgumentError, "backup repository is unavailable" unless File.directory?(@repository) && !File.symlink?(@repository)
      sources = safe_manifest_lines(@sources_path)
      safe_manifest_lines(@excludes_path)
      sources.each do |path|
        raise ArgumentError, "configured source is unavailable: #{display_path(path)}" unless File.exist?(path) && File.readable?(path)
        raise ArgumentError, "configured source must not be a symlink: #{display_path(path)}" if File.symlink?(path)
      end
      raise ArgumentError, "active creative or model work blocks a consistent snapshot" if active_work?
      snapshots = snapshot_inventory(password)
      roots = topmost_paths(sources)
      estimated = roots.sum { |path| disk_usage(path) }
      { "sources" => sources, "estimated_bytes" => estimated, "prior_snapshot_id" => snapshots.first&.fetch("id", nil) }
    end

    def snapshot_inventory(password)
      result = restic(password, "snapshots", "--json", "--tag", "soul-state", timeout: 30, output: 1024 * 1024)
      raise ArgumentError, "repository password was rejected" if result.exit_status == 12
      raise "snapshot inventory failed#{restic_failure_suffix(result)}" unless result.success?
      parsed = JSON.parse(result.stdout)
      raise "snapshot inventory is invalid" unless parsed.is_a?(Array) && parsed.length <= MAX_SNAPSHOTS
      parsed.map do |item|
        identity = snapshot_identity(item, "local")
        id = identity.fetch("id")
        {
          "id" => id, "short_id" => id[0, 8], "time" => Time.iso8601(item.fetch("time")).utc.iso8601,
          "original_id" => identity["original_id"], "lineage_id" => identity.fetch("lineage_id"),
          "hostname" => item["hostname"].to_s.byteslice(0, 120),
          "paths" => Array(item["paths"]).first(64).map { |path| display_path(path.to_s) },
          "tags" => Array(item["tags"]).first(16).map(&:to_s)
        }
      end.sort_by { |item| item.fetch("time") }.reverse
    rescue JSON::ParserError, KeyError, ArgumentError => error
      raise ArgumentError, error.message if error.message.include?("password")
      raise "snapshot inventory is invalid"
    end

    def snapshot_identity(item, label)
      raise "#{label} snapshot inventory is invalid" unless item.is_a?(Hash)
      id = item["id"].to_s
      original_id = item["original"].to_s
      original_id = nil if original_id.empty?
      raise "#{label} snapshot inventory contains an invalid ID" unless id.match?(SNAPSHOT_ID)
      if original_id && !original_id.match?(SNAPSHOT_ID)
        raise "#{label} snapshot inventory contains an invalid original ID"
      end
      { "id" => id, "original_id" => original_id, "lineage_id" => original_id || id }
    end

    def build_snapshot_manifest(password, snapshot_id)
      paths = snapshot_paths(password, snapshot_id)
      configured = safe_manifest_lines(@sources_path)
      missing = configured.reject { |source| paths.include?(source) || paths.any? { |path| path.start_with?("#{source}/") } }
      raise "snapshot inventory omitted a configured source" unless missing.empty?
      roots = configured.sort
      paths = paths.select { |path| roots.any? { |source| path == source || path.start_with?("#{source}/") } }
      paths = (paths + roots).uniq.sort
      {
        "schema_version" => BackupRetentionLedger::MANIFEST_SCHEMA_VERSION,
        "snapshot_id" => snapshot_id,
        "verified_at" => @clock.call.utc.iso8601,
        "repository_id" => repository_fingerprint,
        "source_roots" => roots.sort,
        "paths" => paths,
        "verification" => { "check_mode" => "metadata", "result" => "passed" }
      }
    end

    def snapshot_paths(password, snapshot_id)
      result = restic(password, "ls", "--json", snapshot_id, timeout: CHECK_TIMEOUT, output: 16 * 1024 * 1024)
      raise "snapshot path inventory failed#{restic_failure_suffix(result)}" unless result.success?
      paths = json_lines(result.stdout).filter_map { |item| item["path"].to_s if item["struct_type"] == "node" }
      paths = paths.map { |path| File.expand_path(path) }.uniq.sort
      raise "snapshot path inventory is empty or too large" if paths.empty? || paths.length > MAX_INVENTORY_PATHS
      paths
    end

    def verify_repository!(password)
      result = restic(password, "check", timeout: CHECK_TIMEOUT, output: 1024 * 1024)
      raise "repository verification failed#{restic_failure_suffix(result)}" unless result.success?
      true
    end

    def restic(password, *args, timeout:, output: 256 * 1024)
      @runner.run("restic", "--repo", @repository, *args, timeout_seconds: timeout, max_output_bytes: output, env: { "RESTIC_PASSWORD" => password })
    end

    def mount_status
      result = @runner.run("findmnt", "--json", "-T", @repository, timeout_seconds: 5, max_output_bytes: 32 * 1024)
      return { "mounted" => false, "writable" => false, "target" => display_path(@mount), "state" => "unavailable" } unless result.success?
      item = JSON.parse(result.stdout).fetch("filesystems").first
      options = item.fetch("options", "").split(",")
      {
        "mounted" => true, "writable" => !options.include?("ro"),
        "target" => display_path(item.fetch("target")), "source" => item.fetch("source").to_s,
        "filesystem" => item.fetch("fstype").to_s,
        "expected_target" => File.expand_path(item.fetch("target")) == @mount,
        "state" => options.include?("ro") ? "read_only" : "ready"
      }
    rescue JSON::ParserError, KeyError
      { "mounted" => false, "writable" => false, "target" => display_path(@mount), "state" => "invalid" }
    end

    def safe_manifest_lines(path, required: true)
      unless regular_file?(path)
        raise ArgumentError, "backup manifest is unavailable: #{display_path(path)}" if required
        return []
      end
      raise ArgumentError, "backup manifest exceeds size limit" if File.size(path) > 256 * 1024
      lines = File.readlines(path, chomp: true).map(&:strip).reject { |line| line.empty? || line.start_with?("#") }
      raise ArgumentError, "backup manifest is empty" if required && lines.empty?
      return lines if path == @excludes_path
      normalized = lines.map { |line| File.expand_path(line) }
      raise ArgumentError, "backup source paths must be absolute, unique, and normalized" unless normalized == lines && normalized.uniq.length == lines.length
      raise ArgumentError, "backup source count exceeds 256" if lines.length > 256
      lines
    end

    def active_work?
      job_active = Dir.glob(File.join(@root, "Soul", "music", "jobs", "job_*.json")).any? do |path|
        next false unless regular_file?(path) && File.size(path) <= 256 * 1024
        %w[accepted running].include?(JSON.parse(File.read(path))["status"])
      rescue JSON::ParserError, Errno::ENOENT
        true
      end
      lease_active = Dir.glob(File.join(@root, "Soul", "runtime", "model_runtime", "leases", "*.json")).any? { |path| regular_file?(path) }
      job_active || lease_active
    end

    def normalize_snapshot_ids(value, maximum:)
      raise ArgumentError, "snapshot selection must be an array" unless value.is_a?(Array) && value.length <= maximum
      ids = value.map(&:to_s)
      raise ArgumentError, "snapshot selection contains invalid or duplicate IDs" unless ids.all? { |id| id.match?(SNAPSHOT_ID) } && ids.uniq.length == ids.length
      ids.sort
    end

    def normalize_restore_paths(value)
      raise ArgumentError, "restore paths must be an array" unless value.is_a?(Array) && value.length <= MAX_RESTORE_PATHS
      paths = value.map { |path| File.expand_path(path.to_s) }
      raise ArgumentError, "restore paths must be absolute, unique, and normalized" unless paths == value && paths.uniq.length == paths.length && paths.all? { |path| path.start_with?("/") }
      paths.sort
    end

    def staged_inventory(root)
      files = []
      Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH).sort.each do |path|
        next if [".", ".."].include?(File.basename(path))
        stat = File.lstat(path)
        next if stat.directory? || stat.symlink?
        raise "staged restore inventory exceeds #{MAX_INVENTORY_PATHS}" if files.length >= MAX_INVENTORY_PATHS
        relative = path.delete_prefix("#{root}/")
        files << [relative, stat.size, Digest::SHA256.file(path).hexdigest]
      end
      { "file_count" => files.length, "total_bytes" => files.sum { |item| item[1] }, "inventory_digest" => digest(files) }
    end

    def disk_usage(path)
      result = @runner.run("du", "-s", "-B1", "--", path, timeout_seconds: 30, max_output_bytes: 4096)
      result.success? ? Integer(result.stdout.split.first) : 0
    rescue ArgumentError
      0
    end

    def topmost_paths(paths)
      paths.sort_by(&:length).reject { |path| paths.any? { |other| other != path && path.start_with?("#{other}/") } }
    end

    def repository_fingerprint
      config = File.join(@repository, "config")
      raise "repository config is unavailable" unless regular_file?(config) && File.size(config) <= 1024 * 1024
      Digest::SHA256.file(config).hexdigest
    end

    def write_receipt(kind, data)
      FileUtils.mkdir_p(@receipt_root, mode: 0o700)
      timestamp = @clock.call.utc
      id = "#{kind}_#{timestamp.strftime('%Y%m%dT%H%M%SZ')}_#{@id_generator.call}"
      receipt = {
        "schema_version" => "soul.backup_receipt.v1", "receipt_id" => id,
        "operation" => kind, "completed_at" => timestamp.iso8601,
        "repository_fingerprint" => repository_fingerprint
      }.merge(data)
      path = File.join(@receipt_root, "#{id}.json")
      atomic_json(path, receipt)
      receipt.merge("receipt_path" => display_path(path))
    end

    def atomic_json(path, value)
      body = JSON.pretty_generate(value) + "\n"
      temporary = "#{path}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(body); file.flush; file.fsync
      end
      File.rename(temporary, path)
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary
    end

    def regular_file?(path)
      File.file?(path) && !File.symlink?(path)
    end

    def regular_json_count(path)
      return 0 unless File.directory?(path) && !File.symlink?(path)
      Dir.glob(File.join(path, "*.json")).count { |item| regular_file?(item) }
    end

    def regular_directory_count(path)
      return 0 unless File.directory?(path) && !File.symlink?(path)
      Dir.children(path).count { |name| File.directory?(File.join(path, name)) && !File.symlink?(File.join(path, name)) }
    end

    def max_repack_size
      value = @env.fetch("SOUL_BACKUP_MAX_REPACK_SIZE", "4G").to_s
      raise ArgumentError, "backup max repack size is invalid" unless value.match?(/\A(?:[1-9]\d{0,3})(?:M|G)\z/)
      value
    end

    def acquire_operation_lock
      FileUtils.mkdir_p(@state_root, mode: 0o700)
      lock = File.open(@operation_lock_path, File::RDWR | File::CREAT, 0o600)
      return lock if lock.flock(File::LOCK_EX | File::LOCK_NB)
      lock.close
      nil
    end

    def validate_private_state_root!
      [File.join(@root, "Soul"), File.join(@root, "Soul", "private"), @state_root].each do |path|
        raise ArgumentError, "backup state path must not traverse a symlink" if File.symlink?(path)
      end
      return unless File.exist?(@state_root)
      raise ArgumentError, "backup state root must be a directory" unless File.directory?(@state_root)
      raise ArgumentError, "backup state root must be owner-only" unless (File.stat(@state_root).mode & 0o077).zero?
    end

    def release_operation_lock(lock)
      return unless lock
      lock.flock(File::LOCK_UN)
      lock.close
    rescue IOError
      nil
    end

    def validate_password(value)
      password = value.to_s.dup
      raise ArgumentError, "repository password is required" if password.empty?
      raise ArgumentError, "repository password exceeds size limit" if password.bytesize > MAX_PASSWORD_BYTES || password.include?("\0")
      password
    end

    def json_lines(value)
      value.to_s.lines.filter_map { |line| JSON.parse(line) unless line.strip.empty? }
    rescue JSON::ParserError
      raise "restic JSON output is invalid"
    end

    def restic_failure_suffix(result)
      return " (password rejected)" if result.exit_status == 12
      return " (repository locked)" if result.exit_status == 11
      return " (timed out)" if result.status == "timeout"
      " (exit #{result.exit_status || 'unavailable'})"
    end

    def safe_error(error)
      error.message.to_s.gsub(@root, "[PROJECT_ROOT]").gsub(@home, "~").gsub(@repository, "[BACKUP_REPOSITORY]").slice(0, 240)
    end

    def display_path(path)
      expanded = File.expand_path(path)
      return "~#{expanded.delete_prefix(@home)}" if expanded == @home || expanded.start_with?("#{@home}/")
      return expanded.delete_prefix("#{@root}/") if expanded.start_with?("#{@root}/")
      expanded
    end

    def within?(path, root)
      path == root || path.start_with?("#{root}/")
    end

    def digest(value)
      Digest::SHA256.hexdigest(JSON.generate(canonical(value)))
    end

    def canonical(value)
      case value
      when Hash then value.keys.sort.to_h { |key| [key, canonical(value.fetch(key))] }
      when Array then value.map { |item| canonical(item) }
      else value
      end
    end

    def secure_equal?(provided, expected)
      left = provided.to_s; right = expected.to_s
      left.bytesize == right.bytesize && Digest::SHA256.hexdigest(left) == Digest::SHA256.hexdigest(right)
    end

    def complete(reason, data, mutation = "none")
      { "ok" => true, "lifecycle_state" => "complete", "reason" => reason, "data" => data, "mutation" => mutation }
    end

    def awaiting(reason)
      { "ok" => false, "lifecycle_state" => "awaiting_input", "reason" => reason, "data" => {}, "mutation" => "none" }
    end

    def blocked(reason)
      { "ok" => false, "lifecycle_state" => "blocked_for_human_review", "reason" => reason, "data" => {}, "mutation" => "none" }
    end

    def failed(reason)
      { "ok" => false, "lifecycle_state" => "failed", "reason" => reason, "data" => {}, "mutation" => "none" }
    end
  end
end
