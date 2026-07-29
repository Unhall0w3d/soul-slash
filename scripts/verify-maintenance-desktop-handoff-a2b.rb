#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"

require_relative "../lib/soul_core/bounded_command_runner"
require_relative "../lib/soul_core/maintenance_desktop_handoff"

failures = []
check = lambda do |description, condition|
  puts "- #{description}: #{condition ? 'ok' : 'FAILED'}"
  failures << description unless condition
end

class A2BRunner
  Result = SoulCore::BoundedCommandRunner::Result

  def run(*argv, **_options)
    stdout = if argv.take(4) == ["/usr/bin/xdg-mime", "query", "default", "x-scheme-handler/soul-maintenance"]
      "soul-maintenance.desktop\n"
    elsif argv == ["/usr/bin/gio", "mime", "x-scheme-handler/soul-maintenance"]
      "Default application for “x-scheme-handler/soul-maintenance”: soul-maintenance.desktop\n"
    else
      ""
    end
    Result.new(stdout: stdout, stderr: "", exit_status: 0, status: "ok", truncated: false)
  end
end

class A2BAssessor
  def assess(include_updates:)
    raise "updates must be requested" unless include_updates
    {
      "status" => "ok",
      "read_only" => true,
      "managers" => {
        "pacman" => {
          "detected" => true,
          "updates" => {"status" => "complete", "count" => 1, "items" => ["fixture 1 -> 2"], "truncated" => false}
        },
        "yay" => {
          "detected" => true,
          "updates" => {"status" => "no_results", "count" => 0, "items" => [], "truncated" => false}
        },
        "flatpak" => {
          "detected" => true,
          "updates" => {"status" => "no_results", "count" => 0, "items" => [], "truncated" => false}
        }
      },
      "reboot" => {"status" => "complete", "fresh" => true, "recommended" => false}
    }
  end
end

class A2BTransactionRunner
  attr_reader :calls

  def initialize
    @calls = []
  end

  def run(transaction_path:, mode:)
    @calls << [transaction_path, mode]
    transaction = JSON.parse(File.read(transaction_path))
    {
      "schema_version" => "soul.maintenance.transaction_result.v1",
      "transaction_id" => transaction.fetch("transaction_id"),
      "lifecycle_state" => "complete",
      "password_prompts" => 1,
      "commands" => transaction.fetch("commands").map do |command|
        {"adapter" => command.fetch("adapter"), "exit_status" => 0, "status" => "complete"}
      end,
      "sudo_ticket_invalidated" => true,
      "reboot_requested" => false,
      "reason" => ""
    }
  end
end

def fixture_transaction(root, now)
  id = "maintenance_tx_fedcba9876543210"
  {
    "schema_version" => "soul.maintenance.transaction.v1",
    "transaction_id" => id,
    "mode" => "live",
    "owner_uid" => Process.uid,
    "created_at" => now.iso8601,
    "deadline_at" => (now + 600).iso8601,
    "plan_digest" => "d" * 64,
    "commands" => [
      {
        "adapter" => "arch_and_aur.full_upgrade",
        "argv" => ["/usr/bin/yay", "--sudoflags=-n", "-Syu"],
        "interactive" => true,
        "requires_existing_sudo_ticket" => true,
        "shell" => false
      }
    ],
    "sudo_validation_argv" => ["/usr/bin/sudo", "-v"],
    "sudo_refresh_argv" => ["/usr/bin/sudo", "-n", "-v"],
    "sudo_invalidate_argv" => ["/usr/bin/sudo", "-k"],
    "reboot_allowed" => false,
    "result_path" => File.join(root, "Soul", "private", "host_maintenance", "transactions", "#{id}.result.json")
  }
end

def fixture_passwordless_reboot_transaction(root, now)
  id = "maintenance_tx_1111222233334444"
  {
    "schema_version" => "soul.maintenance.transaction.v1",
    "transaction_id" => id,
    "mode" => "live_reboot",
    "owner_uid" => Process.uid,
    "created_at" => now.iso8601,
    "deadline_at" => (now + 600).iso8601,
    "plan_digest" => "e" * 64,
    "commands" => [],
    "authority_mode" => "root_owned_passwordless",
    "sudo_validation_argv" => [],
    "sudo_refresh_argv" => [],
    "sudo_invalidate_argv" => [],
    "reboot_allowed" => true,
    "reboot_argv" => ["/usr/bin/sudo", "-n", "/usr/local/libexec/soul-maintenance-authority", "reboot", id],
    "source_boot_id" => "1" * 36,
    "restore_registry_digest" => "f" * 64,
    "result_path" => File.join(root, "Soul", "private", "host_maintenance", "transactions", "#{id}.result.json")
  }
end

puts "Maintenance desktop handoff A2B verification:"

now = Time.utc(2026, 7, 27, 18, 0, 0)
clock = -> { now }

Dir.mktmpdir("soul-maintenance-a2b") do |root|
  home = File.join(root, "home")
  scripts = File.join(root, "scripts")
  applications = File.join(home, ".local", "share", "applications")
  FileUtils.mkdir_p([scripts, applications])
  handler = File.join(scripts, "soul-maintenance-uri")
  File.write(handler, "#!/usr/bin/env ruby\n")
  File.chmod(0o755, handler)

  transaction_runner = A2BTransactionRunner.new
  handoff = SoulCore::MaintenanceDesktopHandoff.new(
    root: root,
    home: home,
    clock: clock,
    runner: A2BRunner.new,
    package_assessor: A2BAssessor.new,
    transaction_runner_factory: -> { transaction_runner },
    id_generator: -> { "0123456789abcdef" }
  )
  File.write(handoff.desktop_path, handoff.desktop_entry, mode: "w", perm: 0o644)
  validation_output, validation_status = Open3.capture2e("/usr/bin/desktop-file-validate", handoff.desktop_path)

  status = handoff.status
  check.call("exact user-local desktop entry is recognized without a service or listener",
             status["available"] && status["system_service"] == false && status["persistent_process"] == false &&
               (File.stat(handoff.desktop_path).mode & 0o777) == 0o644)
  check.call("desktop entry uses one URL field code and the fixed repository handler",
             handoff.desktop_entry.include?("TryExec=#{handler}") &&
             handoff.desktop_entry.include?("Exec=#{handler} %u") &&
               handoff.desktop_entry.include?("Icon=#{File.join(root, 'assets', 'brand', 'soul-account-avatar-150.png')}") &&
               handoff.desktop_entry.include?("MimeType=x-scheme-handler/soul-maintenance;") &&
               !handoff.desktop_entry.match?(/(?:sh -c|bash -c|systemctl|Listen)/))
  check.call("desktop entry passes the same freedesktop validator used by the host",
             validation_status.success? && !validation_output.include?("error:"))

  evidence_reservation = handoff.reserve_evidence
  evidence_uri = evidence_reservation.fetch("launch_uri")
  evidence_result = handoff.handle_uri(evidence_uri)
  evidence = handoff.native_evidence
  evidence_path = File.join(root, "Soul", "private", "host_maintenance", "native_package_evidence.json")
  check.call("single-use evidence URI records fresh owner-private package evidence",
             evidence_result["lifecycle_state"] == "complete" && evidence["available"] &&
               File.file?(evidence_path) && (File.stat(evidence_path).mode & 0o777) == 0o600)
  replay = handoff.handle_uri(evidence_uri)
  check.call("evidence URI cannot be replayed", replay["lifecycle_state"] == "failed")

  malformed = handoff.handle_uri("#{evidence_uri}?command=rm")
  check.call("query fields and command-bearing URI variants are rejected",
             malformed["lifecycle_state"] == "blocked_for_human_review")

  transaction = fixture_transaction(root, now)
  reservation = handoff.reserve_transaction(transaction)
  check.call("transaction URI carries only opaque ID and reviewed digest",
             reservation.fetch("launch_uri") == "soul-maintenance://transaction/#{transaction.fetch('transaction_id')}/#{reservation.fetch('expected_digest')}" &&
               reservation.fetch("expected_digest").match?(/\A[a-f0-9]{64}\z/) &&
               !reservation.fetch("launch_uri").include?("/usr/bin"))
  completed = handoff.handle_uri(reservation.fetch("launch_uri"))
  receipt_path = File.join(root, "Soul", "private", "host_maintenance", "receipts", "maintenance_receipt_fedcba9876543210.json")
  receipt = JSON.parse(File.read(receipt_path))
  check.call("desktop transaction terminates with one redacted receipt and no reboot",
             completed["lifecycle_state"] == "complete" && transaction_runner.calls.length == 1 &&
               transaction_runner.calls.first.first.end_with?("/maintenance_tx_fedcba9876543210.json") &&
               !transaction_runner.calls.first.first.include?(".claimed.json") &&
               receipt["password_prompts"] == 1 && receipt["sudo_ticket_invalidated"] &&
               receipt["reboot_requested"] == false && receipt["redacted"] == true)
  check.call("transaction reservation cannot be replayed",
             handoff.handle_uri(reservation.fetch("launch_uri"))["lifecycle_state"] == "failed")

  reboot_transaction = fixture_passwordless_reboot_transaction(root, now)
  reboot_reservation = handoff.reserve_transaction(reboot_transaction)
  reboot_reservation_path = File.join(
    root, "Soul", "private", "host_maintenance", "transactions",
    "#{reboot_transaction.fetch('transaction_id')}.reserved.json"
  )
  check.call("passwordless reboot reservation accepts only the exact A4 helper vector",
             reboot_reservation.fetch("launch_uri").start_with?("soul-maintenance://transaction/#{reboot_transaction.fetch('transaction_id')}/") &&
               JSON.parse(File.read(reboot_reservation_path)).fetch("reboot_argv") ==
                 ["/usr/bin/sudo", "-n", "/usr/local/libexec/soul-maintenance-authority", "reboot", reboot_transaction.fetch("transaction_id")])

  altered_reboot = fixture_passwordless_reboot_transaction(root, now).merge(
    "transaction_id" => "maintenance_tx_5555666677778888",
    "reboot_argv" => ["/usr/bin/sudo", "-n", "/usr/bin/systemctl", "reboot"],
    "result_path" => File.join(root, "Soul", "private", "host_maintenance", "transactions", "maintenance_tx_5555666677778888.result.json")
  )
  begin
    handoff.reserve_transaction(altered_reboot)
    altered_reboot_rejected = false
  rescue StandardError
    altered_reboot_rejected = true
  end
  check.call("passwordless reboot reservation rejects the legacy direct systemctl vector", altered_reboot_rejected)

  tampered_evidence = JSON.parse(File.read(evidence_path))
  tampered_evidence["package_evidence"]["managers"]["pacman"]["updates"]["count"] = 99
  File.write(evidence_path, JSON.pretty_generate(tampered_evidence) + "\n", mode: "w", perm: 0o600)
  check.call("modified native evidence fails its content digest",
             handoff.native_evidence["reason"] == "native package evidence integrity mismatch")

  late = fixture_transaction(root, now).merge(
    "transaction_id" => "maintenance_tx_aaaaaaaaaaaaaaaa",
    "deadline_at" => (now + 601).iso8601,
    "result_path" => File.join(root, "Soul", "private", "host_maintenance", "transactions", "maintenance_tx_aaaaaaaaaaaaaaaa.result.json")
  )
  begin
    handoff.reserve_transaction(late)
    late_rejected = false
  rescue StandardError
    late_rejected = true
  end
  check.call("desktop launch authority expires within ten minutes", late_rejected)
end

uri_script = File.read(File.expand_path("soul-maintenance-uri", __dir__))
dashboard = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
check.call("URI process uses fixed argv exec rather than a shell", uri_script.include?("Process.exec(") && !uri_script.match?(/system\s*\(\s*['\"]|sh -c|bash -c/))
check.call("Dashboard launches only strict maintenance URIs and contains no polling loop",
           dashboard.include?("function launchMaintenanceUri") &&
             dashboard.include?("soul-maintenance:") &&
             !dashboard.match?(/maintenance.{0,200}(?:setInterval|WebSocket|EventSource)/m))

Dir.glob(File.expand_path("../docs/soul/schemas/maintenance_*.schema.json", __dir__)).each do |path|
  JSON.parse(File.read(path))
end
check.call("all maintenance schemas are valid JSON", true)

abort "Maintenance desktop handoff A2B verification failed: #{failures.join(', ')}" unless failures.empty?
puts "Maintenance desktop handoff A2B verification complete."
