#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "socket"
require "stringio"
require "tmpdir"
require "time"

require_relative "../lib/soul_core/application_contract"
require_relative "../lib/soul_core/maintenance_reboot_coordinator"
require_relative "../lib/soul_core/maintenance_reboot_restore_service"
require_relative "../lib/soul_core/maintenance_resume_deployment"
require_relative "../lib/soul_core/maintenance_session_restorer"
require_relative "../lib/soul_core/maintenance_transaction_runner"

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'FAILED'}"
  errors << label unless condition
end
clock = -> { Time.utc(2026, 7, 27, 20, 0, 0) }
old_boot = "11111111-1111-1111-1111-111111111111"
new_boot = "22222222-2222-2222-2222-222222222222"

class A3RehearsalFixture
  attr_reader :registry, :snapshot

  def initialize
    @registry = {
      "schema_version" => "soul.maintenance.restore_registry.v1",
      "entries" => [
        {
          "entry_id" => "fixture.window", "identities" => ["fixture-app"],
          "process_identities" => [], "argv" => ["/usr/bin/true"],
          "maximum_instances" => 1, "title_policy" => "omit",
          "startup_policy" => "launch_window", "executable_available" => true
        },
        {
          "entry_id" => "fixture.background", "identities" => ["fixture-background"],
          "process_identities" => ["fixture-background"], "argv" => ["/usr/bin/true"],
          "maximum_instances" => 1, "title_policy" => "omit",
          "startup_policy" => "launch_if_absent", "executable_available" => true
        }
      ]
    }
    @snapshot = {
      "schema_version" => "soul.maintenance.window_snapshot.v1",
      "privacy" => {"titles_stored" => false, "raw_command_lines_stored" => false, "urls_stored" => false, "environment_stored" => false},
      "process_inventory" => {"raw_arguments_stored" => false, "unmatched_processes_stored" => false},
      "active_workspace" => {"id" => 2, "name" => "2"},
      "monitors" => [{"id" => 0, "name" => "fixture"}],
      "workspaces" => [{"id" => 2, "name" => "2"}],
      "windows" => [{
        "initial_class" => "fixture-app", "class" => "fixture-app",
        "workspace" => {"id" => 2, "name" => "2"}, "monitor_id" => 0,
        "floating" => false, "fullscreen" => 0, "pinned" => false,
        "restore_status" => "restorable", "restore_entry_id" => "fixture.window",
        "launch_argv" => ["/usr/bin/true"], "title_stored" => false
      }, {
        "initial_class" => "unknown-game", "class" => "unknown-game",
        "workspace" => {"id" => 4, "name" => "4"}, "monitor_id" => 0,
        "floating" => false, "fullscreen" => 0, "pinned" => false,
        "restore_status" => "unsupported", "restore_entry_id" => nil,
        "launch_argv" => nil, "reason" => "application identity is not allowlisted",
        "title_stored" => false
      }],
      "background_applications" => [{
        "process_identity" => "fixture-background", "restore_status" => "restorable",
        "restore_entry_id" => "fixture.background", "launch_argv" => ["/usr/bin/true"],
        "startup_policy" => "launch_if_absent", "placement" => "background_no_window",
        "raw_arguments_stored" => false
      }],
      "restorable_count" => 2, "unsupported_count" => 1
    }
  end

  def restore_registry = @registry
  def capture_window_snapshot = Marshal.load(Marshal.dump(@snapshot))
end

class A3AdapterFixture
  attr_reader :launches, :placements, :activations

  def initialize(background_running: true)
    @background_running = background_running
    @launches = []
    @placements = []
    @activations = []
    @windows = []
  end

  def wait_ready(_seconds) = true
  def recover_displays = true
  def windows = @windows
  def settle(_seconds) = true
  def process_running?(_identity) = @background_running
  def launch(entry_id, argv, attempt)
    @launches << [entry_id, argv, attempt]
    true
  end
  def wait_for_window(_identities, _excluded, _seconds)
    window = {"address" => "0xabc", "initialClass" => "fixture-app", "class" => "fixture-app"}
    @windows << window unless @windows.any? { |item| item["address"] == window["address"] }
    window
  end
  def place_window(window, record)
    @placements << [window, record]
    true
  end
  def activate_workspace(workspace)
    @activations << workspace
    true
  end
end

class A3HyprlandRunnerFixture
  attr_reader :calls

  Result = Struct.new(:stdout, :stderr, :exit_status, :status, :truncated, keyword_init: true) do
    def success? = status == "ok"
  end

  def initialize
    @calls = []
  end

  def run(*argv, **options)
    @calls << {argv: argv, options: options}
    stdout = argv.include?("monitors") ? JSON.generate([{"name" => "DP-1"}]) : ""
    Result.new(stdout: stdout, stderr: "", exit_status: 0, status: "ok", truncated: false)
  end
end

class A3PartialAdapter < A3AdapterFixture
  def launch(entry_id, argv, attempt)
    @launches << [entry_id, argv, attempt]
    false
  end

  def process_running?(_identity) = true
end

def transaction(root, clock, registry_digest, mode: "live_reboot", authority_mode: "native_prompt")
  id = "maintenance_tx_1111111111111111"
  {
    "schema_version" => "soul.maintenance.transaction.v1",
    "transaction_id" => id,
    "mode" => mode,
    "authority_mode" => authority_mode,
    "owner_uid" => Process.uid,
    "created_at" => clock.call.iso8601,
    "deadline_at" => (clock.call + 600).iso8601,
    "plan_digest" => "a" * 64,
    "commands" => (mode == "live_reboot" ? [] : [
      {"adapter" => "official_repository.full_upgrade", "argv" => ["/usr/bin/sudo", "-n", "/usr/bin/pacman", "-Syu"], "shell" => false}
    ]),
    "sudo_validation_argv" => ["/usr/bin/sudo", "-v"],
    "sudo_refresh_argv" => ["/usr/bin/sudo", "-n", "-v"],
    "sudo_invalidate_argv" => ["/usr/bin/sudo", "-k"],
    "reboot_allowed" => mode == "live_reboot",
    "reboot_argv" => (["/usr/bin/sudo", "-n", "/usr/bin/systemctl", "reboot"] if mode == "live_reboot"),
    "source_boot_id" => "11111111-1111-1111-1111-111111111111",
    "restore_registry_digest" => registry_digest,
    "result_path" => File.join(root, "Soul", "private", "host_maintenance", "transactions", "#{id}.result.json")
  }.compact
end

puts "Maintenance conditional reboot and restore A3 verification:"

tracked_registry = JSON.parse(File.binread(File.expand_path("../config/maintenance_restore_registry.json", __dir__)))
tracked_entries = tracked_registry.fetch("entries").to_h { |entry| [entry.fetch("entry_id"), entry] }
webex = tracked_entries["communication.webex"]
teams = tracked_entries["communication.teams_for_linux"]
steam = tracked_entries["games.steam"]
obsidian = tracked_entries["notes.obsidian"]
chatgpt = tracked_entries["development.chatgpt_desktop"]
winboat = tracked_entries["virtualization.winboat"]
check.call(
  "Webex, Teams, and Steam restore only when represented in the pre-reboot window or process snapshot",
  webex == {
    "entry_id" => "communication.webex",
    "identities" => ["webex"],
    "process_identities" => ["ciscocollabhost"],
    "argv" => ["/usr/bin/env", "QT_QPA_PLATFORM=wayland", "/opt/Webex/bin/CiscoCollabHost"],
    "maximum_instances" => 1,
    "title_policy" => "omit",
    "startup_policy" => "manual_after_login"
  } &&
    teams == {
      "entry_id" => "communication.teams_for_linux",
      "identities" => ["teams-for-linux"],
      "process_identities" => ["teams-for-linux"],
      "argv" => ["/usr/bin/teams-for-linux", "--gtk-version=3"],
      "maximum_instances" => 1,
      "title_policy" => "omit",
      "startup_policy" => "launch_if_absent"
    } &&
    steam == {
      "entry_id" => "games.steam",
      "identities" => ["steam"],
      "process_identities" => ["steam"],
      "argv" => ["/usr/bin/env", "NO_AT_BRIDGE=1", "/usr/bin/steam"],
      "maximum_instances" => 1,
      "title_policy" => "omit",
      "startup_policy" => "launch_if_absent"
    }
)
check.call(
  "native ChatGPT, Obsidian, and WinBoat identities use their reviewed local launch vectors",
  obsidian == {
    "entry_id" => "notes.obsidian", "identities" => ["obsidian", "md.obsidian.obsidian"],
    "process_identities" => [], "argv" => ["/usr/bin/obsidian"], "maximum_instances" => 1,
    "title_policy" => "omit", "startup_policy" => "launch_window"
  } &&
    chatgpt == {
      "entry_id" => "development.chatgpt_desktop", "identities" => ["chatgpt"],
      "process_identities" => [], "argv" => ["/usr/bin/chatgpt"], "maximum_instances" => 1,
      "title_policy" => "omit", "startup_policy" => "launch_window"
    } &&
    winboat == {
      "entry_id" => "virtualization.winboat", "identities" => ["winboat"],
      "process_identities" => ["winboat"], "argv" => ["/opt/winboat/winboat"], "maximum_instances" => 1,
      "title_policy" => "omit", "startup_policy" => "launch_if_absent"
    }
)

Dir.mktmpdir("soul-a3-hyprland") do |runtime_parent|
  runtime_root = File.join(runtime_parent, "hypr")
  signature = "fixture_signature_1234567890"
  instance = File.join(runtime_root, signature)
  FileUtils.mkdir_p(instance)
  File.write(File.join(instance, "hyprland.lock"), "#{Process.pid}\nwayland-1\n")
  UNIXServer.new(File.join(instance, ".socket.sock")).close
  runner = A3HyprlandRunnerFixture.new
  adapter = SoulCore::MaintenanceSessionRestorer::HyprlandAdapter.new(
    runner: runner, sleeper: ->(_seconds) {}, user_id: Process.uid,
    runtime_root: runtime_root, home: runtime_parent
  )
  ready = adapter.wait_ready(2)
  recovered = adapter.recover_displays
  placed = adapter.place_window(
    {"address" => "0xabc", "floating" => false, "pinned" => false, "fullscreen" => 0},
    {"workspace" => {"id" => 2}, "floating" => true, "pinned" => true, "fullscreen" => 2}
  )
  activated = adapter.activate_workspace({"id" => 2})
  monitor_call = runner.calls.find { |item| item[:argv].include?("monitors") }
  check.call("one-shot restoration discovers the live Hyprland instance without inherited session variables",
             ready &&
             monitor_call.dig(:options, :env, "HYPRLAND_INSTANCE_SIGNATURE") == signature &&
             monitor_call.dig(:options, :env, "WAYLAND_DISPLAY") == "wayland-1")
  check.call("one-shot restoration uses current typed Hyprland dispatchers for display and placement",
             recovered && placed && activated &&
             runner.calls.none? { |item| item[:argv].include?("dispatch") } &&
             runner.calls.count { |item| item[:argv].include?("eval") } == 6)
end

Dir.mktmpdir("soul-a3-runner") do |root|
  fixture = A3RehearsalFixture.new
  registry_digest = Digest::SHA256.hexdigest(JSON.generate(fixture.registry))
  coordinator = SoulCore::MaintenanceRebootCoordinator.new(
    root: root, clock: clock, rehearsal_service: fixture,
    package_lock_probe: -> { false }, active_work_probe: -> { [] },
    resume_unit_probe: -> { true }, reboot_permission_probe: -> { true },
    boot_id_reader: -> { old_boot }
  )
  calls = []
  executor = lambda do |argv, _timeout, callback|
    calls << argv
    callback.call(12_345)
    0
  end
  tx = transaction(root, clock, registry_digest)
  path = File.join(root, "Soul", "private", "host_maintenance", "transactions", "#{tx.fetch('transaction_id')}.claimed.json")
  FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
  File.write(path, JSON.pretty_generate(tx) + "\n", mode: "w", perm: 0o600)
  runner = SoulCore::MaintenanceTransactionRunner.new(
    root: root, clock: clock, command_executor: executor,
    reboot_coordinator: coordinator, sleeper: ->(_seconds) { Thread.pass },
    output: StringIO.new
  )
  result = runner.run(transaction_path: path, mode: "live_reboot")
  journal = JSON.parse(File.read(File.join(root, "Soul", "private", "host_maintenance", "pending_restore.json")))
  check.call("A3 writes a durable journal before one fixed reboot request",
             result["lifecycle_state"] == "awaiting_login" &&
             result["reboot_requested"] == true &&
             calls.include?(SoulCore::MaintenanceRebootRestoreService::FIXED_REBOOT_ARGV) &&
             journal["current_state"] == "reboot_requested" &&
             journal["reboot_requested"] == true)
  check.call("A3 uses one password prompt and invalidates its sudo ticket",
             result["password_prompts"] == 1 && result["sudo_ticket_invalidated"] == true &&
             calls.count { |argv| argv == ["/usr/bin/sudo", "-v"] } == 1 &&
             calls.include?(["/usr/bin/sudo", "-k"]))
  check.call("A3 reboot is separate from maintenance and runs no package command",
             tx.fetch("commands").empty? &&
               calls.none? { |argv| argv.include?("/usr/bin/yay") || argv.include?("/usr/bin/flatpak") })

  adapter = A3AdapterFixture.new
  restorer = SoulCore::MaintenanceSessionRestorer.new(
    root: root, clock: clock, adapter: adapter,
    rehearsal_service: fixture, boot_id_reader: -> { new_boot }
  )
  restored = restorer.run
  second = restorer.run
  check.call("post-login restoration is allowlisted, duplicate-aware, and one-shot",
             restored["lifecycle_state"] == "complete" &&
             adapter.launches.map(&:first) == ["fixture.window"] &&
             restored.dig("data", "skipped") == 1 &&
             second.dig("data", "restored") == 0 &&
             !File.exist?(File.join(root, "Soul", "private", "host_maintenance", "pending_restore.json")))
end

Dir.mktmpdir("soul-a3-passwordless") do |root|
  fixture = A3RehearsalFixture.new
  registry_digest = Digest::SHA256.hexdigest(JSON.generate(fixture.registry))
  coordinator = SoulCore::MaintenanceRebootCoordinator.new(
    root: root, clock: clock, rehearsal_service: fixture,
    package_lock_probe: -> { false }, active_work_probe: -> { [] },
    resume_unit_probe: -> { true }, reboot_permission_probe: -> { true },
    boot_id_reader: -> { old_boot }
  )
  journal = coordinator.prepare(transaction(root, clock, registry_digest, authority_mode: "root_owned_passwordless"))
  coordinator.mark_reboot_requested
  restored = SoulCore::MaintenanceSessionRestorer.new(
    root: root, clock: clock, adapter: A3AdapterFixture.new,
    rehearsal_service: fixture, boot_id_reader: -> { new_boot }
  ).run
  receipt = restored.dig("data", "receipt")
  check.call("root-owned maintenance authority records a truthful zero-prompt reboot receipt",
             journal["authority_mode"] == "root_owned_passwordless" && journal["password_prompts"] == 0 &&
             receipt["authority_mode"] == "root_owned_passwordless" && receipt["password_prompts"] == 0)
end

Dir.mktmpdir("soul-a3-manual-post-login") do |root|
  fixture = A3RehearsalFixture.new
  fixture.registry.fetch("entries") << {
    "entry_id" => "fixture.manual", "identities" => ["fixture-manual"],
    "process_identities" => ["fixture-manual"], "argv" => ["/usr/bin/true"],
    "maximum_instances" => 1, "title_policy" => "omit",
    "startup_policy" => "manual_after_login", "executable_available" => true
  }
  fixture.snapshot.fetch("windows") << {
    "initial_class" => "fixture-manual", "class" => "fixture-manual",
    "workspace" => {"id" => 3, "name" => "3"}, "monitor_id" => 0,
    "floating" => false, "fullscreen" => 0, "pinned" => false,
    "restore_status" => "restorable", "restore_entry_id" => "fixture.manual",
    "launch_argv" => ["/usr/bin/true"], "title_stored" => false
  }
  fixture.snapshot.fetch("background_applications") << {
    "process_identity" => "fixture-manual", "restore_status" => "restorable",
    "restore_entry_id" => "fixture.manual", "launch_argv" => ["/usr/bin/true"],
    "startup_policy" => "manual_after_login", "placement" => "background_no_window",
    "raw_arguments_stored" => false
  }
  fixture.snapshot["restorable_count"] += 2
  registry_digest = Digest::SHA256.hexdigest(JSON.generate(fixture.registry))
  coordinator = SoulCore::MaintenanceRebootCoordinator.new(
    root: root, clock: clock, rehearsal_service: fixture,
    package_lock_probe: -> { false }, active_work_probe: -> { [] },
    resume_unit_probe: -> { true }, reboot_permission_probe: -> { true },
    boot_id_reader: -> { old_boot }
  )
  coordinator.prepare(transaction(root, clock, registry_digest))
  coordinator.mark_reboot_requested
  adapter = A3AdapterFixture.new
  restored = SoulCore::MaintenanceSessionRestorer.new(
    root: root, clock: clock, adapter: adapter,
    rehearsal_service: fixture, boot_id_reader: -> { new_boot }
  ).run
  manual_attempt = restored.dig("data", "receipt", "restore_summary")
  check.call("reviewed manual post-login applications do not fail or launch the bounded restore",
             restored["lifecycle_state"] == "complete" &&
             adapter.launches.none? { |entry_id, _argv, _attempt| entry_id == "fixture.manual" } &&
             manual_attempt["skipped"] == 3 && manual_attempt["failed"] == 0)
end

[
  ["package lock", {package_lock_probe: -> { true }, active_work_probe: -> { [] }, resume_unit_probe: -> { true }, reboot_permission_probe: -> { true }}],
  ["active Soul work", {package_lock_probe: -> { false }, active_work_probe: -> { ["music_generation"] }, resume_unit_probe: -> { true }, reboot_permission_probe: -> { true }}],
  ["missing resume unit", {package_lock_probe: -> { false }, active_work_probe: -> { [] }, resume_unit_probe: -> { false }, reboot_permission_probe: -> { true }}],
  ["unavailable reboot permission", {package_lock_probe: -> { false }, active_work_probe: -> { [] }, resume_unit_probe: -> { true }, reboot_permission_probe: -> { false }}]
].each do |label, probes|
  Dir.mktmpdir("soul-a3-blocker") do |root|
    fixture = A3RehearsalFixture.new
    digest = Digest::SHA256.hexdigest(JSON.generate(fixture.registry))
    coordinator = SoulCore::MaintenanceRebootCoordinator.new(
      root: root, clock: clock, rehearsal_service: fixture,
      boot_id_reader: -> { old_boot }, **probes
    )
    blocked = begin
      coordinator.prepare(transaction(root, clock, digest))
      false
    rescue StandardError
      true
    end
    check.call("#{label} blocks journal creation and reboot preparation",
               blocked && !File.exist?(File.join(root, "Soul", "private", "host_maintenance", "pending_restore.json")))
  end
end

Dir.mktmpdir("soul-a3-same-boot") do |root|
  fixture = A3RehearsalFixture.new
  digest = Digest::SHA256.hexdigest(JSON.generate(fixture.registry))
  coordinator = SoulCore::MaintenanceRebootCoordinator.new(
    root: root, clock: clock, rehearsal_service: fixture,
    package_lock_probe: -> { false }, active_work_probe: -> { [] },
    resume_unit_probe: -> { true }, reboot_permission_probe: -> { true },
    boot_id_reader: -> { old_boot }
  )
  coordinator.prepare(transaction(root, clock, digest))
  coordinator.mark_reboot_requested
  adapter = A3AdapterFixture.new
  result = SoulCore::MaintenanceSessionRestorer.new(
    root: root, clock: clock, adapter: adapter,
    rehearsal_service: fixture, boot_id_reader: -> { old_boot }
  ).run
  check.call("same-boot journal fails closed without launching an application",
             result["lifecycle_state"] == "blocked_for_human_review" && adapter.launches.empty?)
end

Dir.mktmpdir("soul-a3-registry-drift") do |root|
  fixture = A3RehearsalFixture.new
  original_digest = Digest::SHA256.hexdigest(JSON.generate(fixture.registry))
  coordinator = SoulCore::MaintenanceRebootCoordinator.new(
    root: root, clock: clock, rehearsal_service: fixture,
    package_lock_probe: -> { false }, active_work_probe: -> { [] },
    resume_unit_probe: -> { true }, reboot_permission_probe: -> { true },
    boot_id_reader: -> { old_boot }
  )
  coordinator.prepare(transaction(root, clock, original_digest))
  coordinator.mark_reboot_requested
  fixture.registry.fetch("entries").first["argv"] = ["/usr/bin/false"]
  adapter = A3AdapterFixture.new
  result = SoulCore::MaintenanceSessionRestorer.new(
    root: root, clock: clock, adapter: adapter,
    rehearsal_service: fixture, boot_id_reader: -> { new_boot }
  ).run
  check.call("changed restore registry fails closed without launching an application",
             result["lifecycle_state"] == "blocked_for_human_review" && adapter.launches.empty?)
end

Dir.mktmpdir("soul-a3-partial") do |root|
  fixture = A3RehearsalFixture.new
  digest = Digest::SHA256.hexdigest(JSON.generate(fixture.registry))
  coordinator = SoulCore::MaintenanceRebootCoordinator.new(
    root: root, clock: clock, rehearsal_service: fixture,
    package_lock_probe: -> { false }, active_work_probe: -> { [] },
    resume_unit_probe: -> { true }, reboot_permission_probe: -> { true },
    boot_id_reader: -> { old_boot }
  )
  coordinator.prepare(transaction(root, clock, digest))
  coordinator.mark_reboot_requested
  adapter = A3PartialAdapter.new
  result = SoulCore::MaintenanceSessionRestorer.new(
    root: root, clock: clock, adapter: adapter,
    rehearsal_service: fixture, boot_id_reader: -> { new_boot }
  ).run
  check.call("partial restoration terminates for human review after one retry",
             result["lifecycle_state"] == "blocked_for_human_review" &&
             adapter.launches.length == 2 &&
             !File.exist?(File.join(root, "Soul", "private", "host_maintenance", "pending_restore.json")))
end

Dir.mktmpdir("soul-a3-stale") do |root|
  fixture = A3RehearsalFixture.new
  digest = Digest::SHA256.hexdigest(JSON.generate(fixture.registry))
  coordinator = SoulCore::MaintenanceRebootCoordinator.new(
    root: root, clock: clock, rehearsal_service: fixture,
    package_lock_probe: -> { false }, active_work_probe: -> { [] },
    resume_unit_probe: -> { true }, reboot_permission_probe: -> { true },
    boot_id_reader: -> { old_boot }
  )
  coordinator.prepare(transaction(root, clock, digest))
  coordinator.mark_reboot_requested
  adapter = A3AdapterFixture.new
  late_clock = -> { clock.call + 1_801 }
  result = SoulCore::MaintenanceSessionRestorer.new(
    root: root, clock: late_clock, adapter: adapter,
    rehearsal_service: fixture, boot_id_reader: -> { new_boot }
  ).run
  check.call("stale post-login journal is consumed and never launches later",
             result["lifecycle_state"] == "blocked_for_human_review" &&
             adapter.launches.empty? &&
             !File.exist?(File.join(root, "Soul", "private", "host_maintenance", "pending_restore.json")))
end

Dir.mktmpdir("soul-a3-tamper") do |root|
  fixture = A3RehearsalFixture.new
  digest = Digest::SHA256.hexdigest(JSON.generate(fixture.registry))
  coordinator = SoulCore::MaintenanceRebootCoordinator.new(
    root: root, clock: clock, rehearsal_service: fixture,
    package_lock_probe: -> { false }, active_work_probe: -> { [] },
    resume_unit_probe: -> { true }, reboot_permission_probe: -> { true },
    boot_id_reader: -> { old_boot }
  )
  coordinator.prepare(transaction(root, clock, digest))
  coordinator.mark_reboot_requested
  path = File.join(root, "Soul", "private", "host_maintenance", "pending_restore.json")
  journal = JSON.parse(File.read(path))
  journal["source_boot_id"] = "33333333-3333-3333-3333-333333333333"
  File.write(path, JSON.pretty_generate(journal) + "\n", mode: "w", perm: 0o600)
  adapter = A3AdapterFixture.new
  result = SoulCore::MaintenanceSessionRestorer.new(
    root: root, clock: clock, adapter: adapter,
    rehearsal_service: fixture, boot_id_reader: -> { new_boot }
  ).run
  check.call("tampered journal is quarantined without restoration",
             result["lifecycle_state"] == "blocked_for_human_review" && adapter.launches.empty?)
end

Dir.mktmpdir("soul-a3-a2-boundary") do |root|
  fixture = A3RehearsalFixture.new
  digest = Digest::SHA256.hexdigest(JSON.generate(fixture.registry))
  tx = transaction(root, clock, digest, mode: "live")
  path = File.join(root, "Soul", "private", "host_maintenance", "transactions", "#{tx.fetch('transaction_id')}.claimed.json")
  FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
  File.write(path, JSON.pretty_generate(tx) + "\n", mode: "w", perm: 0o600)
  calls = []
  executor = ->(argv, _timeout, callback) { calls << argv; callback.call(1); 0 }
  result = SoulCore::MaintenanceTransactionRunner.new(root: root, clock: clock, command_executor: executor, sleeper: ->(_seconds) { Thread.pass }, output: StringIO.new).run(transaction_path: path, mode: "live")
  check.call("existing A2 path remains incapable of reboot",
             result["lifecycle_state"] == "complete" && result["reboot_requested"] == false &&
             !calls.include?(SoulCore::MaintenanceRebootRestoreService::FIXED_REBOOT_ARGV))
end

class A3ForegroundFixture
  def initialize
    @preview_count = 0
  end

  def preview(force_database_refresh:)
    @preview_count += 1
    plan = {
      "force_database_refresh" => force_database_refresh == true || force_database_refresh == "true",
      "commands" => [{"adapter" => "official_repository.full_upgrade", "argv" => ["/usr/bin/sudo", "-n", "/usr/bin/pacman", "-Syu"], "shell" => false}],
      "flatpak_installations" => [],
      "restore_registry_digest" => "b" * 64,
      "window_restore_summary" => {"restorable_count" => 1, "unsupported_count" => 0},
      "preflight" => {
        "live_blockers" => [], "rehearsal_blockers" => [],
        "disk_free" => [{"path" => "/", "mount" => "/", "available_kib" => 1_000_000 - @preview_count}]
      },
      "expected_digest" => "c" * 64
    }
    {"ok" => true, "lifecycle_state" => "complete", "data" => {"plan" => plan}}
  end
end

class A3HandoffFixture
  attr_reader :transaction
  def pending_live_digest?(_digest) = false
  def reserve_transaction(value)
    @transaction = value
    {"launch_uri" => "soul-maintenance://transaction/#{value.fetch('transaction_id')}/#{"d" * 64}"}
  end
  def status = {"available" => true}
end

class A3ResumeFixture
  def status
    {"data" => {"unit_name" => "soul-maintenance-resume.service", "installed_exact" => true, "enabled" => true, "ready" => true, "persistent_process" => false, "restart_policy" => "none", "timer" => false}}
  end
end

Dir.mktmpdir("soul-a3-service") do |root|
  handoff = A3HandoffFixture.new
  disabled = SoulCore::MaintenanceRebootRestoreService.new(
    root: root, clock: clock, foreground_service: A3ForegroundFixture.new,
    desktop_handoff: handoff, resume_deployment: A3ResumeFixture.new,
    live_execution_enabled: false, boot_id_reader: -> { old_boot },
    reboot_permission_probe: -> { true }, id_generator: -> { "1234567890abcdef" }
  )
  preview = disabled.preview(force_database_refresh: false)
  blocked = disabled.execute(force_database_refresh: false, expected_digest: preview.dig("data", "expected_digest"), confirmation: SoulCore::MaintenanceRebootRestoreService::CONFIRMATION)
  check.call("tracked A3 behavior remains disabled without a supervised local gate",
             preview.dig("data", "plan", "execution_available") == false && blocked["lifecycle_state"] == "blocked_for_human_review")

  enabled = SoulCore::MaintenanceRebootRestoreService.new(
    root: root, clock: clock, foreground_service: A3ForegroundFixture.new,
    desktop_handoff: handoff, resume_deployment: A3ResumeFixture.new,
    live_execution_enabled: true, boot_id_reader: -> { old_boot },
    reboot_permission_probe: -> { true }, id_generator: -> { "1234567890abcdef" }
  )
  ready = enabled.preview(force_database_refresh: false)
  reserved = enabled.execute(force_database_refresh: false, expected_digest: ready.dig("data", "expected_digest"), confirmation: SoulCore::MaintenanceRebootRestoreService::CONFIRMATION)
  check.call("enabled A3 reserves only one exact desktop handoff and does not reboot in the Dashboard",
             ready.dig("data", "plan", "execution_available") == true &&
             ready.dig("data", "plan", "maintenance_replay") == false &&
             ready.dig("data", "plan", "commands") == [] &&
             reserved["lifecycle_state"] == "complete" &&
             handoff.transaction["mode"] == "live_reboot" &&
             handoff.transaction["commands"] == [] &&
             handoff.transaction["reboot_argv"] == SoulCore::MaintenanceRebootRestoreService::FIXED_REBOOT_ARGV &&
             reserved.dig("data", "reboot_requested") == false)
  check.call("safe raw disk-space fluctuations do not invalidate an exact A3 review",
             reserved.dig("data", "plan", "preflight", "disk_free", 0, "available_kib") <
               ready.dig("data", "plan", "preflight", "disk_free", 0, "available_kib"))
end

Dir.mktmpdir("soul-a3-deployment") do |home|
  commands = []
  runner = lambda do |argv|
    commands << argv
    if argv.include?("is-enabled")
      {"success" => true, "stdout" => "enabled\n", "stderr" => ""}
    else
      {"success" => true, "stdout" => "", "stderr" => ""}
    end
  end
  deployment = SoulCore::MaintenanceResumeDeployment.new(root: File.expand_path("..", __dir__), home: home, command_runner: runner)
  unit = deployment.unit_content
  waiting = deployment.install(confirmation: nil)
  installed = deployment.install(confirmation: SoulCore::MaintenanceResumeDeployment::CONFIRM_INSTALL)
  status = deployment.status
  check.call("resume deployment is one-shot without restart, timer, watcher, or network listener",
             unit.include?("Type=oneshot") && unit.include?("ConditionPathExists=") &&
             !unit.include?("Restart=") && !unit.include?("[Timer]") &&
             deployment.plan.dig("data", "persistent_process") == false)
  check.call("resume deployment requires exact confirmation and never starts the unit during install",
             waiting["lifecycle_state"] == "awaiting_input" &&
             installed["lifecycle_state"] == "complete" &&
             status.dig("data", "ready") == true &&
             deployment.plan["mutation"] == "none" &&
             status["mutation"] == "none" &&
             installed["mutation"] == "local_service_configuration" &&
             commands.none? { |argv| argv.include?("start") || argv.include?("restart") })
end

contract = SoulCore::ApplicationContract::OPERATIONS
html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
javascript = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
check.call("typed Dashboard exposes A3 preview, execute, and status without password fields or polling",
           %w[maintenance.reboot_restore.preview maintenance.reboot_restore.execute maintenance.reboot_restore.status].all? { |operation| contract.key?(operation) } &&
           html.include?('id="preview-maintenance-reboot"') &&
           html.include?('id="execute-maintenance-reboot"') &&
           javascript.include?('"maintenance.reboot_restore.preview"') &&
           javascript.include?('"maintenance.reboot_restore.execute"') &&
           !html.match?(/maintenance-reboot[^<]{0,100}password[^<]{0,100}<input/i) &&
           !javascript.match?(/maintenanceReboot.{0,200}(?:setInterval|WebSocket|EventSource)/m))

Dir.glob(File.expand_path("../docs/soul/schemas/maintenance_*.schema.json", __dir__)).each { |path| JSON.parse(File.read(path)) }
check.call("all maintenance schemas are valid JSON", true)
check.call("public A3 default remains disabled", File.read(File.expand_path("../.env.example", __dir__)).include?("SOUL_MAINTENANCE_A3_LIVE=false"))

abort "Maintenance A3 verification failed: #{errors.join(', ')}" unless errors.empty?
puts "Maintenance conditional reboot and restore A3 verification complete."
