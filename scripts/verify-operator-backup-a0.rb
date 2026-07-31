#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

require_relative "../lib/soul_core/application_facade"
require_relative "../lib/soul_core/backup_administration_service"
require_relative "../lib/soul_core/bounded_command_runner"
require_relative "../lib/soul_core/operator_backup_manifest_policy"

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

class OperatorBackupNoResticRunner
  attr_reader :calls

  def initialize
    @calls = []
  end

  def which(_name)
    nil
  end

  def run(*command, **_options)
    @calls << command.flatten.map(&:to_s)
    SoulCore::BoundedCommandRunner::Result.new(
      stdout: "", stderr: "not mounted", exit_status: 1,
      status: "failed", truncated: false
    )
  end
end

puts "Operator Backup A0 verification:"

Dir.mktmpdir("soul-operator-backup-") do |root|
  home = File.join(root, "home")
  system_root = File.join(root, "system")
  FileUtils.mkdir_p(home)

  %w[
    Documents Music Pictures Videos Servers Tools Projects ComSource
    Anbernic OneDrive Scripts Templates
  ].each do |directory|
    path = File.join(home, directory)
    FileUtils.mkdir_p(path)
    File.write(File.join(path, "fixture.txt"), "#{directory}\n")
  end
  %w[hypr noctalia fastfetch kitty systemd].each do |directory|
    path = File.join(home, ".config", directory)
    FileUtils.mkdir_p(path)
    File.write(File.join(path, "fixture.conf"), "#{directory}\n")
  end
  [
    File.join(home, ".config", "gtk-3.0", "settings.ini"),
    File.join(home, ".config", "MangoHud", "MangoHud.conf"),
    File.join(home, ".config", "dolphinrc"),
    File.join(home, ".local", "share", "Steam", "userdata", "fixture", "save.dat"),
    File.join(home, ".local", "share", "Larian Studios", "fixture", "save.dat")
  ].each do |path|
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "fixture\n")
  end
  [
    File.join(home, ".ssh", "id_ed25519_operator"),
    File.join(home, ".gnupg", "private-keys-v1.d", "fixture.key"),
    File.join(home, ".local", "share", "keyrings", "login.keyring"),
    File.join(home, ".codex", "auth.json"),
    File.join(home, ".zshrc")
  ].each do |path|
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "fixture\n")
  end
  FileUtils.mkdir_p(File.join(home, "ai_models"))
  File.write(File.join(home, "ai_models", "reproducible.gguf"), "not backed up\n")
  FileUtils.mkdir_p(File.join(home, "Projects", "application", "target"))
  File.write(File.join(home, "Projects", "application", "target", "generated.bin"), "generated\n")
  FileUtils.mkdir_p(File.join(home, "Projects", "soul"))
  File.write(File.join(home, "Projects", "soul", "private.txt"), "separate continuity\n")

  [
    "boot/limine.conf",
    "etc/fstab",
    "etc/lact/config.yaml",
    "etc/systemd/system/fixture.service",
    "var/lib/pacman/local/fixture/desc"
  ].each do |relative|
    path = File.join(system_root, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "fixture\n")
  end

  FileUtils.mkdir_p(File.join(root, "config"))
  FileUtils.cp(
    File.expand_path("../config/operator_recovery_assets.json", __dir__),
    File.join(root, "config", "operator_recovery_assets.json")
  )

  policy = SoulCore::OperatorBackupManifestPolicy.new(
    root: root, home: home, system_root: system_root
  )
  sources = policy.sources
  exclusions = policy.exclusions
  summary = policy.summary

  check.call("personal media and requested workstation folders are selected",
             %w[Music Pictures Videos Documents Servers Tools Projects].all? do |name|
               sources.include?(File.join(home, name))
             end)
  check.call("Hyprland Noctalia shell and private recovery state are selected",
             sources.include?(File.join(home, ".config", "hypr")) &&
               sources.include?(File.join(home, ".config", "noctalia")) &&
               sources.include?(File.join(home, ".zshrc")) &&
               sources.include?(File.join(home, ".ssh")) &&
               sources.include?(File.join(home, ".gnupg")) &&
               sources.include?(File.join(home, ".local", "share", "keyrings")))
  check.call("desktop settings and irreplaceable local game state are selected without installations",
             sources.include?(File.join(home, ".config", "gtk-3.0")) &&
               sources.include?(File.join(home, ".config", "MangoHud")) &&
               sources.include?(File.join(home, ".config", "dolphinrc")) &&
               sources.include?(File.join(home, ".local", "share", "Steam", "userdata")) &&
               sources.include?(File.join(home, ".local", "share", "Larian Studios")) &&
               !sources.include?(File.join(home, ".local", "share", "Steam")))
  check.call("readable host rebuild evidence is selected",
             sources.include?(File.join(system_root, "etc", "fstab")) &&
               sources.include?(File.join(system_root, "etc", "lact", "config.yaml")) &&
               sources.include?(File.join(system_root, "var", "lib", "pacman", "local")))
  check.call("raw AI weights are absent while exact recovery assets are tracked",
             !sources.include?(File.join(home, "ai_models")) &&
               summary["raw_model_weights_included"] == false &&
               summary["reproducible_asset_count"] == 3 &&
               summary["reproducible_asset_bytes"] == 22_269_129_472 &&
               summary["reproducible_assets"].all? { |asset| asset["sha256"].match?(/\A[a-f0-9]{64}\z/) })
  check.call("generated project trees and separately protected Soul state are excluded",
             exclusions.include?("**/target/**") &&
               exclusions.include?(File.join(home, "Projects", "soul", "**")) &&
               exclusions.include?(File.join(home, "Knowledge", "soul-vault", "**")))
  check.call("ambiguous and privileged gaps remain explicit",
             summary["explicit_manual_review_gaps"].include?("browser profiles and session stores") &&
               summary["explicit_manual_review_gaps"].include?("root-only NetworkManager connection profiles"))

  script = File.expand_path("soul-backup-config", __dir__)
  plan_stdout, plan_stderr, plan_status = Open3.capture3(
    RbConfig.ruby, script, "plan", "--profile", "operator",
    "--root", root, "--home", home
  )
  plan = plan_status.success? ? JSON.parse(plan_stdout) : {}
  check.call("portable configuration plans a distinct owner-only Operator manifest",
             plan_status.success? &&
               plan.dig("data", "profile_id") == "operator" &&
               plan.dig("data", "confirmation_phrase") == "CONFIGURE_OPERATOR_BACKUP_MANIFESTS" &&
               plan.dig("data", "sources_path").end_with?("/Soul/private/operator_backup/sources.txt"))
  check.call("configuration plan emits no warning or secret output", plan_stderr.empty?)

  execute_stdout, execute_stderr, execute_status = Open3.capture3(
    RbConfig.ruby, script, "execute", "--profile", "operator",
    "--root", root, "--home", home,
    "--expected-digest", plan.dig("data", "expected_digest").to_s,
    "--confirmation", "CONFIGURE_OPERATOR_BACKUP_MANIFESTS"
  )
  executed = execute_status.success? ? JSON.parse(execute_stdout) : {}
  state_root = File.join(root, "Soul", "private", "operator_backup")
  check.call("exact configuration creates separate owner-only manifests",
             execute_status.success? && execute_stderr.empty? &&
               executed["mutation"] == "operator_backup_manifests_configured" &&
               %w[sources.txt excludes.txt].all? do |name|
                 path = File.join(state_root, name)
                 File.file?(path) && (File.stat(path).mode & 0o077).zero?
               end)

  runner = OperatorBackupNoResticRunner.new
  service = SoulCore::BackupAdministrationService.new(
    root: root, home: home, process_env: {
      "SOUL_BACKUP_MOUNT" => File.join(root, "recovery"),
      "SOUL_BACKUP_REPOSITORY" => File.join(root, "recovery", "restic")
    }, runner: runner, profile_id: "operator"
  )
  status = service.status
  check.call("service reports separated Operator identity and policy without Restic",
             status["ok"] &&
               status.dig("data", "profile_id") == "operator" &&
               status.dig("data", "snapshot_tag") == "operator-state" &&
               status.dig("data", "policy", "raw_model_weights_included") == false)

  preview = service.manifest_reconciliation_preview
  shared_lock_path = File.join(root, "Soul", "private", "backup", "operation.lock")
  FileUtils.mkdir_p(File.dirname(shared_lock_path), mode: 0o700)
  File.open(shared_lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
    lock.flock(File::LOCK_EX | File::LOCK_NB)
    blocked = service.manifest_reconciliation_execute(
      confirmation: preview.dig("data", "confirmation_phrase"),
      expected_digest: preview.dig("data", "expected_digest")
    )
    check.call("shared Soul and Operator mutation lock fails closed",
               blocked["lifecycle_state"] == "blocked_for_human_review")
  end
  check.call("Operator confirmations and state do not reuse Soul authority",
             preview.dig("data", "confirmation_phrase") ==
               SoulCore::BackupAdministrationService::OPERATOR_MANIFEST_RECONCILIATION_CONFIRMATION &&
               preview.dig("data", "profile_id") == "operator")

  facade = SoulCore::ApplicationFacade.new(
    root: root, operator_backup_administration_service: service
  )
  envelope = facade.call({
    "schema_version" => "soul.application.v1",
    "request_id" => "operator-backup-test-0001",
    "operation" => "operator_backup.status",
    "parameters" => {},
    "context" => { "interface" => "dashboard_test" }
  })
  check.call("application contract exposes the Operator profile",
             envelope["ok"] && envelope.dig("data", "profile_id") == "operator")
end

javascript = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
brief = File.read(File.expand_path("../docs/soul/OPERATOR_BACKUP_A0_BRIEF.md", __dir__))
documentation = File.read(File.expand_path("../docs/soul/BACKUP_AND_RECOVERY.md", __dir__))
check.call("Dashboard selects the profile before deriving every operation",
           html.include?('id="backup-profile"') &&
             javascript.include?('function backupOperation(suffix)') &&
             !javascript.match?(/callSoul\("backup\.(?:status|create|retention|restore|replica|drs)/) &&
             !javascript.match?(/callNdjson\([^\\n]+, "backup\.(?:create|retention|restore|replica|drs)/))
check.call("Operator scope remains manual and models are documented as reproducible",
           brief.include?("manual only") &&
             brief.include?("Add no timer, scheduler, daemon") &&
             documentation.include?("raw GGUF weights are deliberately excluded") &&
             documentation.include?("systemd-creds"))

abort "Operator Backup A0 verification failed: #{errors.join(', ')}" unless errors.empty?
puts "Operator Backup A0 is candidate-ready for manifest and live recovery review."
