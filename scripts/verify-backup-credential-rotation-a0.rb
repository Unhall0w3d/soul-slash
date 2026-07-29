#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"

require_relative "../lib/soul_core/backup_credential_rotation_service"
require_relative "../lib/soul_core/secret_file_command_runner"

class FailSecondPasswordChangeRunner
  attr_reader :commands

  def initialize
    @delegate = SoulCore::SecretFileCommandRunner.new
    @commands = []
    @password_change_count = 0
  end

  def run(*command, **options)
    argv = command.flatten.map(&:to_s)
    @commands << argv
    if argv.include?("passwd")
      @password_change_count += 1
      if @password_change_count == 2
        return SoulCore::SecretFileCommandRunner::Result.new(
          stdout: "", exit_status: 1, status: "failed", truncated: false
        )
      end
    end
    @delegate.run(*command, **options)
  end
end

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'FAIL'}"
  errors << label unless condition
end

puts "Backup Credential Rotation A0 verification:"
Dir.mktmpdir("soul-backup-rotation-") do |directory|
  repositories = %w[local replica].map { |name| {"label" => name.capitalize, "repository" => File.join(directory, name)} }
  old_password = "fixture-old-password-123"
  new_password = "fixture-new-password-456"
  runner = SoulCore::SecretFileCommandRunner.new
  repositories.each do |repository|
    result = runner.run(
      "restic", "--no-cache", "--repo", repository.fetch("repository"),
      "--password-file", "/proc/self/fd/3", "init", "--quiet",
      password: old_password
    )
    raise "fixture repository initialization failed" unless result.success?
  end

  lock_path = File.join(directory, "operation.lock")
  service = SoulCore::BackupCredentialRotationService.new(
    repositories: repositories, lock_path: lock_path, runner: runner
  )
  plan = service.plan
  check.call("plan names both repositories without requesting a password",
             plan.fetch("ok") && plan.dig("data", "repositories").length == 2 &&
             plan.dig("data", "persistent_secret_storage") == false)

  too_short = service.rotate(old_password: old_password, new_password: "short")
  check.call("short replacement password cannot mutate a repository",
             too_short["lifecycle_state"] == "awaiting_input")

  result = service.rotate(old_password: old_password, new_password: new_password)
  check.call("both independently encrypted repositories rotate successfully",
             result.fetch("ok") && result.fetch("mutation") == "backup_credentials_rotated" &&
             result.dig("data", "repositories").all? { |item| item.fetch("old_password_rejected") })

  verifier = SoulCore::SecretFileCommandRunner.new
  new_works = repositories.all? do |repository|
    verifier.run(
      "restic", "--no-cache", "--repo", repository.fetch("repository"),
      "--password-file", "/proc/self/fd/3", "cat", "config",
      password: new_password
    ).success?
  end
  old_rejected = repositories.all? do |repository|
    !verifier.run(
      "restic", "--no-cache", "--repo", repository.fetch("repository"),
      "--password-file", "/proc/self/fd/3", "cat", "config",
      password: old_password
    ).success?
  end
  check.call("new password opens both repositories and old password opens neither",
             new_works && old_rejected)

  rollback_password = "fixture-rollback-password-789"
  failure_runner = FailSecondPasswordChangeRunner.new
  failed_service = SoulCore::BackupCredentialRotationService.new(
    repositories: repositories, lock_path: lock_path, runner: failure_runner
  )
  failed_rotation = failed_service.rotate(
    old_password: new_password, new_password: rollback_password
  )
  original_state_restored = repositories.all? do |repository|
    verifier.run(
      "restic", "--no-cache", "--repo", repository.fetch("repository"),
      "--password-file", "/proc/self/fd/3", "cat", "config",
      password: new_password
    ).success? &&
      !verifier.run(
        "restic", "--no-cache", "--repo", repository.fetch("repository"),
        "--password-file", "/proc/self/fd/3", "cat", "config",
        password: rollback_password
      ).success?
  end
  check.call("second-repository failure rolls the first repository back",
             failed_rotation["lifecycle_state"] == "failed" &&
             failed_rotation.dig("data", "rollback").all? { |item| item.fetch("restored") } &&
             original_state_restored)

  File.open(lock_path, File::WRONLY | File::CREAT, 0o600) do |held_lock|
    held_lock.flock(File::LOCK_EX)
    blocked = service.rotate(old_password: new_password, new_password: rollback_password)
    check.call("a concurrent backup administration operation blocks without waiting",
               blocked["lifecycle_state"] == "blocked_for_human_review")
  end

  command_text = (runner.commands + verifier.commands).flatten.join("\n")
  check.call("passwords never enter command arguments",
             !command_text.include?(old_password) && !command_text.include?(new_password) &&
             command_text.include?("/proc/self/fd/3"))

  source = File.read(File.join(__dir__, "soul-backup-credential-rotation"))
  check.call("live wrapper requires an interactive terminal and exact confirmation",
             source.include?("$stdin.tty?") && source.include?("ROTATE_BACKUP_CREDENTIALS") &&
             source.include?("$stdin.noecho") && source.include?("value.replace"))
end

if errors.empty?
  puts "Backup Credential Rotation A0 verification passed."
  exit 0
end

warn "Backup Credential Rotation A0 verification failed: #{errors.join(', ')}"
exit 1
