#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require "time"

require_relative "../lib/soul_core/backup_administration_service"
require_relative "../lib/soul_core/bounded_command_runner"

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

class OperatorDrsRepairRunner
  attr_reader :calls
  attr_accessor :omit_backup_summary

  def initialize(mount:, source:, snapshots:)
    @mount = mount
    @source = source
    @snapshots = snapshots
    @calls = []
  end

  def which(name) = name == "restic" ? "/usr/bin/restic" : nil

  def run(*command, **options)
    argv = command.flatten.map(&:to_s)
    @calls << {"argv" => argv, "options" => options}
    return ok(JSON.generate("filesystems" => [{
      "target" => @mount, "source" => "/dev/test", "fstype" => "ext4",
      "options" => "rw,nosuid,nodev,noexec"
    }])) if argv.first == "findmnt"
    return ok("4096 #{@source}\n") if argv.first == "du"
    return failed("unexpected command") unless argv.first == "restic"

    action = argv[argv.index("--repo") + 2]
    case action
    when "snapshots"
      ok(JSON.generate(@snapshots))
    when "check"
      ok("repository metadata verified\n")
    when "ls"
      nodes = [@source, File.join(@source, "state.json")].map do |path|
        JSON.generate("struct_type" => "node", "path" => path)
      end
      ok(nodes.join("\n") + "\n")
    when "backup"
      snapshot_id = "f" * 64
      @snapshots << snapshot(snapshot_id, "2026-08-29T06:00:00Z") unless @snapshots.any? { |item| item["id"] == snapshot_id }
      return ok("", truncated: true) if @omit_backup_summary
      ok(JSON.generate("message_type" => "summary", "snapshot_id" => snapshot_id) + "\n", truncated: true)
    else
      failed("unsupported restic action #{action}")
    end
  end

  private

  def snapshot(id, time)
    {"id" => id, "time" => time, "hostname" => "fixture", "paths" => [@source], "tags" => ["operator-state"]}
  end

  def ok(stdout, truncated: false)
    SoulCore::BoundedCommandRunner::Result.new(
      stdout: stdout, stderr: "", exit_status: 0, status: "ok", truncated: truncated
    )
  end

  def failed(stderr)
    SoulCore::BoundedCommandRunner::Result.new(
      stdout: "", stderr: stderr, exit_status: 1, status: "failed", truncated: false
    )
  end
end

def fixture(root)
  mount = File.join(root, "recovery")
  repository = File.join(mount, "restic")
  source = File.join(root, "operator-state")
  state = File.join(root, "Soul", "private", "operator_backup")
  FileUtils.mkdir_p(repository)
  FileUtils.mkdir_p(source)
  FileUtils.mkdir_p(state)
  File.chmod(0o700, state)
  File.write(File.join(repository, "config"), "encrypted fixture\n")
  File.write(File.join(source, "state.json"), "{}\n")
  File.write(File.join(state, "sources.txt"), "#{source}\n")
  File.write(File.join(state, "excludes.txt"), "#{File.join(state, 'restores')}/**\n")
  [File.join(state, "sources.txt"), File.join(state, "excludes.txt")].each { |path| File.chmod(0o600, path) }
  [mount, repository, source, state]
end

puts "Operator DRS stream reconciliation A0 verification:"

Dir.mktmpdir("soul-operator-drs-repair-") do |root|
  mount, repository, source, state = fixture(root)
  snapshots = [
    {"id" => "a" * 64, "time" => "2026-08-16T06:00:00Z", "hostname" => "fixture", "paths" => [source], "tags" => ["operator-state"]},
    {"id" => "b" * 64, "time" => "2026-08-17T06:00:00Z", "hostname" => "fixture", "paths" => [source], "tags" => ["operator-state"]}
  ]
  runner = OperatorDrsRepairRunner.new(mount: mount, source: source, snapshots: snapshots)
  tick = -1
  clock = -> { Time.utc(2026, 8, 29, 12, 0, 0) + (tick += 1) }
  service = SoulCore::BackupAdministrationService.new(
    root: root, home: root, runner: runner, profile_id: "operator",
    process_env: {"OPERATOR_BACKUP_REPOSITORY" => repository, "OPERATOR_BACKUP_MOUNT" => mount},
    clock: clock, id_generator: -> { "0123456789abcdef" }
  )

  preview = service.snapshot_evidence_reconciliation_preview(password: "fixture-secret")
  check.call("preview is exact and read-only",
             preview["ok"] && preview.dig("data", "candidate_snapshot_ids") == ["a" * 64, "b" * 64] &&
               !File.exist?(File.join(state, "retention-ledger.json")))

  shared_lock_path = File.join(root, "Soul", "private", "backup", "operation.lock")
  FileUtils.mkdir_p(File.dirname(shared_lock_path), mode: 0o700)
  shared_lock = File.open(shared_lock_path, File::RDWR | File::CREAT, 0o600)
  shared_lock.flock(File::LOCK_EX)
  locked = service.snapshot_evidence_reconciliation_execute(
    password: "fixture-secret",
    confirmation: SoulCore::BackupAdministrationService::OPERATOR_SNAPSHOT_EVIDENCE_RECONCILIATION_CONFIRMATION,
    expected_digest: preview.dig("data", "expected_digest")
  )
  check.call("shared operation lock blocks reconciliation without mutation",
             !locked["ok"] && locked["lifecycle_state"] == "blocked_for_human_review" &&
               !File.exist?(File.join(state, "retention-ledger.json")))
  shared_lock.flock(File::LOCK_UN)
  shared_lock.close

  rejected = service.snapshot_evidence_reconciliation_execute(
    password: "fixture-secret", confirmation: "wrong",
    expected_digest: preview.dig("data", "expected_digest")
  )
  check.call("wrong confirmation mutates no evidence",
             !rejected["ok"] && !File.exist?(File.join(state, "retention-ledger.json")))

  stale = service.snapshot_evidence_reconciliation_execute(
    password: "fixture-secret",
    confirmation: SoulCore::BackupAdministrationService::OPERATOR_SNAPSHOT_EVIDENCE_RECONCILIATION_CONFIRMATION,
    expected_digest: "0" * 64
  )
  check.call("stale digest mutates no evidence",
             !stale["ok"] && !File.exist?(File.join(state, "retention-ledger.json")))

  executed = service.snapshot_evidence_reconciliation_execute(
    password: "fixture-secret",
    confirmation: SoulCore::BackupAdministrationService::OPERATOR_SNAPSHOT_EVIDENCE_RECONCILIATION_CONFIRMATION,
    expected_digest: preview.dig("data", "expected_digest")
  )
  ledger = JSON.parse(File.read(File.join(state, "retention-ledger.json")))
  check.call("exact execution records manifests in chronological order",
             executed["ok"] && executed.dig("data", "recorded_snapshot_ids") == ["a" * 64, "b" * 64] &&
               ledger.dig("last_verified_snapshot", "snapshot_id") == "b" * 64 &&
               %w[a b].all? { |id| File.file?(File.join(state, "manifests", id * 64 + ".json")) })

  replay = service.snapshot_evidence_reconciliation_preview(password: "fixture-secret")
  check.call("reconciliation replay is idempotent", replay["ok"] && replay.dig("data", "candidate_count") == 0)

  backup = service.backup_preview(password: "fixture-secret")
  captured = service.backup_execute(
    password: "fixture-secret",
    confirmation: backup.dig("data", "confirmation_phrase"),
    expected_digest: backup.dig("data", "expected_digest")
  )
  backup_call = runner.calls.reverse.find { |call| call.fetch("argv").include?("backup") }
  check.call("backup uses complete-line tail capture and accepts its terminal summary",
             captured["ok"] && captured.dig("data", "snapshot_id") == "f" * 64 &&
               backup_call.dig("options", :capture_mode) == :complete_line_tail)

  runner.omit_backup_summary = true
  indeterminate_preview = service.backup_preview(password: "fixture-secret")
  indeterminate = service.backup_execute(
    password: "fixture-secret",
    confirmation: indeterminate_preview.dig("data", "confirmation_phrase"),
    expected_digest: indeterminate_preview.dig("data", "expected_digest")
  )
  check.call("successful process without a summary reports indeterminate mutation",
             !indeterminate["ok"] && indeterminate["mutation"] == "backup_snapshot_indeterminate_requires_reconciliation" &&
               indeterminate.dig("data", "reconciliation_required") == true)

  receipt_text = Dir.glob(File.join(state, "receipts", "*.json")).map { |path| File.read(path) }.join
  check.call("receipts retain no repository password", !receipt_text.include?("fixture-secret"))

  snapshots.reject! { |item| item["id"] == "f" * 64 }
  absent_checkpoint = service.snapshot_evidence_reconciliation_preview(password: "fixture-secret")
  check.call("missing repository checkpoint blocks reconciliation",
             !absent_checkpoint["ok"] &&
               absent_checkpoint["lifecycle_state"] == "blocked_for_human_review")
end

if errors.empty?
  puts "Operator DRS stream reconciliation A0 verification passed."
  exit 0
end

warn "Operator DRS stream reconciliation A0 verification failed: #{errors.join(', ')}"
exit 1
