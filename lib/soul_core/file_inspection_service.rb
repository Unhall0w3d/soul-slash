# frozen_string_literal: true

require "digest"
require "pathname"
require "time"

module SoulCore
  class FileInspectionService
    ROOTS_ENV = "SOUL_FILES_INSPECT_ROOTS"
    DEFAULT_ROOTS = "project=."
    ROOT_ID = /\A[a-z][a-z0-9_-]{0,31}\z/
    MAX_ROOTS = 8
    MAX_RELATIVE_PATH_BYTES = 512
    MAX_DIRECTORY_ENTRIES = 100
    MAX_DIRECTORY_SCAN = 1_000
    MAX_READ_BYTES = 32 * 1024
    MAX_RETURNED_LINES = 400

    TEXT_EXTENSIONS = %w[
      .bash .c .cfg .conf .cpp .css .csv .diff .go .h .hpp .html .ini .java
      .js .json .jsx .kt .lock .md .patch .py .rb .rs .sh .sql .swift .toml
      .ts .tsv .tsx .txt .xml .yaml .yml .zsh
    ].freeze
    TEXT_FILENAMES = %w[
      Dockerfile Gemfile LICENSE Makefile Procfile Rakefile README
    ].freeze
    SECRET_FILENAMES = /\A(?:\.env(?:\..*)?|\.netrc|\.git-credentials|authorized_keys|known_hosts|id_(?:rsa|dsa|ecdsa|ed25519)(?:\.pub)?|credentials?(?:\..*)?|secrets?(?:\..*)?)\z/i
    SECRET_EXTENSIONS = %w[.der .key .p12 .pfx .pem].freeze
    SECRET_CONTENT = [
      /-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----/,
      /\bAKIA[0-9A-Z]{16}\b/,
      /\bgh[pousr]_[A-Za-z0-9]{20,}\b/,
      /\bsk-[A-Za-z0-9_-]{20,}\b/,
      /\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b/
    ].freeze

    class AwaitingInput < StandardError; end
    class BoundaryViolation < StandardError; end

    def initialize(root: Dir.pwd, process_env: ENV, clock: -> { Time.now.utc })
      @project_root = File.expand_path(root)
      @process_env = process_env.to_h.transform_keys(&:to_s)
      @clock = clock
    end

    def roots
      records = configured_roots.map do |root_id, path|
        begin
          validate_root!(path)
          { "root_id" => root_id, "available" => true }
        rescue StandardError => error
          { "root_id" => root_id, "available" => false, "reason" => error.message }
        end
      end
      complete({ "roots" => records, "count" => records.length }, "approved file roots inspected")
    rescue AwaitingInput => error
      awaiting(error.message)
    rescue BoundaryViolation => error
      blocked(error.message)
    rescue StandardError => error
      failed("approved file roots failed safely: #{error.class}")
    end

    def list(root_id:, relative_path: ".")
      root, clean, target = resolve_target(root_id, relative_path)
      stat = safe_lstat(target)
      raise AwaitingInput, "requested path does not exist" unless stat
      raise AwaitingInput, "requested path is not a directory" unless stat.directory?

      records = []
      omitted = 0
      scanned = 0
      Dir.each_child(target) do |name|
        scanned += 1
        break if scanned > MAX_DIRECTORY_SCAN
        if prohibited_name?(name) || name.start_with?(".")
          omitted += 1
          next
        end

        child = File.join(target, name)
        child_stat = safe_lstat(child)
        if child_stat.nil? || child_stat.symlink?
          omitted += 1
          next
        end
        records << metadata(name, child_stat)
      rescue Errno::EACCES, Errno::ENOENT
        omitted += 1
      end
      records.sort_by! { |record| [record.fetch("type"), record.fetch("name").downcase] }
      truncated = scanned > MAX_DIRECTORY_SCAN || records.length > MAX_DIRECTORY_ENTRIES
      records = records.first(MAX_DIRECTORY_ENTRIES)
      complete({
        "root_id" => root_id.to_s,
        "relative_path" => clean,
        "entries" => records,
        "count" => records.length,
        "omitted_count" => omitted,
        "truncated" => truncated,
        "limits" => { "entries" => MAX_DIRECTORY_ENTRIES, "scanned" => MAX_DIRECTORY_SCAN }
      }, "approved directory inspected")
    rescue AwaitingInput => error
      awaiting(error.message)
    rescue BoundaryViolation => error
      blocked(error.message)
    rescue StandardError => error
      failed("directory inspection failed safely: #{error.class}")
    end

    def stat(root_id:, relative_path:)
      _root, clean, target = resolve_target(root_id, relative_path)
      stat = safe_lstat(target)
      raise AwaitingInput, "requested path does not exist" unless stat

      complete({
        "root_id" => root_id.to_s,
        "relative_path" => clean,
        "entry" => metadata(File.basename(target), stat)
      }, "approved path inspected")
    rescue AwaitingInput => error
      awaiting(error.message)
    rescue BoundaryViolation => error
      blocked(error.message)
    rescue StandardError => error
      failed("path inspection failed safely: #{error.class}")
    end

    def read(root_id:, relative_path:)
      _root, clean, target = resolve_target(root_id, relative_path)
      stat = safe_lstat(target)
      raise AwaitingInput, "requested path does not exist" unless stat
      raise AwaitingInput, "requested path is not a regular file" unless stat.file?
      raise BoundaryViolation, "requested file type is outside the reviewed text allowlist" unless text_file?(target)
      raise BoundaryViolation, "requested file exceeds the #{MAX_READ_BYTES}-byte read limit" if stat.size > MAX_READ_BYTES

      flags = File::RDONLY
      flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
      bytes = File.open(target, flags) do |file|
        opened = file.stat
        unless opened.file? && opened.dev == stat.dev && opened.ino == stat.ino
          raise BoundaryViolation, "requested file changed during safe open"
        end
        file.read(MAX_READ_BYTES + 1)
      end
      raise BoundaryViolation, "requested file exceeds the #{MAX_READ_BYTES}-byte read limit" if bytes.bytesize > MAX_READ_BYTES

      content = bytes.dup.force_encoding(Encoding::UTF_8)
      raise BoundaryViolation, "requested file is not valid UTF-8 text" unless content.valid_encoding? && !content.include?("\0")
      raise BoundaryViolation, "requested file appears to contain credential material" if SECRET_CONTENT.any? { |pattern| content.match?(pattern) }

      lines = content.lines
      returned = lines.first(MAX_RETURNED_LINES).join
      complete({
        "root_id" => root_id.to_s,
        "relative_path" => clean,
        "content" => returned,
        "bytes" => bytes.bytesize,
        "sha256" => Digest::SHA256.hexdigest(bytes),
        "line_count" => lines.length,
        "returned_lines" => [lines.length, MAX_RETURNED_LINES].min,
        "truncated" => lines.length > MAX_RETURNED_LINES,
        "content_trusted" => false,
        "authority" => "reference_only"
      }, "approved text file read")
    rescue AwaitingInput => error
      awaiting(error.message)
    rescue BoundaryViolation => error
      blocked(error.message)
    rescue StandardError => error
      failed("file read failed safely: #{error.class}")
    end

    private

    def configured_roots
      raw = @process_env.fetch(ROOTS_ENV, DEFAULT_ROOTS).to_s.strip
      raw = DEFAULT_ROOTS if raw.empty?
      entries = raw.split(";", -1)
      raise AwaitingInput, "#{ROOTS_ENV} must declare 1..#{MAX_ROOTS} roots" unless entries.length.between?(1, MAX_ROOTS)

      entries.each_with_object({}) do |entry, roots|
        root_id, path = entry.split("=", 2).map { |value| value.to_s.strip }
        raise AwaitingInput, "approved roots must use root_id=/absolute/or/project-relative/path" if root_id.empty? || path.empty?
        raise AwaitingInput, "approved root ID is invalid: #{root_id}" unless root_id.match?(ROOT_ID)
        raise AwaitingInput, "approved root ID is duplicated: #{root_id}" if roots.key?(root_id)

        roots[root_id] = File.expand_path(path, @project_root)
      end
    end

    def resolve_target(root_id, relative_path)
      id = root_id.to_s.strip
      roots = configured_roots
      raise AwaitingInput, "approved root is required; ask to show approved file roots" if id.empty?
      raise AwaitingInput, "unknown approved root #{id}; ask to show approved file roots" unless roots.key?(id)

      root = roots.fetch(id)
      validate_root!(root)
      clean = normalize_relative_path(relative_path)
      target = clean == "." ? root : File.expand_path(clean, root)
      prefix = root.end_with?(File::SEPARATOR) ? root : "#{root}#{File::SEPARATOR}"
      raise BoundaryViolation, "requested path escapes the approved root" unless target == root || target.start_with?(prefix)

      validate_target_ancestry!(root, clean)
      [root, clean, target]
    end

    def normalize_relative_path(relative_path)
      text = relative_path.to_s.strip
      raise AwaitingInput, "relative path is required" if text.empty?
      raise BoundaryViolation, "relative path exceeds #{MAX_RELATIVE_PATH_BYTES} bytes" if text.bytesize > MAX_RELATIVE_PATH_BYTES
      raise BoundaryViolation, "relative path must be valid UTF-8" unless text.valid_encoding?
      raise BoundaryViolation, "relative path must not contain NUL bytes" if text.include?("\0")
      raise BoundaryViolation, "relative path must not be absolute" if Pathname.new(text).absolute?
      raise BoundaryViolation, "relative path must use forward slashes" if text.include?("\\")

      clean = Pathname.new(text).cleanpath.to_s
      raise BoundaryViolation, "relative path escapes the approved root" if clean == ".." || clean.start_with?("../")
      clean.split("/").each do |segment|
        next if segment == "."
        raise BoundaryViolation, "hidden paths are outside the reviewed inspection boundary" if segment.start_with?(".")
        raise BoundaryViolation, "secret-bearing paths are outside the reviewed inspection boundary" if prohibited_name?(segment)
      end
      clean
    end

    def validate_root!(root)
      raise BoundaryViolation, "approved root must be an existing directory" unless File.directory?(root)
      validate_no_symlink_components!(root)
      stat = File.lstat(root)
      raise BoundaryViolation, "approved root must be a non-symlink directory" unless stat.directory? && !stat.symlink?
      true
    rescue Errno::EACCES, Errno::ENOENT
      raise BoundaryViolation, "approved root is unavailable"
    end

    def validate_target_ancestry!(root, clean)
      cursor = root
      clean.split("/").each do |segment|
        next if segment == "."
        cursor = File.join(cursor, segment)
        break unless File.exist?(cursor) || File.symlink?(cursor)
        raise BoundaryViolation, "requested path traverses a symbolic link" if File.lstat(cursor).symlink?
      end
    end

    def validate_no_symlink_components!(path)
      expanded = File.expand_path(path)
      cursor = File::SEPARATOR
      expanded.split(File::SEPARATOR).reject(&:empty?).each do |segment|
        cursor = File.join(cursor, segment)
        next unless File.exist?(cursor) || File.symlink?(cursor)
        raise BoundaryViolation, "approved root traverses a symbolic link" if File.lstat(cursor).symlink?
      end
    end

    def safe_lstat(path)
      File.lstat(path)
    rescue Errno::EACCES
      raise BoundaryViolation, "requested path is not readable"
    rescue Errno::ENOENT
      nil
    end

    def prohibited_name?(name)
      name.match?(SECRET_FILENAMES) || SECRET_EXTENSIONS.include?(File.extname(name).downcase)
    end

    def text_file?(path)
      basename = File.basename(path)
      TEXT_FILENAMES.include?(basename) || TEXT_FILENAMES.include?(File.basename(path, File.extname(path))) || TEXT_EXTENSIONS.include?(File.extname(path).downcase)
    end

    def metadata(name, stat)
      {
        "name" => name,
        "type" => stat.directory? ? "directory" : (stat.file? ? "file" : "other"),
        "bytes" => stat.file? ? stat.size : nil,
        "modified_at" => stat.mtime.utc.iso8601(6),
        "readable" => stat.readable?,
        "writable" => stat.writable?
      }.compact
    end

    def complete(data, message)
      outcome(true, "complete", message, data)
    end

    def awaiting(message)
      outcome(false, "awaiting_input", message, {})
    end

    def blocked(message)
      outcome(false, "blocked_for_human_review", message, {})
    end

    def failed(message)
      outcome(false, "failed", message, {})
    end

    def outcome(ok, lifecycle, message, data)
      {
        "ok" => ok,
        "lifecycle_state" => lifecycle,
        "message" => message,
        "data" => data,
        "mutation" => "none",
        "retrieved_at" => @clock.call.iso8601(6)
      }
    end
  end
end
