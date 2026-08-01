#!/usr/bin/ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "stringio"
require "tmpdir"
require "time"

require_relative "../lib/soul_core/maintenance_foreground_execution_service"
require_relative "../lib/soul_core/maintenance_passwordless_authority"
require_relative "../lib/soul_core/maintenance_transaction_runner"

errors = []
puts "Maintenance passwordless authority A4 verification:"
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'FAILED'}"
  errors << label unless condition
end

root = File.expand_path("..", __dir__)
authority = SoulCore::MaintenancePasswordlessAuthority.new(root: root)
plan_one = authority.plan
plan_two = authority.plan
data = plan_one.fetch("data", {})
helper = data.fetch("helper_content", "")
sudoers = data.fetch("sudoers_content", "")

check.call(
  "root-owned deployment plan is deterministic and exact-confirmation gated",
  plan_one["ok"] && plan_one["lifecycle_state"] == "blocked_for_human_review" &&
    data["expected_digest"] == plan_two.dig("data", "expected_digest") &&
    data["confirmation_phrase"] == SoulCore::MaintenancePasswordlessAuthority::CONFIRM_INSTALL &&
    data["owner_gid"].is_a?(Integer)
)
check.call(
  "sudoers grants only the digest-bound fixed helper operations",
  sudoers.include?("sha256:#{Digest::SHA256.hexdigest(helper)}") &&
    sudoers.include?("/usr/local/libexec/soul-maintenance-authority arch-update maintenance_tx_*") &&
    sudoers.include?("/usr/local/libexec/soul-maintenance-authority pacman-bridge maintenance_tx_* *") &&
    sudoers.include?("/usr/local/libexec/soul-maintenance-authority flatpak-system-update maintenance_tx_*") &&
    sudoers.include?("/usr/local/libexec/soul-maintenance-authority reboot maintenance_tx_*") &&
    !sudoers.match?(/NOPASSWD:\s*(?:ALL|\/usr\/bin\/(?:yay|pacman|flatpak|systemctl|ruby|sh|bash))/)
)
check.call(
  "helper accepts no caller-selected executable, target, or shell command",
  helper.include?("operation = ARGV.shift.to_s") &&
    helper.include?("fail_closed(\"argument count is invalid\")") &&
    helper.include?("transaction command vector is invalid") &&
    helper.include?("pacman bridge executable changed") &&
    helper.include?("pacman bridge is not descended through bounded sudo ancestry from active yay") &&
    !helper.include?("system(*ARGV)") &&
    !helper.include?("eval(") &&
    !helper.include?("`")
)
check.call(
  "yay runs unprivileged with a transaction-scoped pacman bridge and fixed unattended policy",
  %w[--noconfirm --answerclean --answerdiff --answeredit --answerupgrade --noremovemake --pgpfetch=false --provides=false --useask=false --sudoloop=false].all? { |flag| helper.include?(flag) } &&
    helper.include?("\"None\"") && helper.include?("\"All\"") &&
    helper.include?("Process::GID.change_privilege(OWNER_GID)") &&
    helper.include?("Process::UID.change_privilege(OWNER_UID)") &&
    helper.include?("\"--sudo\", PATHS.fetch(\"sudo\")") &&
    helper.include?("pacman-bridge \#{transaction.fetch('transaction_id')}") &&
    helper.include?("refresh\n    ]") &&
    !helper.include?("--nodeps") && !helper.include?("--overwrite")
)
check.call(
  "pacman bridge is limited to active yay ancestry and accepts only yay's exact install-reason bookkeeping shape",
  helper.include?("active_arch_update") &&
    helper.include?("yay_start_ticks") &&
    helper.include?("MAX_SUDO_ANCESTRY_DEPTH = 3") &&
    helper.include?("ancestor[\"exe\"] == File.realpath(PATHS.fetch(\"sudo\"))") &&
    helper.include?("ancestor[\"start_ticks\"] == yay[\"start_ticks\"]") &&
    helper.include?('explicit_prefix = ["-D", "--asexplicit", "-q", "--noconfirm", "--config", "/etc/pacman.conf", "--"]') &&
    helper.include?("explicit_targets.length.between?(1, 128)") &&
    helper.include?('operation == "mark_explicit"') &&
    %w[--remove --database --root --sysroot --dbpath --cachedir --hookdir --logfile --gpgdir].all? { |flag| helper.include?(flag) } &&
    helper.include?("pacman bridge configuration changed")
)
check.call(
  "Flatpak and reboot remain separate fixed operations",
  helper.include?("[PATHS.fetch(\"flatpak\"), \"update\", \"--system\", \"--noninteractive\"]") &&
    helper.include?("[PATHS.fetch(\"systemctl\"), \"reboot\"]") &&
    helper.include?("journal[\"current_state\"] == \"reboot_requested\"")
)

syntax_out, syntax_err, syntax_status = Open3.capture3("/usr/bin/ruby", "-c", stdin_data: helper)
check.call("generated root helper is valid Ruby", syntax_status.success? && syntax_out.include?("Syntax OK") && syntax_err.empty?)

helper_definitions = helper.split("\nverify_caller!\n", 2).first
bridge_probe = <<~RUBY
  #{helper_definitions}
  require "json"
  cases = {
    "exact" => ["-D", "--asexplicit", "-q", "--noconfirm", "--config", "/etc/pacman.conf", "--", "webex-bin"],
    "multiple" => ["-D", "--asexplicit", "-q", "--noconfirm", "--config", "/etc/pacman.conf", "--", "one", "two-bin"],
    "no_target" => ["-D", "--asexplicit", "-q", "--noconfirm", "--config", "/etc/pacman.conf", "--"],
    "path_target" => ["-D", "--asexplicit", "-q", "--noconfirm", "--config", "/etc/pacman.conf", "--", "../../root"],
    "asdeps" => ["-D", "--asdeps", "-q", "--noconfirm", "--config", "/etc/pacman.conf", "--", "webex-bin"],
    "changed_config" => ["-D", "--asexplicit", "-q", "--noconfirm", "--config", "/tmp/pacman.conf", "--", "webex-bin"],
    "sync" => ["-Syu"],
    "archive" => ["-U", "--noconfirm", "--", "/home/operator/.cache/yay/example/example.pkg.tar.zst"]
  }
  puts JSON.generate(cases.transform_values { |arguments| pacman_bridge_operation(arguments) })
RUBY
probe_out, probe_err, probe_status = Open3.capture3("/usr/bin/ruby", stdin_data: bridge_probe)
probe = probe_status.success? ? JSON.parse(probe_out) : {}
check.call(
  "generated helper classifies only the exact install-reason vector as bounded bookkeeping",
  probe_err.empty? &&
    probe == {
      "exact" => "mark_explicit",
      "multiple" => "mark_explicit",
      "no_target" => nil,
      "path_target" => nil,
      "asdeps" => nil,
      "changed_config" => nil,
      "sync" => "package_mutation",
      "archive" => "package_mutation"
    }
)

begin
  authority.command_for("arch-update", "maintenance_tx_0123456789abcdef")
  valid_vector = true
rescue StandardError
  valid_vector = false
end
rejected = 0
[
  ["shell", "maintenance_tx_0123456789abcdef"],
  ["arch-update", "maintenance_tx_../../etc/shadow"],
  ["arch-update", "maintenance_tx_0123456789abcdef --flag"]
].each do |operation, transaction|
  begin
    authority.command_for(operation, transaction)
  rescue ArgumentError
    rejected += 1
  end
end
check.call("public command builder accepts only one operation token and opaque transaction ID", valid_vector && rejected == 3)

install_calls = []
gated = SoulCore::MaintenancePasswordlessAuthority.new(
  root: root,
  command_runner: lambda do |argv|
    install_calls << argv
    if argv == ["/usr/bin/yay", "--version"]
      {"success" => true, "stdout" => "yay v13.0.1 - libalpm v15.0.0\n", "stderr" => ""}
    else
      {"success" => false, "stdout" => "", "stderr" => "not installed"}
    end
  end
)
blocked_install = gated.install(expected_digest: gated.plan.dig("data", "expected_digest"), confirmation: "wrong")
check.call("installation performs no privileged call without exact confirmation", blocked_install["lifecycle_state"] == "awaiting_input" && install_calls.all? { |argv| argv == ["/usr/bin/yay", "--version"] })

confined_runner = lambda do |argv|
  if argv == ["/usr/bin/yay", "--version"]
    {"success" => true, "stdout" => "yay v13.0.1 - libalpm v16.0.1\n", "stderr" => ""}
  else
    {"success" => false, "stdout" => "", "stderr" => "sudo: The \"no new privileges\" flag is set\n"}
  end
end
confined_authority = SoulCore::MaintenancePasswordlessAuthority.new(root: root, command_runner: confined_runner)
confined_authority.define_singleton_method(:regular_file_exact?) { |_path, _digest, _mode| true }
confined_status = confined_authority.status
check.call(
  "confined Dashboard defers sudoers proof to the native handoff without disabling A4",
  confined_status.dig("data", "ready") == true &&
    confined_status.dig("data", "sudoers_authorization_exact") == false &&
    confined_status.dig("data", "authorization_verification") == "deferred_to_native_handoff"
)

fake_authority = Object.new
def fake_authority.status
  {"ok" => true, "data" => {"ready" => true, "authority_mode" => "root_owned_passwordless", "helper_sha256" => "a" * 64}}
end
def fake_authority.command_for(operation, transaction_id)
  ["/usr/bin/sudo", "-n", "/usr/local/libexec/soul-maintenance-authority", operation, transaction_id]
end
service = SoulCore::MaintenanceForegroundExecutionService.new(
  root: Dir.mktmpdir("soul-a4-service"),
  passwordless_authority_enabled: true,
  passwordless_authority: fake_authority
)
materialized = service.materialize_live_commands([
  {"adapter" => "arch_and_aur.full_upgrade", "argv" => ["/usr/local/libexec/soul-maintenance-authority", "arch-update", "<transaction_id>"], "shell" => false},
  {"adapter" => "flatpak.user_update", "argv" => ["/usr/bin/flatpak", "update", "--user", "--noninteractive"], "shell" => false},
  {"adapter" => "flatpak.system_update", "argv" => ["/usr/local/libexec/soul-maintenance-authority", "flatpak-system-update", "<transaction_id>"], "shell" => false}
], "maintenance_tx_0123456789abcdef")
check.call(
  "A2 materializes only fixed passwordless vectors after transaction ID allocation",
  materialized.map { |row| row.fetch("argv") } == [
    ["/usr/bin/sudo", "-n", "/usr/local/libexec/soul-maintenance-authority", "arch-update", "maintenance_tx_0123456789abcdef"],
    ["/usr/bin/flatpak", "update", "--user", "--noninteractive"],
    ["/usr/bin/sudo", "-n", "/usr/local/libexec/soul-maintenance-authority", "flatpak-system-update", "maintenance_tx_0123456789abcdef"]
  ] && service.privilege_fields("maintenance_tx_0123456789abcdef")["sudo_validation_argv"].empty?
)

Dir.mktmpdir("soul-a4-runner") do |temporary|
  transaction_root = File.join(temporary, "Soul", "private", "host_maintenance", "transactions")
  FileUtils.mkdir_p(transaction_root)
  id = "maintenance_tx_0123456789abcdef"
  commands = materialized.first(2)
  transaction = {
    "schema_version" => "soul.maintenance.transaction.v1",
    "transaction_id" => id,
    "mode" => "live",
    "owner_uid" => Process.uid,
    "created_at" => Time.now.utc.iso8601,
    "deadline_at" => (Time.now.utc + 600).iso8601,
    "plan_digest" => "b" * 64,
    "authority_mode" => "root_owned_passwordless",
    "commands" => commands,
    "sudo_validation_argv" => [],
    "sudo_refresh_argv" => [],
    "sudo_invalidate_argv" => [],
    "reboot_allowed" => false,
    "result_path" => File.join(transaction_root, "#{id}.result.json")
  }
  path = File.join(transaction_root, "#{id}.json")
  File.write(path, JSON.generate(transaction), mode: "w", perm: 0o600)
  calls = []
  runner = SoulCore::MaintenanceTransactionRunner.new(
    root: temporary,
    command_executor: ->(argv, _timeout, _pid_callback) { calls << argv; 0 },
    output: StringIO.new
  )
  result = runner.run(transaction_path: path, mode: "live")
  check.call(
    "passwordless runner makes zero authentication calls and records zero prompts",
    result["lifecycle_state"] == "complete" && result["password_prompts"] == 0 &&
      result["sudo_ticket_invalidated"] == true && calls == commands.map { |row| row.fetch("argv") }
  )

  hostile = Marshal.load(Marshal.dump(transaction))
  hostile["transaction_id"] = "maintenance_tx_fedcba9876543210"
  hostile["result_path"] = File.join(transaction_root, "#{hostile['transaction_id']}.result.json")
  hostile["commands"][0]["argv"] = ["/usr/bin/sudo", "-n", "/usr/bin/pacman", "-Syu"]
  hostile_path = File.join(transaction_root, "#{hostile['transaction_id']}.json")
  File.write(hostile_path, JSON.generate(hostile), mode: "w", perm: 0o600)
  hostile_calls = []
  hostile_result = SoulCore::MaintenanceTransactionRunner.new(
    root: temporary,
    command_executor: ->(argv, _timeout, _pid_callback) { hostile_calls << argv; 0 },
    output: StringIO.new
  ).run(transaction_path: hostile_path, mode: "live")
  check.call("runner rejects direct pacman or altered vectors before execution", hostile_result["lifecycle_state"] == "failed" && hostile_calls.empty?)

  reboot_id = "maintenance_tx_1111111111111111"
  reboot_transaction = transaction.merge(
    "transaction_id" => reboot_id,
    "mode" => "live_reboot",
    "commands" => [],
    "reboot_allowed" => true,
    "reboot_argv" => ["/usr/bin/sudo", "-n", "/usr/local/libexec/soul-maintenance-authority", "reboot", reboot_id],
    "result_path" => File.join(transaction_root, "#{reboot_id}.result.json")
  )
  reboot_path = File.join(transaction_root, "#{reboot_id}.json")
  File.write(reboot_path, JSON.generate(reboot_transaction), mode: "w", perm: 0o600)
  coordinator = Object.new
  coordinator.define_singleton_method(:prepare) { |_transaction| true }
  coordinator.define_singleton_method(:mark_reboot_requested) { true }
  coordinator.define_singleton_method(:mark_reboot_failed) { |_reason| true }
  reboot_calls = []
  reboot_result = SoulCore::MaintenanceTransactionRunner.new(
    root: temporary,
    reboot_coordinator: coordinator,
    command_executor: ->(argv, _timeout, _pid_callback) { reboot_calls << argv; 0 },
    output: StringIO.new
  ).run(transaction_path: reboot_path, mode: "live_reboot")
  check.call(
    "A3 retains its journal gate and requests one fixed reboot with zero prompts",
    reboot_result["lifecycle_state"] == "awaiting_login" &&
      reboot_result["password_prompts"] == 0 &&
      reboot_result["reboot_requested"] == true &&
      reboot_calls == [reboot_transaction.fetch("reboot_argv")]
  )
end

env_example = File.read(File.join(root, ".env.example"))
schema = File.read(File.join(root, "lib", "soul_core", "configuration_schema.rb"))
check.call(
  "public passwordless mode defaults off and documents its residual risk",
  env_example.include?("SOUL_MAINTENANCE_PASSWORDLESS=false") &&
    schema.include?("Any process already running as the desktop owner")
)

review = File.read(File.join(root, "docs", "soul", "MAINTENANCE_PASSWORDLESS_AUTHORITY_A4_BRIEF.md"))
check.call(
  "human brief records unattended fixed decisions and prohibits a general privilege hole",
  review.include?("## Unattended decision behavior") &&
    review.include?("no password") &&
    review.include?("NOPASSWD: ALL") &&
    review.include?("arbitrary command")
)

abort("Maintenance passwordless authority A4 verification failed: #{errors.join(', ')}") unless errors.empty?
puts "Maintenance passwordless authority A4 verification complete."
