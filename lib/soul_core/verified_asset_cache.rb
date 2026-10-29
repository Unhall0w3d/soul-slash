# frozen_string_literal: true

require "openssl"
require "thread"

module SoulCore
  # Process-local proof of a full SHA-256 read, never an authorization or a
  # persisted trust stamp. Fresh request services may share this cache without
  # sharing cancellation callbacks, manifests, approvals or compute decisions.
  class VerifiedAssetCache
    class Canceled < StandardError; end
    MAX_ENTRIES = 256
    CHUNK_BYTES = 4 * 1024 * 1024

    def initialize
      @mutex = Mutex.new
      @entries = {}
      @stats = {"full_hashes" => 0, "cache_hits" => 0, "bytes_hashed" => 0, "hash_seconds" => 0.0}
    end

    def verified?(path, bytes:, sha256:, cancel: nil)
      return false unless bytes.is_a?(Integer) && bytes >= 0 && sha256.is_a?(String) && /\A[0-9a-f]{64}\z/.match?(sha256)
      # A caller's mutable manifest string must never rewrite a cached proof.
      sha256 = sha256.dup.freeze
      path = File.expand_path(path)
      check_cancel!(cancel)
      # An fd pins the inode even if a path is replaced mid-check. NONBLOCK
      # prevents a substituted FIFO from hanging before its type is rejected.
      File.open(path, File::RDONLY | File::NOFOLLOW | File::NONBLOCK) do |file|
        identity = current_identity(path, file, bytes)
        return false unless identity
        locked(cancel) do
          return false unless current_identity(path, file, bytes) == identity
          key = [identity, sha256]
          if @entries[path] == key
            check_cancel!(cancel)
            return false unless current_identity(path, file, bytes) == identity
            @stats["cache_hits"] += 1
            return true
          end
          @entries.delete(path)
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @stats["full_hashes"] += 1
          actual = digest_file(file, cancel)
          @stats["hash_seconds"] += Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
          return false unless current_identity(path, file, bytes) == identity && actual == sha256
          @entries.shift if @entries.length >= MAX_ENTRIES
          @entries[path] = key
          true
        end
      end
    rescue SystemCallError, IOError
      false
    end

    def stats = @mutex.synchronize { @stats.dup }

    private

    def check_cancel!(cancel)
      raise Canceled, "Asset verification canceled" if cancel&.call
    end

    def locked(cancel)
      until @mutex.try_lock
        check_cancel!(cancel)
        sleep 0.01
      end
      begin
        check_cancel!(cancel)
        yield
      ensure
        @mutex.unlock
      end
    end

    def current_identity(path, file, bytes)
      stat = File.lstat(path)
      return unless stat.file? && !stat.symlink? && stat.nlink == 1 && stat.size == bytes && File.realpath(path) == path
      identity = fingerprint(stat)
      identity if fingerprint(file.stat) == identity
    end

    def fingerprint(stat)
      [stat.dev, stat.ino, stat.mode, stat.uid, stat.gid, stat.nlink, stat.size, stat.mtime.to_r, stat.ctime.to_r]
    end

    def digest_file(file, cancel)
      hash = OpenSSL::Digest::SHA256.new
      buffer = +""
      while file.read(CHUNK_BYTES, buffer)
        check_cancel!(cancel)
        hash.update(buffer)
        @stats["bytes_hashed"] += buffer.bytesize
      end
      check_cancel!(cancel)
      hash.hexdigest
    end
  end
end
