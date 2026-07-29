#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "fileutils"
require "tmpdir"

require_relative "../lib/soul_core/bounded_command_runner"
require_relative "../lib/soul_core/maintenance_device_control_service"
require_relative "../lib/soul_core/maintenance_fleet_status_deployment"
require_relative "../lib/soul_core/maintenance_fleet_status_service"

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

class C1FleetStub
  attr_reader :collect_count

  def initialize
    @collect_count = 0
  end

  def collect
    @collect_count += 1
    {"ok" => true, "lifecycle_state" => "complete", "mutation" => "status_cache", "data" => {"schema_version" => "soul.maintenance.fleet_status.v1", "devices" => [{"id" => "forge"}]}}
  end

  def snapshot
    {"ok" => true, "lifecycle_state" => "complete", "mutation" => "none", "data" => {"schema_version" => "soul.maintenance.fleet_status.v1", "devices" => []}}
  end
end

class C1Runner
  attr_reader :calls

  def initialize(reconnect: true, readiness_after: 0)
    @calls = []
    @boot_reads = 0
    @reconnect = reconnect
    @readiness_after = readiness_after
    @readiness_round = 0
  end

  def run(*command, **options)
    argv = command.flatten.map(&:to_s)
    @calls << {"argv" => argv, "options" => options}
    remote = argv.drop_while { |part| !%w[proxmox-maintenance pihole-maintenance].include?(part) }.drop(1)
    if remote == ["/usr/bin/cat", "/proc/sys/kernel/random/boot_id"]
      @boot_reads += 1
      return ok(@boot_reads == 1 || !@reconnect ? "boot-old\n" : "boot-new\n")
    end
    return failed(255) if remote == ["/usr/bin/systemctl", "reboot"]
    if remote == ["/usr/bin/pveversion"]
      @readiness_round += 1
      return ok(@readiness_round <= @readiness_after ? "" : "pve-manager/9.2.5\n")
    end
    return ok("status: running\n") if remote == ["/usr/sbin/pct", "status", "100"]
    return ok("active\nactive\n") if remote == ["/usr/bin/systemctl", "is-active", "pihole-FTL", "unbound"]
    return ok("Core version is v6.4.3\nWeb version is v6.6\nFTL version is v6.7\n") if remote == ["/usr/local/bin/pihole", "-v"]
    return ok("FTL is listening on port 53\nPi-hole blocking is enabled\n") if remote == ["/usr/local/bin/pihole", "status"]
    ok("")
  end

  private

  def ok(stdout)
    SoulCore::BoundedCommandRunner::Result.new(stdout: stdout, stderr: "", exit_status: 0, status: "ok", truncated: false)
  end

  def failed(code)
    SoulCore::BoundedCommandRunner::Result.new(stdout: "", stderr: "", exit_status: code, status: "failed", truncated: false)
  end
end

puts "Maintenance device control C1 verification:"

Dir.mktmpdir("soul-device-control-") do |root|
  fleet = C1FleetStub.new
  disabled_runner = C1Runner.new
  disabled = SoulCore::MaintenanceDeviceControlService.new(
    root: root, fleet_status_service: fleet, runner: disabled_runner,
    clock: -> { Time.utc(2026, 7, 27, 22, 0, 0) }, sleeper: ->(_seconds) {}, live_execution_enabled: false,
    process_env: {"SOUL_FLEET_PIHOLE_LABEL" => "Warden"}
  )
  forge_preview = disabled.preview(device_id: "forge", action: "maintenance")
  forge_plan = forge_preview.dig("data", "plan")
  check.call("preview binds one fixed device and exposes no fleet-wide action",
             forge_preview["lifecycle_state"] == "complete" &&
               forge_plan["device_id"] == "forge" &&
               forge_plan["fleet_wide"] == false &&
               forge_plan["ssh_alias"] == "proxmox-maintenance" &&
               forge_plan["commands"].all? { |entry| entry["argv"].first.start_with?("/usr/") })

  disabled_result = disabled.execute(
    device_id: "forge", action: "maintenance",
    confirmation: forge_preview.dig("data", "confirmation"),
    expected_digest: forge_preview.dig("data", "expected_digest")
  )
  check.call("remote mutation remains disabled by default",
             disabled_result["lifecycle_state"] == "blocked_for_human_review" && disabled_runner.calls.empty?)
  warden_preview = disabled.preview(device_id: "pihole", action: "maintenance")
  check.call("deployment label changes presentation without changing the fixed Pi-hole target",
             warden_preview.dig("data", "plan", "device_label") == "Warden" &&
               warden_preview.dig("data", "plan", "device_id") == "pihole" &&
               warden_preview.dig("data", "plan", "ssh_alias") == "pihole-maintenance")

  rejected_workstation_ids = %w[workstation maven].all? do |device_id|
    disabled.preview(device_id: device_id, action: "maintenance")["lifecycle_state"] == "awaiting_input"
  end
  check.call("remote service cannot target the local workstation, its legacy alias, or a request-supplied host",
             rejected_workstation_ids)

  lock_clock = Time.utc(2026, 7, 27, 22, 2, 0)
  lock_case = lambda do |name, process_alive:|
    case_root = File.join(root, "lock-cases", name)
    fleet = C1FleetStub.new
    runner = C1Runner.new
    service = SoulCore::MaintenanceDeviceControlService.new(
      root: case_root, fleet_status_service: fleet, runner: runner,
      clock: -> { lock_clock }, sleeper: ->(_seconds) {}, live_execution_enabled: true,
      process_alive: process_alive, id_generator: -> { "#{name}fixture" }
    )
    state_root = File.join(case_root, "Soul", "private", "host_maintenance")
    FileUtils.mkdir_p(state_root)
    [service, runner, state_root]
  end

  live_lock_service, live_lock_runner, live_lock_root = lock_case.call("live", process_alive: ->(_pid) { true })
  live_lock_path = File.join(live_lock_root, "operation.lock")
  File.write(live_lock_path, JSON.generate({"owner_pid" => Process.pid, "started_at" => lock_clock.iso8601}))
  live_lock_preview = live_lock_service.preview(device_id: "forge", action: "maintenance")
  live_lock_result = live_lock_service.execute(
    device_id: "forge", action: "maintenance",
    confirmation: live_lock_preview.dig("data", "confirmation"),
    expected_digest: live_lock_preview.dig("data", "expected_digest")
  )
  check.call("a live operation owner remains authoritative and blocks mutation",
             live_lock_result["lifecycle_state"] == "blocked_for_human_review" &&
               live_lock_runner.calls.empty? &&
               File.file?(live_lock_path) &&
               Dir.glob("#{live_lock_path}.stale-*").empty?)

  dead_lock_service, dead_lock_runner, dead_lock_root = lock_case.call("dead", process_alive: ->(_pid) { false })
  dead_lock_path = File.join(dead_lock_root, "operation.lock")
  File.write(dead_lock_path, JSON.generate({"owner_pid" => 424_242, "started_at" => lock_clock.iso8601}))
  dead_lock_preview = dead_lock_service.preview(device_id: "forge", action: "maintenance")
  dead_lock_result = dead_lock_service.execute(
    device_id: "forge", action: "maintenance",
    confirmation: dead_lock_preview.dig("data", "confirmation"),
    expected_digest: dead_lock_preview.dig("data", "expected_digest")
  )
  check.call("a dead-owner lock is quarantined once before the fixed transaction",
             dead_lock_result["lifecycle_state"] == "complete" &&
               dead_lock_runner.calls.length == 2 &&
               !File.exist?(dead_lock_path) &&
               Dir.glob("#{dead_lock_path}.stale-*").length == 1)

  reused_lock_service, reused_lock_runner, reused_lock_root = lock_case.call("reused-pid", process_alive: ->(_pid) { true })
  reused_lock_path = File.join(reused_lock_root, "operation.lock")
  File.write(
    reused_lock_path,
    JSON.generate({
      "owner_pid" => Process.pid,
      "owner_start_ticks" => "not-the-current-process-start",
      "started_at" => lock_clock.iso8601
    })
  )
  reused_lock_preview = reused_lock_service.preview(device_id: "forge", action: "maintenance")
  reused_lock_result = reused_lock_service.execute(
    device_id: "forge", action: "maintenance",
    confirmation: reused_lock_preview.dig("data", "confirmation"),
    expected_digest: reused_lock_preview.dig("data", "expected_digest")
  )
  check.call("a reused live PID with a different process start identity is stale",
             reused_lock_result["lifecycle_state"] == "complete" &&
               reused_lock_runner.calls.length == 2 &&
               !File.exist?(reused_lock_path) &&
               Dir.glob("#{reused_lock_path}.stale-*").length == 1)

  empty_lock_service, empty_lock_runner, empty_lock_root = lock_case.call("young-empty", process_alive: ->(_pid) { false })
  empty_lock_path = File.join(empty_lock_root, "operation.lock")
  FileUtils.touch(empty_lock_path)
  File.utime(lock_clock, lock_clock, empty_lock_path)
  empty_lock_preview = empty_lock_service.preview(device_id: "forge", action: "maintenance")
  empty_lock_result = empty_lock_service.execute(
    device_id: "forge", action: "maintenance",
    confirmation: empty_lock_preview.dig("data", "confirmation"),
    expected_digest: empty_lock_preview.dig("data", "expected_digest")
  )
  check.call("a young empty lock is treated as an acquisition race and never bypassed",
             empty_lock_result["lifecycle_state"] == "blocked_for_human_review" &&
               empty_lock_runner.calls.empty? &&
               File.file?(empty_lock_path))

  malformed_lock_service, malformed_lock_runner, malformed_lock_root = lock_case.call("old-malformed", process_alive: ->(_pid) { false })
  malformed_lock_path = File.join(malformed_lock_root, "operation.lock")
  File.write(malformed_lock_path, "{incomplete")
  stale_time = lock_clock - SoulCore::MaintenanceDeviceControlService::LOCK_RECOVERY_GRACE_SECONDS - 1
  File.utime(stale_time, stale_time, malformed_lock_path)
  malformed_lock_preview = malformed_lock_service.preview(device_id: "forge", action: "maintenance")
  malformed_lock_result = malformed_lock_service.execute(
    device_id: "forge", action: "maintenance",
    confirmation: malformed_lock_preview.dig("data", "confirmation"),
    expected_digest: malformed_lock_preview.dig("data", "expected_digest")
  )
  check.call("an old malformed or empty lock is quarantined after the race grace period",
             malformed_lock_result["lifecycle_state"] == "complete" &&
               malformed_lock_runner.calls.length == 2 &&
               !File.exist?(malformed_lock_path) &&
               Dir.glob("#{malformed_lock_path}.stale-*").length == 1)

  replacement_service, _replacement_runner, replacement_root = lock_case.call("replacement", process_alive: ->(_pid) { true })
  replacement_path = File.join(replacement_root, "operation.lock")
  owned_descriptor = replacement_service.send(:acquire_lock)
  File.rename(replacement_path, "#{replacement_path}.moved")
  File.write(replacement_path, JSON.generate({"owner_pid" => Process.pid}))
  replacement_service.send(:release_lock, owned_descriptor)
  check.call("lock cleanup cannot delete a replacement lock with a different inode", File.file?(replacement_path))

  maintenance_runner = C1Runner.new
  maintenance_fleet = C1FleetStub.new
  maintenance = SoulCore::MaintenanceDeviceControlService.new(
    root: root, fleet_status_service: maintenance_fleet, runner: maintenance_runner,
    clock: -> { Time.utc(2026, 7, 27, 22, 5, 0) }, sleeper: ->(_seconds) {}, live_execution_enabled: true,
    id_generator: -> { "maintenancefixture" }
  )
  preview = maintenance.preview(device_id: "pihole", action: "maintenance")
  progress_events = []
  wrong = maintenance.execute(
    device_id: "pihole", action: "maintenance",
    confirmation: preview.dig("data", "confirmation"),
    expected_digest: "0" * 64
  )
  check.call("stale or wrong digest runs no command", wrong["lifecycle_state"] == "blocked_for_human_review" && maintenance_runner.calls.empty?)

  completed = maintenance.execute(
    device_id: "pihole", action: "maintenance",
    confirmation: preview.dig("data", "confirmation"),
    expected_digest: preview.dig("data", "expected_digest"),
    progress: ->(event) { progress_events << event }
  )
  remote_commands = maintenance_runner.calls.map { |call| call["argv"] }
  check.call("Pi-hole maintenance uses only three fixed shell-free steps and recollects status",
             completed["lifecycle_state"] == "complete" &&
               remote_commands.length == 3 &&
               remote_commands.none? { |argv| argv.any? { |part| %w[sh bash zsh -c].include?(part) } } &&
               remote_commands.none? { |argv| argv.include?("reboot") } &&
               progress_events.first["stage"] == "authorized" &&
               progress_events.last["stage"] == "collecting" &&
               maintenance_fleet.collect_count == 1)

  reboot_runner = C1Runner.new(reconnect: true, readiness_after: 1)
  reboot_fleet = C1FleetStub.new
  reboot = SoulCore::MaintenanceDeviceControlService.new(
    root: root, fleet_status_service: reboot_fleet, runner: reboot_runner,
    clock: -> { Time.utc(2026, 7, 27, 22, 10, 0) }, sleeper: ->(_seconds) {}, live_execution_enabled: true,
    id_generator: -> { "rebootfixture" }
  )
  reboot_preview = reboot.preview(device_id: "forge", action: "reboot")
  reboot_result = reboot.execute(
    device_id: "forge", action: "reboot",
    confirmation: reboot_preview.dig("data", "confirmation"),
    expected_digest: reboot_preview.dig("data", "expected_digest")
  )
  reboot_requests = reboot_runner.calls.count { |call| call["argv"].last(2) == ["/usr/bin/systemctl", "reboot"] }
  reboot_evidence = reboot_result.dig("data", "receipt", "evidence") || []
  check.call("Forge reboot discloses Pi-hole impact, sends one request, waits for fixed readiness, and recollects",
             reboot_preview.dig("data", "plan", "impact").join.include?("Pi-hole") &&
               reboot_preview.dig("data", "plan", "readiness").length == 5 &&
               reboot_preview.dig("data", "plan", "readiness").count { |check| check["ssh_alias"] == "pihole-maintenance" } == 3 &&
               reboot_requests == 1 &&
               reboot_evidence.any? { |entry| entry["status"] == "not_ready" } &&
               reboot_evidence.any? { |entry| entry["adapter"].start_with?("reboot.readiness.") && entry["status"] == "ok" } &&
               reboot_result["lifecycle_state"] == "complete" &&
               reboot_fleet.collect_count == 1)

  unready_runner = C1Runner.new(reconnect: true, readiness_after: SoulCore::MaintenanceDeviceControlService::RECONNECT_ATTEMPTS + 1)
  unready_fleet = C1FleetStub.new
  unready_reboot = SoulCore::MaintenanceDeviceControlService.new(
    root: root, fleet_status_service: unready_fleet, runner: unready_runner,
    clock: -> { Time.utc(2026, 7, 27, 22, 12, 0) }, sleeper: ->(_seconds) {}, live_execution_enabled: true
  )
  unready_preview = unready_reboot.preview(device_id: "forge", action: "reboot")
  unready_result = unready_reboot.execute(
    device_id: "forge", action: "reboot",
    confirmation: unready_preview.dig("data", "confirmation"),
    expected_digest: unready_preview.dig("data", "expected_digest")
  )
  unready_requests = unready_runner.calls.count { |call| call["argv"].last(2) == ["/usr/bin/systemctl", "reboot"] }
  check.call("changed boot without reviewed readiness stops without recollection or reboot retry",
             unready_result["lifecycle_state"] == "blocked_for_human_review" &&
               unready_result.dig("data", "receipt", "summary").to_s.include?("did not pass reviewed readiness") &&
               unready_requests == 1 &&
               unready_fleet.collect_count == 0)

  failed_runner = C1Runner.new(reconnect: false)
  failed_fleet = C1FleetStub.new
  failed_reboot = SoulCore::MaintenanceDeviceControlService.new(
    root: root, fleet_status_service: failed_fleet, runner: failed_runner,
    clock: -> { Time.utc(2026, 7, 27, 22, 15, 0) }, sleeper: ->(_seconds) {}, live_execution_enabled: true
  )
  failed_preview = failed_reboot.preview(device_id: "pihole", action: "reboot")
  failed_result = failed_reboot.execute(
    device_id: "pihole", action: "reboot",
    confirmation: failed_preview.dig("data", "confirmation"),
    expected_digest: failed_preview.dig("data", "expected_digest")
  )
  failed_requests = failed_runner.calls.count { |call| call["argv"].last(2) == ["/usr/bin/systemctl", "reboot"] }
  check.call("reconnect exhaustion stops for review without reboot retry or replacing the prior snapshot",
             failed_result["lifecycle_state"] == "blocked_for_human_review" &&
               failed_requests == 1 &&
               failed_fleet.collect_count == 0)

  deployment = SoulCore::MaintenanceFleetStatusDeployment.new(
    root: root, home: root, ruby_path: RbConfig.ruby, systemctl_path: "/usr/bin/systemctl"
  )
  timer = deployment.rendered.fetch(SoulCore::MaintenanceFleetStatusDeployment::TIMER)
  unit = deployment.rendered.fetch(SoulCore::MaintenanceFleetStatusDeployment::SERVICE)
  check.call("scheduled collector is one-shot, noon/midnight only, persistent, and mutation-free",
             timer.scan("OnCalendar=").length == 2 &&
               timer.include?("*-*-* 00:00:00") &&
               timer.include?("*-*-* 12:00:00") &&
               timer.include?("Persistent=true") &&
               unit.include?("Type=oneshot") &&
               !unit.include?("Restart=") &&
               !unit.match?(/maintenance\\.device|apt-get|systemctl reboot/))

  snapshot_service = SoulCore::MaintenanceFleetStatusService.new(root: root)
  snapshot_data = {
    "schema_version" => "soul.maintenance.fleet_status.v1",
    "collected_at" => "2026-07-27T22:20:00Z",
    "devices" => [{"id" => "maven"}],
    "summary" => {"device_count" => 1},
    "topology" => {
      "network" => {"lan_node_ids" => ["maven"], "cloud_node_ids" => ["internet"]},
      "nodes" => [{"id" => "maven"}, {"id" => "internet"}],
      "edges" => [{"from" => "maven", "to" => "internet"}]
    },
    "refreshed_device_id" => "maven"
  }
  snapshot_service.send(:persist_snapshot, snapshot_data)
  snapshot = snapshot_service.snapshot
  snapshot_path = File.join(root, "Soul", "private", "host_maintenance", "fleet_status.json")
  check.call("legacy fleet snapshots are private, schema-checked, and read through the workstation compatibility alias",
             snapshot["lifecycle_state"] == "complete" &&
               snapshot.dig("data", "devices", 0, "id") == "workstation" &&
               snapshot.dig("data", "topology", "nodes", 0, "id") == "workstation" &&
               snapshot.dig("data", "topology", "edges", 0, "from") == "workstation" &&
               snapshot.dig("data", "topology", "network", "lan_node_ids") == ["workstation"] &&
               snapshot.dig("data", "refreshed_device_id") == "workstation" &&
               (File.stat(snapshot_path).mode & 0o777) == 0o600 &&
               Dir.glob("#{snapshot_path}.tmp-*").empty?)
end

html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
javascript = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
http = File.read(File.expand_path("../lib/soul_core/dashboard_http_application.rb", __dir__))
check.call("Dashboard removes visible A1/A2/A3 cards and generates exactly two device actions",
           html.include?('id="maintenance-legacy-controls" hidden') &&
             javascript.include?('["maintenance", "reboot"].forEach') &&
             html.include?('id="maintenance-device-dialog"'))
check.call("workstation dialog automatically refreshes evidence with bounded polling and retains one reviewed click gate",
           !html.include?('id="maintenance-workstation-evidence-actions"') &&
             !html.include?('id="refresh-maintenance-device-evidence"') &&
             !html.include?('id="recheck-maintenance-device-preflight"') &&
             javascript.include?("MAINTENANCE_EVIDENCE_POLL_LIMIT = 120") &&
             javascript.include?("MAINTENANCE_RECEIPT_POLL_LIMIT = 600") &&
             javascript.include?("refreshWorkstationEvidenceAndWait") &&
             javascript.include?("waitForWorkstationMaintenanceReceipt") &&
             javascript.include?('prefillApprovalGate("maintenance-device-confirmation", "execute-maintenance-device-action"') &&
             javascript.include?('return deviceId === "maven" ? "workstation" : deviceId;') &&
             javascript.include?("A4 fixed-operation authority · no password prompt"))
check.call("workstation maintenance refreshes fleet evidence after its exact receipt while reboot remains separate",
             javascript.include?('if (preview.action === "maintenance")') &&
             javascript.include?("await loadMaintenanceFleet()") &&
             javascript.include?("reboot remains a separate action") &&
             javascript.include?("Array.isArray(plan.commands) && plan.commands.length === 0") &&
             javascript.include?("not included · reboot and restore only") &&
             javascript.include?('["maintenance", "reboot"].forEach'))
check.call("cards distinguish maintenance channels from status-only probes while Pi-hole OpenSSH duplication is absent",
           javascript.include?('"Status probe" : (inventoryOnly ? "Inventory probe" : "Maintenance channel")') &&
             javascript.include?('const inventoryOnly = device.control !== "maintenance"') &&
             !javascript.include?("SSH evidence ·") &&
             !javascript.include?("OpenSSH ·"))
check.call("Dashboard loads persisted status and contains no fleet-wide mutation control",
           javascript.include?('callSoul("maintenance.fleet.snapshot"') &&
             !html.match?(/Maintain fleet|Reboot fleet/i))
check.call("remote execution uses the bounded administration stream with progress",
           javascript.include?('callNdjson("/api/v1/administration-stream", "maintenance.device.execute"') &&
             javascript.include?("Fixed verification") &&
             http.include?("maintenance.device.execute"))

if errors.empty?
  puts "Maintenance device control C1 verification passed."
  exit 0
end

warn "Maintenance device control C1 verification failed: #{errors.join(', ')}"
exit 1
