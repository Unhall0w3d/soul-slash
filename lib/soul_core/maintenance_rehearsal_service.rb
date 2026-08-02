# frozen_string_literal: true

require "digest"
require "json"
require "time"

require_relative "bounded_command_runner"
require_relative "package_manager_assessor"

module SoulCore
  class MaintenanceRehearsalService
    PLAN_SCHEMA = "soul.maintenance.plan.v1"
    JOURNAL_SCHEMA = "soul.maintenance.journal.v1"
    SNAPSHOT_SCHEMA = "soul.maintenance.window_snapshot.v1"
    REGISTRY_SCHEMA = "soul.maintenance.restore_registry.v1"
    MAX_CLIENTS = 256
    MAX_REGISTRY_ENTRIES = 128
    MAX_OUTPUT_BYTES = 512 * 1024
    COMMAND_TIMEOUT_SECONDS = 12

    def initialize(
      root: Dir.pwd,
      clock: -> { Time.now.utc },
      runner: BoundedCommandRunner.new,
      package_assessor: nil,
      registry_path: nil,
      user_id: Process.uid
    )
      @root = File.expand_path(root)
      @clock = clock
      @runner = runner
      @package_assessor = package_assessor
      @user_id = Integer(user_id)
      @registry_path = File.expand_path(
        registry_path || File.join(@root, "config", "maintenance_restore_registry.json")
      )
    end

    def preview(force_database_refresh: false)
      force_refresh = boolean(force_database_refresh)
      registry = load_registry
      package_evidence = package_assessor.assess(include_updates: true)
      snapshot = window_snapshot(registry)
      flatpak_installations = inspect_flatpak_installations(package_evidence)
      commands = planned_commands(
        package_evidence: package_evidence,
        flatpak_installations: flatpak_installations,
        force_database_refresh: force_refresh
      )
      plan_basis = {
        "schema_version" => PLAN_SCHEMA,
        "risk_class" => "class_5",
        "adapter" => "official_repository_flatpak_reboot_restore",
        "force_database_refresh" => force_refresh,
        "commands" => commands,
        "aur_review" => aur_review(package_evidence),
        "package_evidence" => package_evidence,
        "flatpak_installations" => flatpak_installations,
        "window_snapshot" => snapshot,
        "restore_registry_digest" => digest(registry),
        "one_authentication_required" => true,
        "automatic_reboot_on_verified_success" => true,
        "execution_authorized" => false,
        "rehearsal_only" => true
      }
      source_digest = digest(plan_basis)
      plan = plan_basis.merge(
        "plan_id" => "maintenance_#{source_digest[0, 16]}",
        "created_at" => @clock.call.iso8601,
        "source_digest" => source_digest,
        "human_review_required" => true,
        "lifecycle_state" => "planned",
        "prohibited_effects" => prohibited_effects
      )
      success(
        "plan" => plan,
        "expected_digest" => plan_digest(plan),
        "read_only" => true,
        "host_command_executed" => false,
        "state_written" => false
      )
    rescue ArgumentError => error
      awaiting(error.message)
    rescue StandardError => error
      failed("maintenance preview failed safely: #{error.message}")
    end

    def rehearse(force_database_refresh: false)
      preview_result = preview(force_database_refresh: force_database_refresh)
      return preview_result unless preview_result["ok"]

      plan = preview_result.dig("data", "plan")
      snapshot = plan.fetch("window_snapshot")
      blockers = rehearsal_blockers(plan)
      simulated = %w[
        planned authorized authenticating updates_running updates_verified
        snapshot_recorded reboot_requested awaiting_login restoring complete
      ].map { |state| {"state" => state, "simulated" => true} }
      journal = {
        "schema_version" => JOURNAL_SCHEMA,
        "journal_id" => "rehearsal_#{plan.fetch('source_digest')[0, 16]}",
        "plan_id" => plan.fetch("plan_id"),
        "created_at" => @clock.call.iso8601,
        "current_state" => blockers.empty? ? "complete" : "blocked_for_human_review",
        "simulated_lifecycle" => simulated,
        "rehearsal" => true,
        "one_authentication_required" => true,
        "password_requested" => false,
        "commands_executed" => [],
        "state_written" => false,
        "applications_launched" => 0,
        "reboot_requested" => false,
        "restorable_count" => snapshot.fetch("restorable_count"),
        "unsupported_count" => snapshot.fetch("unsupported_count"),
        "blockers" => blockers
      }
      return blocked("rehearsal found conditions requiring human review", {"journal" => journal, "plan" => plan}) unless blockers.empty?

      success(
        "journal" => journal,
        "plan" => plan,
        "read_only" => true,
        "host_command_executed" => false,
        "state_written" => false
      )
    end

    # A3 captures this again only after every update leg succeeds. Keeping the
    # collector here preserves the A1 privacy and allowlist boundary.
    def capture_window_snapshot
      window_snapshot(load_registry)
    end

    def restore_registry
      load_registry
    end

    private

    def package_assessor
      @package_assessor ||= PackageManagerAssessor.new(runner: @runner, clock: @clock)
    end

    def load_registry
      raise "restore registry is missing" unless File.file?(@registry_path)
      raise "restore registry must not be a symbolic link" if File.symlink?(@registry_path)
      raise "restore registry exceeds the size limit" if File.size(@registry_path) > MAX_OUTPUT_BYTES

      registry = JSON.parse(File.binread(@registry_path, MAX_OUTPUT_BYTES))
      raise "restore registry schema is invalid" unless registry["schema_version"] == REGISTRY_SCHEMA
      entries = registry["entries"]
      raise "restore registry entries are invalid" unless entries.is_a?(Array) && entries.length <= MAX_REGISTRY_ENTRIES
      normalized = entries.map { |entry| normalize_registry_entry(entry) }
      {"schema_version" => REGISTRY_SCHEMA, "entries" => normalized}
    rescue JSON::ParserError
      raise "restore registry is not valid JSON"
    end

    def normalize_registry_entry(entry)
      raise "restore registry entry is invalid" unless entry.is_a?(Hash)
      entry_id = entry["entry_id"].to_s
      identities = Array(entry["identities"]).map { |value| value.to_s.strip.downcase }.reject(&:empty?).uniq
      process_identities = Array(entry["process_identities"]).map { |value| value.to_s.strip.downcase }.reject(&:empty?).uniq
      argv = Array(entry["argv"]).map(&:to_s)
      maximum = Integer(entry.fetch("maximum_instances", 1))
      startup_policy = entry.fetch("startup_policy", "launch_window").to_s
      raise "restore registry entry id is invalid" unless entry_id.match?(/\A[a-z0-9][a-z0-9._-]{1,63}\z/)
      raise "restore registry identities are invalid" if identities.empty? || identities.length > 16
      raise "restore registry process identities are invalid" if process_identities.length > 16
      raise "restore registry argv is invalid" if argv.empty? || argv.length > 16
      raise "restore registry executable must be an absolute path" unless argv.first.start_with?("/")
      raise "restore registry argv contains an unsafe value" if argv.any? { |value| value.empty? || value.bytesize > 512 || value.include?("\0") }
      raise "restore registry maximum_instances is invalid" unless maximum.between?(1, 8)
      raise "restore registry title policy is invalid" unless entry.fetch("title_policy", "omit") == "omit"
      raise "restore registry startup policy is invalid" unless %w[launch_window launch_if_absent].include?(startup_policy)

      {
        "entry_id" => entry_id,
        "identities" => identities,
        "process_identities" => process_identities,
        "argv" => argv,
        "maximum_instances" => maximum,
        "title_policy" => "omit",
        "startup_policy" => startup_policy,
        "executable_available" => File.file?(argv.first) && File.executable?(argv.first)
      }
    end

    def window_snapshot(registry)
      clients = hypr_json("clients", expected: Array)
      raise "Hyprland client inventory exceeds #{MAX_CLIENTS}" if clients.length > MAX_CLIENTS
      monitors = hypr_json("monitors", expected: Array)
      workspaces = hypr_json("workspaces", expected: Array)
      active_workspace = hypr_json("activeworkspace", expected: Hash)
      counts = Hash.new(0)

      windows = clients.map.with_index do |client, index|
        safe_client(client, index, registry, counts)
      end
      background_applications = background_applications(registry, windows)
      restorable_count = windows.count { |window| window["restore_status"] == "restorable" } +
        background_applications.count { |application| application["restore_status"] == "restorable" }
      unsupported_count = windows.count { |window| window["restore_status"] != "restorable" } +
        background_applications.count { |application| application["restore_status"] != "restorable" }
      {
        "schema_version" => SNAPSHOT_SCHEMA,
        "captured_at" => @clock.call.iso8601,
        "source" => "hyprctl structured JSON",
        "privacy" => {
          "titles_stored" => false,
          "raw_command_lines_stored" => false,
          "urls_stored" => false,
          "environment_stored" => false
        },
        "process_inventory" => {
          "source" => "ps comm field for the desktop owner",
          "raw_arguments_stored" => false,
          "unmatched_processes_stored" => false
        },
        "active_workspace" => safe_workspace(active_workspace),
        "monitors" => monitors.first(16).map { |monitor| safe_monitor(monitor) },
        "workspaces" => workspaces.first(128).map { |workspace| safe_workspace(workspace) },
        "windows" => windows,
        "background_applications" => background_applications,
        "restorable_count" => restorable_count,
        "unsupported_count" => unsupported_count,
        "truncated" => false
      }
    end

    def background_applications(registry, windows)
      result = @runner.run(
        "ps", "-u", @user_id.to_s, "-o", "comm=",
        timeout_seconds: COMMAND_TIMEOUT_SECONDS,
        max_output_bytes: MAX_OUTPUT_BYTES
      )
      raise "desktop process inventory is #{result.status}" unless result.success? && !result.truncated
      process_names = result.stdout.lines.map { |line| line.strip.downcase }.reject(&:empty?).uniq.first(4_096)
      represented = windows.filter_map { |window| window["restore_entry_id"] }.uniq
      registry.fetch("entries").filter_map do |entry|
        next if entry.fetch("process_identities").empty?
        next if represented.include?(entry.fetch("entry_id"))
        matched = entry.fetch("process_identities").find { |identity| process_names.include?(identity) }
        next unless matched
        supported = entry["executable_available"] && entry["startup_policy"] == "launch_if_absent"
        {
          "process_identity" => matched,
          "restore_status" => supported ? "restorable" : "unsupported",
          "restore_entry_id" => supported ? entry.fetch("entry_id") : nil,
          "launch_argv" => supported ? entry.fetch("argv") : nil,
          "startup_policy" => entry.fetch("startup_policy"),
          "placement" => "background_no_window",
          "reason" => supported ? "launch only if the process did not auto-start after login" : "background restore policy or executable is unavailable",
          "raw_arguments_stored" => false
        }
      end
    end

    def hypr_json(subject, expected:)
      result = @runner.run(
        "hyprctl", "-j", subject,
        timeout_seconds: COMMAND_TIMEOUT_SECONDS,
        max_output_bytes: MAX_OUTPUT_BYTES
      )
      raise "Hyprland #{subject} inventory is #{result.status}" unless result.success? && !result.truncated
      parsed = JSON.parse(result.stdout)
      raise "Hyprland #{subject} response has the wrong type" unless parsed.is_a?(expected)
      parsed
    rescue JSON::ParserError
      raise "Hyprland #{subject} response is invalid JSON"
    end

    def safe_client(client, index, registry, counts)
      raise "Hyprland client entry is invalid" unless client.is_a?(Hash)
      initial_class = bounded_identity(client["initialClass"])
      current_class = bounded_identity(client["class"])
      identities = [initial_class, current_class].reject(&:empty?).map(&:downcase)
      entry = registry.fetch("entries").find { |candidate| (candidate.fetch("identities") & identities).any? }
      counts[entry["entry_id"]] += 1 if entry
      supported = entry && entry["executable_available"] && counts[entry["entry_id"]] <= entry["maximum_instances"]
      reason = if entry.nil?
        "application identity is not allowlisted"
      elsif !entry["executable_available"]
        "allowlisted executable is unavailable on this host"
      elsif !supported
        "application instance limit was reached"
      end
      {
        "window_index" => index,
        "initial_class" => initial_class,
        "class" => current_class,
        "workspace" => safe_workspace(client["workspace"]),
        "monitor_id" => bounded_integer(client["monitor"]),
        "floating" => client["floating"] == true,
        "fullscreen" => bounded_integer(client["fullscreen"]),
        "pinned" => client["pinned"] == true,
        "restore_status" => supported ? "restorable" : "unsupported",
        "restore_entry_id" => supported ? entry.fetch("entry_id") : nil,
        "launch_argv" => supported ? entry.fetch("argv") : nil,
        "reason" => reason,
        "title_stored" => false
      }
    end

    def safe_monitor(monitor)
      return {} unless monitor.is_a?(Hash)
      {
        "id" => bounded_integer(monitor["id"]),
        "name" => bounded_identity(monitor["name"]),
        "description" => bounded_identity(monitor["description"]),
        "active_workspace" => safe_workspace(monitor["activeWorkspace"])
      }
    end

    def safe_workspace(workspace)
      return {} unless workspace.is_a?(Hash)
      {"id" => bounded_integer(workspace["id"]), "name" => bounded_identity(workspace["name"])}
    end

    def inspect_flatpak_installations(package_evidence)
      return [] unless package_evidence.dig("managers", "flatpak", "detected")
      result = @runner.run(
        "flatpak", "--installations",
        timeout_seconds: COMMAND_TIMEOUT_SECONDS,
        max_output_bytes: 64 * 1024
      )
      raise "Flatpak installation inventory is #{result.status}" unless result.success? && !result.truncated
      installations = []
      system_paths = result.stdout.lines.map(&:strip).reject(&:empty?).first(16)
      installations << {"scope" => "system", "path_kind" => "system_or_custom"} unless system_paths.empty?

      user = @runner.run(
        "flatpak", "list", "--user", "--columns=application",
        timeout_seconds: COMMAND_TIMEOUT_SECONDS,
        max_output_bytes: 64 * 1024
      )
      raise "Flatpak user installation inventory is #{user.status}" unless user.success? && !user.truncated
      installations << {"scope" => "user", "path_kind" => "user"} unless user.stdout.lines.all? { |line| line.strip.empty? }
      installations
    end

    def planned_commands(package_evidence:, flatpak_installations:, force_database_refresh:)
      pacman_path = package_evidence.dig("managers", "pacman", "path")
      raise "pacman is required for the approved repository transaction" unless pacman_path.to_s.start_with?("/")
      commands = [{
        "adapter" => "official_repository.full_upgrade",
        "argv" => ["/usr/bin/sudo", "-n", pacman_path, force_database_refresh ? "-Syyu" : "-Syu"],
        "interactive" => true,
        "executes_in_a1" => false
      }]
      flatpak_path = package_evidence.dig("managers", "flatpak", "path")
      flatpak_installations.each do |installation|
        argv = [flatpak_path, "update", "--user"]
        argv = ["/usr/bin/sudo", "-n", flatpak_path, "update", "--system"] if installation["scope"] == "system"
        commands << {
          "adapter" => "flatpak.#{installation.fetch('scope')}_update",
          "argv" => argv,
          "interactive" => true,
          "executes_in_a1" => false
        }
      end
      commands
    end

    def aur_review(package_evidence)
      helper = package_evidence.fetch("preferred_aur_helper", nil)
      updates = helper ? package_evidence.dig("managers", helper, "updates") : nil
      items = Array(updates && updates["items"]).map(&:to_s).first(2_000)
      {
        "helper" => helper,
        "status" => items.empty? ? "not_required" : "review_required",
        "count" => items.length,
        "items" => items,
        "included_in_unattended_maintenance" => false,
        "review_contract" => "separate_visible_interactive_terminal",
        "required_review" => %w[package_set PKGBUILD install_script source_checksums build_diff]
      }
    end

    def rehearsal_blockers(plan)
      blockers = []
      package_evidence = plan.fetch("package_evidence")
      blockers << "package assessment is unavailable" unless package_evidence["status"] == "ok"
      blockers << "Hyprland returned no monitor inventory" if plan.dig("window_snapshot", "monitors").empty?
      blockers << "no windows currently match the restore allowlist" if plan.dig("window_snapshot", "restorable_count").zero?
      blockers
    end

    def prohibited_effects
      [
        "request or cache sudo credentials",
        "execute pacman, AUR helper, or flatpak update commands",
        "write a maintenance journal or snapshot",
        "launch, move, or close applications",
        "request or perform a reboot"
      ]
    end

    def bounded_identity(value)
      value.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "�").strip.byteslice(0, 160).to_s
    end

    def bounded_integer(value)
      Integer(value)
    rescue ArgumentError, TypeError
      nil
    end

    def boolean(value)
      return value if value == true || value == false
      return true if value.to_s == "true"
      return false if value.to_s == "false" || value.nil?
      raise ArgumentError, "force_database_refresh must be true or false"
    end

    def plan_digest(plan)
      digest(plan.reject { |key, _value| key == "created_at" })
    end

    def digest(value)
      Digest::SHA256.hexdigest(JSON.generate(value))
    end

    def success(data)
      {"ok" => true, "lifecycle_state" => "complete", "data" => data, "mutation" => "none"}
    end

    def awaiting(reason)
      {"ok" => false, "lifecycle_state" => "awaiting_input", "reason" => reason, "mutation" => "none"}
    end

    def failed(reason)
      {"ok" => false, "lifecycle_state" => "failed", "reason" => reason, "mutation" => "none"}
    end

    def blocked(reason, data)
      {
        "ok" => false,
        "lifecycle_state" => "blocked_for_human_review",
        "reason" => reason,
        "data" => data,
        "mutation" => "none"
      }
    end
  end
end
