#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require "time"

require_relative "../lib/soul_core/application_facade"
require_relative "../lib/soul_core/bounded_command_runner"
require_relative "../lib/soul_core/maintenance_rehearsal_service"

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

class MaintenanceFakePackageAssessor
  def assess(include_updates:)
    raise "fresh update evidence is required" unless include_updates
    {
      "status" => "ok",
      "read_only" => true,
      "updates_checked" => true,
      "preferred_aur_helper" => "yay",
      "managers" => {
        "pacman" => {
          "detected" => true,
          "path" => "/usr/bin/pacman",
          "updates" => {"status" => "complete", "fresh" => true, "count" => 2, "items" => ["ruby 3.4 -> 3.5", "linux 1 -> 2"]}
        },
        "yay" => {
          "detected" => true,
          "path" => "/usr/bin/yay",
          "updates" => {"status" => "complete", "count" => 1, "items" => ["fixture-aur 1 -> 2"]}
        },
        "flatpak" => {
          "detected" => true,
          "path" => "/usr/bin/flatpak",
          "updates" => {"status" => "complete", "count" => 1, "items" => ["fixture.Flatpak"]}
        }
      },
      "reboot" => {"status" => "complete", "fresh" => true, "recommended" => false}
    }
  end
end

class MaintenanceFakeRunner
  attr_reader :calls
  attr_accessor :clients, :process_names

  def initialize
    @calls = []
    @process_names = ["qbittorrent"]
    @clients = [
      {
        "initialClass" => "kitty", "class" => "kitty", "title" => "secret terminal command",
        "workspace" => {"id" => 2, "name" => "2"}, "monitor" => 1,
        "floating" => false, "fullscreen" => 0, "pinned" => false
      },
      {
        "initialClass" => "steam_app_123", "class" => "steam_app_123", "title" => "private game",
        "workspace" => {"id" => 5, "name" => "5"}, "monitor" => 0,
        "floating" => false, "fullscreen" => 2, "pinned" => false
      }
    ]
  end

  def run(*command, **options)
    argv = command.flatten.map(&:to_s)
    @calls << {"argv" => argv, "timeout" => options[:timeout_seconds]}
    return ok("/var/lib/flatpak\n") if argv == ["flatpak", "--installations"]
    return ok("") if argv == ["flatpak", "list", "--user", "--columns=application"]
    return ok(@process_names.join("\n") + (@process_names.empty? ? "" : "\n")) if argv == ["ps", "-u", "1000", "-o", "comm="]
    return ok(JSON.generate(@clients)) if argv == ["hyprctl", "-j", "clients"]
    return ok(JSON.generate([{"id" => 0, "name" => "DP-1", "description" => "left", "activeWorkspace" => {"id" => 5, "name" => "5"}}])) if argv == ["hyprctl", "-j", "monitors"]
    return ok(JSON.generate([{"id" => 2, "name" => "2"}, {"id" => 5, "name" => "5"}])) if argv == ["hyprctl", "-j", "workspaces"]
    return ok(JSON.generate({"id" => 5, "name" => "5"})) if argv == ["hyprctl", "-j", "activeworkspace"]
    failed("unexpected command #{argv.join(' ')}")
  end

  private

  def ok(stdout)
    SoulCore::BoundedCommandRunner::Result.new(stdout: stdout, stderr: "", exit_status: 0, status: "ok", truncated: false)
  end

  def failed(stderr)
    SoulCore::BoundedCommandRunner::Result.new(stdout: "", stderr: stderr, exit_status: 1, status: "failed", truncated: false)
  end
end

puts "Maintenance reboot and restore A1 verification:"

Dir.mktmpdir("soul-maintenance-a1-") do |root|
  registry_path = File.join(root, "registry.json")
  registry = {
    "schema_version" => "soul.maintenance.restore_registry.v1",
    "entries" => [
      {
        "entry_id" => "terminal.kitty",
        "identities" => ["kitty"],
        "process_identities" => [],
        "argv" => ["/bin/true"],
        "maximum_instances" => 1,
        "title_policy" => "omit",
        "startup_policy" => "launch_window"
      },
      {
        "entry_id" => "transfer.qbittorrent",
        "identities" => ["qbittorrent"],
        "process_identities" => ["qbittorrent"],
        "argv" => ["/bin/true"],
        "maximum_instances" => 1,
        "title_policy" => "omit",
        "startup_policy" => "launch_if_absent"
      }
    ]
  }
  File.write(registry_path, JSON.pretty_generate(registry))
  runner = MaintenanceFakeRunner.new
  service = SoulCore::MaintenanceRehearsalService.new(
    root: root,
    clock: -> { Time.utc(2026, 7, 27, 12, 0, 0) },
    runner: runner,
    package_assessor: MaintenanceFakePackageAssessor.new,
    registry_path: registry_path,
    user_id: 1000
  )

  preview = service.preview(force_database_refresh: true)
  plan = preview.dig("data", "plan")
  snapshot = plan.fetch("window_snapshot")
  check.call("preview emits a typed Class-5 rehearsal-only plan with the requested forced refresh",
             preview["ok"] &&
               plan["schema_version"] == "soul.maintenance.plan.v1" &&
               plan["risk_class"] == "class_5" &&
               plan["execution_authorized"] == false &&
               plan["force_database_refresh"] == true &&
               plan.dig("commands", 0, "argv") == ["/usr/bin/yay", "-Syyu"])
  check.call("system Flatpak update is planned through the one existing non-interactive sudo ticket",
             plan.fetch("commands").any? { |command| command["argv"] == ["/usr/bin/sudo", "-n", "/usr/bin/flatpak", "update", "--system"] })
  check.call("Hyprland snapshot keeps safe placement hints and omits sensitive titles and command lines",
             snapshot["restorable_count"] == 2 &&
               snapshot["unsupported_count"] == 1 &&
               snapshot.dig("privacy", "titles_stored") == false &&
               !JSON.generate(snapshot).include?("secret terminal command") &&
               !JSON.generate(snapshot).include?("private game") &&
               snapshot.fetch("windows").all? { |window| window["title_stored"] == false })
  check.call("allowlisted tray-only applications are captured from process names without arguments",
             snapshot.fetch("background_applications").length == 1 &&
               snapshot.dig("background_applications", 0, "process_identity") == "qbittorrent" &&
               snapshot.dig("background_applications", 0, "startup_policy") == "launch_if_absent" &&
               snapshot.dig("background_applications", 0, "raw_arguments_stored") == false)
  check.call("games and unknown identities remain visibly unsupported",
             snapshot.fetch("windows").last["restore_status"] == "unsupported" &&
               snapshot.fetch("windows").last["reason"].include?("not allowlisted"))

  rehearsal = service.rehearse(force_database_refresh: true)
  journal = rehearsal.dig("data", "journal")
  check.call("rehearsal exercises the declared lifecycle and terminates complete",
             rehearsal["ok"] &&
               journal["schema_version"] == "soul.maintenance.journal.v1" &&
               journal["current_state"] == "complete" &&
               journal.fetch("simulated_lifecycle").last["state"] == "complete")
  check.call("rehearsal requests no password, executes nothing, writes nothing, launches nothing, and never reboots",
             journal["password_requested"] == false &&
               journal["commands_executed"].empty? &&
               journal["state_written"] == false &&
               journal["applications_launched"].zero? &&
               journal["reboot_requested"] == false)
  check.call("the runner receives read-only inventory commands only",
             runner.calls.all? { |call|
               [
                 %w[flatpak --installations],
                 %w[flatpak list --user --columns=application],
                 %w[ps -u 1000 -o comm=],
                 %w[hyprctl -j clients],
                 %w[hyprctl -j monitors],
                 %w[hyprctl -j workspaces],
                 %w[hyprctl -j activeworkspace]
               ].include?(call["argv"])
             })

  normal = service.preview(force_database_refresh: false)
  invalid = service.preview(force_database_refresh: "sometimes")
  check.call("normal mode uses one coherent yay -Syu plan and invalid boolean input fails closed",
             normal.dig("data", "plan", "commands", 0, "argv") == ["/usr/bin/yay", "-Syu"] &&
               invalid["lifecycle_state"] == "awaiting_input")

  runner.clients = [{
    "initialClass" => "unknown", "class" => "unknown", "title" => "private",
    "workspace" => {"id" => 1, "name" => "1"}, "monitor" => 0,
    "floating" => false, "fullscreen" => 0, "pinned" => false
  }]
  runner.process_names = []
  blocked = service.rehearse
  check.call("a host with no safely restorable windows stops for human review without mutation",
             blocked["lifecycle_state"] == "blocked_for_human_review" &&
               blocked.dig("data", "journal", "blockers").include?("no windows currently match the restore allowlist") &&
               blocked.dig("data", "journal", "reboot_requested") == false)

  facade = SoulCore::ApplicationFacade.new(root: root, maintenance_rehearsal_service: service)
  envelope = facade.call({
    "schema_version" => "soul.application.v1",
    "request_id" => "maintenance-a1-0001",
    "operation" => "maintenance.preview",
    "parameters" => {"force_database_refresh" => "true"},
    "context" => {"interface" => "dashboard_test"}
  })
  check.call("typed application facade exposes the read-only preview",
             envelope["lifecycle_state"] == "complete" &&
               envelope.dig("data", "plan", "rehearsal_only") == true)

  linked = File.join(root, "linked-registry.json")
  File.symlink(registry_path, linked)
  linked_service = SoulCore::MaintenanceRehearsalService.new(
    root: root, runner: runner, package_assessor: MaintenanceFakePackageAssessor.new, registry_path: linked, user_id: 1000
  )
  check.call("a symbolic-link restore registry fails closed",
             linked_service.preview["lifecycle_state"] == "failed")
end

schema_paths = %w[
  maintenance_plan.schema.json maintenance_journal.schema.json
  maintenance_window_snapshot.schema.json maintenance_restore_registry.schema.json
].map { |name| File.expand_path("../docs/soul/schemas/#{name}", __dir__) }
check.call("all four public schemas are valid JSON with Soul identifiers",
           schema_paths.all? { |path| JSON.parse(File.read(path)).fetch("$id").start_with?("soul.maintenance.") })

operations = SoulCore::ApplicationContract::OPERATIONS
check.call("typed operations expose preview and rehearsal only",
           operations.key?("maintenance.preview") &&
             operations.key?("maintenance.rehearsal") &&
             operations.keys.none? { |operation| operation.match?(/\Amaintenance\.(?:execute|reboot|restore)\z/) })

html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
javascript = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
check.call("Self Assessment exposes a clearly read-only preview and rehearsal",
           html.include?('id="preview-maintenance"') &&
             html.include?('id="rehearse-maintenance"') &&
             html.include?("A1 cannot authenticate") &&
             javascript.include?('callSoul("maintenance.preview"') &&
             javascript.include?('callSoul("maintenance.rehearsal"'))
check.call("A1 dashboard code adds no scheduler or poller",
           !javascript.match?(/maintenance.*(?:setInterval|requestAnimationFrame)/m))

abort "Verification failed: #{errors.join(', ')}" unless errors.empty?
puts "Verification complete."
