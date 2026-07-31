#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require "time"

require_relative "../lib/soul_core/application_facade"
require_relative "../lib/soul_core/backup_administration_service"
require_relative "../lib/soul_core/bounded_command_runner"

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

class CrucibleBackupRunner
  attr_reader :calls
  attr_accessor :target_identity

  def initialize(mount:, source_root:, local_repository:)
    @mount = mount
    @source_root = source_root
    @local_repository = local_repository
    @target_identity = "directory,souladmin,700\n"
    @calls = []
    @initialized = false
    @source = %w[a b].map.with_index do |letter, index|
      {"id" => letter * 64, "time" => Time.utc(2026, 7, 27 + index).iso8601, "hostname" => "atelier", "paths" => [source_root], "tags" => ["soul-state"]}
    end
    @remote = []
  end

  def which(name) = %w[restic ssh].include?(name) ? "/usr/bin/#{name}" : nil

  def run(*command, **options)
    argv = command.flatten.map(&:to_s)
    @calls << {"argv" => argv, "env" => options[:env]&.transform_values { |value| value&.dup }, "timeout" => options[:timeout_seconds]}
    return result(@target_identity) if argv.first == "ssh"
    return result(JSON.generate("filesystems" => [{"target" => @mount, "source" => "/dev/test", "fstype" => "ext4", "options" => "rw,nodev"}])) if argv.first == "findmnt"
    return failure(1, "unexpected command") unless argv.first == "restic"

    repository = argv[argv.index("--repo") + 1]
    action = argv[argv.index("--repo") + 2]
    remote = repository.start_with?("sftp:")
    return failure(10, "repository does not exist") if remote && !@initialized && action != "init"
    case action
    when "init"
      @initialized = true
      result("{}")
    when "snapshots"
      result(JSON.generate(remote ? @remote : @source))
    when "copy"
      @remote = @source.map.with_index do |snapshot, index|
        snapshot.merge("id" => (index.zero? ? "c" : "d") * 64, "original" => snapshot.fetch("id"))
      end
      result("copied")
    when "check"
      result("verified")
    when "cat"
      result(JSON.generate("id" => "e" * 64))
    else
      failure(1, "unsupported")
    end
  end

  private

  def result(stdout)
    SoulCore::BoundedCommandRunner::Result.new(stdout: stdout, stderr: "", exit_status: 0, status: "ok", truncated: false)
  end

  def failure(code, stderr)
    SoulCore::BoundedCommandRunner::Result.new(stdout: "", stderr: stderr, exit_status: code, status: "failed", truncated: false)
  end
end

puts "Crucible Backup Replication A2 verification:"

Dir.mktmpdir("soul-crucible-copy-") do |root|
  mount = File.join(root, "backup")
  repository = File.join(mount, "restic")
  state = File.join(root, "Soul", "private", "backup")
  source = File.join(root, "source")
  FileUtils.mkdir_p(repository)
  FileUtils.mkdir_p(state)
  FileUtils.mkdir_p(source)
  File.chmod(0o700, state)
  File.write(File.join(repository, "config"), "local encrypted config")
  File.write(File.join(state, "sources.txt"), "#{source}\n")
  File.write(File.join(state, "excludes.txt"), "#{state}/restores/**\n")
  ssh_config = File.join(root, "ssh_config")
  File.write(ssh_config, "Host crucible-maintenance\n  HostName fixture.invalid\n")
  File.chmod(0o600, ssh_config)
  runner = CrucibleBackupRunner.new(mount: mount, source_root: source, local_repository: repository)
  password = "one-request-secret"
  service = SoulCore::BackupAdministrationService.new(
    root: root, home: root, runner: runner, clock: -> { Time.utc(2026, 7, 29) },
    id_generator: -> { "0123456789abcdef" },
    process_env: {"SOUL_BACKUP_MOUNT" => mount, "SOUL_BACKUP_REPOSITORY" => repository, "SOUL_BACKUP_REPLICA_SSH_CONFIG" => ssh_config}
  )

  locked = service.status
  check.call("locked status verifies only the fixed target and retains no password",
             locked.dig("data", "replica", "state") == "locked" &&
               locked.dig("data", "replica", "password_retained") == false &&
               runner.calls.none? { |call| call["argv"].include?("snapshots") })

  preview = service.replica_preview(password: password)
  check.call("preview binds initialization, all source snapshots, no deletion, and no retry",
             preview["ok"] && preview.dig("data", "initialize_target") == true &&
               preview.dig("data", "missing_snapshot_ids") == ["a" * 64, "b" * 64] &&
               preview.dig("data", "remote_deletion") == false &&
               preview.dig("data", "automatic_retry") == false)

  denied = service.replica_execute(password: password, confirmation: "yes", expected_digest: preview.dig("data", "expected_digest"))
  check.call("wrong authority cannot initialize or copy", denied["lifecycle_state"] == "awaiting_input" &&
             runner.calls.none? { |call| call["argv"].include?("init") || call["argv"].include?("copy") })

  completed = service.replica_execute(
    password: password, confirmation: preview.dig("data", "confirmation_phrase"),
    expected_digest: preview.dig("data", "expected_digest")
  )
  check.call("approved gate initializes, copies, verifies, proves coverage, and records one receipt",
             completed["ok"] && completed["mutation"] == "backup_replica_verified" &&
               completed.dig("data", "target_snapshot_count") == 2 &&
               completed.dig("data", "source_snapshot_ids") == ["a" * 64, "b" * 64] &&
               completed.dig("data", "destination_snapshot_ids") == ["c" * 64, "d" * 64] &&
               completed.dig("data", "destination_snapshot_lineage_ids") == ["a" * 64, "b" * 64] &&
               runner.calls.any? { |call| call["argv"].include?("init") } &&
               runner.calls.any? { |call| call["argv"].include?("copy") } &&
               runner.calls.any? { |call| call["argv"].include?("check") })

  reconciled = service.replica_preview(password: password)
  check.call("post-copy preview recognizes destination IDs through preserved original lineage",
             reconciled["ok"] && reconciled.dig("data", "target_snapshot_ids") == ["c" * 64, "d" * 64] &&
               reconciled.dig("data", "target_snapshot_lineage_ids") == ["a" * 64, "b" * 64] &&
               reconciled.dig("data", "missing_snapshot_ids") == [])

  runner.target_identity = "directory,root,755\n"
  unsafe = service.replica_preview(password: password)
  check.call("changed target owner or mode blocks before mutation", unsafe["lifecycle_state"] == "awaiting_input")

  persisted = Dir.glob(File.join(state, "**", "*")).select { |path| File.file?(path) }.map { |path| File.binread(path) }.join
  argv = runner.calls.flat_map { |call| call["argv"] }.join(" ")
  child_secrets = runner.calls.select { |call| call["argv"].first == "restic" }.all? do |call|
    call.dig("env", "RESTIC_PASSWORD") == password &&
      (!call["argv"].include?("copy") || call.dig("env", "RESTIC_FROM_PASSWORD") == password)
  end
  check.call("password exists only in bounded restic child environments", child_secrets && !argv.include?(password) && !persisted.include?(password))

  facade = SoulCore::ApplicationFacade.new(root: root, backup_administration_service: service)
  envelope = facade.call({
    "schema_version" => "soul.application.v1", "request_id" => "replica-test-0001",
    "operation" => "backup.replica.preview", "parameters" => {"password" => password},
    "context" => {"interface" => "dashboard_test"}
  })
  check.call("application contract exposes the bounded replica preview", %w[complete awaiting_input].include?(envelope["lifecycle_state"]))
end

html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
javascript = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
http = File.read(File.expand_path("../lib/soul_core/dashboard_http_application.rb", __dir__))
service_source = File.read(File.expand_path("../lib/soul_core/backup_administration_service.rb", __dir__))
check.call("Dashboard exposes one request-bound initialize/copy/verify gate",
           %w[backup-replica-state preview-backup-replica execute-backup-replica backup-replica-progress].all? { |id| html.include?("id=\"#{id}\"") } &&
             javascript.include?('backupOperation("replica.preview")') &&
             javascript.include?('backupOperation("replica.execute")') &&
             http.include?("backup.replica.execute"))
check.call("replica flow contains no forget, prune, scheduler, or background retry",
           !service_source[/def replica_preview.*?def retention_preview/m].to_s.match?(/forget|prune|cron|timer|sleep/i))

abort(errors.map { |error| "- #{error}" }.join("\n")) unless errors.empty?
puts "Crucible Backup Replication A2 is candidate-ready for human review."
