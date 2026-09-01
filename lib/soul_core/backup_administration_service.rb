# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require "socket"
require "time"

require_relative "backup_manifest_policy"
require_relative "backup_retention_ledger"
require_relative "bounded_command_runner"
require_relative "operator_backup_manifest_policy"

module SoulCore
  class BackupAdministrationService
    BACKUP_CONFIRMATION = "CREATE_VERIFIED_BACKUP"
    RETENTION_CONFIRMATION = "FORGET_SELECTED_BACKUP_SNAPSHOTS"
    RESTORE_CONFIRMATION = "STAGE_BACKUP_RESTORE"
    REPLICA_CONFIRMATION = "COPY_VERIFIED_BACKUP_TO_CRUCIBLE"
    DRS_CONFIRMATION = "CREATE_AND_REPLICATE_VERIFIED_DRS_BACKUP"
    MANIFEST_RECONCILIATION_CONFIRMATION = "RECONCILE_BACKUP_MANIFESTS"
    OPERATOR_BACKUP_CONFIRMATION = "CREATE_VERIFIED_OPERATOR_BACKUP"
    OPERATOR_RETENTION_CONFIRMATION = "FORGET_SELECTED_OPERATOR_BACKUP_SNAPSHOTS"
    OPERATOR_RESTORE_CONFIRMATION = "STAGE_OPERATOR_BACKUP_RESTORE"
    OPERATOR_REPLICA_CONFIRMATION = "COPY_VERIFIED_OPERATOR_BACKUP_TO_CRUCIBLE"
    OPERATOR_DRS_CONFIRMATION = "CREATE_AND_REPLICATE_VERIFIED_OPERATOR_DRS_BACKUP"
    OPERATOR_MANIFEST_RECONCILIATION_CONFIRMATION = "RECONCILE_OPERATOR_BACKUP_MANIFESTS"
    OPERATOR_SNAPSHOT_EVIDENCE_RECONCILIATION_CONFIRMATION = "RECONCILE_OPERATOR_SNAPSHOT_EVIDENCE"
    SNAPSHOT_ID = /\A[a-f0-9]{64}\z/
    MAX_PASSWORD_BYTES = 1024
    MAX_SNAPSHOTS = 100
    MAX_RETENTION_SELECTION = 50
    MAX_RESTORE_PATHS = 20
    MAX_INVENTORY_PATHS = BackupRetentionLedger::MAX_PATHS
    OPERATOR_MAX_SOURCE_ROOTS = 256
    BACKUP_TIMEOUT = 3600
    CHECK_TIMEOUT = 1200
    RETENTION_TIMEOUT = 3600
    RESTORE_TIMEOUT = 3600
    REPLICA_TIMEOUT = 3600
    REPLICA_CHECK_TIMEOUT = 1800

    def initialize(root: Dir.pwd, home: Dir.home, process_env: ENV, runner: BoundedCommandRunner.new, clock: -> { Time.now.utc }, id_generator: -> { SecureRandom.hex(8) }, profile_id: "soul")
      @root = File.expand_path(root)
      @home = File.expand_path(home)
      @env = process_env.to_h
      @runner = runner
      @clock = clock
      @id_generator = id_generator
      @profile_id = profile_id.to_s
      raise ArgumentError, "backup profile must be soul or operator" unless %w[soul operator].include?(@profile_id)

      operator = @profile_id == "operator"
      @profile_label = operator ? "Operator" : "Soul"
      @snapshot_tag = operator ? OperatorBackupManifestPolicy::SNAPSHOT_TAG : "soul-state"
      @environment_prefix = operator ? "OPERATOR_BACKUP" : "SOUL_BACKUP"
      @repository = File.expand_path(profile_environment("REPOSITORY", "/mnt/soul-backup/restic"))
      @mount = File.expand_path(profile_environment("MOUNT", File.dirname(@repository)))
      @state_root = File.join(@root, "Soul", "private", operator ? "operator_backup" : "backup")
      @sources_path = File.join(@state_root, "sources.txt")
      @excludes_path = File.join(@state_root, "excludes.txt")
      @ledger_path = File.join(@state_root, "retention-ledger.json")
      @manifest_root = File.join(@state_root, "manifests")
      @receipt_root = File.join(@state_root, "receipts")
      @restore_root = File.join(@state_root, "restores")
      @operation_lock_path = File.join(@root, "Soul", "private", "backup", "operation.lock")
      @replica_repository = profile_environment("REPLICA_REPOSITORY", "sftp:crucible-maintenance:/srv/soul-backup/restic").to_s
      @replica_ssh_alias = profile_environment("REPLICA_SSH_ALIAS", "crucible-maintenance").to_s
      @replica_target_path = profile_environment("REPLICA_TARGET_PATH", "/srv/soul-backup/restic").to_s
      @replica_owner = profile_environment("REPLICA_OWNER", "souladmin").to_s
      @replica_ssh_config = File.expand_path(profile_environment("REPLICA_SSH_CONFIG", File.join(@home, ".ssh", "config")).to_s)
      @manifest_policy = if operator
        OperatorBackupManifestPolicy.new(root: @root, home: @home)
      else
        BackupManifestPolicy.new(root: @root, home: @home)
      end
      @confirmations = if operator
        {
          backup: OPERATOR_BACKUP_CONFIRMATION,
          retention: OPERATOR_RETENTION_CONFIRMATION,
          restore: OPERATOR_RESTORE_CONFIRMATION,
          replica: OPERATOR_REPLICA_CONFIRMATION,
          drs: OPERATOR_DRS_CONFIRMATION,
          manifests: OPERATOR_MANIFEST_RECONCILIATION_CONFIRMATION
        }
      else
        {
          backup: BACKUP_CONFIRMATION,
          retention: RETENTION_CONFIRMATION,
          restore: RESTORE_CONFIRMATION,
          replica: REPLICA_CONFIRMATION,
          drs: DRS_CONFIRMATION,
          manifests: MANIFEST_RECONCILIATION_CONFIRMATION
        }
      end
      @ledger = BackupRetentionLedger.new(
        ledger_path: @ledger_path,
        clock: @clock,
        max_roots: operator ? OPERATOR_MAX_SOURCE_ROOTS : BackupRetentionLedger::MAX_ROOTS
      )
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
          "profile_id" => @profile_id,
          "profile_label" => @profile_label,
          "snapshot_tag" => @snapshot_tag,
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
          "drs" => latest_drs_status,
          "manifest_reconciliation" => manifest_reconciliation_summary,
          "policy" => @manifest_policy.respond_to?(:summary) ? @manifest_policy.summary : {},
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

    def retained_drs_status
      {
        "ok" => true,
        "lifecycle_state" => "complete",
        "mutation" => "none",
        "data" => {
          "profile_id" => @profile_id,
          "drs" => latest_drs_status,
          "source" => "retained_backup_receipt",
          "automatic_refresh" => false
        }
      }
    rescue StandardError => error
      blocked("retained DRS status failed safely: #{safe_error(error)}")
    end

    def manifest_reconciliation_preview
      scope = manifest_reconciliation_scope
      complete("exact add-only backup manifest reconciliation prepared", manifest_reconciliation_view(scope).merge(
        "expected_digest" => digest(scope),
        "confirmation_phrase" => @confirmations.fetch(:manifests)
      ))
    rescue ArgumentError => error
      awaiting(error.message)
    rescue StandardError => error
      blocked("backup manifest reconciliation preview failed safely: #{safe_error(error)}")
    end

    def manifest_reconciliation_execute(confirmation:, expected_digest:)
      return awaiting("exact backup manifest reconciliation confirmation is required") unless confirmation.to_s == @confirmations.fetch(:manifests)
      operation_lock = acquire_operation_lock
      return blocked("another backup administration operation is already active") unless operation_lock

      scope = manifest_reconciliation_scope
      return blocked("backup manifest reconciliation preview digest is stale or invalid") unless secure_equal?(expected_digest, digest(scope))
      if scope.fetch("source_additions").empty? && scope.fetch("exclusion_additions").empty?
        return complete("backup manifests already match the portable policy", manifest_reconciliation_view(scope))
      end

      source_before = manifest_body(@sources_path)
      exclusion_before = manifest_body(@excludes_path)
      source_after = append_manifest_lines(source_before, scope.fetch("source_additions"))
      exclusion_after = append_manifest_lines(exclusion_before, scope.fetch("exclusion_additions"))
      write_manifest_pair(source_after, exclusion_after, source_before, exclusion_before)

      verified = manifest_reconciliation_scope
      raise "backup manifest reconciliation did not reach the reviewed policy" unless verified.fetch("source_additions").empty? && verified.fetch("exclusion_additions").empty?
      receipt = write_manifest_reconciliation_receipt(scope)
      complete("backup manifests reconciled; create a fresh verified snapshot to prove coverage", {
        "source_addition_count" => scope.fetch("source_additions").length,
        "exclusion_addition_count" => scope.fetch("exclusion_additions").length,
        "source_manifest_digest" => Digest::SHA256.file(@sources_path).hexdigest,
        "exclusion_manifest_digest" => Digest::SHA256.file(@excludes_path).hexdigest,
        "receipt_id" => receipt.fetch("receipt_id"),
        "snapshot_verification_required" => true
      }, "backup_manifests_reconciled")
    rescue ArgumentError => error
      awaiting(error.message)
    rescue StandardError => error
      failed("backup manifest reconciliation failed safely: #{safe_error(error)}")
    ensure
      release_operation_lock(operation_lock)
    end

    def replica_preview(password:)
      password = validate_password(password)
      preflight = replica_preflight(password)
      scope = {
        "operation" => "backup_replica_copy",
        "profile_id" => @profile_id,
        "snapshot_tag" => @snapshot_tag,
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
        "expected_digest" => digest(scope), "confirmation_phrase" => @confirmations.fetch(:replica)
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
      return awaiting("exact Crucible copy confirmation is required") unless confirmation.to_s == @confirmations.fetch(:replica)
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
      progress&.call("stage" => "copy", "message" => "Copying missing #{@profile_label} snapshots to Crucible…")
      copied = replica_restic(
        password, "copy", "--from-repo", @repository, "--tag", @snapshot_tag,
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
        "profile_id" => @profile_id,
        "snapshot_tag" => @snapshot_tag,
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
        "expected_digest" => digest(confirmation_scope(scope)), "confirmation_phrase" => @confirmations.fetch(:backup),
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
      return awaiting("exact backup confirmation is required") unless confirmation.to_s == @confirmations.fetch(:backup)
      operation_lock = acquire_operation_lock
      return blocked("another backup administration operation is already active") unless operation_lock
      preview = backup_preview(password: password)
      return preview unless preview["ok"]
      return blocked("backup preview digest is stale or invalid") unless secure_equal?(expected_digest, preview.dig("data", "expected_digest"))

      progress&.call("stage" => "capture", "message" => "Capturing the approved #{@profile_label} sources…")
      result = restic(password, "backup", "--json", "--quiet", "--files-from", @sources_path, "--exclude-file", @excludes_path, "--tag", @snapshot_tag, "--host", Socket.gethostname, timeout: BACKUP_TIMEOUT, output: 2 * 1024 * 1024, capture_mode: :complete_line_tail)
      raise "restic backup failed#{restic_failure_suffix(result)}" unless result.success?
      summary = json_lines(result.stdout).reverse.find { |item| item["message_type"] == "summary" }
      snapshot_id = summary.to_h["snapshot_id"].to_s
      unless snapshot_id.match?(SNAPSHOT_ID)
        receipt = write_receipt("backup_indeterminate", {
          "process_state" => "complete",
          "snapshot_state" => "indeterminate_requires_reconciliation",
          "output_truncated" => result.truncated == true,
          "verification" => "not_attempted"
        })
        return failed(
          "backup process completed but snapshot evidence requires reconciliation",
          receipt.merge("reconciliation_required" => true),
          "backup_snapshot_indeterminate_requires_reconciliation"
        )
      end

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

    def snapshot_evidence_reconciliation_preview(password:)
      raise ArgumentError, "snapshot evidence reconciliation is available only for the Operator profile" unless @profile_id == "operator"
      password = validate_password(password)
      preflight = backup_preflight(password)
      verify_repository!(password)
      checkpoint = retention_checkpoint!
      candidates = unrecorded_snapshot_candidates(password, checkpoint)
      scope = {
        "operation" => "operator_snapshot_evidence_reconciliation",
        "profile_id" => @profile_id,
        "repository_id" => repository_fingerprint,
        "snapshot_tag" => @snapshot_tag,
        "candidate_snapshot_ids" => candidates.map { |item| item.fetch("id") },
        "candidate_snapshot_times" => candidates.map { |item| item.fetch("time") },
        "candidate_count" => candidates.length,
        "source_manifest_digest" => Digest::SHA256.file(@sources_path).hexdigest,
        "exclusion_manifest_digest" => Digest::SHA256.file(@excludes_path).hexdigest,
        "ledger_digest" => checkpoint["ledger_digest"],
        "source_count" => preflight.fetch("sources").length,
        "evidence_only" => true,
        "snapshot_creation" => false,
        "replication" => false,
        "retention_execution" => false,
        "automatic_retry" => false
      }
      complete("unrecorded Operator snapshot evidence prepared for exact reconciliation", scope.merge(
        "expected_digest" => digest(scope),
        "confirmation_phrase" => OPERATOR_SNAPSHOT_EVIDENCE_RECONCILIATION_CONFIRMATION,
        "password_retained" => false
      ))
    rescue ArgumentError => error
      awaiting(error.message)
    rescue StandardError => error
      blocked("snapshot evidence reconciliation preview failed safely: #{safe_error(error)}")
    ensure
      password&.replace("\0" * password.bytesize) if password.is_a?(String) && !password.frozen?
    end

    def snapshot_evidence_reconciliation_execute(password:, confirmation:, expected_digest:, progress: nil)
      password = validate_password(password)
      return awaiting("exact Operator snapshot evidence reconciliation confirmation is required") unless confirmation.to_s == OPERATOR_SNAPSHOT_EVIDENCE_RECONCILIATION_CONFIRMATION
      operation_lock = acquire_operation_lock
      return blocked("another backup administration operation is already active") unless operation_lock

      reviewed = snapshot_evidence_reconciliation_preview(password: password)
      return reviewed unless reviewed["ok"]
      reviewed_scope = reviewed.fetch("data").reject { |key, _value| %w[expected_digest confirmation_phrase password_retained].include?(key) }
      return blocked("snapshot evidence reconciliation preview digest is stale or invalid") unless secure_equal?(expected_digest, digest(reviewed_scope))

      candidate_ids = reviewed_scope.fetch("candidate_snapshot_ids")
      candidate_times = reviewed_scope.fetch("candidate_snapshot_times")
      recorded_ids = []
      return complete("Operator snapshot evidence is already reconciled", {
        "candidate_count" => 0, "recorded_snapshot_ids" => [], "password_retained" => false
      }) if candidate_ids.empty?

      verify_repository!(password)
      base_time = @clock.call.utc
      candidate_ids.zip(candidate_times).each_with_index do |(snapshot_id, _snapshot_time), index|
        progress&.call("stage" => "reconcile", "message" => "Verifying Operator snapshot evidence #{index + 1} of #{candidate_ids.length}…")
        manifest_path = File.join(@manifest_root, "#{snapshot_id}.json")
        manifest = if File.exist?(manifest_path) || File.symlink?(manifest_path)
          load_snapshot_manifest(manifest_path, snapshot_id)
        else
          build_snapshot_manifest(password, snapshot_id, verified_at: (base_time + index).iso8601)
        end
        FileUtils.mkdir_p(@manifest_root, mode: 0o700)
        atomic_json(manifest_path, manifest) unless File.exist?(manifest_path)
        observation = @ledger.observe_preview(manifest: manifest)
        raise observation["reason"] unless observation["ok"]
        recorded = @ledger.observe_execute(
          manifest: manifest,
          confirmation: BackupRetentionLedger::OBSERVE_CONFIRMATION,
          expected_digest: observation.dig("data", "expected_digest")
        )
        raise recorded["reason"] unless recorded["ok"]
        recorded_ids << snapshot_id
      end
      receipt = write_receipt("snapshot_evidence_reconciliation", {
        "candidate_count" => candidate_ids.length,
        "recorded_snapshot_ids" => recorded_ids,
        "remaining_snapshot_ids" => [],
        "ledger_digest" => retention_checkpoint!.fetch("ledger_digest"),
        "verification" => "passed",
        "deletion" => false,
        "replication" => false
      })
      complete("Operator snapshot evidence reconciled", receipt.merge(
        "recorded_snapshot_ids" => recorded_ids,
        "password_retained" => false
      ), "operator_snapshot_evidence_reconciled")
    rescue ArgumentError => error
      awaiting(error.message)
    rescue StandardError => error
      remaining_ids = defined?(candidate_ids) ? candidate_ids - Array(recorded_ids) : []
      receipt = write_receipt("snapshot_evidence_reconciliation", {
        "candidate_count" => defined?(candidate_ids) ? candidate_ids.length : 0,
        "recorded_snapshot_ids" => Array(recorded_ids),
        "remaining_snapshot_ids" => remaining_ids,
        "verification" => "incomplete",
        "deletion" => false,
        "replication" => false,
        "reason" => safe_error(error)
      }) rescue {}
      failed("snapshot evidence reconciliation failed safely: #{safe_error(error)}", receipt.merge(
        "recorded_snapshot_ids" => Array(recorded_ids),
        "remaining_snapshot_ids" => remaining_ids,
        "review_required" => true
      ), Array(recorded_ids).empty? ? "none" : "operator_snapshot_evidence_partially_reconciled")
    ensure
      release_operation_lock(operation_lock)
      password&.replace("\0" * password.bytesize) if password.is_a?(String) && !password.frozen?
    end

    def drs_preview(password:)
      password = validate_password(password)
      local = backup_preview(password: password)
      return local unless local["ok"]

      replica = replica_preview(password: password)
      scope = {
        "operation" => "backup_drs_transaction",
        "profile_id" => @profile_id,
        "snapshot_tag" => @snapshot_tag,
        "local_capture" => component_scope(local),
        "replica_preflight" => component_scope(replica),
        "stage_order" => %w[local_capture local_verify deletion_ledger replica_copy replica_verify],
        "new_snapshot_lineage_required_on_replica" => true,
        "local_success_survives_replica_failure" => true,
        "automatic_retention" => false,
        "remote_deletion" => false,
        "automatic_retry" => false,
        "scheduled" => false,
        "password_retained" => false
      }
      complete("exact supervised DRS transaction prepared", scope.merge(
        "expected_digest" => digest(confirmation_scope(scope)),
        "confirmation_phrase" => @confirmations.fetch(:drs)
      ))
    rescue ArgumentError => error
      awaiting(error.message)
    rescue StandardError => error
      blocked("DRS preview failed safely: #{safe_error(error)}")
    ensure
      password&.replace("\0" * password.bytesize) if password.is_a?(String) && !password.frozen?
    end

    def drs_execute(password:, confirmation:, expected_digest:, progress: nil)
      password = validate_password(password)
      return awaiting("exact DRS confirmation is required") unless confirmation.to_s == @confirmations.fetch(:drs)

      reviewed = drs_preview(password: password)
      return reviewed unless reviewed["ok"]
      reviewed_scope = reviewed.fetch("data").reject { |key, _value| %w[expected_digest confirmation_phrase].include?(key) }
      return blocked("DRS preview digest is stale or invalid") unless secure_equal?(expected_digest, digest(confirmation_scope(reviewed_scope)))

      progress&.call("stage" => "local_preview", "message" => "Revalidating the exact local capture scope…")
      local_preview = backup_preview(password: password)
      unless local_preview["ok"]
        receipt = write_drs_receipt(
          state: "failed", local: component_result(local_preview), replica: {"state" => "not_attempted"},
          reason: local_preview["reason"], mutation: "none"
        )
        return failed("DRS local preflight failed safely: #{local_preview['reason']}", {"drs_receipt" => receipt})
      end

      progress&.call("stage" => "local_capture", "message" => "Creating and verifying the encrypted local recovery snapshot…")
      local = backup_execute(
        password: password,
        confirmation: local_preview.dig("data", "confirmation_phrase"),
        expected_digest: local_preview.dig("data", "expected_digest"),
        progress: progress
      )
      unless local["ok"]
        receipt = write_drs_receipt(
          state: "failed", local: component_result(local), replica: {"state" => "not_attempted"},
          reason: local["reason"], mutation: local.fetch("mutation", "none")
        )
        return failed("DRS local capture failed safely: #{local['reason']}", {"drs_receipt" => receipt}, local.fetch("mutation", "none"))
      end

      snapshot_id = local.dig("data", "snapshot_id").to_s
      raise "verified local capture did not return one snapshot ID" unless snapshot_id.match?(SNAPSHOT_ID)

      progress&.call("stage" => "replica_preview", "message" => "Binding the fresh local lineage to the exact Crucible copy…")
      replica_gate = replica_preview(password: password)
      unless replica_gate["ok"]
        receipt = write_drs_receipt(
          state: "partial", local: successful_local_component(local),
          replica: component_result(replica_gate), reason: replica_gate["reason"],
          mutation: "backup_snapshot_created_replica_incomplete"
        )
        return failed(
          "local backup verified but Crucible reconciliation failed safely: #{replica_gate['reason']}",
          {"snapshot_id" => snapshot_id, "drs_receipt" => receipt, "review_required" => true},
          "backup_snapshot_created_replica_incomplete"
        )
      end

      progress&.call("stage" => "replica_copy", "message" => "Copying and verifying missing lineage on Crucible…")
      replica = replica_execute(
        password: password,
        confirmation: replica_gate.dig("data", "confirmation_phrase"),
        expected_digest: replica_gate.dig("data", "expected_digest"),
        progress: progress
      )
      unless replica["ok"]
        receipt = write_drs_receipt(
          state: "partial", local: successful_local_component(local),
          replica: component_result(replica), reason: replica["reason"],
          mutation: "backup_snapshot_created_replica_incomplete"
        )
        return failed(
          "local backup verified but Crucible reconciliation failed safely: #{replica['reason']}",
          {"snapshot_id" => snapshot_id, "drs_receipt" => receipt, "review_required" => true},
          "backup_snapshot_created_replica_incomplete"
        )
      end

      lineage = Array(replica.dig("data", "destination_snapshot_lineage_ids"))
      raise "Crucible verification omitted the newly captured snapshot lineage" unless lineage.include?(snapshot_id)

      receipt = write_drs_receipt(
        state: "complete",
        local: successful_local_component(local),
        replica: successful_replica_component(replica),
        reason: "local snapshot and exact Crucible lineage verified",
        mutation: "backup_drs_verified"
      )
      raise "DRS parent receipt could not be recorded" unless receipt

      progress&.call("stage" => "complete", "message" => "Local and Crucible recovery lineage verified.")
      complete(
        "verified DRS transaction completed",
        {
          "snapshot_id" => snapshot_id,
          "target_snapshot_count" => replica.dig("data", "target_snapshot_count"),
          "destination_snapshot_lineage_ids" => lineage,
          "drs_receipt" => receipt,
          "automatic_retention" => false,
          "remote_deletion" => false,
          "scheduled" => false
        },
        "backup_drs_verified"
      )
    rescue ArgumentError => error
      awaiting(error.message)
    rescue StandardError => error
      failed("DRS transaction failed safely: #{safe_error(error)}")
    ensure
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
        "profile_id" => @profile_id,
        "snapshot_tag" => @snapshot_tag,
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
        "expected_digest" => digest(scope), "confirmation_phrase" => @confirmations.fetch(:retention),
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
      return awaiting("exact retention confirmation is required") unless confirmation.to_s == @confirmations.fetch(:retention)
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

    def restore_preview(password:, snapshot_id:, paths: [], target_root: nil, repository_source: "local")
      password = validate_password(password)
      id = snapshot_id.to_s
      raise ArgumentError, "snapshot ID is invalid" unless id.match?(SNAPSHOT_ID)
      snapshots = snapshot_inventory(password)
      raise ArgumentError, "snapshot was not found" unless snapshots.any? { |item| item["id"] == id }
      source = normalize_restore_repository_source(repository_source)
      recovery_snapshot = restore_snapshot_context(password, source_snapshot_id: id, repository_source: source)
      includes = normalize_restore_paths(paths)
      inventory = recovery_snapshot.fetch("inventory")
      missing = includes.reject { |path| inventory.any? { |candidate| candidate == path || candidate.start_with?("#{path}/") } }
      raise ArgumentError, "restore path is absent from the snapshot" unless missing.empty?
      target = restore_target_scope(target_root)
      rehearsal = includes.empty? && target.fetch("mode") == "selected_empty_directory"
      source_roots = if rehearsal
        recovery_snapshot["source_roots"] || snapshot_manifest_source_roots(id, inventory)
      else
        []
      end
      scope = {
        "operation" => "backup_staged_restore",
        "profile_id" => @profile_id,
        "snapshot_tag" => @snapshot_tag,
        "repository_source" => source,
        "repository_fingerprint" => recovery_snapshot.fetch("repository_fingerprint"),
        "source_snapshot_id" => id,
        "snapshot_id" => recovery_snapshot.fetch("restore_snapshot_id"),
        "includes" => includes,
        "scope" => includes.empty? ? "full_snapshot" : "selected_paths",
        "target" => target,
        "target_root" => target.fetch("display_path"),
        "source_root_count" => source_roots.length,
        "full_recovery_rehearsal" => rehearsal,
        "verify_restored_files" => true,
        "live_tree_mutation" => false,
        "automatic_retry" => false
      }
      complete("exact staged restore prepared", scope.merge(
        "expected_digest" => digest(scope), "confirmation_phrase" => @confirmations.fetch(:restore),
        "password_retained" => false
      ))
    rescue ArgumentError => error
      awaiting(error.message)
    rescue StandardError => error
      blocked("restore preview failed safely: #{safe_error(error)}")
    ensure
      password&.replace("\0" * password.bytesize) if password.is_a?(String) && !password.frozen?
    end

    def restore_execute(password:, snapshot_id:, paths: [], target_root: nil, repository_source: "local", confirmation:, expected_digest:, progress: nil)
      password = validate_password(password)
      return awaiting("exact staged-restore confirmation is required") unless confirmation.to_s == @confirmations.fetch(:restore)
      operation_lock = acquire_operation_lock
      return blocked("another backup administration operation is already active") unless operation_lock
      preview = restore_preview(password: password, snapshot_id: snapshot_id, paths: paths, target_root: target_root, repository_source: repository_source)
      return preview unless preview["ok"]
      return blocked("restore preview digest is stale or invalid") unless secure_equal?(expected_digest, preview.dig("data", "expected_digest"))
      target_scope = preview.dig("data", "target")
      if target_scope.fetch("mode") == "managed_private_staging"
        restore_id = "restore_#{@id_generator.call}"
        raise "restore ID is invalid" unless restore_id.match?(/\Arestore_[a-f0-9]{16}\z/)
        target = File.join(@restore_root, restore_id)
        FileUtils.mkdir_p(@restore_root, mode: 0o700)
        raise "restore target already exists" if File.exist?(target) || File.symlink?(target)
        FileUtils.mkdir(target, mode: 0o700)
      else
        restore_id = "rehearsal_#{@id_generator.call}"
        raise "rehearsal ID is invalid" unless restore_id.match?(/\Arehearsal_[a-f0-9]{16}\z/)
        target = target_scope.fetch("path")
        current_target = restore_target_scope(target)
        raise "selected restore target changed after review" unless current_target == target_scope
      end
      args = ["restore", preview.dig("data", "snapshot_id"), "--target", target, "--verify"]
      preview.dig("data", "includes").each { |path| args.concat(["--include", path]) }
      progress&.call("stage" => "restore", "message" => "Restoring the approved snapshot into isolated staging…")
      result = if preview.dig("data", "repository_source") == "crucible_replica"
        replica_restic(password, *args, timeout: RESTORE_TIMEOUT, output: 2 * 1024 * 1024)
      else
        restic(password, *args, timeout: RESTORE_TIMEOUT, output: 2 * 1024 * 1024)
      end
      ownership_normalized = !result.success? && restic_ancestor_ownership_only_failure?(
        result, target: target, includes: preview.dig("data", "includes")
      )
      raise "restic restore failed#{restic_failure_suffix(result)}" unless result.success? || ownership_normalized
      evidence = staged_inventory(target)
      rehearsal = if preview.dig("data", "full_recovery_rehearsal")
        recovery_snapshot = restore_snapshot_context(
          password,
          source_snapshot_id: preview.dig("data", "source_snapshot_id"),
          repository_source: preview.dig("data", "repository_source")
        )
        source_roots = recovery_snapshot["source_roots"] || snapshot_manifest_source_roots(
          preview.dig("data", "source_snapshot_id"), recovery_snapshot.fetch("inventory")
        )
        recovery_rehearsal_evidence(target, source_roots)
      else
        {"mode" => preview.dig("data", "scope"), "status" => "staged_restore_only"}
      end
      receipt = write_receipt("restore", {
        "restore_id" => restore_id,
        "snapshot_id" => preview.dig("data", "snapshot_id"),
        "source_snapshot_id" => preview.dig("data", "source_snapshot_id"),
        "repository_source" => preview.dig("data", "repository_source"),
        "includes" => preview.dig("data", "includes"),
        "staged_path" => display_path(target),
        "file_count" => evidence.fetch("file_count"),
        "total_bytes" => evidence.fetch("total_bytes"),
        "inventory_digest" => evidence.fetch("inventory_digest"),
        "target_mode" => target_scope.fetch("mode"),
        "target_identity" => target_scope["identity"],
        "recovery_rehearsal" => rehearsal,
        "content_verification" => "passed",
        "ownership" => ownership_normalized ? "normalized_to_current_user_for_unprivileged_staging" : "restored_without_error",
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

    def confirmation_scope(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, item), scoped|
          scoped[key] = confirmation_scope(item) unless key == "estimated_bytes"
        end
      when Array
        value.map { |item| confirmation_scope(item) }
      else
        value
      end
    end

    def component_scope(outcome)
      {
        "lifecycle_state" => outcome.fetch("lifecycle_state"),
        "reason" => outcome.fetch("reason", ""),
        "data" => outcome.fetch("data", {}).reject { |key, _value| key == "confirmation_phrase" }
      }
    end

    def component_result(outcome)
      {
        "state" => outcome["ok"] ? "complete" : outcome.fetch("lifecycle_state", "failed"),
        "reason" => outcome.fetch("reason", "").to_s.slice(0, 240),
        "mutation" => outcome.fetch("mutation", "none")
      }
    end

    def successful_local_component(outcome)
      {
        "state" => "complete",
        "snapshot_id" => outcome.dig("data", "snapshot_id"),
        "receipt_id" => outcome.dig("data", "receipt_id"),
        "verification" => outcome.dig("data", "verification")
      }
    end

    def successful_replica_component(outcome)
      {
        "state" => "complete",
        "receipt_id" => outcome.dig("data", "receipt_id"),
        "target_snapshot_count" => outcome.dig("data", "target_snapshot_count"),
        "destination_snapshot_lineage_ids" => Array(outcome.dig("data", "destination_snapshot_lineage_ids"))
      }
    end

    def write_drs_receipt(state:, local:, replica:, reason:, mutation:)
      receipt = write_receipt("drs", {
        "state" => state,
        "local" => local,
        "replica" => replica,
        "reason" => reason.to_s.slice(0, 240),
        "mutation" => mutation,
        "automatic_retention" => false,
        "remote_deletion" => false,
        "automatic_retry" => false,
        "scheduled" => false,
        "password_retained" => false
      })
      {
        "receipt_id" => receipt.fetch("receipt_id"),
        "state" => state,
        "local" => {"state" => local["state"]},
        "replica" => {"state" => replica["state"]}
      }
    rescue StandardError
      nil
    end

    def latest_drs_status
      candidates = Dir.glob(File.join(@receipt_root, "drs_*.json")).select { |path| regular_file?(path) && File.size(path) <= 128 * 1024 }
      path = candidates.max_by { |candidate| [File.mtime(candidate).to_f, candidate] }
      return {"state" => "not_run", "scheduled" => false, "password_retained" => false} unless path

      receipt = JSON.parse(File.binread(path, 128 * 1024))
      raise "DRS receipt schema is invalid" unless receipt["schema_version"] == "soul.backup_receipt.v1" && receipt["operation"] == "drs"
      receipt_profile = receipt.fetch("profile_id", "soul")
      raise "DRS receipt profile is invalid" unless receipt_profile == @profile_id
      {
        "state" => receipt.fetch("state", "unknown"),
        "completed_at" => receipt["completed_at"],
        "receipt_id" => receipt["receipt_id"],
        "local_state" => receipt.dig("local", "state"),
        "replica_state" => receipt.dig("replica", "state"),
        "scheduled" => false,
        "password_retained" => false
      }
    rescue JSON::ParserError, KeyError, SystemCallError
      {"state" => "invalid", "scheduled" => false, "password_retained" => false}
    end

    def manifest_reconciliation_summary
      scope = manifest_reconciliation_scope
      {
        "state" => scope.fetch("source_additions").empty? && scope.fetch("exclusion_additions").empty? ? "current" : "review_required",
        "source_addition_count" => scope.fetch("source_additions").length,
        "exclusion_addition_count" => scope.fetch("exclusion_additions").length,
        "snapshot_verification_required" => !scope.fetch("source_additions").empty?
      }
    rescue StandardError => error
      { "state" => "unavailable", "reason" => safe_error(error), "snapshot_verification_required" => false }
    end

    def manifest_reconciliation_scope
      current_sources = safe_manifest_lines(@sources_path)
      current_exclusions = safe_manifest_lines(@excludes_path)
      policy_sources = @manifest_policy.sources
      policy_exclusions = @manifest_policy.exclusions
      {
        "operation" => "backup_manifest_reconciliation",
        "profile_id" => @profile_id,
        "snapshot_tag" => @snapshot_tag,
        "source_manifest_digest" => Digest::SHA256.file(@sources_path).hexdigest,
        "exclusion_manifest_digest" => Digest::SHA256.file(@excludes_path).hexdigest,
        "source_additions" => policy_sources - current_sources,
        "exclusion_additions" => policy_exclusions - current_exclusions,
        "source_removals" => [],
        "exclusion_removals" => [],
        "replace_existing" => false,
        "restic_operation" => false,
        "password_required" => false,
        "snapshot_verification_required" => true,
        "automatic_retry" => false
      }
    end

    def manifest_reconciliation_view(scope)
      {
        "operation" => scope.fetch("operation"),
        "profile_id" => @profile_id,
        "snapshot_tag" => @snapshot_tag,
        "source_additions" => scope.fetch("source_additions").map { |path| display_path(path) },
        "exclusion_additions" => scope.fetch("exclusion_additions").map { |pattern| display_pattern(pattern) },
        "source_removals" => [],
        "exclusion_removals" => [],
        "changes_required" => !scope.fetch("source_additions").empty? || !scope.fetch("exclusion_additions").empty?,
        "replace_existing" => false,
        "restic_operation" => false,
        "password_required" => false,
        "snapshot_verification_required" => true,
        "automatic_retry" => false
      }
    end

    def manifest_body(path)
      raise ArgumentError, "backup manifest is unavailable: #{display_path(path)}" unless regular_file?(path)
      raise ArgumentError, "backup manifest exceeds size limit" if File.size(path) > 256 * 1024
      raise ArgumentError, "backup manifest must be owner-only" unless (File.stat(path).mode & 0o077).zero?
      File.binread(path)
    end

    def append_manifest_lines(body, additions)
      return body if additions.empty?
      prefix = body.empty? || body.end_with?("\n") ? body : "#{body}\n"
      prefix + additions.join("\n") + "\n"
    end

    def write_manifest_pair(source_body, exclusion_body, source_before, exclusion_before)
      source_written = false
      atomic_text(@sources_path, source_body)
      source_written = true
      atomic_text(@excludes_path, exclusion_body)
    rescue StandardError
      atomic_text(@sources_path, source_before) if source_written
      atomic_text(@excludes_path, exclusion_before) if regular_file?(@excludes_path) && File.binread(@excludes_path) != exclusion_before
      raise
    end

    def atomic_text(path, body)
      temporary = "#{path}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
      begin
        File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
          file.write(body)
          file.flush
          file.fsync
        end
        File.rename(temporary, path)
      ensure
        FileUtils.rm_f(temporary)
      end
    end

    def write_manifest_reconciliation_receipt(scope)
      FileUtils.mkdir_p(@receipt_root, mode: 0o700)
      timestamp = @clock.call.utc
      receipt = {
        "schema_version" => "soul.backup_manifest_reconciliation_receipt.v1",
        "receipt_id" => "manifest_reconciliation_#{timestamp.strftime('%Y%m%dT%H%M%SZ')}_#{@id_generator.call}",
        "operation" => "manifest_reconciliation",
        "profile_id" => @profile_id,
        "snapshot_tag" => @snapshot_tag,
        "completed_at" => timestamp.iso8601,
        "source_addition_count" => scope.fetch("source_additions").length,
        "exclusion_addition_count" => scope.fetch("exclusion_additions").length,
        "source_additions_digest" => digest(scope.fetch("source_additions")),
        "exclusion_additions_digest" => digest(scope.fetch("exclusion_additions")),
        "snapshot_verification_required" => true,
        "restic_operation" => false
      }
      atomic_json(File.join(@receipt_root, "#{receipt.fetch("receipt_id")}.json"), receipt)
      receipt
    end

    def display_pattern(pattern)
      pattern.to_s.gsub(@root, "[PROJECT_ROOT]").gsub(@home, "~")
    end

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
      raise ArgumentError, "local backup repository contains no #{@profile_label} snapshots" if source.empty?
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
      result = replica_restic(password, "snapshots", "--json", "--tag", @snapshot_tag, timeout: 60, output: 1024 * 1024)
      return { "state" => "uninitialized", "ids" => [], "lineage_ids" => [], "records" => [], "repository_id" => nil } if result.exit_status == 10
      raise ArgumentError, "Crucible repository password was rejected" if result.exit_status == 12
      raise "Crucible snapshot inventory failed#{restic_failure_suffix(result)}" unless result.success?
      snapshots = JSON.parse(result.stdout)
      raise "Crucible snapshot inventory is invalid" unless snapshots.is_a?(Array) && snapshots.length <= MAX_SNAPSHOTS
      records = snapshots.map do |item|
        identity = snapshot_identity(item, "Crucible")
        roots = Array(item["paths"])
        unless roots.any? && roots.length <= OPERATOR_MAX_SOURCE_ROOTS && roots.all? { |root| root.is_a?(String) && root == File.expand_path(root) }
          raise "Crucible snapshot inventory contains invalid source roots"
        end
        identity.merge("source_roots" => roots.uniq.sort)
      end
      ids = records.map { |item| item.fetch("id") }
      raise "Crucible snapshot inventory contains an invalid ID" unless ids.all? { |id| id.match?(SNAPSHOT_ID) } && ids.uniq.length == ids.length
      config = replica_restic(password, "cat", "config", timeout: 60, output: 1024 * 1024)
      raise "Crucible repository identity failed#{restic_failure_suffix(config)}" unless config.success?
      repository_id = JSON.parse(config.stdout).fetch("id").to_s
      raise "Crucible repository identity is invalid" unless repository_id.match?(SNAPSHOT_ID)
      {
        "state" => "ready",
        "ids" => ids.sort,
        "lineage_ids" => records.map { |item| item.fetch("lineage_id") }.uniq.sort,
        "repository_id" => repository_id,
        "records" => records
      }
    rescue JSON::ParserError, KeyError
      raise "Crucible repository inventory is invalid"
    end

    def replica_restic(password, *args, timeout:, output: 256 * 1024, extra_env: {}, capture_mode: :prefix, max_records: 100_000, &record_transform)
      @runner.run(
        "restic", "-o", "sftp.command=ssh -F #{@replica_ssh_config} #{@replica_ssh_alias} -s sftp", "--repo", @replica_repository, *args,
        timeout_seconds: timeout, max_output_bytes: output,
        capture_mode: capture_mode,
        max_records: max_records,
        env: { "RESTIC_PASSWORD" => password }.merge(extra_env),
        &record_transform
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
      result = restic(password, "snapshots", "--json", "--tag", @snapshot_tag, timeout: 30, output: 1024 * 1024)
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

    def build_snapshot_manifest(password, snapshot_id, verified_at: nil)
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
        "verified_at" => verified_at || @clock.call.utc.iso8601,
        "repository_id" => repository_fingerprint,
        "source_roots" => roots.sort,
        "paths" => paths,
        "verification" => { "check_mode" => "metadata", "result" => "passed" }
      }
    end

    def snapshot_paths(password, snapshot_id)
      result = restic(
        password, "ls", "--json", snapshot_id,
        timeout: CHECK_TIMEOUT, output: 24 * 1024 * 1024,
        capture_mode: :json_lines, max_records: MAX_INVENTORY_PATHS
      ) { |item| item["path"].to_s if item["struct_type"] == "node" }
      raise "snapshot path inventory failed#{restic_failure_suffix(result)}" unless result.success?
      raise "snapshot path inventory is too large" if result.truncated
      paths = result.records || json_lines(result.stdout).filter_map { |item| item["path"].to_s if item["struct_type"] == "node" }
      paths = paths.map { |path| File.expand_path(path) }.uniq.sort
      raise "snapshot path inventory is empty or too large" if paths.empty? || paths.length > MAX_INVENTORY_PATHS
      paths
    end

    def replica_snapshot_paths(password, snapshot_id)
      result = replica_restic(
        password, "ls", "--json", snapshot_id,
        timeout: CHECK_TIMEOUT, output: 24 * 1024 * 1024,
        capture_mode: :json_lines, max_records: MAX_INVENTORY_PATHS
      ) { |item| item["path"].to_s if item["struct_type"] == "node" }
      raise "Crucible snapshot path inventory failed#{restic_failure_suffix(result)}" unless result.success?
      raise "Crucible snapshot path inventory is too large" if result.truncated
      paths = result.records || json_lines(result.stdout).filter_map { |item| item["path"].to_s if item["struct_type"] == "node" }
      paths = paths.map { |path| File.expand_path(path) }.uniq.sort
      raise "Crucible snapshot path inventory is empty or too large" if paths.empty? || paths.length > MAX_INVENTORY_PATHS
      paths
    end

    def verify_repository!(password)
      result = restic(password, "check", timeout: CHECK_TIMEOUT, output: 1024 * 1024)
      raise "repository verification failed#{restic_failure_suffix(result)}" unless result.success?
      true
    end

    def restic(password, *args, timeout:, output: 256 * 1024, capture_mode: :prefix, max_records: 100_000, &record_transform)
      @runner.run(
        "restic", "--repo", @repository, *args,
        timeout_seconds: timeout, max_output_bytes: output,
        capture_mode: capture_mode,
        max_records: max_records,
        env: { "RESTIC_PASSWORD" => password },
        &record_transform
      )
    end

    def retention_checkpoint!
      checkpoint = @ledger.checkpoint
      raise checkpoint["reason"] unless checkpoint["ok"]
      checkpoint.fetch("data")
    end

    def unrecorded_snapshot_candidates(password, checkpoint)
      snapshots = snapshot_inventory(password).sort_by { |item| [item.fetch("time"), item.fetch("id")] }
      checkpoint_id = checkpoint["snapshot_id"].to_s
      candidates = if checkpoint_id.empty?
        snapshots
      else
        checkpoint_index = snapshots.index { |item| item.fetch("id") == checkpoint_id }
        raise "retention checkpoint snapshot is absent from the repository inventory" unless checkpoint_index
        snapshots.drop(checkpoint_index + 1)
      end
      raise "snapshot evidence reconciliation exceeds the #{MAX_SNAPSHOTS}-snapshot bound" if candidates.length > MAX_SNAPSHOTS
      candidates
    rescue ArgumentError
      raise "snapshot evidence reconciliation inventory is invalid"
    end

    def regular_snapshot_manifest?(path)
      return false unless File.exist?(path) || File.symlink?(path)
      stat = File.lstat(path)
      stat.file? && !stat.symlink? && stat.size.between?(1, BackupRetentionLedger::MAX_LEDGER_BYTES)
    rescue SystemCallError
      false
    end

    def load_snapshot_manifest(path, expected_snapshot_id)
      raise "snapshot manifest path is unsafe" unless regular_snapshot_manifest?(path)
      manifest = JSON.parse(File.binread(path, BackupRetentionLedger::MAX_LEDGER_BYTES))
      raise "snapshot manifest identity is invalid" unless manifest["snapshot_id"] == expected_snapshot_id
      manifest
    rescue JSON::ParserError, SystemCallError
      raise "snapshot manifest is invalid"
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

    def normalize_restore_repository_source(value)
      source = value.to_s
      raise ArgumentError, "restore repository source must be local or crucible_replica" unless %w[local crucible_replica].include?(source)
      source
    end

    def restore_snapshot_context(password, source_snapshot_id:, repository_source:)
      if repository_source == "local"
        return {
          "restore_snapshot_id" => source_snapshot_id,
          "repository_fingerprint" => repository_fingerprint,
          "inventory" => snapshot_paths(password, source_snapshot_id)
        }
      end

      validate_replica_configuration!
      target = replica_target_status
      raise ArgumentError, "Crucible backup target identity is invalid" unless target["ready"]
      remote = replica_inventory(password)
      identity = remote.fetch("records").find { |item| item.fetch("lineage_id") == source_snapshot_id }
      raise ArgumentError, "selected local snapshot lineage is absent from Crucible" unless identity
      {
        "restore_snapshot_id" => identity.fetch("id"),
        "repository_fingerprint" => remote.fetch("repository_id"),
        "inventory" => replica_snapshot_paths(password, identity.fetch("id")),
        "source_roots" => identity.fetch("source_roots")
      }
    end

    def restore_target_scope(value)
      raw = value.to_s.strip
      if raw.empty?
        return {
          "mode" => "managed_private_staging",
          "path" => @restore_root,
          "display_path" => display_path(@restore_root),
          "empty_required" => false
        }
      end

      raise ArgumentError, "restore target exceeds size limit" if raw.bytesize > 4096 || raw.include?("\0")
      path = File.expand_path(raw)
      raise ArgumentError, "restore target must be an exact normalized absolute path" unless raw == path && path.start_with?("/")
      raise ArgumentError, "restore target must already exist" unless File.exist?(path)
      stat = File.lstat(path)
      raise ArgumentError, "restore target must be a regular directory" unless stat.directory? && !stat.symlink?
      raise ArgumentError, "restore target path must not traverse a symlink" unless File.realpath(path) == path
      raise ArgumentError, "restore target must be owned by the current operator" unless stat.uid == Process.uid
      raise ArgumentError, "restore target must be owner-only" unless (stat.mode & 0o077).zero?
      raise ArgumentError, "restore target must be readable, writable, and searchable" unless File.readable?(path) && File.writable?(path) && File.executable?(path)

      protected = [@root, @state_root, @mount, @repository].uniq
      if path == "/" || path == @home || protected.any? { |item| within?(path, item) || within?(item, path) }
        raise ArgumentError, "restore target overlaps protected live or repository state"
      end
      sources = safe_manifest_lines(@sources_path)
      if sources.any? { |source| within?(path, source) || within?(source, path) }
        raise ArgumentError, "restore target overlaps a configured backup source"
      end
      raise ArgumentError, "restore target must be empty" unless Dir.children(path).empty?

      {
        "mode" => "selected_empty_directory",
        "path" => path,
        "display_path" => display_path(path),
        "empty_required" => true,
        "identity" => {
          "device" => stat.dev,
          "inode" => stat.ino,
          "uid" => stat.uid,
          "mode" => format("%04o", stat.mode & 0o7777)
        }
      }
    rescue Errno::ENOENT, Errno::EACCES, Errno::ENOTDIR, Errno::ELOOP => error
      raise ArgumentError, "restore target is unavailable: #{error.class.name.split('::').last}"
    end

    def snapshot_manifest_source_roots(snapshot_id, inventory)
      path = File.join(@manifest_root, "#{snapshot_id}.json")
      raise "verified snapshot manifest is unavailable for recovery rehearsal" unless regular_file?(path) && File.size(path) <= 64 * 1024 * 1024
      manifest = JSON.parse(File.read(path))
      raise "verified snapshot manifest does not match the selected snapshot" unless manifest["snapshot_id"] == snapshot_id
      raise "verified snapshot manifest repository identity changed" unless manifest["repository_id"] == repository_fingerprint
      roots = Array(manifest["source_roots"])
      unless roots.any? && roots.length <= OPERATOR_MAX_SOURCE_ROOTS && roots.all? { |root| root.is_a?(String) && root == File.expand_path(root) }
        raise "verified snapshot manifest source roots are invalid"
      end
      missing = roots.reject { |root| inventory.include?(root) || inventory.any? { |item| item.start_with?("#{root}/") } }
      raise "verified snapshot inventory no longer covers every source root" unless missing.empty?
      roots.sort
    rescue JSON::ParserError
      raise "verified snapshot manifest is invalid"
    end

    def recovery_rehearsal_evidence(target, source_roots)
      missing = source_roots.reject do |root|
        restored = File.join(target, root.delete_prefix("/"))
        File.exist?(restored) && !File.symlink?(restored)
      end
      raise "full recovery rehearsal omitted one or more documented source roots" unless missing.empty?
      {
        "mode" => "full_snapshot",
        "status" => "verified",
        "source_root_count" => source_roots.length,
        "restored_source_root_count" => source_roots.length,
        "missing_source_root_count" => 0,
        "coverage_classes" => recovery_coverage_classes(source_roots),
        "live_promotion" => false
      }
    end

    def recovery_coverage_classes(source_roots)
      patterns = {
        "private_state" => [File.join(@root, "Soul", "private")],
        "conversation_state" => [File.join(@root, "Soul", "runtime", "chats"), File.join(@root, "Soul", "chats")],
        "creative_archives" => [File.join(@root, "Soul", "music"), File.join(@root, "Soul", "visual"), File.join(@home, "Music", "soul-music")],
        "knowledge_vault" => [File.join(@home, "Knowledge", "soul-vault")],
        "service_configuration" => [File.join(@home, ".config", "soul"), File.join(@home, ".config", "systemd", "user"), File.join(@home, ".local", "share", "caddy")]
      }
      patterns.map do |id, candidates|
        count = source_roots.count do |root|
          candidates.any? { |candidate| within?(root, candidate) || within?(candidate, root) }
        end
        {"id" => id, "covered" => count.positive?, "source_root_count" => count}
      end
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

    def restic_ancestor_ownership_only_failure?(result, target:, includes:)
      return false unless result.exit_status == 1 && !result.truncated
      selected = Array(includes)
      return false if selected.empty? || selected.any? { |path| !within?(path, @home) }

      lines = result.stderr.to_s.lines.map(&:strip).reject(&:empty?)
      fatal = lines.last.to_s.match(/\AFatal: There (?:was|were) (\d+) errors?\z/i)
      return false unless fatal
      ownership_errors = lines[0...-1]
      return false unless ownership_errors.length == Integer(fatal[1]) && !ownership_errors.empty?

      ownership_errors.all? do |line|
        match = line.match(/\Aignoring error for (.+): lchown (.+): invalid argument\z/)
        next false unless match
        ancestor = File.expand_path(match[1])
        staged = File.expand_path(match[2])
        expected_staged = File.join(target, ancestor.delete_prefix("/"))
        ancestor.start_with?("/") && staged == expected_staged &&
          selected.any? { |path| path.start_with?("#{ancestor}/") }
      end
    rescue ArgumentError
      false
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
        "profile_id" => @profile_id,
        "snapshot_tag" => @snapshot_tag,
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
      value = profile_environment("MAX_REPACK_SIZE", "4G").to_s
      raise ArgumentError, "backup max repack size is invalid" unless value.match?(/\A(?:[1-9]\d{0,3})(?:M|G)\z/)
      value
    end

    def acquire_operation_lock
      FileUtils.mkdir_p(@state_root, mode: 0o700)
      FileUtils.mkdir_p(File.dirname(@operation_lock_path), mode: 0o700)
      lock = File.open(@operation_lock_path, File::RDWR | File::CREAT, 0o600)
      return lock if lock.flock(File::LOCK_EX | File::LOCK_NB)
      lock.close
      nil
    end

    def validate_private_state_root!
      [
        File.join(@root, "Soul"),
        File.join(@root, "Soul", "private"),
        @state_root,
        File.dirname(@operation_lock_path)
      ].uniq.each do |path|
        raise ArgumentError, "backup state path must not traverse a symlink" if File.symlink?(path)
      end
      return unless File.exist?(@state_root)
      raise ArgumentError, "backup state root must be a directory" unless File.directory?(@state_root)
      raise ArgumentError, "backup state root must be owner-only" unless (File.stat(@state_root).mode & 0o077).zero?
    end

    def profile_environment(suffix, default)
      profile_key = "#{@environment_prefix}_#{suffix}"
      return @env.fetch(profile_key).to_s if @env.key?(profile_key)
      return @env.fetch("SOUL_BACKUP_#{suffix}").to_s if @profile_id == "operator" && @env.key?("SOUL_BACKUP_#{suffix}")

      default.to_s
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
      lines = result.stderr.to_s.lines.map(&:strip).reject(&:empty?)
      terminal = lines.last.to_s
      diagnostic = lines.reverse.find { |line| line != terminal && !line.match?(/\AFatal: There (?:was|were) \d+ errors?\z/i) }.to_s
      detail = [diagnostic, terminal].reject(&:empty?).uniq.join(" | ")
      detail = safe_error(StandardError.new(detail)) unless detail.empty?
      suffix = " (exit #{result.exit_status || 'unavailable'}"
      suffix += ": #{detail}" unless detail.empty?
      "#{suffix})"
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

    def failed(reason, data = {}, mutation = "none")
      { "ok" => false, "lifecycle_state" => "failed", "reason" => reason, "data" => data, "mutation" => mutation }
    end
  end
end
