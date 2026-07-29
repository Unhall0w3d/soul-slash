# frozen_string_literal: true

require "json"
require "fileutils"

require_relative "secret_file_command_runner"

module SoulCore
  class BackupCredentialRotationService
    MAX_SNAPSHOTS = 10_000

    def initialize(repositories:, lock_path:, runner: SecretFileCommandRunner.new)
      @repositories = Array(repositories).map { |item| normalize_repository(item) }.freeze
      @lock_path = File.expand_path(lock_path.to_s)
      @runner = runner
      raise ArgumentError, "exactly two backup repositories are required" unless @repositories.length == 2
      raise ArgumentError, "backup repository labels must be unique" unless @repositories.map { |item| item.fetch("label") }.uniq.length == 2
      raise ArgumentError, "backup repository locations must be unique" unless @repositories.map { |item| item.fetch("repository") }.uniq.length == 2
      raise ArgumentError, "backup operation lock path is required" if lock_path.to_s.empty?
    end

    def plan
      complete(
        "Backup credential rotation is ready for local interactive review.",
        {
          "repositories" => @repositories.map { |item| item.slice("label", "repository") },
          "credential_transport" => "inherited anonymous file descriptors",
          "persistent_secret_storage" => false,
          "dashboard_input" => false,
          "automatic_retry" => false,
          "shared_operation_lock" => @lock_path,
          "rollback_on_partial_failure" => true
        }
      )
    end

    def rotate(old_password:, new_password:)
      validate_passwords!(old_password, new_password)
      with_operation_lock do
        perform_rotation(old_password, new_password)
      end
    rescue ArgumentError => error
      awaiting(error.message)
    rescue StandardError => error
      failed("Backup credential rotation failed before mutation.", {"reason" => safe_reason(error)})
    end

    private

    def perform_rotation(old_password, new_password)
      baselines = @repositories.to_h { |repository| [repository.fetch("label"), inventory(repository, old_password)] }
      rotated = []
      @repositories.each do |repository|
        rotate_one(repository, old_password, new_password, baselines.fetch(repository.fetch("label")))
        rotated << repository
      rescue StandardError => error
        affected = rotated.dup
        affected << repository if credential_works?(repository, new_password)
        rollback = affected.uniq.reverse.map do |item|
          rollback_one(item, new_password, old_password, baselines.fetch(item.fetch("label")))
        end
        return failed(
          "Backup credential rotation failed safely; repositories accepting the new password were rolled back.",
          {
            "failed_repository" => repository.fetch("label"),
            "reason" => safe_reason(error),
            "rollback" => rollback,
            "manual_recovery_required" => rollback.any? { |item| !item.fetch("restored") }
          }
        )
      end
      complete(
        "Both backup repository credentials were rotated and verified.",
        {
          "repositories" => @repositories.map do |repository|
            baseline = baselines.fetch(repository.fetch("label"))
            {
              "label" => repository.fetch("label"),
              "snapshot_count" => baseline.fetch("snapshot_ids").length,
              "repository_identity_preserved" => true,
              "old_password_rejected" => true
            }
          end,
          "persistent_secret_storage" => false
        },
        "backup_credentials_rotated"
      )
    end

    def with_operation_lock
      directory = File.dirname(@lock_path)
      FileUtils.mkdir_p(directory, mode: 0o700)
      raise "backup operation lock directory is unsafe" if File.symlink?(directory)
      raise "backup operation lock directory must be owner-only" unless (File.stat(directory).mode & 0o077).zero?
      raise "backup operation lock path is unsafe" if File.symlink?(@lock_path)
      File.open(@lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
        return blocked("Another backup administration operation is active.") unless lock.flock(File::LOCK_EX | File::LOCK_NB)

        yield
      ensure
        lock.flock(File::LOCK_UN) rescue nil
      end
    end

    def normalize_repository(item)
      input = item.to_h.transform_keys(&:to_s)
      label = input.fetch("label").to_s.strip
      repository = input.fetch("repository").to_s.strip
      raise ArgumentError, "backup repository label is invalid" unless label.match?(/\A[A-Za-z][A-Za-z0-9 _-]{0,63}\z/)
      raise ArgumentError, "backup repository location is invalid" if repository.empty? || repository.bytesize > 1024 || repository.match?(/[\r\n\0]/)

      {"label" => label, "repository" => repository}
    end

    def validate_passwords!(old_password, new_password)
      old_value = old_password.to_s
      new_value = new_password.to_s
      raise ArgumentError, "current repository password is required" if old_value.empty?
      raise ArgumentError, "new repository password must contain at least 16 characters" if new_value.length < 16
      raise ArgumentError, "repository passwords cannot exceed 512 bytes" if old_value.bytesize > 512 || new_value.bytesize > 512
      raise ArgumentError, "repository passwords cannot contain line breaks" if old_value.match?(/[\r\n]/) || new_value.match?(/[\r\n]/)
      raise ArgumentError, "new repository password must differ from the current password" if secure_equal?(old_value, new_value)
    end

    def inventory(repository, password)
      config = restic(repository, password, "cat", "config")
      raise "repository configuration could not be read" unless config.success?
      config_json = parse_json(config.stdout, Hash, "repository configuration")
      repository_id = config_json.fetch("id").to_s
      raise "repository identity is invalid" unless repository_id.match?(/\A[0-9a-f]{64}\z/)

      keys = restic(repository, password, "--json", "key", "list")
      raise "repository key inventory could not be read" unless keys.success?
      key_json = parse_json(keys.stdout, Array, "repository key inventory")
      raise "repository must contain exactly one access key before rotation" unless key_json.length == 1
      raise "repository key inventory has no current key" unless key_json.first["current"] == true

      snapshots = restic(repository, password, "--json", "snapshots", "--tag", "soul")
      raise "repository snapshot inventory could not be read" unless snapshots.success?
      snapshot_json = parse_json(snapshots.stdout, Array, "repository snapshot inventory")
      raise "repository snapshot inventory exceeds limit" if snapshot_json.length > MAX_SNAPSHOTS
      snapshot_ids = snapshot_json.map { |item| item.fetch("id").to_s }
      raise "repository snapshot inventory contains an invalid ID" unless snapshot_ids.all? { |id| id.match?(/\A[0-9a-f]{64}\z/) } && snapshot_ids.uniq.length == snapshot_ids.length

      {"repository_id" => repository_id, "snapshot_ids" => snapshot_ids.sort}
    rescue KeyError, JSON::ParserError
      raise "repository evidence is malformed"
    end

    def rotate_one(repository, old_password, new_password, baseline)
      changed = restic(repository, old_password, "key", "passwd", "--new-password-file", "/proc/self/fd/4", new_password: new_password)
      raise "repository password change was rejected" unless changed.success?
      verify_inventory!(repository, new_password, baseline)
      raise "old repository password still opens the repository" if credential_works?(repository, old_password)
      true
    end

    def rollback_one(repository, current_password, restored_password, baseline)
      changed = restic(repository, current_password, "key", "passwd", "--new-password-file", "/proc/self/fd/4", new_password: restored_password)
      verified = changed.success? && begin
        verify_inventory!(repository, restored_password, baseline)
        !credential_works?(repository, current_password)
      rescue StandardError
        false
      end
      {"repository" => repository.fetch("label"), "restored" => verified}
    rescue StandardError
      {"repository" => repository.fetch("label"), "restored" => false}
    end

    def verify_inventory!(repository, password, baseline)
      current = inventory(repository, password)
      raise "repository identity changed during password rotation" unless current.fetch("repository_id") == baseline.fetch("repository_id")
      raise "repository snapshot inventory changed during password rotation" unless current.fetch("snapshot_ids") == baseline.fetch("snapshot_ids")
      true
    end

    def credential_works?(repository, password)
      restic(repository, password, "cat", "config").success?
    end

    def restic(repository, password, *arguments, new_password: nil)
      @runner.run(
        "restic", "--no-cache", "--repo", repository.fetch("repository"),
        "--password-file", "/proc/self/fd/3", *arguments,
        password: password, new_password: new_password,
        timeout_seconds: arguments.include?("passwd") ? 180 : 60
      )
    end

    def parse_json(text, type, label)
      value = JSON.parse(text)
      raise "#{label} is invalid" unless value.is_a?(type)

      value
    end

    def secure_equal?(left, right)
      return false unless left.bytesize == right.bytesize
      left.bytes.zip(right.bytes).reduce(0) { |memo, pair| memo | (pair[0] ^ pair[1]) }.zero?
    end

    def safe_reason(error)
      error.message.to_s.gsub(/[^\w .,:;()-]/, "?")[0, 240]
    end

    def complete(message, data, mutation = "none")
      {"ok" => true, "lifecycle_state" => "complete", "message" => message, "data" => data, "mutation" => mutation}
    end

    def awaiting(message)
      {"ok" => false, "lifecycle_state" => "awaiting_input", "message" => message, "data" => {}, "mutation" => "none"}
    end

    def failed(message, data)
      {"ok" => false, "lifecycle_state" => "failed", "message" => message, "data" => data, "mutation" => "none"}
    end

    def blocked(message)
      {"ok" => false, "lifecycle_state" => "blocked_for_human_review", "message" => message, "data" => {}, "mutation" => "none"}
    end
  end
end
