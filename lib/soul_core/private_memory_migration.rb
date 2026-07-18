# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require "time"
require_relative "memory_paths"

module SoulCore
  class PrivateMemoryMigration
    CONFIRMATION = "COPY_PRIVATE_MEMORY_STATE"
    SCHEMA = "soul.private_memory_migration.v1"
    ROOT_FILES = %w[
      aliases.yaml
      approved_lessons.md
      approved_rules.md
      conversation_memory.jsonl
      lessons.md
      projects.yaml
      user.yaml
    ].freeze
    MAX_EXPORTS = 512
    MAX_FILE_BYTES = 64 * 1024 * 1024
    MAX_TOTAL_BYTES = 256 * 1024 * 1024

    def initialize(root: Dir.pwd, paths: nil, clock: -> { Time.now })
      @root = File.expand_path(root)
      @paths = paths || MemoryPaths.new(root: @root)
      @clock = clock
    end

    def preview
      return blocked("private-memory migration is already complete", data: current_state) if @paths.migrated?
      return blocked("public seed installation has no legacy owner state to migrate", data: current_state) if @paths.public_seed?

      scope = build_scope
      blocked("human review and exact confirmation are required", data: scope.merge(
        "expected_digest" => digest(scope),
        "confirmation_phrase" => CONFIRMATION
      ))
    rescue StandardError => error
      failed(error.message)
    end

    def execute(confirmation:, expected_digest:)
      return awaiting("confirmation and preview digest are required") if confirmation.to_s.empty? || expected_digest.to_s.empty?
      return blocked("private-memory migration is already complete", data: current_state) if @paths.migrated?
      return blocked("public seed installation has no legacy owner state to migrate", data: current_state) if @paths.public_seed?
      return blocked("exact private-memory migration confirmation did not match") unless confirmation == CONFIRMATION

      scope = build_scope
      return blocked("private-memory source state changed; preview again") unless secure_compare(expected_digest, digest(scope))

      copy_and_verify(scope)
    rescue StandardError => error
      failed(error.message)
    end

    private

    def build_scope
      validate_directory!(@paths.legacy_root)
      validate_destination_tree!
      records = source_paths.map { |path| record_for(path) }
      raise "no legacy memory files were found" if records.empty?
      total = records.sum { |record| record.fetch("bytes") }
      raise "legacy memory exceeds the #{MAX_TOTAL_BYTES}-byte migration bound" if total > MAX_TOTAL_BYTES

      conflicts = records.select { |record| record["destination_state"] == "conflict" }
      raise "private-memory destination conflicts with legacy source: #{conflicts.map { |row| row['relative_path'] }.join(', ')}" unless conflicts.empty?

      {
        "schema" => SCHEMA,
        "operation" => "copy_then_verify",
        "source_root" => @paths.relative_to_project(@paths.legacy_root),
        "destination_root" => @paths.relative_to_project(@paths.private_root),
        "source_files_retained" => true,
        "rollback_source_retained" => true,
        "files" => records,
        "file_count" => records.length,
        "total_bytes" => total,
        "cutover" => "verified marker written after every destination matches its source",
        "repository_sanitization_included" => false
      }
    end

    def source_paths
      paths = ROOT_FILES.filter_map do |relative|
        path = File.join(@paths.legacy_root, relative)
        path if File.exist?(path) || File.symlink?(path)
      end
      exports_root = File.join(@paths.legacy_root, "exports")
      if File.exist?(exports_root) || File.symlink?(exports_root)
        validate_directory!(exports_root)
        exports = Dir.children(exports_root).sort
        raise "legacy memory export count exceeds #{MAX_EXPORTS}" if exports.length > MAX_EXPORTS
        exports.each do |name|
          raise "legacy memory export name is unsafe" if name == "." || name == ".." || name.include?(File::SEPARATOR)
          paths << File.join(exports_root, name)
        end
      end
      paths
    end

    def record_for(source)
      validate_file!(source)
      relative = source.delete_prefix("#{@paths.legacy_root}#{File::SEPARATOR}")
      validate_destination_tree!(File.dirname(relative))
      destination = File.join(@paths.private_root, relative)
      source_sha = sha256(source)
      state = destination_state(destination, source_sha)
      {
        "relative_path" => relative,
        "source" => @paths.relative_to_project(source),
        "destination" => @paths.relative_to_project(destination),
        "bytes" => File.size(source),
        "sha256" => source_sha,
        "destination_state" => state
      }
    end

    def destination_state(path, source_sha)
      return "absent" unless File.exist?(path) || File.symlink?(path)

      validate_file!(path)
      secure_compare(sha256(path), source_sha) ? "verified_copy" : "conflict"
    end

    def validate_directory!(path)
      stat = File.lstat(path)
      raise "memory migration directory must not be a symlink: #{path}" if stat.symlink?
      raise "memory migration export path must be a directory: #{path}" unless stat.directory?
    end

    def validate_destination_tree!(relative = nil)
      destination_root_relative = @paths.private_root.delete_prefix("#{@root}#{File::SEPARATOR}")
      components = destination_root_relative.split(File::SEPARATOR)
      unless relative.nil? || relative == "."
        components.concat(relative.split(File::SEPARATOR))
      end
      cursor = @root
      components.each do |component|
        cursor = File.join(cursor, component)
        next unless File.exist?(cursor) || File.symlink?(cursor)

        stat = File.lstat(cursor)
        raise "private-memory destination ancestry must not contain symlinks: #{cursor}" if stat.symlink?
        raise "private-memory destination ancestry must contain only directories: #{cursor}" unless stat.directory?
      end
    end

    def validate_file!(path)
      stat = File.lstat(path)
      raise "memory migration source must be a regular non-symlink file: #{path}" unless stat.file? && !stat.symlink?
      raise "memory migration file exceeds #{MAX_FILE_BYTES} bytes: #{path}" if stat.size > MAX_FILE_BYTES
    rescue Errno::ENOENT
      raise "memory migration source disappeared: #{path}"
    end

    def copy_and_verify(scope)
      created = []
      FileUtils.mkdir_p(@paths.private_root, mode: 0o700)
      File.chmod(0o700, @paths.private_root)
      scope.fetch("files").each do |record|
        source = File.join(@root, record.fetch("source"))
        destination = File.join(@root, record.fetch("destination"))
        if record["destination_state"] == "absent"
          atomic_copy(source, destination)
          created << destination
        end
        raise "private-memory verification failed for #{record['relative_path']}" unless secure_compare(sha256(destination), record.fetch("sha256"))
      end

      marker = {
        "schema" => SCHEMA,
        "completed_at" => @clock.call.iso8601(6),
        "preview_digest" => digest(scope),
        "files" => scope.fetch("files").map { |row| row.slice("relative_path", "bytes", "sha256") },
        "source_files_retained" => true
      }
      atomic_write(@paths.marker_path, JSON.pretty_generate(marker) + "\n")
      complete(scope.merge(
        "marker" => @paths.relative_to_project(@paths.marker_path),
        "verified" => true,
        "next_gate" => "replace tracked owner state with neutral public seed templates"
      ))
    rescue StandardError
      created.reverse_each { |path| FileUtils.rm_f(path) }
      raise
    end

    def atomic_copy(source, destination)
      FileUtils.mkdir_p(File.dirname(destination), mode: 0o700)
      File.chmod(0o700, File.dirname(destination))
      temporary = "#{destination}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |output|
        File.open(source, "rb") { |input| IO.copy_stream(input, output) }
        output.flush
        output.fsync
      end
      File.rename(temporary, destination)
      File.chmod(0o600, destination)
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary
    end

    def atomic_write(path, content)
      FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
      temporary = "#{path}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(content)
        file.flush
        file.fsync
      end
      File.rename(temporary, path)
      File.chmod(0o600, path)
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary
    end

    def sha256(path)
      Digest::SHA256.file(path).hexdigest
    end

    def digest(value)
      Digest::SHA256.hexdigest(JSON.generate(canonicalize(value)))
    end

    def canonicalize(value)
      case value
      when Hash
        value.keys.map(&:to_s).sort.to_h { |key| [key, canonicalize(value.fetch(key))] }
      when Array then value.map { |item| canonicalize(item) }
      else value
      end
    end

    def secure_compare(left, right)
      left = left.to_s
      right = right.to_s
      return false unless left.bytesize == right.bytesize

      left.bytes.zip(right.bytes).reduce(0) { |difference, pair| difference | (pair[0] ^ pair[1]) }.zero?
    end

    def current_state
      {
        "marker" => @paths.relative_to_project(@paths.marker_path),
        "migrated" => @paths.migrated?,
        "public_seed" => @paths.public_seed?
      }
    end

    def complete(data)
      { "ok" => true, "lifecycle_state" => "complete", "message" => "private memory copied and verified", "data" => data }
    end

    def awaiting(message)
      { "ok" => false, "lifecycle_state" => "awaiting_input", "message" => message, "data" => {} }
    end

    def blocked(message, data: {})
      { "ok" => false, "lifecycle_state" => "blocked_for_human_review", "message" => message, "data" => data }
    end

    def failed(message)
      { "ok" => false, "lifecycle_state" => "failed", "message" => message, "data" => {} }
    end
  end
end
