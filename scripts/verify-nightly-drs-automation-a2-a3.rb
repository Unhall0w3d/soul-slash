#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"

require_relative "../lib/soul_core/nightly_drs_deployment"
require_relative "../lib/soul_core/nightly_drs_runner"

errors = []
check = lambda do |label, condition|
  puts "#{condition ? 'PASS' : 'FAIL'}: #{label}"
  errors << label unless condition
end

class DrsAutomationBackupStub
  attr_reader :passwords

  def initialize(ok: true)
    @ok = ok
    @passwords = []
  end

  def status(password:)
    @passwords << password.dup
    return {
      "ok" => false,
      "lifecycle_state" => "awaiting_input",
      "reason" => "repository password was rejected",
      "data" => {}
    } unless password == "fixture secret"
    {
      "ok" => true,
      "lifecycle_state" => "complete",
      "reason" => "inspected",
      "data" => {
        "snapshot_access" => "unlocked",
        "snapshots" => [{"id" => "a" * 64}],
        "replica" => {"configured" => true, "state" => "ready", "target_ready" => true, "snapshot_count" => 1}
      }
    }
  end

  def drs_preview(password:)
    @passwords << password.dup
    {
      "ok" => true,
      "lifecycle_state" => "complete",
      "reason" => "prepared",
      "mutation" => "none",
      "data" => {"confirmation_phrase" => "CREATE_AND_REPLICATE_VERIFIED_DRS_BACKUP", "expected_digest" => "a" * 64}
    }
  end

  def drs_execute(password:, confirmation:, expected_digest:)
    @passwords << password.dup
    raise "gate mismatch" unless confirmation == "CREATE_AND_REPLICATE_VERIFIED_DRS_BACKUP" && expected_digest == "a" * 64
    if @ok
      {
        "ok" => true,
        "lifecycle_state" => "complete",
        "reason" => "verified DRS transaction completed",
        "mutation" => "backup_drs_verified",
        "data" => {
          "snapshot_id" => "b" * 64,
          "drs_receipt" => {
            "receipt_id" => "drs_fixture_complete",
            "local" => {"state" => "complete"},
            "replica" => {"state" => "complete"}
          }
        }
      }
    else
      {
        "ok" => false,
        "lifecycle_state" => "failed",
        "reason" => "local complete; replica unavailable",
        "mutation" => "backup_snapshot_created_replica_incomplete",
        "data" => {
          "snapshot_id" => "c" * 64,
          "drs_receipt" => {
            "receipt_id" => "drs_fixture_partial",
            "local" => {"state" => "complete"},
            "replica" => {"state" => "failed"}
          }
        }
      }
    end
  end
end

Dir.mktmpdir("soul-nightly-drs-automation-") do |sandbox|
  root = File.join(sandbox, "project")
  home = File.join(sandbox, "home")
  state_root = File.join(root, "Soul", "private", "backup")
  credential_delivery = File.join(sandbox, "credentials")
  FileUtils.mkdir_p(state_root, mode: 0o700)
  FileUtils.mkdir_p(File.join(root, "scripts"), mode: 0o700)
  FileUtils.mkdir_p(home, mode: 0o700)
  FileUtils.mkdir_p(credential_delivery, mode: 0o700)
  File.write(File.join(root, "scripts", "soul-nightly-drs-run"), "# fixture\n")
  File.chmod(0o700, File.join(root, "scripts", "soul-nightly-drs-run"))

  now = Time.new(2026, 7, 29, 22, 0, 0, "-04:00")
  commands = []
  secret_inputs = []
  systemctl_status = {
    "ActiveState" => "active",
    "SubState" => "waiting",
    "UnitFileState" => "enabled",
    "NextElapseUSecRealtime" => "Wed 2026-07-29 22:02:00 EDT",
    "LastTriggerUSec" => "n/a",
    "Result" => "success",
    "ExecMainStatus" => "0"
  }
  runner = lambda do |argv, stdin_data: nil|
    commands << argv
    if argv.include?("encrypt")
      secret_inputs << stdin_data.dup
      File.write(argv.last, "encrypted-fixture-not-plaintext")
      {"success" => true, "stdout" => "", "stderr" => ""}
    elsif argv.include?("show")
      properties = argv.find { |item| item.start_with?("--property=") }.delete_prefix("--property=").split(",")
      stdout = properties.map { |key| "#{key}=#{systemctl_status[key]}" }.join("\n") + "\n"
      {"success" => true, "stdout" => stdout, "stderr" => ""}
    else
      {"success" => true, "stdout" => "", "stderr" => ""}
    end
  end

  deployment = SoulCore::NightlyDrsDeployment.new(
    root: root,
    home: home,
    process_env: {"SOUL_BACKUP_MOUNT" => File.join(sandbox, "backup-mount")},
    clock: -> { now },
    ruby_path: RbConfig.ruby,
    systemctl_path: "/usr/bin/true",
    systemd_creds_path: "/usr/bin/true",
    backup_service: DrsAutomationBackupStub.new,
    runner: runner
  )

  credential_plan = deployment.credential_plan
  check.call("credential enrollment is separately review-gated",
             credential_plan["lifecycle_state"] == "blocked_for_human_review" &&
               credential_plan.dig("data", "plaintext_file_created") == false)
  wrong_credential = deployment.enroll_credential(password: "fixture secret", confirmation: "WRONG")
  check.call("wrong credential confirmation writes nothing",
             wrong_credential["lifecycle_state"] == "awaiting_input" && secret_inputs.empty?)
  rejected_credential = deployment.enroll_credential(
    password: "wrong secret",
    confirmation: SoulCore::NightlyDrsDeployment::CONFIRM_CREDENTIAL
  )
  check.call("credential is verified against both repositories before encryption",
             rejected_credential["lifecycle_state"] == "awaiting_input" &&
               rejected_credential.dig("data", "credential_replaced") == false &&
               secret_inputs.empty?)
  enrolled = deployment.enroll_credential(
    password: "fixture secret",
    confirmation: SoulCore::NightlyDrsDeployment::CONFIRM_CREDENTIAL
  )
  credential_path = File.join(home, ".config", "credstore.encrypted", "soul-backup-repository-password.cred")
  check.call("credential enrollment uses user-scoped host encryption without a plaintext file",
             enrolled["ok"] && secret_inputs == ["fixture secret"] &&
               File.read(credential_path) == "encrypted-fixture-not-plaintext" &&
               (File.stat(credential_path).mode & 0o077).zero?)

  too_late = deployment.test_plan(run_at: (now + 600).iso8601)
  check.call("qualification schedule is bounded to the near future",
             too_late["lifecycle_state"] == "awaiting_input")
  test_at = (now + 120).iso8601
  test_plan = deployment.test_plan(run_at: test_at)
  check.call("two-minute qualification plan binds exact units and digest",
             test_plan["ok"] &&
               test_plan.dig("data", "mode") == "qualification" &&
               test_plan.dig("data", "calendar") == "2026-07-29 22:02:00" &&
               test_plan.dig("data", "units", SoulCore::NightlyDrsDeployment::TIMER).include?("Persistent=true"))
  stale = deployment.install_test(
    run_at: test_at,
    confirmation: SoulCore::NightlyDrsDeployment::CONFIRM_TEST,
    expected_digest: "0" * 64
  )
  check.call("stale qualification digest installs no units",
             stale["lifecycle_state"] == "blocked_for_human_review" &&
               !File.exist?(File.join(home, ".config", "systemd", "user", SoulCore::NightlyDrsDeployment::TIMER)))
  installed = deployment.install_test(
    run_at: test_at,
    confirmation: SoulCore::NightlyDrsDeployment::CONFIRM_TEST,
    expected_digest: test_plan.dig("data", "expected_digest")
  )
  service_path = File.join(home, ".config", "systemd", "user", SoulCore::NightlyDrsDeployment::SERVICE)
  timer_path = File.join(home, ".config", "systemd", "user", SoulCore::NightlyDrsDeployment::TIMER)
  service_body = File.read(service_path)
  check.call("qualification installs one hardened no-restart oneshot and one timer",
             installed["ok"] &&
               service_body.include?("Type=oneshot") &&
               service_body.include?("Restart=no") &&
               service_body.include?("LoadCredentialEncrypted=soul-backup-repository-password:") &&
               service_body.include?("CacheDirectory=soul-drs") &&
               service_body.include?("CacheDirectoryMode=0700") &&
               service_body.include?("Environment=XDG_CACHE_HOME=%C/soul-drs") &&
               service_body.include?("ProtectSystem=strict") &&
               service_body.include?("--schedule-mode qualification") &&
               File.read(timer_path).include?("OnCalendar=2026-07-29 22:02:00"))
  check.call("qualification is armed but is not reported as permanent-ready",
             installed.dig("data", "armed") == true && installed.dig("data", "ready") == false)
  check.call("systemd activation is bounded to reload, enable, and timer restart",
             commands.any? { |command| command.include?("daemon-reload") } &&
               commands.any? { |command| command.include?("enable") && command.include?("--now") } &&
               commands.any? { |command| command.include?("restart") && command.include?(SoulCore::NightlyDrsDeployment::TIMER) })
  blocked_permanent = deployment.permanent_plan
  check.call("permanent timer remains blocked before successful timed evidence",
             blocked_permanent["lifecycle_state"] == "blocked_for_human_review")

  File.write(File.join(credential_delivery, SoulCore::NightlyDrsRunner::CREDENTIAL_NAME), "fixture secret")
  backup = DrsAutomationBackupStub.new
  runner_service = SoulCore::NightlyDrsRunner.new(
    root: root,
    home: home,
    process_env: {"CREDENTIALS_DIRECTORY" => credential_delivery},
    clock: -> { now },
    id_generator: -> { "fixture" },
    backup_service: backup
  )
  run = runner_service.run(trigger: "systemd_timer", schedule_mode: "qualification")
  state = JSON.parse(File.read(File.join(state_root, "nightly-drs-state.json")))
  check.call("scheduled runner completes through the accepted DRS preview and execution",
             run["ok"] && backup.passwords == ["fixture secret", "fixture secret"] &&
               state["state"] == "complete" &&
               state["schedule_mode"] == "qualification" &&
               state["drs_receipt_id"] == "drs_fixture_complete" &&
               state["password_retained"] == false)
  check.call("run state contains evidence but no credential",
             !File.read(File.join(state_root, "nightly-drs-state.json")).include?("fixture secret"))

  missing_receipt_plan = deployment.permanent_plan
  check.call("runner summary alone cannot unlock permanent activation",
             missing_receipt_plan["lifecycle_state"] == "blocked_for_human_review")
  FileUtils.mkdir_p(File.join(state_root, "receipts"), mode: 0o700)
  File.write(
    File.join(state_root, "receipts", "drs_fixture_complete.json"),
    JSON.pretty_generate({
      "schema_version" => "soul.backup_receipt.v1",
      "receipt_id" => "drs_fixture_complete",
      "operation" => "drs",
      "state" => "complete",
      "local" => {
        "state" => "complete",
        "verification" => "passed",
        "snapshot_id" => "b" * 64
      },
      "replica" => {
        "state" => "complete",
        "destination_snapshot_lineage_ids" => ["b" * 64]
      }
    }) + "\n"
  )
  File.chmod(0o600, File.join(state_root, "receipts", "drs_fixture_complete.json"))
  permanent_plan = deployment.permanent_plan
  check.call("matching timed state and parent receipt unlock the permanent plan",
             permanent_plan["ok"] &&
               permanent_plan.dig("data", "calendar") == SoulCore::NightlyDrsDeployment::PERMANENT_CALENDAR)
  receipt_status = deployment.status
  check.call("status projects local and Crucible component evidence from the parent receipt",
             receipt_status.dig("data", "last_run", "local_state") == "complete" &&
               receipt_status.dig("data", "last_run", "replica_state") == "complete")
  permanent = deployment.install_permanent(
    confirmation: SoulCore::NightlyDrsDeployment::CONFIRM_PERMANENT,
    expected_digest: permanent_plan.dig("data", "expected_digest")
  )
  check.call("permanent activation replaces qualification with nightly 3:00 AM",
             permanent["ok"] &&
               File.read(timer_path).include?("OnCalendar=*-*-* 03:00:00") &&
               File.read(service_path).include?("--schedule-mode permanent"))

  partial_root = File.join(sandbox, "partial", "Soul", "private", "backup")
  FileUtils.mkdir_p(partial_root, mode: 0o700)
  partial = SoulCore::NightlyDrsRunner.new(
    root: File.join(sandbox, "partial"),
    home: home,
    process_env: {"CREDENTIALS_DIRECTORY" => credential_delivery},
    clock: -> { now },
    id_generator: -> { "partial" },
    backup_service: DrsAutomationBackupStub.new(ok: false)
  ).run(trigger: "systemd_timer", schedule_mode: "qualification")
  partial_state = JSON.parse(File.read(File.join(partial_root, "nightly-drs-state.json")))
  check.call("replica failure terminates partial without retry and preserves evidence",
             !partial["ok"] && partial_state["state"] == "partial" &&
               partial_state["local_state"] == "complete" &&
               partial_state["replica_state"] == "failed" &&
               partial_state["automatic_retry"] == false)
end

deployment_source = File.read(File.expand_path("../lib/soul_core/nightly_drs_deployment.rb", __dir__))
runner_source = File.read(File.expand_path("../lib/soul_core/nightly_drs_runner.rb", __dir__))
dashboard = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
check.call("automation source contains no retention, pruning, remote deletion, or restart authority",
           !deployment_source.match?(/\\b(?:forget|prune)\\b/) &&
             deployment_source.include?("Restart=no") &&
             dashboard.include?('automation.ready ? `Nightly · ${scheduleLabel}`'))
check.call("runner has one terminal state file and no retry loop",
           runner_source.include?("nightly-drs-state.json") &&
             !runner_source.match?(/\b(?:sleep|retry)\b/) &&
             runner_source.include?('"automatic_retry" => false'))

abort "Nightly DRS automation A2/A3 verification failed: #{errors.join(', ')}" unless errors.empty?
puts "Nightly DRS automation A2/A3 is candidate-ready for live qualification."
