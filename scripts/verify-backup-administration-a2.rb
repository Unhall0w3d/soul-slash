#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "digest"
require "json"
require "open3"
require "tmpdir"
require "time"

require_relative "../lib/soul_core/application_facade"
require_relative "../lib/soul_core/backup_administration_service"
require_relative "../lib/soul_core/bounded_command_runner"

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

class BackupAdministrationFakeRunner
  attr_reader :calls
  attr_accessor :mount_options, :mount_target

  def initialize(mount:, source_root:)
    @mount = mount
    @source_root = source_root
    @mount_target = mount
    @mount_options = "rw,nosuid,nodev,noatime"
    @calls = []
    @snapshots = %w[a b c].map.with_index do |letter, index|
      {
        "id" => letter * 64,
        "time" => Time.utc(2026, 7, 20 + index, 12, 0, 0).iso8601,
        "hostname" => "fixture-host", "paths" => [source_root], "tags" => ["soul-state"]
      }
    end
  end

  def which(name)
    return "/usr/bin/restic" if name == "restic"
    return "/usr/bin/ssh" if name == "ssh"
    nil
  end

  def run(*command, **options)
    argv = command.flatten.map(&:to_s)
    captured_env = options[:env]&.transform_values { |value| value&.dup }
    @calls << { "argv" => argv, "env" => captured_env, "timeout" => options[:timeout_seconds] }
    return ok(JSON.generate("filesystems" => [{ "target" => @mount_target, "source" => "/dev/test1", "fstype" => "ext4", "options" => @mount_options }])) if argv.first == "findmnt"
    return ok("4096 #{@source_root}\n") if argv.first == "du"
    return ok("directory,souladmin,700\n") if argv.first == "ssh"
    return failed("unexpected command") unless argv.first == "restic"

    repository = argv[argv.index("--repo") + 1]
    remote = repository.start_with?("sftp:")
    action = argv[argv.index("--repo") + 2]
    case action
    when "snapshots"
      snapshots = if remote
        @snapshots.map do |item|
          item.merge("id" => Digest::SHA256.hexdigest("remote:#{item.fetch('id')}"), "original" => item.fetch("id"))
        end
      else
        @snapshots
      end
      ok(JSON.generate(snapshots))
    when "cat"
      remote ? ok(JSON.generate("id" => "9" * 64)) : failed("local cat not supported")
    when "backup"
      id = "d" * 64
      @snapshots << {
        "id" => id, "time" => Time.utc(2026, 7, 23, 12, 0, 0).iso8601,
        "hostname" => "fixture-host", "paths" => [@source_root], "tags" => ["soul-state"]
      } unless @snapshots.any? { |item| item["id"] == id }
      ok(JSON.generate("message_type" => "summary", "snapshot_id" => id) + "\n")
    when "check"
      ok("repository metadata verified")
    when "ls"
      id = argv.last
      ids = remote ? @snapshots.map { |item| Digest::SHA256.hexdigest("remote:#{item.fetch('id')}") } : @snapshots.map { |item| item["id"] }
      return failed("missing snapshot") unless ids.include?(id)
      nodes = [@source_root, File.join(@source_root, "state.json")].map { |path| JSON.generate("struct_type" => "node", "path" => path) }
      ok(nodes.join("\n") + "\n")
    when "forget"
      unless argv.include?("--dry-run")
        ids = argv.select { |item| item.match?(/\A[a-f0-9]{64}\z/) }
        @snapshots.reject! { |item| ids.include?(item["id"]) }
      end
      ok("{}\n")
    when "restore"
      target = argv[argv.index("--target") + 1]
      restored = File.join(target, @source_root.delete_prefix("/"), "state.json")
      FileUtils.mkdir_p(File.dirname(restored))
      File.write(restored, "{\"restored\":true}\n")
      ok("restore verified")
    else
      failed("unsupported restic action #{action}")
    end
  end

  private

  def ok(stdout)
    SoulCore::BoundedCommandRunner::Result.new(stdout: stdout, stderr: "", exit_status: 0, status: "ok", truncated: false)
  end

  def failed(stderr)
    SoulCore::BoundedCommandRunner::Result.new(stdout: "", stderr: stderr, exit_status: 1, status: "failed", truncated: false)
  end
end

puts "Backup Administration A2 verification:"

restore_contract = {
  "schema_version" => SoulCore::ApplicationContract::SCHEMA_VERSION,
  "request_id" => "verify-backup-restore-0001",
  "operation" => "operator_backup.restore.preview",
  "parameters" => {
    "password" => "fixture-secret-never-persist",
    "snapshot_id" => "d" * 64,
    "paths" => ["/home/operator/.ssh/config", "/home/operator/.zshrc"],
    "target_root" => "/home/operator/Recovery/soul-rehearsal"
  },
  "context" => { "interface" => "dashboard" }
}
retention_contract = Marshal.load(Marshal.dump(restore_contract))
retention_contract["request_id"] = "verify-backup-retention-0001"
retention_contract["operation"] = "operator_backup.retention.preview"
retention_contract["parameters"] = {
  "password" => "fixture-secret-never-persist",
  "snapshot_ids" => ["d" * 64]
}
invalid_restore_contract = Marshal.load(Marshal.dump(restore_contract))
invalid_restore_contract["parameters"]["paths"] = ["/home/operator/.ssh/config", 7]
check.call("typed transport accepts bounded restore and retention string arrays while rejecting mixed values",
           SoulCore::ApplicationContract.validate(restore_contract)["ok"] == true &&
             SoulCore::ApplicationContract.validate(retention_contract)["ok"] == true &&
             SoulCore::ApplicationContract.validate(invalid_restore_contract)["ok"] == false)

Dir.mktmpdir("soul-backup-administration-") do |root|
  mount = File.join(root, "recovery")
  repository = File.join(mount, "restic")
  state_root = File.join(root, "Soul", "private", "backup")
  source_root = File.join(root, "owner-state")
  FileUtils.mkdir_p(repository)
  FileUtils.mkdir_p(state_root)
  File.chmod(0o700, state_root)
  FileUtils.mkdir_p(source_root)
  File.chmod(0o700, source_root)
  File.write(File.join(repository, "config"), "encrypted repository fixture\n")
  File.write(File.join(source_root, "state.json"), "{\"state\":true}\n")
  File.write(File.join(state_root, "sources.txt"), "#{source_root}\n")
  File.write(File.join(state_root, "excludes.txt"), "#{File.join(state_root, "restores")}/**\n")
  FileUtils.mkdir_p(File.join(root, ".ssh"))
  File.write(File.join(root, ".ssh", "config"), "Host crucible-maintenance\n  HostName 192.0.2.2\n")
  File.chmod(0o600, File.join(root, ".ssh", "config"))
  File.chmod(0o600, File.join(state_root, "sources.txt"))
  File.chmod(0o600, File.join(state_root, "excludes.txt"))

  password = "fixture-secret-never-persist"
  clock = -> { Time.utc(2026, 7, 23, 12, 0, 0) }
  runner = BackupAdministrationFakeRunner.new(mount: mount, source_root: source_root)
  service = SoulCore::BackupAdministrationService.new(
    root: root, home: root, process_env: {
      "SOUL_BACKUP_REPOSITORY" => repository,
      "SOUL_BACKUP_MOUNT" => mount,
      "SOUL_BACKUP_MAX_REPACK_SIZE" => "1G"
    }, runner: runner, clock: clock, id_generator: -> { "0123456789abcdef" }
  )

  restore_failure = SoulCore::BoundedCommandRunner::Result.new(
    stdout: "", stderr: "restoring files\nerror: open #{File.join(root, 'private-item')}: permission denied\nFatal: There were 1 errors\n",
    exit_status: 1, status: "failed", truncated: false
  )
  failure_suffix = service.send(:restic_failure_suffix, restore_failure)
  check.call("bounded Restic failures retain the actionable line and sanitize private roots",
             failure_suffix.include?("permission denied") &&
               failure_suffix.include?("Fatal: There were 1 errors") &&
               failure_suffix.include?("[PROJECT_ROOT]") &&
               !failure_suffix.include?(root))

  ownership_target = File.join(state_root, "restores", "restore_0123456789abcdef")
  ownership_failure = SoulCore::BoundedCommandRunner::Result.new(
    stdout: "Summary: Restored 2 / 1 files/dirs\n",
    stderr: "ignoring error for #{root}: lchown #{ownership_target}#{root}: invalid argument\nFatal: There were 1 errors\n",
    exit_status: 1, status: "failed", truncated: false
  )
  accepted_ownership = service.send(
    :restic_ancestor_ownership_only_failure?, ownership_failure,
    target: ownership_target, includes: [File.join(root, "owner-state", "state.json")]
  )
  rejected_content = SoulCore::BoundedCommandRunner::Result.new(
    stdout: "", stderr: "error: damaged restored file\nFatal: There were 1 errors\n",
    exit_status: 1, status: "failed", truncated: false
  )
  check.call("only exact untruncated ancestor ownership failures under the owner home are accepted",
             accepted_ownership &&
               !service.send(:restic_ancestor_ownership_only_failure?, rejected_content,
                             target: ownership_target, includes: [File.join(root, "owner-state", "state.json")]))

  locked = service.status
  check.call("status inspects configuration without requesting or retaining the repository password",
             locked["ok"] && locked.dig("data", "snapshot_access") == "locked" &&
               locked.dig("data", "mount", "expected_target") == true &&
               runner.calls.none? { |call| call["argv"].include?("snapshots") })

  runner.mount_options = "ro,nosuid,nodev,noatime"
  read_only = service.backup_preview(password: password)
  runner.mount_options = "rw,nosuid,nodev,noatime"
  runner.mount_target = root
  wrong_mount = service.backup_preview(password: password)
  runner.mount_target = mount
  check.call("capture blocks a read-only target and a repository resolved onto the wrong filesystem",
             read_only["lifecycle_state"] == "awaiting_input" && read_only["reason"].include?("read-only") &&
               wrong_mount["lifecycle_state"] == "awaiting_input" && wrong_mount["reason"].include?("configured recovery mount"))

  preview = service.backup_preview(password: password)
  check.call("backup preview binds exact sources, repository identity, prior snapshot, and verification",
             preview["ok"] &&
               preview.dig("data", "confirmation_phrase") == SoulCore::BackupAdministrationService::BACKUP_CONFIRMATION &&
               preview.dig("data", "source_count") == 1 &&
               preview.dig("data", "prior_snapshot_id") == "c" * 64 &&
               preview.dig("data", "expected_digest").match?(/\A[a-f0-9]{64}\z/))

  wrong_gate = service.backup_execute(
    password: password, confirmation: "yes",
    expected_digest: preview.dig("data", "expected_digest")
  )
  check.call("wrong capture authority cannot start restic backup",
             wrong_gate["lifecycle_state"] == "awaiting_input" &&
               runner.calls.none? { |call| call["argv"].include?("backup") })

  captured = service.backup_execute(
    password: password,
    confirmation: preview.dig("data", "confirmation_phrase"),
    expected_digest: preview.dig("data", "expected_digest")
  )
  snapshot_id = captured.dig("data", "snapshot_id")
  manifest_path = File.join(state_root, "manifests", "#{snapshot_id}.json")
  ledger_path = File.join(state_root, "retention-ledger.json")
  check.call("approved capture runs backup, metadata check, exact manifest inventory, ledger observation, and receipt",
             captured["ok"] && snapshot_id == "d" * 64 &&
               File.file?(manifest_path) && File.file?(ledger_path) &&
               JSON.parse(File.read(manifest_path)).fetch("paths").include?(File.join(source_root, "state.json")) &&
               (File.stat(manifest_path).mode & 0o777) == 0o600 &&
               runner.calls.any? do |call|
                 argv = call["argv"]
                 argv.include?("backup") && argv.include?("--json") && argv.include?("--quiet")
               end)

  newest_blocked = service.retention_preview(password: password, snapshot_ids: ["d" * 64])
  minimum_blocked = service.retention_preview(password: password, snapshot_ids: ["a" * 64, "b" * 64, "c" * 64])
  check.call("retention protects the newest snapshot and refuses to leave fewer than two",
             newest_blocked["lifecycle_state"] == "awaiting_input" &&
               minimum_blocked["lifecycle_state"] == "awaiting_input")

  retention_preview = service.retention_preview(password: password, snapshot_ids: ["a" * 64])
  check.call("retention preview performs exact hold evaluation and a bounded dry run",
             retention_preview["ok"] &&
               retention_preview.dig("data", "selected_snapshot_ids") == ["a" * 64] &&
               runner.calls.any? { |call| call["argv"].include?("--dry-run") && call["argv"].include?("--prune") })

  retained = service.retention_execute(
    password: password, snapshot_ids: ["a" * 64],
    confirmation: retention_preview.dig("data", "confirmation_phrase"),
    expected_digest: retention_preview.dig("data", "expected_digest")
  )
  check.call("approved retention forgets only the exact snapshot then verifies repository metadata",
             retained["ok"] && retained.dig("data", "forgotten_snapshot_ids") == ["a" * 64] &&
               runner.calls.any? { |call| call["argv"].include?("forget") && !call["argv"].include?("--dry-run") && call["argv"].include?("a" * 64) })

  restore_preview = service.restore_preview(
    password: password, snapshot_id: "d" * 64,
    paths: [File.join(source_root, "state.json")]
  )
  restored = service.restore_execute(
    password: password, snapshot_id: "d" * 64,
    paths: [File.join(source_root, "state.json")],
    confirmation: restore_preview.dig("data", "confirmation_phrase"),
    expected_digest: restore_preview.dig("data", "expected_digest")
  )
  staged_path = restored.dig("data", "staged_path")
  check.call("restore verifies isolated staging and stops for human review without live mutation",
             restore_preview["ok"] &&
               restored["lifecycle_state"] == "blocked_for_human_review" &&
               restored.dig("data", "live_tree_mutation") == false &&
               staged_path.include?("Soul/private/backup/restores/restore_"))

  Dir.mktmpdir("soul-selected-recovery-") do |selected_target|
    File.chmod(0o700, selected_target)
    rehearsal_preview = service.restore_preview(
      password: password, snapshot_id: "d" * 64, paths: [], target_root: selected_target
    )
    rehearsal = service.restore_execute(
      password: password, snapshot_id: "d" * 64, paths: [], target_root: selected_target,
      confirmation: rehearsal_preview.dig("data", "confirmation_phrase"),
      expected_digest: rehearsal_preview.dig("data", "expected_digest")
    )
    check.call("an exact empty owner-selected directory is digest-bound and receives a verified full recovery rehearsal",
               rehearsal_preview["ok"] &&
                 rehearsal_preview.dig("data", "target", "mode") == "selected_empty_directory" &&
                 rehearsal_preview.dig("data", "full_recovery_rehearsal") == true &&
                 rehearsal["lifecycle_state"] == "blocked_for_human_review" &&
                 rehearsal.dig("data", "staged_path") == selected_target &&
                 rehearsal.dig("data", "recovery_rehearsal", "status") == "verified" &&
                 rehearsal.dig("data", "recovery_rehearsal", "missing_source_root_count") == 0 &&
                 runner.calls.any? { |call| call["argv"].include?("restore") && call["argv"].include?(selected_target) })
  end

  Dir.mktmpdir("soul-crucible-recovery-") do |selected_target|
    File.chmod(0o700, selected_target)
    replica_preview = service.restore_preview(
      password: password, snapshot_id: "d" * 64, paths: [], target_root: selected_target,
      repository_source: "crucible_replica"
    )
    replica_rehearsal = service.restore_execute(
      password: password, snapshot_id: "d" * 64, paths: [], target_root: selected_target,
      repository_source: "crucible_replica",
      confirmation: replica_preview.dig("data", "confirmation_phrase"),
      expected_digest: replica_preview.dig("data", "expected_digest")
    )
    check.call("Crucible recovery binds local lineage to its independent remote snapshot and restores from SFTP",
               replica_preview["ok"] &&
                 replica_preview.dig("data", "repository_source") == "crucible_replica" &&
                 replica_preview.dig("data", "source_snapshot_id") == "d" * 64 &&
                 replica_preview.dig("data", "snapshot_id") != "d" * 64 &&
                 replica_rehearsal.dig("data", "recovery_rehearsal", "status") == "verified" &&
                 replica_rehearsal.dig("data", "repository_source") == "crucible_replica" &&
                 runner.calls.any? { |call| call["argv"].include?("restore") && call["argv"].any? { |item| item.start_with?("sftp:") } })
  end

  Dir.mktmpdir("soul-recovery-drift-") do |target_parent|
    selected_target = File.join(target_parent, "selected")
    FileUtils.mkdir(selected_target, mode: 0o700)
    drift_preview = service.restore_preview(
      password: password, snapshot_id: "d" * 64, paths: [], target_root: selected_target
    )
    FileUtils.remove_entry(selected_target)
    FileUtils.mkdir(selected_target, mode: 0o700)
    drifted = service.restore_execute(
      password: password, snapshot_id: "d" * 64, paths: [], target_root: selected_target,
      confirmation: drift_preview.dig("data", "confirmation_phrase"),
      expected_digest: drift_preview.dig("data", "expected_digest")
    )
    check.call("selected directory identity drift invalidates the reviewed digest before restore",
               drifted["lifecycle_state"] == "blocked_for_human_review" &&
                 drifted["reason"].include?("digest is stale") &&
                 Dir.children(selected_target).empty?)
  end

  unsafe_target = service.restore_preview(
    password: password, snapshot_id: "d" * 64, paths: [], target_root: source_root
  )
  Dir.mktmpdir("soul-permissive-recovery-") do |permissive_target|
    File.chmod(0o755, permissive_target)
    permissive = service.restore_preview(
      password: password, snapshot_id: "d" * 64, paths: [], target_root: permissive_target
    )
    check.call("selected recovery roots fail closed on live-source overlap or non-owner-only permissions",
               unsafe_target["lifecycle_state"] == "awaiting_input" &&
                 (unsafe_target["reason"].include?("protected live") || unsafe_target["reason"].include?("backup source")) &&
                 permissive["lifecycle_state"] == "awaiting_input" &&
                 permissive["reason"].include?("owner-only"))
  end

  lock_path = File.join(state_root, "operation.lock")
  File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
    lock.flock(File::LOCK_EX | File::LOCK_NB)
    blocked = service.backup_execute(
      password: password,
      confirmation: preview.dig("data", "confirmation_phrase"),
      expected_digest: preview.dig("data", "expected_digest")
    )
    check.call("a concurrent mutating administration operation fails closed without waiting",
               blocked["lifecycle_state"] == "blocked_for_human_review" &&
                 blocked["reason"].include?("already active"))
  end

  persisted = Dir.glob(File.join(state_root, "**", "*")).select { |path| File.file?(path) }.map { |path| File.binread(path) }.join
  argv_text = runner.calls.flat_map { |call| call.fetch("argv") }.join(" ")
  password_env_only = runner.calls.select { |call| call.fetch("argv").first == "restic" }.all? { |call| call.dig("env", "RESTIC_PASSWORD") == password }
  check.call("repository password reaches only bounded child environments and never argv or persisted evidence",
             password_env_only && !argv_text.include?(password) && !persisted.include?(password))

  facade = SoulCore::ApplicationFacade.new(root: root, backup_administration_service: service)
  envelope = facade.call({
    "schema_version" => "soul.application.v1", "request_id" => "backup-test-0001",
    "operation" => "backup.status", "parameters" => {}, "context" => { "interface" => "dashboard_test" }
  })
  check.call("application contract and facade expose password-optional status through the same lifecycle envelope",
             envelope["lifecycle_state"] == "complete" &&
               envelope.dig("data", "snapshot_access") == "locked")
end

Dir.mktmpdir("soul-backup-configuration-") do |root|
  home = File.join(root, "home")
  FileUtils.mkdir_p(File.join(root, "Soul", "private", "project_tracker"))
  FileUtils.mkdir_p(File.join(home, "Music", "soul-music"))
  script = File.expand_path("soul-backup-config", __dir__)
  stdout, _stderr, status = Open3.capture3("ruby", script, "plan", "--root", root, "--home", home)
  plan = JSON.parse(stdout)
  execute_stdout, _execute_stderr, execute_status = Open3.capture3(
    "ruby", script, "execute", "--root", root, "--home", home,
    "--expected-digest", plan.dig("data", "expected_digest"),
    "--confirmation", plan.dig("data", "confirmation_phrase")
  )
  execute = JSON.parse(execute_stdout)
  sources_path = File.join(root, "Soul", "private", "backup", "sources.txt")
  excludes_path = File.join(root, "Soul", "private", "backup", "excludes.txt")
  check.call("portable configuration previews an exact default scope and creates owner-only non-secret manifests",
             status.success? && execute_status.success? &&
               execute["lifecycle_state"] == "complete" &&
               (File.stat(sources_path).mode & 0o777) == 0o600 &&
               (File.stat(excludes_path).mode & 0o777) == 0o600 &&
               File.read(excludes_path).include?("/Soul/private/backup/restores/**"))

  File.open(sources_path, "a") { |file| file.puts("/operator/custom-scope") }
  changed_stdout, _changed_stderr, changed_status = Open3.capture3("ruby", script, "plan", "--root", root, "--home", home)
  changed = JSON.parse(changed_stdout)
  _blocked_stdout, blocked_stderr, blocked_status = Open3.capture3(
    "ruby", script, "execute", "--root", root, "--home", home,
    "--expected-digest", changed.dig("data", "expected_digest"),
    "--confirmation", changed.dig("data", "confirmation_phrase")
  )
  check.call("portable setup refuses to replace a differing owner backup scope",
             changed_status.success? && !blocked_status.success? &&
               blocked_stderr.include?("never replaces backup scope") &&
               File.read(sources_path).include?("/operator/custom-scope"))
end

html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
javascript = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
css = File.read(File.expand_path("../assets/dashboard/dashboard.css", __dir__))
http = File.read(File.expand_path("../lib/soul_core/dashboard_http_application.rb", __dir__))
check.call("dashboard exposes Administration navigation, repository unlock, exact gates, snapshots, and selectable recovery rehearsal",
           %w[administration-tab administration-menu backup-panel backup-password backup-snapshot-list preview-backup-create execute-backup-create preview-backup-retention execute-backup-retention backup-restore-source backup-restore-target preview-backup-restore execute-backup-restore].all? { |id| html.include?("id=\"#{id}\"") } &&
             javascript.include?('retainText.textContent = "Forget"') &&
             javascript.include?('restoreText.textContent = "Restore"') &&
             javascript.include?('repository_source: backupRestoreSource()') &&
             javascript.include?('state.backupRestorePreview.source_snapshot_id') &&
             css.include?(".backup-snapshot-control") &&
             javascript.include?('backupOperation("create.preview")') &&
             javascript.include?('"/api/v1/administration-stream"') &&
             javascript.include?('["blocked_for_human_review"]'))
check.call("administration stream is request-bound and allow-lists only mutating backup operations",
           http.include?('"/api/v1/administration-stream"') &&
             %w[backup.create.execute backup.retention.execute backup.restore.execute].all? { |operation| http.include?(operation) })
check.call("client never persists or logs the repository password",
           !javascript.match?(/localStorage\.(?:setItem|getItem)\([^)]*backup/i) &&
             !javascript.match?(/console\.(?:log|debug|info)\([^)]*password/i))

abort(errors.map { |error| "- #{error}" }.join("\n")) unless errors.empty?
puts "Backup Administration A2 is candidate-ready for human review."
