# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require "time"

module SoulCore
  class BackupRetentionLedger
    SCHEMA_VERSION = "soul.backup_retention_ledger.v1"
    MANIFEST_SCHEMA_VERSION = "soul.backup_snapshot_manifest.v1"
    RETENTION_DAYS = 30
    HOLD_SECONDS = RETENTION_DAYS * 24 * 60 * 60
    OBSERVE_CONFIRMATION = "RECORD_VERIFIED_BACKUP_SNAPSHOT"
    MAX_LEDGER_BYTES = 32 * 1024 * 1024
    MAX_PATHS = 100_000
    MAX_HOLDS = 100_000
    MAX_ROOTS = 64
    SNAPSHOT_ID = /\A[a-f0-9]{64}\z/
    DIGEST = /\A[a-f0-9]{64}\z/

    def initialize(ledger_path:, clock: -> { Time.now.utc })
      @ledger_path = File.expand_path(ledger_path)
      @clock = clock
    end

    def observe_preview(manifest:)
      normalized = normalize_manifest(manifest)
      ledger = read_ledger
      plan = observation_plan(ledger, normalized)
      scope = {
        "operation" => "backup_retention_observe",
        "manifest_digest" => digest(normalized),
        "previous_ledger_digest" => ledger && digest(ledger),
        "snapshot_id" => normalized.fetch("snapshot_id"),
        "verified_at" => normalized.fetch("verified_at"),
        "source_root_addition_count" => plan.fetch("source_root_additions").length,
        "source_root_addition_digests" => plan.fetch("source_root_additions").map { |path| path_digest(path) },
        "new_deletion_count" => plan.fetch("new_holds").length,
        "reappeared_path_count" => plan.fetch("reappeared_paths").length,
        "active_hold_count_after" => active_holds(plan.fetch("ledger"), at: Time.iso8601(normalized.fetch("verified_at"))).length,
        "total_hold_count_after" => plan.fetch("ledger").fetch("holds").length
      }
      complete(
        "verified snapshot observation prepared for exact human approval",
        scope.merge(
          "confirmation_phrase" => OBSERVE_CONFIRMATION,
          "expected_digest" => digest(scope),
          "new_holds" => public_holds(plan.fetch("new_holds")),
          "reappeared_path_digests" => plan.fetch("reappeared_paths").map { |path| path_digest(path) },
          "ledger_mutation" => plan.fetch("mutation")
        )
      )
    rescue ArgumentError => error
      awaiting(error.message)
    rescue StandardError => error
      blocked("retention observation preview failed safely: #{error.message}")
    end

    def observe_execute(manifest:, confirmation:, expected_digest:)
      preview = observe_preview(manifest: manifest)
      return preview unless preview["ok"]
      return awaiting("exact confirmation phrase is required") unless confirmation.to_s == OBSERVE_CONFIRMATION
      return blocked("retention observation digest is stale or invalid") unless secure_equal?(expected_digest, preview.dig("data", "expected_digest"))

      normalized = normalize_manifest(manifest)
      plan = observation_plan(read_ledger, normalized)
      atomic_json(@ledger_path, plan.fetch("ledger"))
      complete(
        plan.fetch("mutation") == "none" ? "verified snapshot was already recorded" : "verified snapshot and deletion holds recorded",
        {
          "snapshot_id" => normalized.fetch("snapshot_id"),
          "ledger_digest" => digest(plan.fetch("ledger")),
          "source_root_addition_count" => plan.fetch("source_root_additions").length,
          "source_root_addition_digests" => plan.fetch("source_root_additions").map { |path| path_digest(path) },
          "new_deletion_count" => plan.fetch("new_holds").length,
          "reappeared_path_count" => plan.fetch("reappeared_paths").length,
          "retention_days" => RETENTION_DAYS
        },
        plan.fetch("mutation")
      )
    rescue ArgumentError => error
      awaiting(error.message)
    rescue StandardError => error
      blocked("retention observation failed safely: #{error.message}")
    end

    def retention_preview(candidate_snapshot_ids:)
      ledger = read_ledger
      return blocked("retention ledger does not exist; pruning must remain disabled") unless ledger

      now = utc_time(@clock.call, "current time")
      candidates = normalize_snapshot_ids(candidate_snapshot_ids)
      active = active_holds(ledger, at: now)
      expired = ledger.fetch("holds") - active
      protected_ids = active.map { |hold| hold.fetch("protective_snapshot_id") }.uniq.sort
      protected_candidates = candidates & protected_ids
      hold_clear_candidates = candidates - protected_ids
      scope = {
        "operation" => "backup_retention_preview",
        "ledger_digest" => digest(ledger),
        "evaluated_at" => now.iso8601,
        "candidate_snapshot_ids" => candidates,
        "protected_candidate_snapshot_ids" => protected_candidates,
        "hold_clear_candidate_snapshot_ids" => hold_clear_candidates,
        "active_hold_count" => active.length,
        "expired_hold_count" => expired.length,
        "execution_available" => false
      }
      complete(
        "deletion holds evaluated; hold-clear does not itself authorize snapshot removal",
        scope.merge(
          "expected_digest" => digest(scope),
          "active_holds" => public_holds(active),
          "expired_holds" => public_holds(expired),
          "next" => "No forget or prune execute operation exists in this slice."
        )
      )
    rescue ArgumentError => error
      awaiting(error.message)
    rescue StandardError => error
      blocked("retention preview failed safely: #{error.message}")
    end

    private

    def observation_plan(ledger, manifest)
      if ledger.nil?
        return {
          "ledger" => new_ledger(manifest),
          "source_root_additions" => [],
          "new_holds" => [],
          "reappeared_paths" => [],
          "mutation" => "backup_retention_ledger_initialized"
        }
      end

      previous = ledger.fetch("last_verified_snapshot")
      manifest_digest = digest(manifest)
      if manifest.fetch("snapshot_id") == previous.fetch("snapshot_id")
        raise ArgumentError, "snapshot replay differs from the recorded manifest" unless manifest_digest == previous.fetch("manifest_digest")
        return {
          "ledger" => ledger,
          "source_root_additions" => [],
          "new_holds" => [],
          "reappeared_paths" => [],
          "mutation" => "none"
        }
      end

      previous_time = Time.iso8601(previous.fetch("verified_at"))
      current_time = Time.iso8601(manifest.fetch("verified_at"))
      raise ArgumentError, "verified snapshot time must advance monotonically" unless current_time > previous_time
      raise ArgumentError, "repository identity changed; review the backup destination before recording deletions" unless manifest.fetch("repository_id") == previous.fetch("repository_id")
      previous_roots = previous.fetch("source_roots")
      current_roots = manifest.fetch("source_roots")
      removed_roots = previous_roots - current_roots
      unless removed_roots.empty?
        raise ArgumentError, "source roots were removed or replaced; review the backup scope before recording deletions"
      end
      source_root_additions = current_roots - previous_roots

      previous_paths = previous.fetch("paths")
      current_paths = manifest.fetch("paths")
      deleted_paths = previous_paths - current_paths
      reappeared_paths = current_paths & ledger.fetch("holds").map { |hold| hold.fetch("path") }
      retained_holds = ledger.fetch("holds").reject { |hold| reappeared_paths.include?(hold.fetch("path")) }
      held_paths = retained_holds.map { |hold| hold.fetch("path") }
      new_holds = (deleted_paths - held_paths).map do |path|
        {
          "path" => path,
          "path_sha256" => path_digest(path),
          "detected_at" => manifest.fetch("verified_at"),
          "hold_until" => (current_time + HOLD_SECONDS).iso8601,
          "protective_snapshot_id" => previous.fetch("snapshot_id"),
          "detected_by_snapshot_id" => manifest.fetch("snapshot_id")
        }
      end
      holds = (retained_holds + new_holds).sort_by { |hold| hold.fetch("path") }
      raise ArgumentError, "retention hold count exceeds #{MAX_HOLDS}" if holds.length > MAX_HOLDS

      updated = {
        "schema_version" => SCHEMA_VERSION,
        "retention_days" => RETENTION_DAYS,
        "updated_at" => manifest.fetch("verified_at"),
        "last_verified_snapshot" => snapshot_record(manifest),
        "holds" => holds
      }
      {
        "ledger" => updated,
        "source_root_additions" => source_root_additions,
        "new_holds" => new_holds,
        "reappeared_paths" => reappeared_paths,
        "mutation" => "backup_retention_ledger_updated"
      }
    end

    def new_ledger(manifest)
      {
        "schema_version" => SCHEMA_VERSION,
        "retention_days" => RETENTION_DAYS,
        "updated_at" => manifest.fetch("verified_at"),
        "last_verified_snapshot" => snapshot_record(manifest),
        "holds" => []
      }
    end

    def snapshot_record(manifest)
      {
        "snapshot_id" => manifest.fetch("snapshot_id"),
        "verified_at" => manifest.fetch("verified_at"),
        "repository_id" => manifest.fetch("repository_id"),
        "source_roots" => manifest.fetch("source_roots"),
        "paths" => manifest.fetch("paths"),
        "manifest_digest" => digest(manifest)
      }
    end

    def normalize_manifest(value)
      manifest = stringify_hash(value)
      required = %w[schema_version snapshot_id verified_at repository_id source_roots paths verification]
      raise ArgumentError, "snapshot manifest fields are invalid" unless manifest.keys.sort == required.sort
      raise ArgumentError, "snapshot manifest schema is invalid" unless manifest["schema_version"] == MANIFEST_SCHEMA_VERSION
      snapshot_id = manifest["snapshot_id"].to_s
      repository_id = manifest["repository_id"].to_s
      raise ArgumentError, "snapshot ID must be a full restic SHA-256 ID" unless snapshot_id.match?(SNAPSHOT_ID)
      raise ArgumentError, "repository ID must be a SHA-256 identifier" unless repository_id.match?(DIGEST)
      verified_at = utc_time(Time.iso8601(manifest.fetch("verified_at").to_s), "verified_at").iso8601
      verification = stringify_hash(manifest["verification"])
      unless verification.keys.sort == %w[check_mode result].sort && verification["result"] == "passed" && %w[metadata full_data].include?(verification["check_mode"])
        raise ArgumentError, "snapshot verification must record a passed metadata or full-data check"
      end

      roots = normalize_paths(manifest["source_roots"], maximum: MAX_ROOTS, label: "source roots")
      raise ArgumentError, "at least one verified source root is required" if roots.empty?
      paths = normalize_paths(manifest["paths"], maximum: MAX_PATHS, label: "snapshot paths")
      raise ArgumentError, "snapshot inventory does not contain every verified source root" unless (roots - paths).empty?
      outside = paths.find { |path| roots.none? { |root| within?(path, root) } }
      raise ArgumentError, "snapshot path escapes verified source roots" if outside
      {
        "schema_version" => MANIFEST_SCHEMA_VERSION,
        "snapshot_id" => snapshot_id,
        "verified_at" => verified_at,
        "repository_id" => repository_id,
        "source_roots" => roots,
        "paths" => paths,
        "verification" => verification
      }
    rescue KeyError, TypeError, JSON::ParserError
      raise ArgumentError, "snapshot manifest is invalid"
    end

    def read_ledger
      return nil unless File.exist?(@ledger_path) || File.symlink?(@ledger_path)
      stat = File.lstat(@ledger_path)
      raise "retention ledger must be a regular, non-symlink file" unless stat.file? && !stat.symlink?
      raise "retention ledger exceeds size limit" if stat.size > MAX_LEDGER_BYTES
      ledger = JSON.parse(File.binread(@ledger_path, MAX_LEDGER_BYTES))
      validate_ledger!(ledger)
      ledger
    rescue JSON::ParserError, KeyError, TypeError, ArgumentError
      raise "retention ledger is invalid"
    end

    def validate_ledger!(ledger)
      required = %w[schema_version retention_days updated_at last_verified_snapshot holds]
      raise unless ledger.is_a?(Hash) && ledger.keys.sort == required.sort
      raise unless ledger["schema_version"] == SCHEMA_VERSION && ledger["retention_days"] == RETENTION_DAYS
      utc_time(Time.iso8601(ledger.fetch("updated_at")), "ledger updated_at")
      snapshot = ledger.fetch("last_verified_snapshot")
      raise unless snapshot.is_a?(Hash) && snapshot.keys.sort == %w[manifest_digest paths repository_id snapshot_id source_roots verified_at].sort
      raise unless snapshot["snapshot_id"].to_s.match?(SNAPSHOT_ID) && snapshot["repository_id"].to_s.match?(DIGEST) && snapshot["manifest_digest"].to_s.match?(DIGEST)
      roots = normalize_paths(snapshot["source_roots"], maximum: MAX_ROOTS, label: "source roots")
      paths = normalize_paths(snapshot["paths"], maximum: MAX_PATHS, label: "snapshot paths")
      raise unless (roots - paths).empty?
      raise if paths.any? { |path| roots.none? { |root| within?(path, root) } }
      holds = ledger.fetch("holds")
      raise unless holds.is_a?(Array) && holds.length <= MAX_HOLDS
      seen = {}
      holds.each do |hold|
        keys = %w[path path_sha256 detected_at hold_until protective_snapshot_id detected_by_snapshot_id]
        raise unless hold.is_a?(Hash) && hold.keys.sort == keys.sort
        path = normalize_path(hold["path"])
        raise unless hold["path_sha256"] == path_digest(path) && !seen[path]
        raise unless roots.any? { |root| within?(path, root) }
        raise unless hold["protective_snapshot_id"].to_s.match?(SNAPSHOT_ID) && hold["detected_by_snapshot_id"].to_s.match?(SNAPSHOT_ID)
        detected = utc_time(Time.iso8601(hold["detected_at"]), "detected_at")
        expires = utc_time(Time.iso8601(hold["hold_until"]), "hold_until")
        raise unless expires == detected + HOLD_SECONDS
        seen[path] = true
      end
      true
    end

    def normalize_paths(value, maximum:, label:)
      raise ArgumentError, "#{label} must be an array" unless value.is_a?(Array)
      raise ArgumentError, "#{label} exceed #{maximum}" if value.length > maximum
      normalized = value.map { |path| normalize_path(path) }.uniq.sort
      raise ArgumentError, "#{label} contain duplicates or are not sorted" unless normalized.length == value.length && normalized == value
      normalized
    end

    def normalize_path(value)
      path = value.to_s
      raise ArgumentError, "backup paths must be absolute" unless path.start_with?("/")
      raise ArgumentError, "backup path is invalid" if path.empty? || path.bytesize > 4096 || path.include?("\0")
      clean = File.expand_path(path)
      raise ArgumentError, "backup paths must be normalized" unless clean == path
      clean
    end

    def normalize_snapshot_ids(value)
      raise ArgumentError, "candidate snapshot IDs must be an array" unless value.is_a?(Array)
      raise ArgumentError, "candidate snapshot count exceeds 10,000" if value.length > 10_000
      ids = value.map(&:to_s)
      raise ArgumentError, "candidate snapshot ID is invalid" unless ids.all? { |id| id.match?(SNAPSHOT_ID) }
      raise ArgumentError, "candidate snapshot IDs contain duplicates" unless ids.uniq.length == ids.length
      ids.sort
    end

    def active_holds(ledger, at:)
      ledger.fetch("holds").select { |hold| at < Time.iso8601(hold.fetch("hold_until")) }
    end

    def public_holds(holds)
      holds.map do |hold|
        hold.reject { |key, _| key == "path" }
      end
    end

    def within?(path, root)
      path == root || path.start_with?(root + File::SEPARATOR)
    end

    def utc_time(value, label)
      raise ArgumentError, "#{label} must include an explicit UTC offset" unless value.respond_to?(:utc_offset) && value.utc_offset == 0
      value.utc
    end

    def stringify_hash(value)
      raise ArgumentError, "object must be a JSON object" unless value.is_a?(Hash)
      value.to_h { |key, item| [key.to_s, item] }
    end

    def path_digest(path)
      Digest::SHA256.hexdigest(path)
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
      left = provided.to_s
      right = expected.to_s
      left.bytesize == right.bytesize && Digest::SHA256.hexdigest(left) == Digest::SHA256.hexdigest(right)
    end

    def atomic_json(path, value)
      body = JSON.pretty_generate(value) + "\n"
      raise "retention ledger exceeds size limit" if body.bytesize > MAX_LEDGER_BYTES
      directory = File.dirname(path)
      raise "retention ledger directory does not exist" unless File.directory?(directory) && !File.symlink?(directory)
      temporary = "#{path}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(body)
        file.flush
        file.fsync
      end
      File.rename(temporary, path)
      File.open(directory, File::RDONLY) { |entry| entry.fsync }
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary
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
  end
end
