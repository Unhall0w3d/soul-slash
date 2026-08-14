# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "pathname"
require "securerandom"
require "time"

module SoulCore
  class FileStewardService
    ROOTS_ENV = "SOUL_FILE_STEWARD_ROOTS"
    ROOT_ID = /\A[a-z][a-z0-9_-]{0,31}\z/
    QUARANTINE_ID = /\Aq_[a-f0-9]{24}\z/
    MAX_ROOTS = 8
    MAX_PATH_BYTES = 512
    MAX_SCAN = 2_000
    MAX_ENTRIES = 200
    MAX_COPY_BYTES = 512 * 1024 * 1024
    COPY_TIMEOUT_SECONDS = 30
    MAX_QUARANTINE_BYTES = 4 * 1024 * 1024 * 1024
    CHECKSUM_TIMEOUT_SECONDS = 60
    OPERATION_CONFIRMATION = "EXECUTE_FILE_STEWARD_OPERATION"
    QUARANTINE_CONFIRMATION = "QUARANTINE_FILE"
    RESTORE_CONFIRMATION = "RESTORE_QUARANTINED_FILE"
    ACTIONS = %w[rename move copy].freeze
    SECRET_FILENAMES = /\A(?:\.env(?:\..*)?|\.netrc|\.git-credentials|authorized_keys|known_hosts|id_(?:rsa|dsa|ecdsa|ed25519)(?:\.pub)?|credentials?(?:\..*)?|secrets?(?:\..*)?)\z/i
    SECRET_EXTENSIONS = %w[.der .key .p12 .pfx .pem].freeze

    class AwaitingInput < StandardError; end
    class BoundaryViolation < StandardError; end

    def initialize(root: Dir.pwd, process_env: ENV, clock: -> { Time.now.utc }, monotonic_clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @project_root = File.expand_path(root)
      @process_env = process_env.to_h.transform_keys(&:to_s)
      @clock = clock
      @monotonic_clock = monotonic_clock
      @private_root = File.join(@project_root, "Soul", "private", "file_steward")
      @quarantine_root = File.join(@private_root, "quarantine")
      @ledger_path = File.join(@private_root, "quarantine-ledger.json")
      @receipt_root = File.join(@private_root, "receipts")
    end

    def configured?
      !configured_roots.empty?
    rescue StandardError
      false
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
      complete({ "roots" => records, "count" => records.length, "mutation_authority" => "configured_roots_only", "permanent_delete" => false }, "File Steward roots inspected.")
    rescue AwaitingInput => error
      awaiting(error.message)
    rescue BoundaryViolation => error
      blocked(error.message)
    rescue StandardError => error
      failed("File Steward roots failed safely: #{error.class}")
    end

    def inventory(root_id:, relative_path: ".")
      _root, clean, target = resolve_target(root_id, relative_path, allow_root: true)
      stat = safe_lstat(target)
      raise AwaitingInput, "requested path does not exist" unless stat
      raise AwaitingInput, "requested path is not a directory" unless stat.directory?

      entries = []
      omitted = 0
      scanned = 0
      Dir.each_child(target) do |name|
        scanned += 1
        break if scanned > MAX_SCAN
        if prohibited_segment?(name)
          omitted += 1
          next
        end
        child_stat = safe_lstat(File.join(target, name))
        if child_stat.nil? || child_stat.symlink? || !(child_stat.file? || child_stat.directory?)
          omitted += 1
          next
        end
        entries << metadata(name, child_stat)
      rescue Errno::EACCES, Errno::ENOENT
        omitted += 1
      end
      entries.sort_by! { |entry| [entry["type"] == "directory" ? 0 : 1, entry["name"].downcase] }
      truncated = scanned > MAX_SCAN || entries.length > MAX_ENTRIES
      entries = entries.first(MAX_ENTRIES)
      complete({
        "root_id" => root_id.to_s,
        "relative_path" => clean,
        "entries" => entries,
        "count" => entries.length,
        "omitted_count" => omitted,
        "truncated" => truncated,
        "limits" => { "returned_entries" => MAX_ENTRIES, "scanned_entries" => MAX_SCAN },
        "mutation" => "none"
      }, "File Steward inventory collected.")
    rescue AwaitingInput => error
      awaiting(error.message)
    rescue BoundaryViolation => error
      blocked(error.message)
    rescue StandardError => error
      failed("File Steward inventory failed safely: #{error.class}")
    end

    def operation_preview(action:, source_root_id:, source_relative_path:, destination_root_id:, destination_relative_path:)
      plan = build_operation_plan(action, source_root_id, source_relative_path, destination_root_id, destination_relative_path)
      complete(plan.merge("expected_digest" => digest(plan), "confirmation_phrase" => OPERATION_CONFIRMATION), "Exact File Steward operation previewed.")
    rescue AwaitingInput => error
      awaiting(error.message)
    rescue BoundaryViolation => error
      blocked(error.message)
    rescue StandardError => error
      failed("File Steward operation preview failed safely: #{error.class}")
    end

    def operation_execute(action:, source_root_id:, source_relative_path:, destination_root_id:, destination_relative_path:, confirmation:, expected_digest:)
      return blocked("Exact confirmation is required.") unless confirmation.to_s == OPERATION_CONFIRMATION
      plan = build_operation_plan(action, source_root_id, source_relative_path, destination_root_id, destination_relative_path)
      return blocked("File Steward preview changed; review the fresh plan.") unless secure_equal?(digest(plan), expected_digest)

      source = target_for(plan.fetch("source"))
      destination = target_for(plan.fetch("destination"), allow_missing: true)
      result = case plan.fetch("action")
               when "rename", "move" then execute_move(source, destination, plan.fetch("source_fingerprint"))
               when "copy" then execute_copy(source, destination, plan.fetch("source_fingerprint"))
               end
      receipt = write_receipt(plan.merge("result" => result, "executed_at" => @clock.call.iso8601(6)))
      complete({ "action" => plan.fetch("action"), "source" => plan.fetch("source"), "destination" => plan.fetch("destination"), "verification" => result, "receipt_id" => receipt }, "File Steward operation completed and verified.", mutation: "local_file_operation")
    rescue AwaitingInput => error
      awaiting(error.message)
    rescue BoundaryViolation => error
      blocked(error.message)
    rescue StandardError => error
      failed("File Steward operation failed safely: #{error.class}")
    end

    def quarantine_preview(root_id:, relative_path:)
      root, clean, source = resolve_regular_file(root_id, relative_path)
      validate_source!(source)
      raise BoundaryViolation, "quarantine exceeds the #{MAX_QUARANTINE_BYTES}-byte A2 limit" if File.stat(source).size > MAX_QUARANTINE_BYTES
      raise BoundaryViolation, "quarantine requires the source and owner-private store to share one filesystem" unless File.stat(root).dev == File.stat(@project_root).dev
      plan = {
        "operation" => "quarantine",
        "source" => { "root_id" => root_id.to_s, "relative_path" => clean },
        "source_fingerprint" => fingerprint(source),
        "permanent_delete" => false
      }
      complete(plan.merge("expected_digest" => digest(plan), "confirmation_phrase" => QUARANTINE_CONFIRMATION), "Exact quarantine previewed.")
    rescue AwaitingInput => error
      awaiting(error.message)
    rescue BoundaryViolation => error
      blocked(error.message)
    rescue StandardError => error
      failed("Quarantine preview failed safely: #{error.class}")
    end

    def quarantine_execute(root_id:, relative_path:, confirmation:, expected_digest:)
      return blocked("Exact quarantine confirmation is required.") unless confirmation.to_s == QUARANTINE_CONFIRMATION
      preview = quarantine_preview(root_id: root_id, relative_path: relative_path)
      return preview unless preview["ok"]
      plan = preview.fetch("data").reject { |key, _value| %w[expected_digest confirmation_phrase].include?(key) }
      return blocked("Quarantine preview changed; review the fresh plan.") unless secure_equal?(digest(plan), expected_digest)

      source = target_for(plan.fetch("source"))
      validate_unchanged!(source, plan.fetch("source_fingerprint"))
      quarantine_id = "q_#{SecureRandom.hex(12)}"
      destination = File.join(ensure_private_directory(@quarantine_root), quarantine_id)
      move_no_overwrite(source, destination)
      begin
        checksum = sha256_file(destination, max_bytes: MAX_QUARANTINE_BYTES, timeout_seconds: CHECKSUM_TIMEOUT_SECONDS)
        entry = {
          "quarantine_id" => quarantine_id,
          "state" => "quarantined",
          "source" => plan.fetch("source"),
          "source_fingerprint" => plan.fetch("source_fingerprint"),
          "quarantine_fingerprint" => fingerprint(destination),
          "sha256" => checksum,
          "quarantined_at" => @clock.call.iso8601(6)
        }
        update_ledger { |ledger| ledger.fetch("entries") << entry }
      rescue StandardError
        move_no_overwrite(destination, source) if File.exist?(destination) && !File.exist?(source)
        raise
      end
      receipt = write_receipt(entry.merge("operation" => "quarantine"))
      complete({ "quarantine_id" => quarantine_id, "source" => entry.fetch("source"), "sha256" => checksum, "receipt_id" => receipt, "permanent_delete" => false }, "File quarantined and verified.", mutation: "quarantine")
    rescue AwaitingInput => error
      awaiting(error.message)
    rescue BoundaryViolation => error
      blocked(error.message)
    rescue StandardError => error
      failed("Quarantine failed safely: #{error.class}")
    end

    def quarantine_list
      entries = load_ledger.fetch("entries").select { |entry| entry["state"] == "quarantined" }.map do |entry|
        entry.slice("quarantine_id", "source", "sha256", "quarantined_at")
      end
      complete({ "entries" => entries, "count" => entries.length, "permanent_delete" => false }, "Quarantine inventory inspected.")
    rescue StandardError => error
      failed("Quarantine inventory failed safely: #{error.class}")
    end

    def restore_preview(quarantine_id:)
      entry = quarantine_entry(quarantine_id)
      raise AwaitingInput, "quarantine entry is not available for restore" unless entry && entry["state"] == "quarantined"
      destination = target_for(entry.fetch("source"), allow_missing: true)
      raise BoundaryViolation, "original destination is no longer empty" if File.exist?(destination) || File.symlink?(destination)
      source = File.join(@quarantine_root, quarantine_id.to_s)
      validate_quarantine_source!(source, entry)
      plan = {
        "operation" => "restore",
        "quarantine_id" => quarantine_id.to_s,
        "destination" => entry.fetch("source"),
        "quarantine_fingerprint" => fingerprint(source),
        "sha256" => entry.fetch("sha256"),
        "permanent_delete" => false
      }
      complete(plan.merge("expected_digest" => digest(plan), "confirmation_phrase" => RESTORE_CONFIRMATION), "Exact quarantine restore previewed.")
    rescue AwaitingInput => error
      awaiting(error.message)
    rescue BoundaryViolation => error
      blocked(error.message)
    rescue StandardError => error
      failed("Restore preview failed safely: #{error.class}")
    end

    def restore_execute(quarantine_id:, confirmation:, expected_digest:)
      return blocked("Exact restore confirmation is required.") unless confirmation.to_s == RESTORE_CONFIRMATION
      preview = restore_preview(quarantine_id: quarantine_id)
      return preview unless preview["ok"]
      plan = preview.fetch("data").reject { |key, _value| %w[expected_digest confirmation_phrase].include?(key) }
      return blocked("Restore preview changed; review the fresh plan.") unless secure_equal?(digest(plan), expected_digest)
      source = File.join(@quarantine_root, quarantine_id.to_s)
      destination = target_for(plan.fetch("destination"), allow_missing: true)
      raise BoundaryViolation, "original destination is no longer empty" if File.exist?(destination) || File.symlink?(destination)
      move_no_overwrite(source, destination)
      begin
        restored_checksum = sha256_file(destination)
        raise BoundaryViolation, "restored checksum does not match quarantine evidence" unless secure_equal?(restored_checksum, plan.fetch("sha256"))
        update_ledger do |ledger|
          entry = ledger.fetch("entries").find { |record| record["quarantine_id"] == quarantine_id.to_s }
          raise BoundaryViolation, "quarantine ledger changed during restore" unless entry && entry["state"] == "quarantined"
          entry["state"] = "restored"
          entry["restored_at"] = @clock.call.iso8601(6)
        end
      rescue StandardError
        move_no_overwrite(destination, source) if File.exist?(destination) && !File.exist?(source)
        raise
      end
      receipt = write_receipt(plan.merge("operation" => "restore", "restored_at" => @clock.call.iso8601(6)))
      complete({ "quarantine_id" => quarantine_id.to_s, "destination" => plan.fetch("destination"), "sha256" => restored_checksum, "receipt_id" => receipt }, "Quarantined file restored and verified.", mutation: "restore")
    rescue AwaitingInput => error
      awaiting(error.message)
    rescue BoundaryViolation => error
      blocked(error.message)
    rescue StandardError => error
      failed("Restore failed safely: #{error.class}")
    end

    private

    def configured_roots
      raw = @process_env.fetch(ROOTS_ENV, "").to_s.strip
      return {} if raw.empty?
      entries = raw.split(";", -1)
      raise AwaitingInput, "#{ROOTS_ENV} must declare at most #{MAX_ROOTS} roots" unless entries.length.between?(1, MAX_ROOTS)
      entries.each_with_object({}) do |entry, roots|
        root_id, path = entry.split("=", 2).map { |value| value.to_s.strip }
        raise AwaitingInput, "File Steward roots must use root_id=path" if root_id.empty? || path.empty?
        raise AwaitingInput, "File Steward root ID is invalid: #{root_id}" unless root_id.match?(ROOT_ID)
        raise AwaitingInput, "File Steward root ID is duplicated: #{root_id}" if roots.key?(root_id)
        roots[root_id] = File.expand_path(path, @project_root)
      end
    end

    def resolve_target(root_id, relative_path, allow_root: false)
      id = root_id.to_s.strip
      roots = configured_roots
      raise AwaitingInput, "No File Steward roots are configured" if roots.empty?
      raise AwaitingInput, "unknown File Steward root #{id}" unless roots.key?(id)
      root = roots.fetch(id)
      validate_root!(root)
      clean = normalize_relative_path(relative_path, allow_root: allow_root)
      target = clean == "." ? root : File.expand_path(clean, root)
      prefix = "#{root.delete_suffix(File::SEPARATOR)}#{File::SEPARATOR}"
      raise BoundaryViolation, "requested path escapes the configured root" unless target == root || target.start_with?(prefix)
      validate_target_ancestry!(root, clean)
      [root, clean, target]
    end

    def resolve_regular_file(root_id, relative_path)
      root, clean, target = resolve_target(root_id, relative_path)
      stat = safe_lstat(target)
      raise AwaitingInput, "source file does not exist" unless stat
      raise BoundaryViolation, "File Steward operations require one regular file" unless stat.file? && !stat.symlink?
      [root, clean, target]
    end

    def build_operation_plan(action, source_root_id, source_relative_path, destination_root_id, destination_relative_path)
      normalized_action = action.to_s.strip
      raise AwaitingInput, "action must be rename, move, or copy" unless ACTIONS.include?(normalized_action)
      source_root, source_clean, source = resolve_regular_file(source_root_id, source_relative_path)
      destination_root, destination_clean, destination = resolve_target(destination_root_id, destination_relative_path)
      validate_source!(source)
      raise BoundaryViolation, "destination must not be a configured root" if destination == destination_root
      raise BoundaryViolation, "source and destination must differ" if source == destination
      raise BoundaryViolation, "destination already exists" if File.exist?(destination) || File.symlink?(destination)
      parent = File.dirname(destination)
      parent_stat = safe_lstat(parent)
      raise AwaitingInput, "destination directory does not exist" unless parent_stat&.directory?
      raise BoundaryViolation, "destination directory must not be a symbolic link" if parent_stat.symlink?
      if normalized_action == "rename"
        raise BoundaryViolation, "rename must remain within one configured root and directory" unless source_root == destination_root && File.dirname(source_clean) == File.dirname(destination_clean)
      end
      if %w[rename move].include?(normalized_action)
        raise BoundaryViolation, "move requires source and destination on one filesystem" unless File.stat(source).dev == parent_stat.dev
      end
      if normalized_action == "copy" && File.stat(source).size > MAX_COPY_BYTES
        raise BoundaryViolation, "copy exceeds the #{MAX_COPY_BYTES}-byte A1 limit"
      end
      {
        "operation" => "file_steward",
        "action" => normalized_action,
        "source" => { "root_id" => source_root_id.to_s, "relative_path" => source_clean },
        "destination" => { "root_id" => destination_root_id.to_s, "relative_path" => destination_clean },
        "source_fingerprint" => fingerprint(source),
        "destination_absent" => true,
        "limits" => { "copy_bytes" => MAX_COPY_BYTES, "copy_timeout_seconds" => COPY_TIMEOUT_SECONDS },
        "overwrite" => false,
        "permanent_delete" => false
      }
    end

    def validate_source!(path)
      stat = safe_lstat(path)
      raise AwaitingInput, "source file does not exist" unless stat
      raise BoundaryViolation, "source must be a regular non-symlink file" unless stat.file? && !stat.symlink?
      raise BoundaryViolation, "hard-linked files are outside the A1 mutation boundary" unless stat.nlink == 1
      raise BoundaryViolation, "source is not readable" unless stat.readable?
    end

    def execute_move(source, destination, expected_fingerprint)
      validate_unchanged!(source, expected_fingerprint)
      move_no_overwrite(source, destination)
      raise BoundaryViolation, "move verification failed" if File.exist?(source) || !File.file?(destination)
      destination_fingerprint = fingerprint(destination)
      raise BoundaryViolation, "moved file identity changed unexpectedly" unless destination_fingerprint.slice("device", "inode", "bytes", "mtime_ns") == expected_fingerprint.slice("device", "inode", "bytes", "mtime_ns")
      { "source_absent" => true, "destination_present" => true, "destination_fingerprint" => destination_fingerprint }
    end

    def execute_copy(source, destination, expected_fingerprint)
      validate_unchanged!(source, expected_fingerprint)
      temporary = File.join(File.dirname(destination), ".soul-file-steward-#{SecureRandom.hex(8)}.tmp")
      started = @monotonic_clock.call
      source_digest = Digest::SHA256.new
      bytes = 0
      source_flags = File::RDONLY
      source_flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
      File.open(source, source_flags) do |input|
        File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, expected_fingerprint.fetch("mode")) do |output|
          while (chunk = input.read(1024 * 1024))
            raise BoundaryViolation, "copy exceeded the #{COPY_TIMEOUT_SECONDS}-second A1 limit" if @monotonic_clock.call - started > COPY_TIMEOUT_SECONDS
            output.write(chunk)
            source_digest.update(chunk)
            bytes += chunk.bytesize
            raise BoundaryViolation, "copy exceeded the #{MAX_COPY_BYTES}-byte A1 limit" if bytes > MAX_COPY_BYTES
          end
          output.flush
          output.fsync
        end
      end
      validate_unchanged!(source, expected_fingerprint)
      raise BoundaryViolation, "copied byte count changed" unless bytes == expected_fingerprint.fetch("bytes")
      move_no_overwrite(temporary, destination)
      destination_digest = sha256_file(destination, max_bytes: MAX_COPY_BYTES, timeout_seconds: COPY_TIMEOUT_SECONDS)
      raise BoundaryViolation, "copied checksum verification failed" unless secure_equal?(destination_digest, source_digest.hexdigest)
      { "source_present" => true, "destination_present" => true, "bytes" => bytes, "sha256" => destination_digest }
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
    end

    def validate_unchanged!(path, expected)
      current = fingerprint(path)
      raise BoundaryViolation, "source changed after preview" unless current == expected
    end

    def move_no_overwrite(source, destination)
      File.link(source, destination)
      begin
        File.unlink(source)
      rescue StandardError
        File.unlink(destination) if File.exist?(destination)
        raise
      end
      true
    rescue Errno::EEXIST
      raise BoundaryViolation, "destination already exists"
    end

    def fingerprint(path)
      stat = File.lstat(path)
      {
        "device" => stat.dev,
        "inode" => stat.ino,
        "bytes" => stat.size,
        "mtime_ns" => (stat.mtime.to_r * 1_000_000_000).to_i,
        "mode" => stat.mode & 0o777,
        "links" => stat.nlink
      }
    end

    def target_for(reference, allow_missing: false)
      _root, _clean, target = resolve_target(reference.fetch("root_id"), reference.fetch("relative_path"))
      unless allow_missing
        raise AwaitingInput, "referenced file is unavailable" unless File.exist?(target)
      end
      target
    end

    def normalize_relative_path(relative_path, allow_root: false)
      text = relative_path.to_s.strip
      raise AwaitingInput, "relative path is required" if text.empty?
      raise BoundaryViolation, "relative path exceeds #{MAX_PATH_BYTES} bytes" if text.bytesize > MAX_PATH_BYTES
      raise BoundaryViolation, "relative path must be valid UTF-8" unless text.valid_encoding?
      raise BoundaryViolation, "relative path must not contain NUL bytes" if text.include?("\0")
      raise BoundaryViolation, "relative path must not be absolute" if Pathname.new(text).absolute?
      raise BoundaryViolation, "relative path must use forward slashes" if text.include?("\\")
      clean = Pathname.new(text).cleanpath.to_s
      raise BoundaryViolation, "relative path escapes the configured root" if clean == ".." || clean.start_with?("../")
      raise BoundaryViolation, "root mutation is unavailable" if clean == "." && !allow_root
      clean.split("/").each do |segment|
        next if segment == "."
        raise BoundaryViolation, "hidden or secret-shaped paths are outside File Steward authority" if prohibited_segment?(segment)
      end
      clean
    end

    def prohibited_segment?(segment)
      segment.start_with?(".") || segment.match?(SECRET_FILENAMES) || SECRET_EXTENSIONS.include?(File.extname(segment).downcase)
    end

    def validate_root!(root)
      raise BoundaryViolation, "configured root must be an existing directory" unless File.directory?(root)
      validate_no_symlink_components!(root)
      stat = File.lstat(root)
      raise BoundaryViolation, "configured root must be a non-symlink directory" unless stat.directory? && !stat.symlink?
    rescue Errno::EACCES, Errno::ENOENT
      raise BoundaryViolation, "configured root is unavailable"
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
      cursor = File::SEPARATOR
      File.expand_path(path).split(File::SEPARATOR).reject(&:empty?).each do |segment|
        cursor = File.join(cursor, segment)
        next unless File.exist?(cursor) || File.symlink?(cursor)
        raise BoundaryViolation, "configured root traverses a symbolic link" if File.lstat(cursor).symlink?
      end
    end

    def safe_lstat(path)
      File.lstat(path)
    rescue Errno::ENOENT
      nil
    rescue Errno::EACCES
      raise BoundaryViolation, "requested path is not accessible"
    end

    def metadata(name, stat)
      { "name" => name, "type" => stat.directory? ? "directory" : "file", "bytes" => stat.file? ? stat.size : nil, "modified_at" => stat.mtime.utc.iso8601(6), "writable" => stat.writable? }.compact
    end

    def ensure_private_directory(path)
      FileUtils.mkdir_p(path, mode: 0o700)
      File.chmod(0o700, path)
      path
    end

    def load_ledger
      return { "schema_version" => "soul.file-steward.quarantine.v1", "entries" => [] } unless File.exist?(@ledger_path)
      parsed = JSON.parse(File.binread(@ledger_path, 2 * 1024 * 1024))
      raise BoundaryViolation, "quarantine ledger schema is unsupported" unless parsed["schema_version"] == "soul.file-steward.quarantine.v1" && parsed["entries"].is_a?(Array)
      parsed
    end

    def update_ledger
      ledger = load_ledger
      yield ledger
      atomic_private_json(@ledger_path, ledger)
    end

    def quarantine_entry(quarantine_id)
      id = quarantine_id.to_s
      raise AwaitingInput, "quarantine ID is invalid" unless id.match?(QUARANTINE_ID)
      load_ledger.fetch("entries").find { |entry| entry["quarantine_id"] == id }
    end

    def validate_quarantine_source!(path, entry)
      stat = safe_lstat(path)
      raise AwaitingInput, "quarantined file is unavailable" unless stat&.file? && !stat.symlink?
      raise BoundaryViolation, "quarantined file fingerprint changed" unless fingerprint(path) == entry.fetch("quarantine_fingerprint")
      raise BoundaryViolation, "quarantined file checksum changed" unless secure_equal?(sha256_file(path), entry.fetch("sha256"))
    end

    def write_receipt(payload)
      receipt_id = "receipt_#{@clock.call.utc.strftime('%Y%m%dT%H%M%S')}_#{SecureRandom.hex(6)}"
      path = File.join(ensure_private_directory(@receipt_root), "#{receipt_id}.json")
      atomic_private_json(path, { "schema_version" => "soul.file-steward.receipt.v1", "receipt_id" => receipt_id, "payload" => payload })
      receipt_id
    end

    def atomic_private_json(path, payload)
      ensure_private_directory(File.dirname(path))
      temporary = "#{path}.#{SecureRandom.hex(6)}.tmp"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(JSON.pretty_generate(payload))
        file.write("\n")
        file.flush
        file.fsync
      end
      File.rename(temporary, path)
      File.chmod(0o600, path)
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
    end

    def sha256_file(path, max_bytes: MAX_QUARANTINE_BYTES, timeout_seconds: CHECKSUM_TIMEOUT_SECONDS)
      started = @monotonic_clock.call
      bytes = 0
      digest = Digest::SHA256.new
      File.open(path, "rb") do |file|
        while (chunk = file.read(1024 * 1024))
          raise BoundaryViolation, "checksum exceeded the #{timeout_seconds}-second limit" if @monotonic_clock.call - started > timeout_seconds
          bytes += chunk.bytesize
          raise BoundaryViolation, "checksum exceeded the #{max_bytes}-byte limit" if bytes > max_bytes
          digest.update(chunk)
        end
      end
      digest.hexdigest
    end

    def digest(payload)
      Digest::SHA256.hexdigest(JSON.generate(canonical(payload)))
    end

    def canonical(value)
      case value
      when Hash then value.keys.sort.each_with_object({}) { |key, result| result[key] = canonical(value[key]) }
      when Array then value.map { |entry| canonical(entry) }
      else value
      end
    end

    def secure_equal?(left, right)
      a = left.to_s
      b = right.to_s
      return false unless a.bytesize == b.bytesize && !a.empty?
      a.bytes.zip(b.bytes).reduce(0) { |memo, (x, y)| memo | (x ^ y) }.zero?
    end

    def complete(data, message, mutation: "none")
      { "ok" => true, "lifecycle_state" => "complete", "message" => message, "data" => data, "mutation" => mutation, "retrieved_at" => @clock.call.iso8601(6) }
    end

    def awaiting(message)
      { "ok" => false, "lifecycle_state" => "awaiting_input", "message" => message, "data" => {}, "mutation" => "none", "retrieved_at" => @clock.call.iso8601(6) }
    end

    def blocked(message)
      { "ok" => false, "lifecycle_state" => "blocked_for_human_review", "message" => message, "data" => {}, "mutation" => "none", "retrieved_at" => @clock.call.iso8601(6) }
    end

    def failed(message)
      { "ok" => false, "lifecycle_state" => "failed", "message" => message, "data" => {}, "mutation" => "none", "retrieved_at" => @clock.call.iso8601(6) }
    end
  end
end
