#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "pty"
require "stringio"
require "tmpdir"
require "timeout"

require_relative "../lib/soul_core/application_facade"
require_relative "../lib/soul_core/maintenance_foreground_execution_service"
require_relative "../lib/soul_core/maintenance_transaction_runner"

failures = []
check = lambda do |description, condition|
  puts "- #{description}: #{condition ? 'ok' : 'FAILED'}"
  failures << description unless condition
end

class A2FixtureRehearsal
  def initialize(clock)
    @clock = clock
  end

  def preview(force_database_refresh: false)
    mode = force_database_refresh == true || force_database_refresh.to_s == "true"
    plan = {
      "schema_version" => "soul.maintenance.plan.v1",
      "plan_id" => "maintenance_#{"a" * 16}",
      "force_database_refresh" => mode,
      "commands" => [
        {"adapter" => "official_repository.full_upgrade", "argv" => ["/usr/bin/sudo", "-n", "/usr/bin/pacman", mode ? "-Syyu" : "-Syu"], "interactive" => true, "executes_in_a1" => false},
        {"adapter" => "flatpak.user_update", "argv" => ["/usr/bin/flatpak", "update", "--user"], "interactive" => true, "executes_in_a1" => false},
        {"adapter" => "flatpak.system_update", "argv" => ["/usr/bin/sudo", "-n", "/usr/bin/flatpak", "update", "--system"], "interactive" => true, "executes_in_a1" => false}
      ],
      "aur_review" => {"helper" => "yay", "status" => "not_required", "count" => 0, "items" => [], "included_in_unattended_maintenance" => false},
      "package_evidence" => {
        "status" => "ok",
        "managers" => {
          "pacman" => {"detected" => true, "path" => "/usr/bin/pacman", "updates" => {"status" => "complete", "count" => 2, "items" => ["alpha 1 -> 2", "beta 2 -> 3"], "truncated" => false}},
          "yay" => {"detected" => true, "path" => "/usr/bin/yay", "updates" => {"status" => "no_results", "count" => 0, "items" => [], "truncated" => false}},
          "flatpak" => {"detected" => true, "path" => "/usr/bin/flatpak", "updates" => {"status" => "complete", "count" => 1, "items" => ["org.example.App"], "truncated" => false}}
        },
        "reboot" => {"recommended" => true}
      },
      "flatpak_installations" => [{"scope" => "system"}, {"scope" => "user"}],
      "restore_registry_digest" => "b" * 64,
      "window_snapshot" => {
        "captured_at" => @clock.call.iso8601,
        "active_workspace" => {"id" => 2, "name" => "2"},
        "restorable_count" => 2,
        "unsupported_count" => 1,
        "windows" => [{
          "initial_class" => "kitty", "class" => "kitty", "workspace" => {"id" => 2, "name" => "2"},
          "monitor_id" => 0, "floating" => false, "fullscreen" => 0, "pinned" => false,
          "restore_status" => "restorable", "restore_entry_id" => "kitty", "launch_argv" => ["/usr/bin/kitty"]
        }],
        "background_applications" => [{
          "process_identity" => "qbittorrent", "restore_status" => "restorable",
          "restore_entry_id" => "qbittorrent", "launch_argv" => ["/usr/bin/qbittorrent"],
          "startup_policy" => "launch_if_absent"
        }]
      }
    }
    {
      "ok" => true, "lifecycle_state" => "complete", "mutation" => "none",
      "data" => {"plan" => plan, "expected_digest" => "c" * 64}
    }
  end
end

class A2IncompletePackageRehearsal < A2FixtureRehearsal
  def preview(force_database_refresh: false)
    result = super
    result.dig("data", "plan", "package_evidence", "managers", "pacman", "updates")["status"] = "failed"
    result
  end
end

class A2ChangingWindowRehearsal < A2FixtureRehearsal
  def initialize(clock)
    super
    @calls = 0
  end

  def preview(force_database_refresh: false)
    @calls += 1
    result = super
    snapshot = result.dig("data", "plan", "window_snapshot")
    snapshot["active_workspace"] = {"id" => @calls, "name" => @calls.to_s}
    snapshot["windows"].first["class"] = @calls.odd? ? "kitty" : "opera"
    snapshot["windows"].first["workspace"] = snapshot["active_workspace"]
    snapshot["restorable_count"] = @calls
    result
  end
end

class A2FixtureHandoff
  attr_reader :transactions

  def initialize(clock, available: true, evidence_available: true)
    @clock = clock
    @available = available
    @evidence_available = evidence_available
    @transactions = []
  end

  def status
    {
      "available" => @available,
      "registered_desktop_id" => @available ? "soul-maintenance.desktop" : nil,
      "problems" => @available ? [] : ["fixture handoff unavailable"]
    }
  end

  def native_evidence
    return {"available" => false, "reason" => "native package evidence has not been collected"} unless @evidence_available
    evidence = A2FixtureRehearsal.new(@clock).preview.dig("data", "plan", "package_evidence")
    {
      "available" => true,
      "generated_at" => @clock.call.iso8601,
      "expires_at" => (@clock.call + 900).iso8601,
      "evidence_digest" => "e" * 64,
      "package_evidence" => evidence
    }
  end

  def reserve_evidence
    {
      "reservation_id" => "maintenance_evidence_0123456789abcdef",
      "expected_digest" => "e" * 64,
      "launch_uri" => "soul-maintenance://evidence/maintenance_evidence_0123456789abcdef/#{"e" * 64}",
      "expires_at" => (@clock.call + 600).iso8601
    }
  end

  def reserve_transaction(transaction)
    @transactions << transaction
    {
      "transaction_id" => transaction.fetch("transaction_id"),
      "expected_digest" => transaction.fetch("plan_digest"),
      "launch_uri" => "soul-maintenance://transaction/#{transaction.fetch('transaction_id')}/#{transaction.fetch('plan_digest')}",
      "deadline_at" => transaction.fetch("deadline_at")
    }
  end

  def pending_live_digest?(digest)
    @transactions.any? { |transaction| transaction["plan_digest"] == digest }
  end
end

class A2FixtureRunner
  Result = SoulCore::BoundedCommandRunner::Result
  attr_reader :calls

  def initialize(free_kib: 10 * 1024 * 1024, free_kib_delta: 0)
    @free_kib = free_kib
    @free_kib_delta = free_kib_delta
    @calls = []
  end

  def run(*argv, **_options)
    @calls << argv
    if argv.first == "df"
      available = @free_kib
      @free_kib += @free_kib_delta
      Result.new(stdout: "Filesystem 1024-blocks Used Available Capacity Mounted on\nfixture 20000000 1 #{available} 1% #{argv.last}\n", stderr: "", exit_status: 0, status: "ok", truncated: false)
    else
      Result.new(stdout: "", stderr: "", exit_status: 0, status: "ok", truncated: false)
    end
  end
end

class A2FixtureTerminal
  attr_reader :transactions

  def initialize(lifecycle: "complete", password_prompts: nil, command_status: "simulated")
    @lifecycle = lifecycle
    @password_prompts = password_prompts
    @command_status = command_status
    @transactions = []
  end

  def call(transaction_path:, mode:)
    transaction = JSON.parse(File.read(transaction_path))
    @transactions << transaction
    commands = transaction.fetch("commands").map do |command|
      {"adapter" => command.fetch("adapter"), "exit_status" => @lifecycle == "complete" ? 0 : 1, "status" => @command_status}
    end
    result = {
      "schema_version" => "soul.maintenance.transaction_result.v1",
      "transaction_id" => transaction.fetch("transaction_id"),
      "lifecycle_state" => @lifecycle,
      "password_prompts" => @password_prompts.nil? ? (mode == "live" ? 1 : 0) : @password_prompts,
      "commands" => commands,
      "sudo_ticket_invalidated" => true,
      "reboot_requested" => false,
      "reason" => @lifecycle == "complete" ? "" : "fixture failure"
    }
    File.write(transaction.fetch("result_path"), JSON.pretty_generate(result) + "\n", mode: "w", perm: 0o600)
    {"status" => @lifecycle == "complete" ? "complete" : "failed", "exit_status" => @lifecycle == "complete" ? 0 : 1, "argv" => ["/usr/bin/kitty"]}
  end
end

puts "Maintenance foreground execution A2 verification:"

clock_time = Time.utc(2026, 7, 27, 16, 0, 0)
clock = -> { clock_time }

Dir.mktmpdir("soul-maintenance-a2") do |root|
  FileUtils.mkdir_p(File.join(root, "scripts"))
  File.write(File.join(root, "scripts", "soul-maintenance-transaction"), "# fixture\n")
  runner = A2FixtureRunner.new
  terminal = A2FixtureTerminal.new
  handoff = A2FixtureHandoff.new(clock)
  service = SoulCore::MaintenanceForegroundExecutionService.new(
    root: root, clock: clock, rehearsal_service: A2FixtureRehearsal.new(clock),
    runner: runner, terminal_launcher: terminal, active_work_probe: -> { [] },
    package_lock_probe: -> { false }, privilege_transition_probe: -> { true },
    desktop_handoff: handoff,
    id_generator: -> { "0123456789abcdef" }
  )

  preview = service.preview(force_database_refresh: false)
  plan = preview.dig("data", "plan")
  check.call("preview is digest-bound and keeps live execution disabled", preview["ok"] && plan["execution_available"] == false && plan["rehearsal_available"] == true && preview.dig("data", "expected_digest").match?(/\A[a-f0-9]{64}\z/))
  check.call("trusted repository maintenance uses only pacman and excludes AUR", plan.fetch("commands").first.fetch("argv") == ["/usr/bin/sudo", "-n", "/usr/bin/pacman", "-Syu"] && plan.dig("aur_review", "included_in_unattended_maintenance") == false)
  check.call("Flatpak user and system scopes retain fixed vectors", plan.fetch("commands").map { |item| item.fetch("argv") }.include?(["/usr/bin/flatpak", "update", "--user"]) && plan.fetch("commands").map { |item| item.fetch("argv") }.include?(["/usr/bin/sudo", "-n", "/usr/bin/flatpak", "update", "--system"]))
  check.call("preflight observes disk, active work, package lock, and fixed tools", plan.dig("preflight", "blockers").empty? && plan.dig("preflight", "disk_free").length == 3 && plan.dig("preflight", "required_executables", "kitty") == "/usr/bin/kitty")

  changing_windows = SoulCore::MaintenanceForegroundExecutionService.new(
    root: root, clock: clock, rehearsal_service: A2ChangingWindowRehearsal.new(clock),
    runner: runner, terminal_launcher: terminal, active_work_probe: -> { [] },
    package_lock_probe: -> { false }, privilege_transition_probe: -> { true },
    desktop_handoff: handoff
  )
  first_window_plan = changing_windows.preview
  second_window_plan = changing_windows.preview
  check.call(
    "package-only maintenance digest ignores changing window and workspace inventory",
    first_window_plan.dig("data", "expected_digest") == second_window_plan.dig("data", "expected_digest") &&
      !first_window_plan.dig("data", "plan").key?("window_restore_summary") &&
      !first_window_plan.dig("data", "plan").key?("restore_registry_digest") &&
      first_window_plan.dig("data", "restore_evidence", "restore_registry_digest") == "b" * 64 &&
      first_window_plan.dig("data", "restore_evidence", "window_restore_summary", "restorable_count") == 1 &&
      second_window_plan.dig("data", "restore_evidence", "window_restore_summary", "restorable_count") == 2
  )

  confined_service = SoulCore::MaintenanceForegroundExecutionService.new(
    root: root, clock: clock, rehearsal_service: A2IncompletePackageRehearsal.new(clock),
    runner: runner, terminal_launcher: terminal, active_work_probe: -> { [] },
    package_lock_probe: -> { false }, privilege_transition_probe: -> { false },
    desktop_handoff: A2FixtureHandoff.new(clock, available: false, evidence_available: false)
  )
  confined = confined_service.preview
  check.call(
    "fixture rehearsal remains available while live-only evidence and sudo confinement block execution",
    confined.dig("data", "plan", "rehearsal_available") == true &&
      confined.dig("data", "plan", "execution_available") == false &&
      confined.dig("data", "plan", "preflight", "rehearsal_blockers").empty? &&
      confined.dig("data", "plan", "preflight", "live_blockers").include?("native package evidence has not been collected") &&
      confined.dig("data", "plan", "preflight", "live_blockers").include?("reviewed desktop handoff is unavailable")
  )

  wrong = service.rehearse(force_database_refresh: false, expected_digest: preview.dig("data", "expected_digest"), confirmation: "wrong")
  check.call("wrong confirmation opens no terminal and writes no receipt", wrong["lifecycle_state"] == "blocked_for_human_review" && terminal.transactions.empty? && service.receipts.dig("data", "receipts").empty?)

  stale = service.rehearse(force_database_refresh: false, expected_digest: "0" * 64, confirmation: SoulCore::MaintenanceForegroundExecutionService::CONFIRMATION)
  check.call("stale digest opens no terminal", stale["lifecycle_state"] == "blocked_for_human_review" && terminal.transactions.empty?)

  rehearsed = service.rehearse(force_database_refresh: false, expected_digest: preview.dig("data", "expected_digest"), confirmation: SoulCore::MaintenanceForegroundExecutionService::CONFIRMATION)
  receipt = rehearsed.dig("data", "receipt")
  check.call("no-mutation terminal rehearsal terminates complete", rehearsed["lifecycle_state"] == "complete" && receipt["mode"] == "rehearsal" && receipt["password_prompts"].zero? && receipt["reboot_requested"] == false)
  check.call("rehearsal transaction contains fixture adapters and no host argv", terminal.transactions.one? && terminal.transactions.first.fetch("commands").all? { |command| command.fetch("adapter").start_with?("fixture.") && command.fetch("argv").empty? })
  receipt_path = Dir.glob(File.join(root, "Soul", "private", "host_maintenance", "receipts", "*.json")).first
  check.call("receipt is private atomic bounded state", File.file?(receipt_path) && (File.stat(receipt_path).mode & 0o777) == 0o600 && JSON.parse(File.read(receipt_path))["redacted"] == true)

  live_blocked = service.execute(force_database_refresh: false, expected_digest: preview.dig("data", "expected_digest"), confirmation: SoulCore::MaintenanceForegroundExecutionService::CONFIRMATION)
  check.call("unreviewed live execution remains disabled", live_blocked["lifecycle_state"] == "blocked_for_human_review" && terminal.transactions.one?)

  busy_service = SoulCore::MaintenanceForegroundExecutionService.new(
    root: root, clock: clock, rehearsal_service: A2FixtureRehearsal.new(clock),
    runner: runner, terminal_launcher: terminal, active_work_probe: -> { ["music_generation"] },
    package_lock_probe: -> { false }, privilege_transition_probe: -> { true },
    desktop_handoff: A2FixtureHandoff.new(clock)
  )
  busy = busy_service.preview
  check.call("active Soul work blocks rehearsal and execution", busy.dig("data", "plan", "preflight", "blockers").include?("active Soul work must finish: music_generation") && busy.dig("data", "plan", "rehearsal_available") == false)

  lock_service = SoulCore::MaintenanceForegroundExecutionService.new(
    root: root, clock: clock, rehearsal_service: A2FixtureRehearsal.new(clock),
    runner: runner, terminal_launcher: terminal, active_work_probe: -> { [] },
    package_lock_probe: -> { true }, privilege_transition_probe: -> { true },
    desktop_handoff: A2FixtureHandoff.new(clock)
  )
  lock_preview = lock_service.preview
  check.call("pacman database lock blocks the exact plan", lock_preview.dig("data", "plan", "preflight", "blockers").include?("pacman database lock is present"))

  low_service = SoulCore::MaintenanceForegroundExecutionService.new(
    root: root, clock: clock, rehearsal_service: A2FixtureRehearsal.new(clock),
    runner: A2FixtureRunner.new(free_kib: 100), terminal_launcher: terminal,
    active_work_probe: -> { [] }, package_lock_probe: -> { false },
    privilege_transition_probe: -> { true }, desktop_handoff: A2FixtureHandoff.new(clock)
  )
  low_preview = low_service.preview
  check.call("insufficient disk space blocks the exact plan", low_preview.dig("data", "plan", "preflight", "blockers").any? { |item| item.include?("free-space threshold") })
end

Dir.mktmpdir("soul-maintenance-a2-volatile-disk") do |root|
  FileUtils.mkdir_p(File.join(root, "scripts"))
  File.write(File.join(root, "scripts", "soul-maintenance-transaction"), "# fixture\n")
  terminal = A2FixtureTerminal.new
  service = SoulCore::MaintenanceForegroundExecutionService.new(
    root: root, clock: clock, rehearsal_service: A2FixtureRehearsal.new(clock),
    runner: A2FixtureRunner.new(free_kib_delta: 128), terminal_launcher: terminal,
    active_work_probe: -> { [] }, package_lock_probe: -> { false },
    privilege_transition_probe: -> { true },
    desktop_handoff: A2FixtureHandoff.new(clock),
    id_generator: -> { "1234567890abcdef" }
  )
  preview = service.preview
  rehearsed = service.rehearse(
    force_database_refresh: false,
    expected_digest: preview.dig("data", "expected_digest"),
    confirmation: SoulCore::MaintenanceForegroundExecutionService::CONFIRMATION
  )
  check.call(
    "safe free-space fluctuations do not invalidate an otherwise exact reviewed plan",
    rehearsed["lifecycle_state"] == "complete" && terminal.transactions.one?
  )
end

Dir.mktmpdir("soul-maintenance-a2-live") do |root|
  FileUtils.mkdir_p(File.join(root, "scripts"))
  File.write(File.join(root, "scripts", "soul-maintenance-transaction"), "# fixture\n")
  terminal = A2FixtureTerminal.new(command_status: "complete")
  handoff = A2FixtureHandoff.new(clock)
  service = SoulCore::MaintenanceForegroundExecutionService.new(
    root: root, clock: clock, rehearsal_service: A2FixtureRehearsal.new(clock),
    runner: A2FixtureRunner.new, terminal_launcher: terminal, active_work_probe: -> { [] },
    package_lock_probe: -> { false }, privilege_transition_probe: -> { true },
    desktop_handoff: handoff,
    live_execution_enabled: true,
    id_generator: -> { "fedcba9876543210" }
  )
  preview = service.preview(force_database_refresh: true)
  live = service.execute(
    force_database_refresh: true, expected_digest: preview.dig("data", "expected_digest"),
    confirmation: SoulCore::MaintenanceForegroundExecutionService::CONFIRMATION
  )
  transaction = handoff.transactions.first
  check.call("enabled live candidate reserves one exact desktop handoff with reviewed vectors", live["lifecycle_state"] == "complete" && live.dig("data", "handoff", "launch_uri").start_with?("soul-maintenance://transaction/") && transaction["sudo_validation_argv"] == ["/usr/bin/sudo", "-v"] && transaction.fetch("commands").first.fetch("argv") == ["/usr/bin/sudo", "-n", "/usr/bin/pacman", "-Syyu"])
  check.call("live reservation performs no prompt, package command, or reboot inside the Dashboard", terminal.transactions.empty? && live.dig("data", "reboot_requested") == false && service.receipts.dig("data", "receipts").empty?)
  replay = service.execute(
    force_database_refresh: true, expected_digest: preview.dig("data", "expected_digest"),
    confirmation: SoulCore::MaintenanceForegroundExecutionService::CONFIRMATION
  )
  check.call("an exact live digest cannot be replayed", replay["lifecycle_state"] == "blocked_for_human_review" && handoff.transactions.one?)
end

Dir.mktmpdir("soul-maintenance-runner") do |root|
  transactions = File.join(root, "Soul", "private", "host_maintenance", "transactions")
  FileUtils.mkdir_p(transactions)
  id = "maintenance_tx_1111111111111111"
  result_path = File.join(transactions, "#{id}.result.json")
  transaction_path = File.join(transactions, "#{id}.json")
  transaction = {
    "schema_version" => "soul.maintenance.transaction.v1", "transaction_id" => id,
    "mode" => "live", "owner_uid" => Process.uid, "created_at" => clock.call.iso8601,
    "deadline_at" => (clock.call + 600).iso8601, "plan_digest" => "d" * 64,
    "commands" => [
      {"adapter" => "official_repository.full_upgrade", "argv" => ["/usr/bin/sudo", "-n", "/usr/bin/pacman", "-Syu"], "interactive" => true, "requires_existing_sudo_ticket" => true, "shell" => false},
      {"adapter" => "flatpak.user_update", "argv" => ["/usr/bin/flatpak", "update", "--user"], "interactive" => true, "requires_existing_sudo_ticket" => false, "shell" => false}
    ],
    "sudo_validation_argv" => ["/usr/bin/sudo", "-v"],
    "sudo_refresh_argv" => ["/usr/bin/sudo", "-n", "-v"],
    "sudo_invalidate_argv" => ["/usr/bin/sudo", "-k"],
    "reboot_allowed" => false, "result_path" => result_path
  }
  File.write(transaction_path, JSON.pretty_generate(transaction) + "\n", mode: "w", perm: 0o600)
  calls = []
  executor = lambda do |argv, _timeout, _pid_callback|
    calls << argv
    0
  end
  output = StringIO.new
  result = SoulCore::MaintenanceTransactionRunner.new(root: root, clock: clock, command_executor: executor, output: output).run(transaction_path: transaction_path, mode: "live")
  check.call("runner executes only sudo validate, exact trusted updates, and sudo invalidation", result["lifecycle_state"] == "complete" && calls == [["/usr/bin/sudo", "-v"], ["/usr/bin/sudo", "-n", "/usr/bin/pacman", "-Syu"], ["/usr/bin/flatpak", "update", "--user"], ["/usr/bin/sudo", "-k"]])
  check.call("runner result is bounded and records no reboot", JSON.parse(File.read(result_path))["reboot_requested"] == false && output.string.include?("A2 never requests a reboot"))

  bad = transaction.merge(
    "transaction_id" => "maintenance_tx_2222222222222222",
    "result_path" => File.join(transactions, "maintenance_tx_2222222222222222.result.json"),
    "commands" => [transaction.fetch("commands").first.merge("argv" => ["/bin/sh", "-c", "yay -Syu"])]
  )
  bad_path = File.join(transactions, "maintenance_tx_2222222222222222.json")
  File.write(bad_path, JSON.pretty_generate(bad) + "\n", mode: "w", perm: 0o600)
  before = calls.length
  bad_result = SoulCore::MaintenanceTransactionRunner.new(root: root, clock: clock, command_executor: executor, output: StringIO.new).run(transaction_path: bad_path, mode: "live")
  check.call("runner rejects shell or unallowlisted vectors before authentication", bad_result["lifecycle_state"] == "failed" && calls.length == before + 1 && calls.last == ["/usr/bin/sudo", "-k"])

  group_path = File.join(root, "interactive-child-process-group")
  native_runner = SoulCore::MaintenanceTransactionRunner.new(root: root, clock: clock, output: StringIO.new)
  native_status = native_runner.send(
    :spawn_interactive,
    ["/usr/bin/ruby", "-e", "File.write(ARGV.fetch(0), Process.getpgrp.to_s)", group_path],
    5,
    ->(_pid) {}
  )
  check.call(
    "interactive children remain in the visible terminal foreground process group",
    native_status.zero? && File.read(group_path).to_i == Process.getpgrp
  )

  prompt_fixture = File.join(root, "tty-prompt-fixture.rb")
  File.write(prompt_fixture, <<~RUBY)
    require "io/console"
    print "Fixture password: "
    STDOUT.flush
    value = STDIN.noecho(&:gets).to_s.strip
    puts
    exit(value == "fixture-input-token" ? 0 : 1)
  RUBY
  harness = File.join(root, "tty-runner-harness.rb")
  runner_library = File.expand_path("../lib", __dir__)
  File.write(harness, <<~RUBY)
    $LOAD_PATH.unshift(#{runner_library.inspect})
    require "soul_core/maintenance_transaction_runner"
    runner = SoulCore::MaintenanceTransactionRunner.new(root: #{root.inspect})
    status = runner.send(
      :spawn_interactive,
      ["/usr/bin/ruby", #{prompt_fixture.inspect}],
      5,
      ->(_pid) {}
    )
    exit(status)
  RUBY
  transcript = +""
  prompt_sent = false
  PTY.spawn("/usr/bin/ruby", harness) do |reader, writer, pid|
    begin
      Timeout.timeout(8) do
        loop do
          transcript << reader.readpartial(1024)
          next if prompt_sent || !transcript.include?("Fixture password:")
          writer.write("fixture-input-token\n")
          writer.flush
          prompt_sent = true
        end
      end
    rescue EOFError, Errno::EIO
      nil
    ensure
      Process.wait(pid) rescue nil
    end
  end
  check.call(
    "interactive password input is hidden by the child TTY discipline",
    prompt_sent && !transcript.include?("fixture-input-token")
  )
end

Dir.mktmpdir("soul-maintenance-facade") do |root|
  FileUtils.mkdir_p(File.join(root, "scripts"))
  File.write(File.join(root, "scripts", "soul-maintenance-transaction"), "# fixture\n")
  service = SoulCore::MaintenanceForegroundExecutionService.new(
    root: root, clock: clock, rehearsal_service: A2FixtureRehearsal.new(clock),
    runner: A2FixtureRunner.new, terminal_launcher: A2FixtureTerminal.new,
    active_work_probe: -> { [] }, package_lock_probe: -> { false },
    desktop_handoff: A2FixtureHandoff.new(clock)
  )
  facade = SoulCore::ApplicationFacade.new(root: root, clock: clock, maintenance_foreground_execution_service: service)
  request = {
    "schema_version" => "soul.application.v1", "request_id" => "maintenance-a2-preview",
    "operation" => "maintenance.execution.preview", "parameters" => {"force_database_refresh" => "false"},
    "context" => {"interface" => "dashboard_test"}
  }
  envelope = facade.call(request)
  check.call("typed facade exposes A2 preview without mutation", envelope["lifecycle_state"] == "complete" && envelope.dig("meta", "mutation") == "none" && envelope.dig("data", "plan", "automatic_reboot") == false)
end

Dir.mktmpdir("soul-maintenance-live-configuration") do |root|
  File.write(File.join(root, ".env"), "SOUL_MAINTENANCE_A2_LIVE=true\n", mode: "w", perm: 0o600)
  facade = SoulCore::ApplicationFacade.new(root: root, clock: clock)
  envelope = facade.call({
    "schema_version" => "soul.application.v1",
    "request_id" => "maintenance-a2-live-config",
    "operation" => "maintenance.execution.receipts",
    "parameters" => {"limit" => 1},
    "context" => {"interface" => "dashboard_test"}
  })
  check.call(
    "typed true configuration arms the A2 service while its public default remains disabled",
    envelope["lifecycle_state"] == "complete" &&
      envelope.dig("data", "live_execution_enabled") == true &&
      File.read(File.expand_path("../.env.example", __dir__)).include?("SOUL_MAINTENANCE_A2_LIVE=false")
  )
end

Dir.glob(File.expand_path("../docs/soul/schemas/maintenance_*.schema.json", __dir__)).each { |path| JSON.parse(File.read(path)) }
check.call("all maintenance schemas are valid JSON", true)

html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
javascript = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
check.call("Administration exposes preview, evidence handoff, terminal rehearsal, disabled live gate, and receipts",
           %w[preview-maintenance-execution refresh-maintenance-evidence rehearse-maintenance-execution execute-maintenance refresh-maintenance-receipt maintenance-receipts].all? { |id_value| html.include?("id=\"#{id_value}\"") } &&
             javascript.include?('callSoul("maintenance.execution.preview"') &&
             javascript.include?('"maintenance.evidence.reserve"') &&
             javascript.include?('"maintenance.execution.rehearsal"') &&
             javascript.include?('"maintenance.execution.execute"'))
check.call("Dashboard uses click authority and never collects a sudo password",
           javascript.include?("confirmation: preview.confirmation") &&
             !html.match?(/maintenance[^<]{0,100}password[^<]{0,100}<input/i) &&
             html.include?("No password is collected by the Dashboard"))
check.call("A2 uses only bounded dialog-scoped receipt polling and exposes no combined reboot control",
           !javascript.match?(/(?:setInterval|WebSocket|EventSource)/) &&
             javascript.scan("window.setTimeout").length == 1 &&
             javascript.include?("MAINTENANCE_EVIDENCE_POLL_LIMIT = 120") &&
             javascript.include?("MAINTENANCE_RECEIPT_POLL_LIMIT = 600") &&
             javascript.include?("state.maintenanceDeviceFlowToken !== flowToken || !dialog.open") &&
             !html.match?(/<button[^>]*id="[^"]*maintenance[^"]*"[^>]*>\s*Reboot/i))

abort "Maintenance foreground execution A2 verification failed: #{failures.join(', ')}" unless failures.empty?
puts "Maintenance foreground execution A2 verification complete."
