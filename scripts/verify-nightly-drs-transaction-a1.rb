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

class NightlyDrsRunner
  attr_reader :calls
  attr_accessor :fail_remote_after_backup

  def initialize(mount:, source_root:, local_repository:)
    @mount = mount
    @source_root = source_root
    @local_repository = local_repository
    @calls = []
    @fail_remote_after_backup = false
    @local_backup_created = false
    @local = [
      {
        "id" => "a" * 64, "time" => Time.utc(2026, 7, 28).iso8601,
        "hostname" => "atelier", "paths" => [source_root], "tags" => ["soul-state"]
      }
    ]
    @remote = [
      {
        "id" => "c" * 64, "original" => "a" * 64,
        "time" => Time.utc(2026, 7, 28).iso8601,
        "hostname" => "atelier", "paths" => [source_root], "tags" => ["soul-state"]
      }
    ]
  end

  def which(name) = %w[restic ssh].include?(name) ? "/usr/bin/#{name}" : nil

  def run(*command, **options)
    argv = command.flatten.map(&:to_s)
    @calls << {
      "argv" => argv,
      "env" => options[:env]&.transform_values { |value| value&.dup },
      "timeout" => options[:timeout_seconds]
    }
    return ok(JSON.generate("filesystems" => [{"target" => @mount, "source" => "/dev/fixture", "fstype" => "ext4", "options" => "rw,nodev"}])) if argv.first == "findmnt"
    return ok("4096 #{@source_root}\n") if argv.first == "du"
    return ok("directory,souladmin,700\n") if argv.first == "ssh"
    return failed("unexpected command") unless argv.first == "restic"

    repository = argv[argv.index("--repo") + 1]
    action = argv[argv.index("--repo") + 2]
    remote = repository.start_with?("sftp:")
    return failed("Crucible offline") if remote && @fail_remote_after_backup && @local_backup_created

    case action
    when "snapshots"
      ok(JSON.generate(remote ? @remote : @local))
    when "backup"
      id = "d" * 64
      @local << {
        "id" => id, "time" => Time.utc(2026, 7, 29).iso8601,
        "hostname" => "atelier", "paths" => [@source_root], "tags" => ["soul-state"]
      } unless @local.any? { |record| record["id"] == id }
      @local_backup_created = true
      ok(JSON.generate("message_type" => "summary", "snapshot_id" => id) + "\n")
    when "check"
      ok("verified")
    when "ls"
      id = argv.last
      return failed("missing snapshot") unless @local.any? { |record| record["id"] == id }
      nodes = [@source_root, File.join(@source_root, "state.json")].map { |path| JSON.generate("struct_type" => "node", "path" => path) }
      ok(nodes.join("\n") + "\n")
    when "copy"
      @remote = @local.map.with_index do |record, index|
        record.merge("id" => (index.zero? ? "c" : "e") * 64, "original" => record["id"])
      end
      ok("copied")
    when "cat"
      ok(JSON.generate("id" => (remote ? "f" : "b") * 64))
    else
      failed("unsupported Restic action #{action}")
    end
  end

  private

  def ok(stdout)
    SoulCore::BoundedCommandRunner::Result.new(stdout: stdout, stderr: "", exit_status: 0, status: "ok", truncated: false)
  end

  def failed(stderr)
    SoulCore::BoundedCommandRunner::Result.new(stdout: "", stderr: stderr, exit_status: 1, status: "failed", truncated: false)
  end
end

def fixture
  Dir.mktmpdir("soul-nightly-drs-") do |root|
    mount = File.join(root, "recovery")
    repository = File.join(mount, "restic")
    state_root = File.join(root, "Soul", "private", "backup")
    source_root = File.join(root, "owner-state")
    FileUtils.mkdir_p(repository)
    FileUtils.mkdir_p(state_root)
    FileUtils.mkdir_p(source_root)
    File.chmod(0o700, state_root)
    File.write(File.join(repository, "config"), "encrypted local config\n")
    File.write(File.join(source_root, "state.json"), "{\"state\":true}\n")
    File.write(File.join(state_root, "sources.txt"), "#{source_root}\n")
    File.write(File.join(state_root, "excludes.txt"), "#{File.join(state_root, "restores")}/**\n")
    ssh_config = File.join(root, "ssh_config")
    File.write(ssh_config, "Host crucible-maintenance\n  HostName fixture.invalid\n")
    File.chmod(0o600, ssh_config)
    runner = NightlyDrsRunner.new(mount: mount, source_root: source_root, local_repository: repository)
    password = "fixture-secret-never-persist"
    service = SoulCore::BackupAdministrationService.new(
      root: root,
      home: root,
      process_env: {
        "SOUL_BACKUP_MOUNT" => mount,
        "SOUL_BACKUP_REPOSITORY" => repository,
        "SOUL_BACKUP_REPLICA_REPOSITORY" => "sftp:crucible-maintenance:/srv/soul-backup/restic",
        "SOUL_BACKUP_REPLICA_SSH_ALIAS" => "crucible-maintenance",
        "SOUL_BACKUP_REPLICA_TARGET_PATH" => "/srv/soul-backup/restic",
        "SOUL_BACKUP_REPLICA_OWNER" => "souladmin",
        "SOUL_BACKUP_REPLICA_SSH_CONFIG" => ssh_config
      },
      runner: runner,
      clock: -> { Time.utc(2026, 7, 29, 3, 0, 0) },
      id_generator: -> { "0123456789abcdef" }
    )
    yield root, state_root, runner, service, password
  end
end

puts "Nightly DRS Transaction A1 verification:"

fixture do |root, state_root, runner, service, password|
  preview = service.drs_preview(password: password)
  check.call("preview binds one local capture and one no-delete Crucible reconciliation attempt",
             preview["ok"] &&
               preview.dig("data", "confirmation_phrase") == SoulCore::BackupAdministrationService::DRS_CONFIRMATION &&
               preview.dig("data", "expected_digest").match?(/\A[a-f0-9]{64}\z/) &&
               preview.dig("data", "local_capture", "lifecycle_state") == "complete" &&
               preview.dig("data", "replica_preflight", "lifecycle_state") == "complete" &&
               preview.dig("data", "automatic_retention") == false &&
               preview.dig("data", "remote_deletion") == false &&
               preview.dig("data", "automatic_retry") == false &&
               preview.dig("data", "scheduled") == false)

  backup_calls = -> { runner.calls.count { |call| call["argv"].include?("backup") } }
  denied = service.drs_execute(password: password, confirmation: "yes", expected_digest: preview.dig("data", "expected_digest"))
  stale = service.drs_execute(
    password: password,
    confirmation: preview.dig("data", "confirmation_phrase"),
    expected_digest: "0" * 64
  )
  check.call("wrong confirmation and stale digest perform no capture",
             denied["lifecycle_state"] == "awaiting_input" &&
               stale["lifecycle_state"] == "blocked_for_human_review" &&
               backup_calls.call.zero?)

  jobs = File.join(root, "Soul", "music", "jobs")
  FileUtils.mkdir_p(jobs)
  File.write(File.join(jobs, "job_fixture.json"), JSON.generate("status" => "running"))
  active_music = service.drs_preview(password: password)
  FileUtils.rm_f(File.join(jobs, "job_fixture.json"))
  leases = File.join(root, "Soul", "runtime", "model_runtime", "leases")
  FileUtils.mkdir_p(leases)
  File.write(File.join(leases, "visual.json"), "{}")
  active_lease = service.drs_preview(password: password)
  FileUtils.rm_f(File.join(leases, "visual.json"))
  check.call("active Music work and shared model-backed work block capture",
             active_music["lifecycle_state"] == "awaiting_input" &&
               active_lease["lifecycle_state"] == "awaiting_input" &&
               backup_calls.call.zero?)

  lock_path = File.join(state_root, "operation.lock")
  File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
    lock.flock(File::LOCK_EX)
    concurrent_preview = service.drs_preview(password: password)
    concurrent = service.drs_execute(
      password: password,
      confirmation: concurrent_preview.dig("data", "confirmation_phrase"),
      expected_digest: concurrent_preview.dig("data", "expected_digest")
    )
    check.call("concurrent backup work fails without waiting or capture",
               concurrent["lifecycle_state"] == "failed" &&
                 concurrent["reason"].include?("another backup administration operation") &&
                 backup_calls.call.zero?)
  end
end

fixture do |_root, state_root, runner, service, password|
  preview = service.drs_preview(password: password)
  runner.fail_remote_after_backup = true
  partial = service.drs_execute(
    password: password,
    confirmation: preview.dig("data", "confirmation_phrase"),
    expected_digest: preview.dig("data", "expected_digest")
  )
  receipt_path = Dir.glob(File.join(state_root, "receipts", "drs_*.json")).first
  receipt = receipt_path ? JSON.parse(File.read(receipt_path)) : {}
  check.call("remote failure preserves verified local success and records one terminal partial receipt",
             partial["lifecycle_state"] == "failed" &&
               partial["mutation"] == "backup_snapshot_created_replica_incomplete" &&
               partial.dig("data", "snapshot_id") == "d" * 64 &&
               receipt["state"] == "partial" &&
               receipt.dig("local", "state") == "complete" &&
               receipt.dig("replica", "state") != "complete" &&
               receipt["automatic_retry"] == false)
end

fixture do |root, state_root, runner, service, password|
  preview = service.drs_preview(password: password)
  complete = service.drs_execute(
    password: password,
    confirmation: preview.dig("data", "confirmation_phrase"),
    expected_digest: preview.dig("data", "expected_digest")
  )
  status = service.status.dig("data", "drs")
  receipts = Dir.glob(File.join(state_root, "receipts", "*.json")).map { |path| File.read(path) }.join
  argv = runner.calls.flat_map { |call| call["argv"] }.join(" ")
  child_passwords = runner.calls.select { |call| call["argv"].first == "restic" }.all? do |call|
    call.dig("env", "RESTIC_PASSWORD") == password
  end
  check.call("successful transaction proves the new local snapshot lineage on Crucible",
             complete["ok"] &&
               complete["mutation"] == "backup_drs_verified" &&
               complete.dig("data", "snapshot_id") == "d" * 64 &&
               complete.dig("data", "destination_snapshot_lineage_ids").include?("d" * 64) &&
               status["state"] == "complete" &&
               status["local_state"] == "complete" &&
               status["replica_state"] == "complete")
  check.call("password reaches only bounded Restic environments and is never persisted",
             child_passwords && !argv.include?(password) && !receipts.include?(password))
  check.call("transaction runs no local or remote retention command",
             runner.calls.none? { |call| (call["argv"] & %w[forget prune]).any? })

  facade = SoulCore::ApplicationFacade.new(root: root, backup_administration_service: service)
  envelope = facade.call({
    "schema_version" => "soul.application.v1",
    "request_id" => "nightly-drs-preview-0001",
    "operation" => "backup.drs.preview",
    "parameters" => {"password" => password},
    "context" => {"interface" => "dashboard_test"}
  })
  check.call("application contract exposes the same bounded DRS preview",
             envelope["lifecycle_state"] == "complete" &&
               SoulCore::ApplicationContract::OPERATIONS.key?("backup.drs.execute"))
end

html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
javascript = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
http = File.read(File.expand_path("../lib/soul_core/dashboard_http_application.rb", __dir__))
brief = File.read(File.expand_path("../docs/soul/NIGHTLY_DRS_TRANSACTION_A1_BRIEF.md", __dir__))
service_source = File.read(File.expand_path("../lib/soul_core/backup_administration_service.rb", __dir__))
drs_source = service_source[/def drs_preview.*?def retention_preview/m].to_s

check.call("Dashboard separates supervised preview from one exact execution gate",
           %w[backup-drs-state preview-backup-drs backup-drs-confirm execute-backup-drs backup-drs-progress backup-drs-status].all? { |id| html.include?("id=\"#{id}\"") } &&
             javascript.include?('"backup.drs.preview"') &&
             javascript.include?('"backup.drs.execute"') &&
             http.include?("backup.drs.execute"))
check.call("A1 uses the reviewed SSH config and adds no persistence or automatic retention primitive",
           service_source.include?("sftp.command=ssh -F") &&
             !drs_source.match?(/forget|prune|systemctl|timer|OnCalendar|sleep\s*\(/i) &&
             brief.include?("must not install or enable a") &&
             brief.include?("A1 never calls Restic `forget`, `prune`"))

abort(errors.map { |error| "- #{error}" }.join("\n")) unless errors.empty?
puts "Nightly DRS Transaction A1 is candidate-ready for human review."
