# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require "tmpdir"
require "time"

require_relative "artifact_retention_census"
require_relative "bounded_command_runner"

module SoulCore
  class StorageRetentionAssessor
    MAX_PREVIEW_ENTRIES = 256
    MAX_DISCOVERY_ENTRIES = 4_096
    MAX_TREE_ENTRIES = 10_000
    MAX_TOTAL_TREE_ENTRIES = 50_000
    MAX_RECEIPT_BYTES = 64 * 1024
    TEMP_MIN_AGE_SECONDS = 24 * 60 * 60
    LOG_MIN_AGE_SECONDS = 30 * 24 * 60 * 60
    QUARANTINE_MIN_AGE_SECONDS = 24 * 60 * 60
    PREVIEW_CATEGORIES = %w[temp_review_artifacts expired_project_logs failed_music_quarantine].freeze
    CLEANUP_CONFIRMATION = "DELETE_EXACT_STORAGE_CLEANUP_SCOPE"
    CleanupScopeError = Class.new(StandardError)
    TEMP_PREFIXES = %w[
      soul-acestep-cpp-review
      soul-acestep-review
      soul-llama-
      soul-phase11
      soul-whisper
      soul-character
      soul-tooling-plan
      soul-enrichment-plan
    ].freeze

    def initialize(root: Dir.pwd, home: Dir.home, temp_root: Dir.tmpdir, runner: BoundedCommandRunner.new, clock: -> { Time.now })
      @root = File.expand_path(root)
      @home = File.expand_path(home)
      @temp_root = File.expand_path(temp_root)
      @runner = runner
      @clock = clock
      @cleanup_mutex = Mutex.new
      @receipt_root = File.join(@root, "Soul", "logs", "storage_cleanup")
    end

    def inventory
      categories = category_definitions.map { |definition| inspect_category(definition) }
      candidates = PREVIEW_CATEGORIES.to_h do |category|
        result = preview(category: category)
        [category, result["ok"] ? result.dig("data", "entry_count") : 0]
      end
      census = ArtifactRetentionCensus.new(root: @root, home: @home, temp_root: @temp_root, runner: @runner).inventory
      {
        "status" => "ok",
        "assessment" => "storage",
        "schema_version" => "soul.storage_retention.v2",
        "generated_at" => @clock.call.iso8601,
        "read_only" => true,
        "categories" => categories,
        "artifact_classes" => census.fetch("artifact_classes"),
        "backup_coverage" => census.fetch("backup_coverage"),
        "summary" => {
          "observed_bytes" => categories.sum { |item| item.fetch("bytes", 0) },
          "protected_bytes" => categories.select { |item| item["retention"] == "protected" }.sum { |item| item.fetch("bytes", 0) },
          "cleanup_candidate_count" => candidates.values.sum,
          "preview_categories" => candidates,
          "artifact_class_count" => census.fetch("artifact_classes").length
        },
        "dashboard_memory" => dashboard_memory,
        "cleanup_execution_available" => true,
        "verification" => census.fetch("verification").merge("background_measurement" => false)
      }
    end

    def preview(category:)
      category = category.to_s
      return awaiting("cleanup category must be one of: #{PREVIEW_CATEGORIES.join(', ')}") unless PREVIEW_CATEGORIES.include?(category)
      return blocked("active music work prevents quarantine cleanup preview") if category == "failed_music_quarantine" && active_music_lease?

      scope, = cleanup_plan(category)
      complete(scope.merge(
        "confirmation_phrase" => scope.fetch("execution_available") ? CLEANUP_CONFIRMATION : nil,
        "expected_digest" => digest(scope),
        "reason" => scope.fetch("entry_count").zero? ? "no eligible cleanup candidates found" : "exact cleanup scope prepared for human review",
        "next" => scope.fetch("execution_available") ? "Review every exact entry, then authorize this one current scope." : "Nothing is eligible; no cleanup action is available."
      ))
    rescue CleanupScopeError => error
      blocked(error.message)
    rescue SystemCallError => error
      blocked("storage cleanup preview failed safely: #{error.class}")
    end

    def execute(category:, confirmation:, expected_digest:)
      category = category.to_s
      return awaiting("cleanup category must be one of: #{PREVIEW_CATEGORIES.join(', ')}") unless PREVIEW_CATEGORIES.include?(category)
      return awaiting("exact cleanup confirmation is required") unless confirmation.to_s == CLEANUP_CONFIRMATION
      return awaiting("cleanup preview digest is required") unless expected_digest.to_s.match?(/\A[a-f0-9]{64}\z/)
      lock_acquired = @cleanup_mutex.try_lock
      return blocked("another storage cleanup operation is active") unless lock_acquired

      scope, candidates = cleanup_plan(category)
      return blocked("cleanup scope changed; preview the exact candidates again") unless secure_equal?(expected_digest, digest(scope))
      return complete(scope.merge("reason" => "no eligible cleanup candidates found")) unless scope.fetch("execution_available")

      staged = []
      removed = []
      transaction_id = SecureRandom.hex(8)
      begin
        candidates.each_with_index do |candidate, index|
          staged_candidate = stage_candidate(candidate, transaction_id, index)
          staged << staged_candidate
          verify_staged_candidate!(staged_candidate)
        end
        staged.each do |candidate|
          verify_staged_candidate!(candidate)
          remove_staged_candidate!(candidate)
          removed << candidate.fetch("public")
        end
      rescue StandardError => error
        restored = restore_staged_candidates(staged)
        receipt_id = begin
          write_cleanup_receipt(
            transaction_id: transaction_id,
            category: category,
            lifecycle: "failed",
            mutation: removed.empty? ? "none" : "storage_retention_cleanup_partially_completed",
            removed: removed,
            restored_entry_digests: restored
          )
        rescue StandardError
          nil
        end
        return failed(
          "storage cleanup failed safely: #{error.class}",
          {
            "category" => category,
            "removed_entries" => removed,
            "removed_count" => removed.length,
            "restored_entry_digests" => restored,
            "receipt_id" => receipt_id,
            "receipt_status" => receipt_id ? "recorded" : "failed",
            "review_required" => true
          },
          removed.empty? ? "none" : "storage_retention_cleanup_partially_completed"
        )
      end

      receipt_id = begin
        write_cleanup_receipt(
          transaction_id: transaction_id,
          category: category,
          lifecycle: "complete",
          mutation: removed.empty? ? "none" : "storage_retention_cleanup_completed",
          removed: removed,
          restored_entry_digests: []
        )
      rescue StandardError
        nil
      end
      unless receipt_id
        return failed(
          "exact cleanup completed but its owner-private receipt failed",
          {
            "category" => category,
            "removed_entries" => removed,
            "removed_count" => removed.length,
            "removed_bytes" => removed.sum { |entry| entry.fetch("bytes") },
            "receipt_status" => "failed",
            "review_required" => true
          },
          "storage_retention_cleanup_completed_receipt_failed"
        )
      end
      complete(
        {
          "operation" => "storage_retention_cleanup",
          "category" => category,
          "removed_entries" => removed,
          "removed_count" => removed.length,
          "removed_bytes" => removed.sum { |entry| entry.fetch("bytes") },
          "receipt_id" => receipt_id,
          "review_required" => false,
          "reason" => "exact reviewed cleanup scope removed"
        },
        removed.empty? ? "none" : "storage_retention_cleanup_completed"
      )
    rescue CleanupScopeError => error
      blocked(error.message)
    rescue SystemCallError => error
      blocked("storage cleanup failed safely before mutation: #{error.class}")
    ensure
      @cleanup_mutex.unlock if lock_acquired && @cleanup_mutex.owned?
    end

    private

    def category_definitions
      music_root = File.join(@home, ".local", "share", "soul", "music")
      [
        category("private_music_projects", File.join(@root, "Soul", "music"), "protected", "Private projects, candidates, analysis, and reviews"),
        category("production_music_runtime", File.join(music_root, "acestep-cpp"), "protected", "Pinned production Vulkan runtime and models"),
        category("legacy_music_runtime", File.join(music_root, "ace-step"), "manual_review", "Retired Python/CUDA runtime; separate destructive review required"),
        category("music_pilot_evidence", File.join(music_root, "vulkan-pilot-runs"), "protected", "Accepted and diagnostic listening pilots"),
        category("transcription_runtime", File.join(music_root, "transcription"), "protected", "Bounded transcription runtime and models"),
        category("finished_music_exports", File.join(@home, "Music", "soul-music"), "protected", "Operator-selected finished exports"),
        category("project_logs", File.join(@root, "Soul", "logs"), "age_review", "Logs remain reviewable; files older than 30 days may be previewed"),
        category("shared_memory", File.join(@root, "Soul", "private", "memory"), "protected", "Owner-private shared Soul memory"),
        category("legacy_memory_sources", File.join(@root, "Soul", "memory"), "manual_review", "Retained rollback sources; public sanitization requires the separate migration gate"),
        category("temporary_soul_residue", @temp_root, "mixed_review", "Only known allowlisted prefixes older than 24 hours are previewable", temp_scope: true)
      ]
    end

    def category(id, path, retention, note, temp_scope: false)
      { "id" => id, "path" => path, "retention" => retention, "note" => note, "temp_scope" => temp_scope }
    end

    def inspect_category(definition)
      path = definition.fetch("path")
      observed = definition["temp_scope"] ? inspect_temp_root : inspect_path(path)
      definition.reject { |key, _| key == "temp_scope" || key == "path" }.merge(
        "path" => display_path(path), "exists" => observed.fetch("exists"), "bytes" => observed.fetch("bytes"),
        "entry_count" => observed.fetch("entry_count"), "truncated" => observed.fetch("truncated"), "blocked" => observed["blocked"]
      ).compact
    end

    def inspect_temp_root
      entries = temp_entries.select { |entry| entry.fetch("known") || entry.fetch("name").start_with?("soul-") }
      { "exists" => File.directory?(@temp_root), "bytes" => entries.sum { |entry| entry.fetch("bytes") },
        "entry_count" => entries.length, "truncated" => entries.length >= MAX_PREVIEW_ENTRIES,
        "blocked" => entries.any? { |entry| !entry.fetch("known") } ? "unknown Soul-prefixed residue is protected" : nil }
    end

    def inspect_path(path)
      return { "exists" => false, "bytes" => 0, "entry_count" => 0, "truncated" => false } unless File.exist?(path) || File.symlink?(path)
      stat = File.lstat(path)
      return { "exists" => true, "bytes" => 0, "entry_count" => 1, "truncated" => false, "blocked" => "symlink is not followed" } if stat.symlink?
      bytes = disk_usage(path)
      count = if stat.directory?
        [Dir.children(path).length, MAX_PREVIEW_ENTRIES].min
      else
        1
      end
      { "exists" => true, "bytes" => bytes, "entry_count" => count, "truncated" => stat.directory? && Dir.children(path).length > MAX_PREVIEW_ENTRIES }
    rescue Errno::EACCES, Errno::ENOENT => error
      { "exists" => true, "bytes" => 0, "entry_count" => 0, "truncated" => false, "blocked" => error.class.name }
    end

    def disk_usage(path)
      result = @runner.run("du", "-s", "-B1", "--", path, timeout_seconds: 12, max_output_bytes: 4 * 1024)
      return 0 unless result.success?
      Integer(result.stdout.to_s.split.first)
    rescue ArgumentError
      0
    end

    def cleanup_plan(category)
      if category == "failed_music_quarantine" && active_music_lease?
        raise CleanupScopeError, "active music work prevents quarantine cleanup"
      end
      paths = discover_paths(category)
      raise CleanupScopeError, "cleanup candidate count exceeds #{MAX_PREVIEW_ENTRIES}; narrow the scope before execution" if paths.length > MAX_PREVIEW_ENTRIES

      minimum_age = minimum_age_seconds(category)
      tree_entry_count = 0
      candidates = paths.map do |path|
        candidate = inspect_candidate(path, minimum_age: minimum_age)
        tree_entry_count += candidate.fetch("tree_entry_count")
        raise CleanupScopeError, "cleanup tree inventory exceeds #{MAX_TOTAL_TREE_ENTRIES} entries" if tree_entry_count > MAX_TOTAL_TREE_ENTRIES
        candidate
      end
      entries = candidates.map { |candidate| candidate.fetch("public") }
      scope = {
        "operation" => "storage_retention_cleanup",
        "category" => category,
        "entries" => entries,
        "entry_count" => entries.length,
        "total_bytes" => entries.sum { |item| item.fetch("bytes") },
        "execution_available" => !entries.empty?
      }
      [scope, candidates]
    end

    def discover_paths(category)
      paths = case category
      when "temp_review_artifacts" then eligible_temp_paths
      when "expired_project_logs" then expired_log_paths
      when "failed_music_quarantine" then failed_quarantine_paths
      else []
      end
      raise CleanupScopeError, "cleanup candidate discovery exceeds #{MAX_DISCOVERY_ENTRIES} entries" if paths.length > MAX_DISCOVERY_ENTRIES
      paths.sort
    end

    def eligible_temp_paths
      return [] unless safe_directory?(@temp_root)
      children = bounded_children(@temp_root)
      children.filter_map do |name|
        next unless TEMP_PREFIXES.any? { |prefix| name.start_with?(prefix) }
        path = File.join(@temp_root, name)
        stat = File.lstat(path)
        next unless (stat.file? || stat.directory?) && !stat.symlink? && stat.uid == Process.uid
        next unless old_enough?(stat, TEMP_MIN_AGE_SECONDS)
        path
      rescue Errno::ENOENT, Errno::EACCES
        nil
      end
    end

    def expired_log_paths
      root = File.join(@root, "Soul", "logs")
      return [] unless safe_directory?(root)
      bounded_descendants(root).filter_map do |path|
        stat = File.lstat(path)
        next unless stat.file? && !stat.symlink? && stat.uid == Process.uid
        next if File.basename(path).start_with?(".")
        next unless old_enough?(stat, LOG_MIN_AGE_SECONDS)
        path
      rescue Errno::ENOENT, Errno::EACCES
        nil
      end
    end

    def failed_quarantine_paths
      return [] if active_music_lease?
      projects_root = File.join(@root, "Soul", "music", "projects")
      return [] unless safe_directory?(projects_root)

      bounded_children(projects_root).flat_map do |project_name|
        generations = File.join(projects_root, project_name, "generations")
        next [] unless safe_directory?(generations)
        bounded_children(generations).filter_map do |name|
          next unless name.match?(/\A\.candidate_[A-Za-z0-9_-]+\.partial\z/)
          path = File.join(generations, name)
          stat = File.lstat(path)
          next unless stat.directory? && !stat.symlink? && stat.uid == Process.uid
          next unless old_enough?(stat, QUARANTINE_MIN_AGE_SECONDS)
          path
        rescue Errno::ENOENT, Errno::EACCES
          nil
        end
      end
    end

    def inspect_candidate(path, minimum_age:)
      root_stat = File.lstat(path)
      stack = [[path, "."]]
      tree = []
      bytes = 0
      until stack.empty?
        current, relative = stack.pop
        stat = File.lstat(current)
        raise CleanupScopeError, "cleanup candidate contains a symlink" if stat.symlink?
        raise CleanupScopeError, "cleanup candidate contains a special filesystem entry" unless stat.file? || stat.directory?
        raise CleanupScopeError, "cleanup candidate is not owned by the current user" unless stat.uid == Process.uid
        raise CleanupScopeError, "cleanup candidate contains recently modified material" unless old_enough?(stat, minimum_age)
        tree << identity_record(relative, stat)
        raise CleanupScopeError, "one cleanup candidate exceeds #{MAX_TREE_ENTRIES} entries" if tree.length > MAX_TREE_ENTRIES
        if stat.directory?
          bounded_children(current).reverse_each do |name|
            stack << [File.join(current, name), relative == "." ? name : File.join(relative, name)]
          end
        else
          bytes += stat.size
        end
      end
      tree.sort_by! { |record| record.fetch("relative_path") }
      identity_digest = digest(tree)
      public_entry = {
        "path" => display_path(path),
        "bytes" => bytes,
        "modified_at" => root_stat.mtime.iso8601(9),
        "type" => root_stat.directory? ? "directory" : "file",
        "identity_digest" => identity_digest
      }
      {
        "absolute_path" => path,
        "device" => root_stat.dev,
        "inode" => root_stat.ino,
        "identity_digest" => identity_digest,
        "tree_entry_count" => tree.length,
        "public" => public_entry
      }
    end

    def identity_record(relative, stat)
      {
        "relative_path" => relative,
        "type" => stat.directory? ? "directory" : "file",
        "device" => stat.dev,
        "inode" => stat.ino,
        "uid" => stat.uid,
        "mode" => stat.mode & 0o7777,
        "size" => stat.size,
        "modified_at_ns" => (stat.mtime.to_i * 1_000_000_000) + stat.mtime.nsec
      }
    end

    def stage_candidate(candidate, transaction_id, index)
      path = candidate.fetch("absolute_path")
      current = inspect_candidate(path, minimum_age: 0)
      raise CleanupScopeError, "cleanup candidate changed after preview" unless current.fetch("identity_digest") == candidate.fetch("identity_digest")
      staging_path = File.join(File.dirname(path), ".soul-cleanup-stage-#{transaction_id}-#{index}")
      raise CleanupScopeError, "cleanup staging path already exists" if File.exist?(staging_path) || File.symlink?(staging_path)

      File.rename(path, staging_path)
      candidate.merge("staging_path" => staging_path)
    end

    def verify_staged_candidate!(candidate)
      staged = inspect_candidate(candidate.fetch("staging_path"), minimum_age: 0)
      matches = staged.fetch("device") == candidate.fetch("device") &&
        staged.fetch("inode") == candidate.fetch("inode") &&
        staged.fetch("identity_digest") == candidate.fetch("identity_digest")
      raise CleanupScopeError, "staged cleanup candidate changed before removal" unless matches
    end

    def remove_staged_candidate!(candidate)
      path = candidate.fetch("staging_path")
      stat = File.lstat(path)
      if stat.directory?
        FileUtils.remove_entry_secure(path)
      else
        File.unlink(path)
      end
      raise CleanupScopeError, "staged cleanup candidate remains after removal" if File.exist?(path) || File.symlink?(path)
    end

    def restore_staged_candidates(candidates)
      candidates.reverse_each.filter_map do |candidate|
        staged = candidate["staging_path"]
        next unless staged && (File.exist?(staged) || File.symlink?(staged))
        original = candidate.fetch("absolute_path")
        next if File.exist?(original) || File.symlink?(original)
        File.rename(staged, original)
        path_digest(display_path(original))
      rescue SystemCallError
        nil
      end
    end

    def write_cleanup_receipt(transaction_id:, category:, lifecycle:, mutation:, removed:, restored_entry_digests:)
      receipt_id = "storage_cleanup_#{@clock.call.utc.strftime('%Y%m%dT%H%M%SZ')}_#{transaction_id}"
      receipt = {
        "schema_version" => "soul.storage_cleanup_receipt.v1",
        "receipt_id" => receipt_id,
        "completed_at" => @clock.call.utc.iso8601,
        "category" => category,
        "lifecycle_state" => lifecycle,
        "mutation" => mutation,
        "removed_count" => removed.length,
        "removed_bytes" => removed.sum { |entry| entry.fetch("bytes") },
        "removed_entry_digests" => removed.map { |entry| path_digest(entry.fetch("path")) },
        "removed_identity_digests" => removed.map { |entry| entry.fetch("identity_digest") },
        "restored_entry_digests" => restored_entry_digests,
        "automatic" => false
      }
      body = JSON.pretty_generate(receipt) + "\n"
      raise CleanupScopeError, "storage cleanup receipt exceeds size limit" if body.bytesize > MAX_RECEIPT_BYTES

      FileUtils.mkdir_p(@receipt_root, mode: 0o700)
      File.chmod(0o700, @receipt_root)
      temporary = File.join(@receipt_root, ".#{receipt_id}.tmp-#{Process.pid}")
      destination = File.join(@receipt_root, "#{receipt_id}.json")
      raise CleanupScopeError, "storage cleanup receipt already exists" if File.exist?(destination) || File.symlink?(destination)
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(body)
        file.flush
        file.fsync
      end
      File.rename(temporary, destination)
      File.open(@receipt_root, File::RDONLY) { |directory| directory.fsync }
      receipt_id
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary
    end

    def bounded_children(path)
      children = Dir.children(path).sort
      raise CleanupScopeError, "cleanup discovery exceeds #{MAX_DISCOVERY_ENTRIES} entries in one directory" if children.length > MAX_DISCOVERY_ENTRIES
      children
    end

    def bounded_descendants(root)
      result = []
      stack = [root]
      until stack.empty?
        directory = stack.pop
        bounded_children(directory).reverse_each do |name|
          path = File.join(directory, name)
          result << path
          raise CleanupScopeError, "cleanup discovery exceeds #{MAX_DISCOVERY_ENTRIES} entries" if result.length > MAX_DISCOVERY_ENTRIES
          stat = File.lstat(path)
          stack << path if stat.directory? && !stat.symlink?
        end
      end
      result.sort
    end

    def minimum_age_seconds(category)
      case category
      when "temp_review_artifacts" then TEMP_MIN_AGE_SECONDS
      when "expired_project_logs" then LOG_MIN_AGE_SECONDS
      when "failed_music_quarantine" then QUARANTINE_MIN_AGE_SECONDS
      else 0
      end
    end

    def old_enough?(stat, seconds)
      (@clock.call - stat.mtime) >= seconds
    end

    def safe_directory?(path)
      File.directory?(path) && !File.symlink?(path)
    end

    def temp_entries
      return [] unless File.directory?(@temp_root) && !File.symlink?(@temp_root)
      Dir.children(@temp_root).sort.first(MAX_PREVIEW_ENTRIES).filter_map do |name|
        path = File.join(@temp_root, name)
        stat = File.lstat(path)
        next if stat.symlink? || (!stat.file? && !stat.directory?)
        known = TEMP_PREFIXES.any? { |prefix| name.start_with?(prefix) }
        age = @clock.call - stat.mtime
        { "name" => name, "path" => display_path(path), "bytes" => disk_usage(path), "modified_at" => stat.mtime.iso8601,
          "type" => stat.directory? ? "directory" : "file", "known" => known,
          "eligible" => known && stat.uid == Process.uid && age >= TEMP_MIN_AGE_SECONDS }
      rescue Errno::ENOENT, Errno::EACCES
        nil
      end
    end

    def expired_logs
      root = File.join(@root, "Soul", "logs")
      return [] unless File.directory?(root) && !File.symlink?(root)
      Dir.glob(File.join(root, "**", "*")).sort.first(MAX_PREVIEW_ENTRIES * 4).filter_map do |path|
        stat = File.lstat(path)
        next unless stat.file? && !stat.symlink? && (@clock.call - stat.mtime) >= LOG_MIN_AGE_SECONDS
        entry(path, stat)
      rescue Errno::ENOENT, Errno::EACCES
        nil
      end
    end

    def failed_quarantines
      pattern = File.join(@root, "Soul", "music", "projects", "*", "generations", ".candidate_*.partial")
      Dir.glob(pattern).sort.first(MAX_PREVIEW_ENTRIES).filter_map do |path|
        stat = File.lstat(path)
        next unless stat.directory? && !stat.symlink? && (@clock.call - stat.mtime) >= QUARANTINE_MIN_AGE_SECONDS
        entry(path, stat)
      rescue Errno::ENOENT, Errno::EACCES
        nil
      end
    end

    def entry(path, stat)
      { "path" => display_path(path), "bytes" => disk_usage(path), "modified_at" => stat.mtime.iso8601,
        "type" => stat.directory? ? "directory" : "file" }
    end

    def active_music_lease?
      Dir.glob(File.join(@root, "Soul", "runtime", "music", "*.json")).any? { |path| File.file?(path) && !File.symlink?(path) }
    end

    def dashboard_memory
      result = @runner.run("systemctl", "--user", "show", "soul-dashboard.service", "--property=MemoryCurrent", "--property=MemoryPeak", "--property=ActiveState", "--property=SubState", "--no-pager", timeout_seconds: 5, max_output_bytes: 8 * 1024)
      values = result.stdout.to_s.lines.filter_map { |line| line.strip.split("=", 2) if line.include?("=") }.to_h
      { "status" => result.success? ? "complete" : "unavailable", "point_in_time" => true,
        "active_state" => values["ActiveState"], "sub_state" => values["SubState"],
        "current_bytes" => integer_or_nil(values["MemoryCurrent"]), "peak_bytes" => integer_or_nil(values["MemoryPeak"]),
        "background_sampling" => false }
    rescue StandardError
      { "status" => "unavailable", "point_in_time" => true, "background_sampling" => false }
    end

    def integer_or_nil(value)
      Integer(value)
    rescue ArgumentError, TypeError
      nil
    end

    def display_path(path)
      expanded = File.expand_path(path)
      return "~#{expanded.delete_prefix(@home)}" if expanded == @home || expanded.start_with?(@home + File::SEPARATOR)
      return expanded.delete_prefix(@root + File::SEPARATOR) if expanded.start_with?(@root + File::SEPARATOR)
      expanded
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

    def path_digest(path)
      Digest::SHA256.hexdigest(path)
    end

    def secure_equal?(provided, expected)
      left = provided.to_s
      right = expected.to_s
      left.bytesize == right.bytesize && Digest::SHA256.hexdigest(left) == Digest::SHA256.hexdigest(right)
    end

    def complete(data, mutation = "none")
      { "ok" => true, "lifecycle_state" => "complete", "data" => data, "mutation" => mutation }
    end

    def awaiting(reason)
      { "ok" => false, "lifecycle_state" => "awaiting_input", "reason" => reason, "data" => {}, "mutation" => "none" }
    end

    def blocked(reason)
      { "ok" => false, "lifecycle_state" => "blocked_for_human_review", "reason" => reason, "data" => {}, "mutation" => "none" }
    end

    def failed(reason, data, mutation)
      { "ok" => false, "lifecycle_state" => "failed", "reason" => reason, "data" => data, "mutation" => mutation }
    end
  end
end
