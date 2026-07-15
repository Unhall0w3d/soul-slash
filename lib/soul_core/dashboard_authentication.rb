# frozen_string_literal: true

require "base64"
require "digest"
require "json"
require "openssl"
require "securerandom"
require "time"

module SoulCore
  class DashboardAuthentication
    class CredentialError < StandardError; end

    Result = Struct.new(:ok, :status, :code, :reason, :token, :session, :retry_after, keyword_init: true)

    USERNAME = "admin"
    BOOTSTRAP_PASSWORD = "soul123"
    CREDENTIAL_PATH = "Soul/runtime/dashboard_auth/credentials.json"
    PBKDF2_ITERATIONS = 600_000
    HASH_LENGTH = 32
    SALT_LENGTH = 16
    MIN_PASSWORD_CHARACTERS = 12
    MAX_PASSWORD_CHARACTERS = 128
    SESSION_IDLE_SECONDS = 12 * 60 * 60
    SESSION_ABSOLUTE_SECONDS = 24 * 60 * 60
    MAX_SESSIONS = 32
    FAILED_ATTEMPT_LIMIT = 5
    FAILED_ATTEMPT_WINDOW_SECONDS = 5 * 60

    attr_reader :credential_path

    def initialize(root:, credential_path: CREDENTIAL_PATH, iterations: PBKDF2_ITERATIONS,
                   clock: -> { Time.now.utc }, random_bytes: ->(count) { SecureRandom.random_bytes(count) }, reset_to_bootstrap: false)
      @root = File.expand_path(root)
      @credential_path = expand_below_root(credential_path)
      @iterations = Integer(iterations)
      raise ArgumentError, "PBKDF2 iterations must be positive" unless @iterations.positive?

      @clock = clock
      @random_bytes = random_bytes
      @sessions = {}
      @failed_attempts = []
      if reset_to_bootstrap
        raise CredentialError, "dashboard credential path must not be a symlink" if File.symlink?(@credential_path)
        write_credential(password: BOOTSTRAP_PASSWORD, password_change_required: true)
      else
        ensure_credentials!
      end
    end

    def authenticate(username:, password:)
      now = now_f
      prune_failed_attempts(now)
      if @failed_attempts.length >= FAILED_ATTEMPT_LIMIT
        retry_after = [(FAILED_ATTEMPT_WINDOW_SECONDS - (now - @failed_attempts.first)).ceil, 1].max
        return Result.new(ok: false, status: 429, code: "rate_limited", reason: "Too many failed login attempts. Try again later.", retry_after: retry_after)
      end

      supplied_username = bounded_string(username, 64)
      supplied_password = bounded_string(password, MAX_PASSWORD_CHARACTERS * 4)
      valid_password = password_matches?(supplied_password)
      valid_username = secure_compare(supplied_username, USERNAME)
      unless valid_username && valid_password
        @failed_attempts << now
        return Result.new(ok: false, status: 401, code: "invalid_credentials", reason: "Invalid username or password.")
      end

      @failed_attempts.clear
      token, session = issue_session(now)
      Result.new(ok: true, status: 200, token: token, session: public_session(session))
    end

    def session(token, touch: true)
      now = now_f
      credential
      prune_sessions(now)
      digest = token_digest(token)
      return nil unless digest

      record = @sessions[digest]
      return nil unless record

      record["last_seen_at"] = now if touch
      public_session(record)
    end

    def change_password(token:, current_password:, new_password:, confirmation:)
      current_session = session(token, touch: false)
      return Result.new(ok: false, status: 401, code: "authentication_required", reason: "A valid dashboard session is required.") unless current_session

      current = bounded_string(current_password, MAX_PASSWORD_CHARACTERS * 4)
      replacement = bounded_string(new_password, MAX_PASSWORD_CHARACTERS * 4)
      confirmation_value = bounded_string(confirmation, MAX_PASSWORD_CHARACTERS * 4)
      return Result.new(ok: false, status: 401, code: "invalid_current_password", reason: "The current password is incorrect.") unless password_matches?(current)
      return Result.new(ok: false, status: 422, code: "password_confirmation", reason: "The new password and confirmation do not match.") unless secure_compare(replacement, confirmation_value)

      policy_error = password_policy_error(replacement, current)
      return Result.new(ok: false, status: 422, code: "password_policy", reason: policy_error) if policy_error

      write_credential(password: replacement, password_change_required: false)
      @sessions.clear
      token_value, new_session = issue_session(now_f)
      Result.new(ok: true, status: 200, token: token_value, session: public_session(new_session))
    end

    def logout(token)
      digest = token_digest(token)
      @sessions.delete(digest) if digest
      Result.new(ok: true, status: 200)
    end

    def reset_to_bootstrap!
      write_credential(password: BOOTSTRAP_PASSWORD, password_change_required: true)
      @sessions.clear
      @failed_attempts.clear
      true
    end

    def password_change_required?
      credential.fetch("password_change_required")
    end

    private

    def expand_below_root(path)
      expanded = File.expand_path(path, @root)
      prefix = @root.end_with?(File::SEPARATOR) ? @root : "#{@root}#{File::SEPARATOR}"
      raise ArgumentError, "credential path must remain below project root" unless expanded.start_with?(prefix)

      expanded
    end

    def ensure_credentials!
      if File.exist?(@credential_path) || File.symlink?(@credential_path)
        cache_credential(load_credential)
      else
        write_credential(password: BOOTSTRAP_PASSWORD, password_change_required: true)
      end
    end

    def credential
      current = credential_fingerprint
      if @credential.nil? || @credential_fingerprint != current
        @sessions.clear if @credential
        @failed_attempts.clear if @credential
        cache_credential(load_credential)
      end
      @credential
    end

    def cache_credential(value)
      @credential = value
      @credential_fingerprint = credential_fingerprint
      @credential
    end

    def credential_fingerprint
      stat = File.lstat(@credential_path)
      [stat.dev, stat.ino, stat.size, stat.mtime.to_i, stat.mtime.nsec]
    rescue Errno::ENOENT, Errno::EACCES => error
      raise CredentialError, "dashboard credential record cannot be inspected safely: #{error.class}"
    end

    def load_credential
      stat = File.lstat(@credential_path)
      raise CredentialError, "dashboard credential path must be a regular file" unless stat.file? && !stat.symlink?
      raise CredentialError, "dashboard credential file permissions must be owner-only" unless (stat.mode & 0o077).zero?
      raise CredentialError, "dashboard credential file is too large" if stat.size > 16 * 1024

      value = JSON.parse(File.binread(@credential_path))
      required = %w[schema_version username algorithm iterations salt password_hash password_change_required updated_at]
      raise CredentialError, "dashboard credential record is incomplete" unless required.all? { |key| value.key?(key) }
      raise CredentialError, "dashboard credential record has unsupported schema" unless value["schema_version"] == "soul.dashboard.credentials.v1"
      raise CredentialError, "dashboard credential username is invalid" unless value["username"] == USERNAME
      raise CredentialError, "dashboard credential algorithm is invalid" unless value["algorithm"] == "pbkdf2-hmac-sha256"
      raise CredentialError, "dashboard credential iteration count is invalid" unless value["iterations"].is_a?(Integer) && value["iterations"].positive?
      raise CredentialError, "dashboard credential password-change flag is invalid" unless [true, false].include?(value["password_change_required"])
      Base64.strict_decode64(value.fetch("salt"))
      Base64.strict_decode64(value.fetch("password_hash"))
      value.freeze
    rescue Errno::ENOENT, Errno::EACCES, JSON::ParserError, ArgumentError => error
      raise CredentialError, "dashboard credential record cannot be read safely: #{error.class}"
    end

    def write_credential(password:, password_change_required:)
      directory = File.dirname(@credential_path)
      ensure_private_directory(directory)
      File.chmod(0o700, directory)
      salt = @random_bytes.call(SALT_LENGTH)
      record = {
        "schema_version" => "soul.dashboard.credentials.v1",
        "username" => USERNAME,
        "algorithm" => "pbkdf2-hmac-sha256",
        "iterations" => @iterations,
        "salt" => Base64.strict_encode64(salt),
        "password_hash" => Base64.strict_encode64(derive(password, salt, @iterations)),
        "password_change_required" => password_change_required,
        "updated_at" => @clock.call.iso8601
      }
      temporary = "#{@credential_path}.tmp-#{Process.pid}-#{SecureRandom.hex(6)}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(JSON.pretty_generate(record))
        file.write("\n")
        file.flush
        file.fsync
      end
      File.rename(temporary, @credential_path)
      File.chmod(0o600, @credential_path)
      cache_credential(record.freeze)
    ensure
      File.delete(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
    end

    def ensure_private_directory(directory)
      relative = directory.delete_prefix("#{@root}#{File::SEPARATOR}")
      cursor = @root
      relative.split(File::SEPARATOR).each do |component|
        cursor = File.join(cursor, component)
        if File.exist?(cursor) || File.symlink?(cursor)
          stat = File.lstat(cursor)
          raise CredentialError, "dashboard credential directory must not contain symlinks" if stat.symlink?
          raise CredentialError, "dashboard credential directory component is not a directory" unless stat.directory?
        else
          Dir.mkdir(cursor, 0o700)
        end
      end
    end

    def derive(password, salt, iterations)
      OpenSSL::KDF.pbkdf2_hmac(password, salt: salt, iterations: iterations, length: HASH_LENGTH, hash: "SHA256")
    end

    def password_matches?(password)
      salt = Base64.strict_decode64(credential.fetch("salt"))
      expected = Base64.strict_decode64(credential.fetch("password_hash"))
      actual = derive(password, salt, credential.fetch("iterations"))
      secure_compare(actual, expected)
    end

    def password_policy_error(password, current)
      length = password.each_char.count
      return "The new password must be at least #{MIN_PASSWORD_CHARACTERS} characters." if length < MIN_PASSWORD_CHARACTERS
      return "The new password must be no more than #{MAX_PASSWORD_CHARACTERS} characters." if length > MAX_PASSWORD_CHARACTERS
      return "The bootstrap password cannot be reused." if secure_compare(password, BOOTSTRAP_PASSWORD)
      return "The new password must differ from the current password." if secure_compare(password, current)

      nil
    end

    def issue_session(now)
      prune_sessions(now)
      if @sessions.length >= MAX_SESSIONS
        oldest = @sessions.min_by { |_digest, record| record.fetch("last_seen_at") }
        @sessions.delete(oldest.first) if oldest
      end
      begin
        token = Base64.urlsafe_encode64(@random_bytes.call(32), padding: false)
        digest = Digest::SHA256.hexdigest(token)
      end while @sessions.key?(digest)
      record = { "username" => USERNAME, "issued_at" => now, "last_seen_at" => now }
      @sessions[digest] = record
      [token, record]
    end

    def prune_sessions(now)
      @sessions.delete_if do |_digest, record|
        now - record.fetch("last_seen_at") > SESSION_IDLE_SECONDS || now - record.fetch("issued_at") > SESSION_ABSOLUTE_SECONDS
      end
    end

    def prune_failed_attempts(now)
      @failed_attempts.reject! { |attempt| now - attempt >= FAILED_ATTEMPT_WINDOW_SECONDS }
    end

    def public_session(record)
      {
        "authenticated" => true,
        "username" => record.fetch("username"),
        "password_change_required" => password_change_required?
      }
    end

    def token_digest(token)
      return nil unless token.is_a?(String) && token.match?(/\A[A-Za-z0-9_-]{43}\z/)

      Digest::SHA256.hexdigest(token)
    end

    def bounded_string(value, max_bytes)
      string = value.is_a?(String) ? value.dup : ""
      return "" unless string.valid_encoding? && string.bytesize <= max_bytes

      string
    end

    def now_f
      @clock.call.to_f
    end

    def secure_compare(left, right)
      return false unless left.is_a?(String) && right.is_a?(String) && left.bytesize == right.bytesize

      left.bytes.zip(right.bytes).reduce(0) { |memo, (a, b)| memo | (a ^ b) }.zero?
    end
  end
end
