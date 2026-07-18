# frozen_string_literal: true

require "fileutils"

module SoulCore
  class MemoryPaths
    LEGACY_ROOT = "Soul/memory"
    PRIVATE_ROOT = "Soul/private/memory"
    MIGRATION_MARKER = ".migration_complete.json"
    PUBLIC_SEED_MARKER = ".public_seed_v1"

    attr_reader :root, :legacy_root, :private_root

    def initialize(root: Dir.pwd, legacy_root: LEGACY_ROOT, private_root: PRIVATE_ROOT)
      @root = File.expand_path(root)
      @legacy_root = expand_under_root(legacy_root)
      @private_root = expand_under_root(private_root)
    end

    def migrated?
      regular_file?(marker_path)
    end

    def public_seed?
      regular_file?(File.join(@legacy_root, PUBLIC_SEED_MARKER))
    end

    def read_path(relative_path)
      relative = validate_relative_path(relative_path)
      private_path = File.join(@private_root, relative)
      legacy_path = File.join(@legacy_root, relative)
      return private_path if regular_file?(private_path)
      return legacy_path if regular_file?(legacy_path)

      migrated? || public_seed? ? private_path : legacy_path
    end

    def write_path(relative_path)
      relative = validate_relative_path(relative_path)
      base = migrated? || public_seed? || !legacy_entry?(relative) ? @private_root : @legacy_root
      File.join(base, relative)
    end

    def marker_path
      File.join(@private_root, MIGRATION_MARKER)
    end

    def relative_to_project(path)
      expanded = File.expand_path(path)
      prefix = "#{@root}#{File::SEPARATOR}"
      expanded.start_with?(prefix) ? expanded.delete_prefix(prefix) : expanded
    end

    private

    def expand_under_root(path)
      expanded = File.expand_path(path, @root)
      prefix = "#{@root}#{File::SEPARATOR}"
      raise ArgumentError, "memory root must remain inside the project" unless expanded.start_with?(prefix)

      expanded
    end

    def validate_relative_path(path)
      value = path.to_s
      clean = File.expand_path(value, "/").delete_prefix("/")
      if value.empty? || value.start_with?(File::SEPARATOR) || clean != value || value.split(File::SEPARATOR).include?("..")
        raise ArgumentError, "memory path must be a clean relative path"
      end

      value
    end

    def legacy_entry?(relative)
      File.exist?(File.join(@legacy_root, relative)) || File.symlink?(File.join(@legacy_root, relative))
    end

    def regular_file?(path)
      File.file?(path) && !File.symlink?(path)
    end
  end
end
