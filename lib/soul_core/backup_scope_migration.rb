# frozen_string_literal: true

module SoulCore
  # Included in BackupAdministrationService to share its operation lock, private
  # paths and atomic writers. This route is deliberately absent from DRS runners.
  module BackupScopeMigration
    def scope_migration_preview(retirements:)
      context = scope_migration_context(retirements)
      complete("review exact unavailable roots and retained evidence before scope migration",
               context.fetch(:scope).merge("expected_digest" => digest(context.fetch(:scope)),
                                           "confirmation_phrase" => scope_migration_confirmation))
    rescue ArgumentError => error
      awaiting(error.message)
    rescue StandardError => error
      blocked("scope migration preview failed safely: #{safe_error(error)}")
    end

    def scope_migration_execute(retirements:, confirmation:, expected_digest:)
      return awaiting("exact scope migration confirmation is required") unless confirmation == scope_migration_confirmation
      operation_lock = acquire_operation_lock
      return blocked("another backup administration operation is already active") unless operation_lock
      context = scope_migration_context(retirements)
      scope = context.fetch(:scope)
      return blocked("scope migration preview digest is stale or invalid") unless secure_equal?(expected_digest, digest(scope))

      FileUtils.mkdir_p(@receipt_root, mode: 0o700)
      raise "scope receipt directory is unsafe" unless File.directory?(@receipt_root) && !File.symlink?(@receipt_root) && (File.stat(@receipt_root).mode & 0o077).zero?
      receipt_path = File.join(@receipt_root, "#{scope.fetch('receipt_id')}.json")
      recovery = File.join(@receipt_root, "#{scope.fetch('receipt_id')}.recovery")
      raise "scope migration attempt already exists; inspect retained evidence" if File.exist?(receipt_path) || File.symlink?(receipt_path) || File.exist?(recovery) || File.symlink?(recovery)
      Dir.mkdir(recovery, 0o700)
      %w[sources ledger exclusions].each do |name|
        path = {"sources" => @sources_path, "ledger" => @ledger_path, "exclusions" => @excludes_path}.fetch(name)
        body = File.binread(path)
        raise "scope input changed before capture" unless Digest::SHA256.hexdigest(body) == scope.fetch("#{name}_sha256")
        atomic_text(File.join(recovery, "#{name}.before"), body)
      end
      File.open(recovery, File::RDONLY) { |dir| dir.fsync }
      File.open(@receipt_root, File::RDONLY) { |dir| dir.fsync }
      receipt = scope.merge("schema_version" => "soul.backup_scope_migration_receipt.v1",
                            "state" => "prepared", "started_at" => @clock.call.utc.iso8601,
                            "expected_digest" => expected_digest, "recovery_directory" => recovery)
      # A crash from this point onward blocks backups and further migrations.
      # Before-images remain available for explicit reconciliation; never retry
      # or silently roll back across an uncertain concurrent state.
      atomic_json(scope_migration_pending_path, receipt)
      File.open(@state_root, File::RDONLY) { |dir| dir.fsync }
      ledger_plan = context.fetch(:ledger_plan)
      result = @ledger.scope_migration_execute(
        source_roots: scope.fetch("source_roots_after"), repository_id: scope.fetch("repository_id"),
        receipt_id: scope.fetch("receipt_id"), confirmation: BackupRetentionLedger::SCOPE_CONFIRMATION,
        expected_digest: ledger_plan.fetch("expected_digest")
      )
      raise result["reason"] unless result["ok"]
      raise "source manifest changed during migration" unless Digest::SHA256.file(@sources_path).hexdigest == scope.fetch("sources_sha256")
      raise "exclusions changed during migration" unless Digest::SHA256.file(@excludes_path).hexdigest == scope.fetch("exclusions_sha256")
      atomic_text(@sources_path, context.fetch(:source_after))
      File.open(@state_root, File::RDONLY) { |dir| dir.fsync }
      before = JSON.parse(File.binread(File.join(recovery, "ledger.before")))
      after = JSON.parse(File.binread(@ledger_path))
      raise "snapshot history or holds changed" unless before.fetch("last_verified_snapshot") == after.fetch("last_verified_snapshot") && before.fetch("holds") == after.fetch("holds")
      raise "source readback differs" unless safe_manifest_lines(@sources_path).sort == scope.fetch("source_roots_after")
      raise "migrated ledger failed validation" unless @ledger.checkpoint["ok"]
      receipt.merge!("state" => "complete", "completed_at" => @clock.call.utc.iso8601,
                     "sources_after_sha256" => Digest::SHA256.file(@sources_path).hexdigest,
                     "ledger_after_sha256" => Digest::SHA256.file(@ledger_path).hexdigest,
                     "fresh_snapshot_required" => true)
      atomic_json(receipt_path, receipt)
      File.open(@receipt_root, File::RDONLY) { |dir| dir.fsync }
      # Retain the final marker instead of erasing crash-recovery evidence.
      atomic_json(scope_migration_pending_path, receipt)
      File.rename(scope_migration_pending_path, File.join(recovery, "completion-marker.json"))
      File.open(recovery, File::RDONLY) { |dir| dir.fsync }
      File.open(@state_root, File::RDONLY) { |dir| dir.fsync }
      complete("backup source scope migrated; history and holds verified unchanged",
               {"receipt_id" => scope.fetch("receipt_id"), "retired_source_count" => retirements.length,
                "holds_preserved" => after.fetch("holds").length, "fresh_snapshot_required" => true,
                "deletion" => false}, "backup_scope_migrated")
    rescue StandardError => error
      response = blocked("scope migration stopped; inspect retained before-images and pending marker: #{safe_error(error)}")
      if defined?(recovery) && recovery && File.directory?(recovery)
        response["mutation"] = "backup_scope_migration_incomplete"
        response["data"] = {"review_required" => true, "automatic_retry" => false,
                            "recovery_directory" => recovery,
                            "pending_marker" => File.exist?(scope_migration_pending_path)}
      end
      response
    ensure
      release_operation_lock(operation_lock)
    end

    private

    def scope_migration_pending_path
      File.join(@state_root, "scope-migration-pending.json")
    end

    def scope_migration_confirmation
      @profile_id == "operator" ? "MIGRATE_REVIEWED_OPERATOR_BACKUP_SCOPE" : "MIGRATE_REVIEWED_SOUL_BACKUP_SCOPE"
    end

    def scope_migration_context(retirements)
      raise "pending scope migration requires explicit reconciliation" if File.exist?(scope_migration_pending_path) || File.symlink?(scope_migration_pending_path)
      raise ArgumentError, "retirements must be a bounded nonempty array" unless retirements.is_a?(Array) && retirements.length.between?(1, 64)
      sources_body = manifest_body(@sources_path)
      exclusions_body = manifest_body(@excludes_path)
      sources = safe_manifest_lines(@sources_path)
      reviewed = retirements.map do |entry|
        raise ArgumentError, "retirement fields are invalid" unless entry.is_a?(Hash) && entry.keys.sort == %w[evidence path reason]
        path, reason, evidence = entry.values_at("path", "reason", "evidence")
        raise ArgumentError, "retired path must be an exact configured source" unless path.is_a?(String) && sources.include?(path)
        raise ArgumentError, "only unavailable roots may be retired; existing paths need a separate review" if File.exist?(path) || File.symlink?(path)
        raise ArgumentError, "retirement reason is required" unless reason.is_a?(String) && reason.bytesize.between?(10, 2048) && !reason.include?("\0")
        raise ArgumentError, "retained evidence must be an absolute normalized file" unless evidence.is_a?(String) && evidence.start_with?("/") && File.expand_path(evidence) == evidence
        raise ArgumentError, "retained evidence is unavailable or unsafe" unless regular_file?(evidence) && File.realpath(evidence) == evidence && File.size(evidence).between?(1, 1024 * 1024) && File.readable?(evidence)
        entry.merge("evidence_sha256" => Digest::SHA256.file(evidence).hexdigest)
      end.sort_by { |entry| entry.fetch("path") }
      removed = reviewed.map { |entry| entry.fetch("path") }
      raise ArgumentError, "retired paths must be unique" unless removed.uniq == removed
      remaining = (sources - removed).sort
      raise ArgumentError, "at least one live source must remain" if remaining.empty?
      remaining.each do |path|
        raise ArgumentError, "remaining source is unavailable or symlinked: #{display_path(path)}" unless File.exist?(path) && File.readable?(path) && !File.symlink?(path)
      end
      raise ArgumentError, "ledger is unavailable or unsafe" unless regular_file?(@ledger_path) && File.size(@ledger_path) <= BackupRetentionLedger::MAX_LEDGER_BYTES && (File.stat(@ledger_path).mode & 0o077).zero?
      scope = {
        "operation" => "backup_scope_migration", "profile_id" => @profile_id,
        "repository_id" => repository_fingerprint,
        "sources_sha256" => Digest::SHA256.hexdigest(sources_body),
        "exclusions_sha256" => Digest::SHA256.hexdigest(exclusions_body),
        "ledger_sha256" => Digest::SHA256.file(@ledger_path).hexdigest,
        "retirements" => reviewed, "source_roots_after" => remaining,
        "deletion" => false, "automatic_retry" => false, "snapshot_record_preserved" => true
      }
      scope["receipt_id"] = "scope_migration_#{digest(scope)[0, 32]}"
      ledger = @ledger.scope_migration_preview(source_roots: remaining, repository_id: scope.fetch("repository_id"), receipt_id: scope.fetch("receipt_id"))
      raise ArgumentError, ledger["reason"] unless ledger["ok"]
      raise ArgumentError, "retirement list differs from historical capture scope" unless ledger.dig("data", "source_removals") == removed
      scope["ledger_preview_digest"] = ledger.dig("data", "expected_digest")
      scope["holds_preserved"] = ledger.dig("data", "holds_preserved")
      {scope: scope, ledger_plan: ledger.fetch("data"),
       source_after: sources_body.lines.reject { |line| removed.include?(line.strip) }.join}
    end
  end
end
