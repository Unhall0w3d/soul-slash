# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require "time"

require_relative "bounded_command_runner"

module SoulCore
  class StorageRetentionAssessor
    MAX_PREVIEW_ENTRIES = 256
    TEMP_MIN_AGE_SECONDS = 24 * 60 * 60
    LOG_MIN_AGE_SECONDS = 30 * 24 * 60 * 60
    QUARANTINE_MIN_AGE_SECONDS = 24 * 60 * 60
    PREVIEW_CATEGORIES = %w[temp_review_artifacts expired_project_logs failed_music_quarantine].freeze
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
    end

    def inventory
      categories = category_definitions.map { |definition| inspect_category(definition) }
      candidates = PREVIEW_CATEGORIES.to_h { |category| [category, discover(category).length] }
      {
        "status" => "ok",
        "assessment" => "storage",
        "schema_version" => "soul.storage_retention.v1",
        "generated_at" => @clock.call.iso8601,
        "read_only" => true,
        "categories" => categories,
        "summary" => {
          "observed_bytes" => categories.sum { |item| item.fetch("bytes", 0) },
          "protected_bytes" => categories.select { |item| item["retention"] == "protected" }.sum { |item| item.fetch("bytes", 0) },
          "cleanup_candidate_count" => candidates.values.sum,
          "preview_categories" => candidates
        },
        "dashboard_memory" => dashboard_memory,
        "cleanup_execution_available" => false,
        "verification" => { "metadata_only" => true, "symlinks_followed" => false, "files_changed" => false, "background_measurement" => false }
      }
    end

    def preview(category:)
      category = category.to_s
      return awaiting("cleanup category must be one of: #{PREVIEW_CATEGORIES.join(', ')}") unless PREVIEW_CATEGORIES.include?(category)
      return blocked("active music work prevents quarantine cleanup preview") if category == "failed_music_quarantine" && active_music_lease?

      entries = discover(category)
      scope = {
        "operation" => "storage_retention_cleanup_preview",
        "category" => category,
        "entries" => entries,
        "entry_count" => entries.length,
        "total_bytes" => entries.sum { |item| item.fetch("bytes") },
        "execution_available" => false
      }
      complete(scope.merge(
        "expected_digest" => Digest::SHA256.hexdigest(JSON.generate(scope)),
        "reason" => entries.empty? ? "no eligible cleanup candidates found" : "exact cleanup scope prepared for human review",
        "next" => "No cleanup execute operation exists in A1. A later approved slice must revalidate this scope before mutation."
      ))
    rescue SystemCallError => error
      blocked("storage cleanup preview failed safely: #{error.class}")
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
        category("shared_memory", File.join(@root, "Soul", "memory"), "protected", "Shared Soul memory; migration is a separate slice"),
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

    def discover(category)
      entries = case category
      when "temp_review_artifacts" then temp_entries.select { |entry| entry.fetch("eligible") }
      when "expired_project_logs" then expired_logs
      when "failed_music_quarantine" then failed_quarantines
      end
      entries.first(MAX_PREVIEW_ENTRIES).map { |entry| entry.slice("path", "bytes", "modified_at", "type") }
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

    def complete(data)
      { "ok" => true, "lifecycle_state" => "complete", "data" => data, "mutation" => "none" }
    end

    def awaiting(reason)
      { "ok" => false, "lifecycle_state" => "awaiting_input", "reason" => reason, "data" => {}, "mutation" => "none" }
    end

    def blocked(reason)
      { "ok" => false, "lifecycle_state" => "blocked_for_human_review", "reason" => reason, "data" => {}, "mutation" => "none" }
    end
  end
end
