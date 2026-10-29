#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/backup_administration_service"

def check(label, condition)
  raise "FAIL: #{label}" unless condition
  puts "PASS: #{label}"
end

class ScopeNoExternalCommands
  def which(*) = raise("no external calls allowed")
  def run(*) = raise("no external calls allowed")
end

class InterruptedScopeMigration < SoulCore::BackupAdministrationService
  private
  def atomic_text(path, body)
    raise IOError, "fixture interruption after ledger promotion" if path == @sources_path
    super
  end
end

def fixture(profile = "soul", service_class = SoulCore::BackupAdministrationService)
  Dir.mktmpdir("backup-scope-fixture-") do |root|
    private_root = File.join(root, "Soul", "private")
    state = File.join(private_root, profile == "operator" ? "operator_backup" : "backup")
    FileUtils.mkdir_p(state, mode: 0o700)
    File.chmod(0o700, private_root)
    home = File.join(root, "home")
    roots = %w[keep other retired].map { |name| File.join(home, name) }.sort
    roots.first(2).each { |path| FileUtils.mkdir_p(path) }
    repository = File.join(root, "repository")
    FileUtils.mkdir_p(repository)
    File.write(File.join(repository, "config"), "fixture repository identity")
    repo_id = Digest::SHA256.file(File.join(repository, "config")).hexdigest
    evidence = File.join(root, "verified-preservation-receipt.json")
    File.write(evidence, '{"fixture":"retained and verified"}')
    sources = File.join(state, "sources.txt")
    File.write(sources, "# retained comment\n" + roots.join("\n") + "\n", perm: 0o600)
    File.write(File.join(state, "excludes.txt"), "*.tmp\n", perm: 0o600)
    ledger_path = File.join(state, "retention-ledger.json")
    clock = -> { Time.utc(2026, 10, 15, 19) }
    ledger = SoulCore::BackupRetentionLedger.new(ledger_path: ledger_path, clock: clock)
    make_manifest = lambda do |id, time, scope, paths|
      {"schema_version" => SoulCore::BackupRetentionLedger::MANIFEST_SCHEMA_VERSION,
       "snapshot_id" => id * 64, "verified_at" => time.utc.iso8601,
       "repository_id" => repo_id, "source_roots" => scope.sort,
       "paths" => (scope + paths).uniq.sort,
       "verification" => {"check_mode" => "metadata", "result" => "passed"}}
    end
    lost = File.join(roots.last, "earlier-deletion")
    old = File.join(roots.last, "retired-content")
    [make_manifest.call("a", clock.call - 7200, roots, [lost, old]),
     make_manifest.call("b", clock.call - 3600, roots, [old])].each do |manifest|
      p = ledger.observe_preview(manifest: manifest)
      r = ledger.observe_execute(manifest: manifest, confirmation: p.dig("data", "confirmation_phrase"), expected_digest: p.dig("data", "expected_digest"))
      raise r["reason"] unless r["ok"]
    end
    env = {"SOUL_BACKUP_REPOSITORY" => repository, "SOUL_BACKUP_MOUNT" => repository}
    service = service_class.new(root: root, home: home, process_env: env, profile_id: profile, runner: ScopeNoExternalCommands.new, clock: clock)
    retired = [{"path" => roots.last, "reason" => "Old desktop configuration retained but intentionally inactive", "evidence" => evidence}]
    yield({root: root, state: state, sources: sources, ledger_path: ledger_path,
           ledger: ledger, service: service, retirements: retired, roots: roots,
           evidence: evidence, make_manifest: make_manifest, clock: clock,
           old: old, lost: lost, repository: repository})
  end
end

def apply_scope(f, preview)
  f[:service].scope_migration_execute(retirements: f[:retirements],
    confirmation: preview.dig("data", "confirmation_phrase"), expected_digest: preview.dig("data", "expected_digest"))
end

%w[soul operator].each do |profile|
  fixture(profile) do |f|
    service, ledger = f.values_at(:service, :ledger)
    original = File.binread(f[:ledger_path])
    original_sources = File.binread(f[:sources])
    preview = service.scope_migration_preview(retirements: f[:retirements])
    check("#{profile} preview is exact, non-mutating and profile-specific", preview["ok"] && preview.dig("data", "confirmation_phrase").include?(profile.upcase) && File.binread(f[:ledger_path]) == original)
    wrong = service.scope_migration_execute(retirements: f[:retirements], confirmation: "yes", expected_digest: preview.dig("data", "expected_digest"))
    check("wrong confirmation preserves inputs", !wrong["ok"] && File.binread(f[:ledger_path]) == original && File.binread(f[:sources]) == original_sources)
    File.write(f[:evidence], "changed evidence")
    stale = apply_scope(f, preview)
    check("evidence drift rejects execution before mutation", !stale["ok"] && File.binread(f[:ledger_path]) == original)
    File.write(f[:evidence], '{"fixture":"retained and verified"}')
    File.open(f[:sources], "a") { |file| file.puts "# drift" }
    check("manifest drift invalidates preview", !apply_scope(f, preview)["ok"])
    File.write(f[:sources], original_sources)
    exclusion_path = File.join(f[:state], "excludes.txt")
    File.write(exclusion_path, "*.tmp\n# drift\n")
    check("exclusion drift invalidates preview", !apply_scope(f, preview)["ok"])
    File.write(exclusion_path, "*.tmp\n")
    changed_ledger = JSON.parse(original).merge("updated_at" => (f[:clock].call + 1).iso8601)
    File.write(f[:ledger_path], JSON.generate(changed_ledger))
    check("ledger drift invalidates preview", !apply_scope(f, preview)["ok"])
    File.write(f[:ledger_path], original)
    FileUtils.mkdir_p(f[:roots].last)
    check("a source that reappears cannot be retired", !service.scope_migration_preview(retirements: f[:retirements])["ok"])
    Dir.rmdir(f[:roots].last)
    File.symlink(f[:roots].first, f[:roots].last)
    check("symlinked retired sources fail closed", !service.scope_migration_preview(retirements: f[:retirements])["ok"])
    File.unlink(f[:roots].last)
    check("duplicate retirements are rejected", !service.scope_migration_preview(retirements: f[:retirements] * 2)["ok"])
    lock_path = File.join(f[:root], "Soul/private/backup/operation.lock")
    FileUtils.mkdir_p(File.dirname(lock_path), mode: 0o700)
    File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
      lock.flock(File::LOCK_EX)
      check("shared operation lock prevents concurrent mutation", !apply_scope(f, preview)["ok"])
    end
    result = apply_scope(f, preview)
    check("#{profile} migration completes", result["ok"])
    before, after = JSON.parse(original), JSON.parse(File.binread(f[:ledger_path]))
    check("snapshot identity inventory and every hold are unchanged", before["last_verified_snapshot"] == after["last_verified_snapshot"] && before["holds"] == after["holds"])
    check("new capture scope and retired roots are explicit", after["approved_source_roots"] == f[:roots].first(2) && after["retired_source_roots"] == [f[:roots].last])
    check("comments exclusions and before-images are preserved", File.binread(f[:sources]).start_with?("# retained comment\n") && File.read(File.join(f[:state], "excludes.txt")) == "*.tmp\n" && File.binread(Dir.glob(File.join(f[:state], "receipts/*.recovery/ledger.before")).first) == original)
    receipt = JSON.parse(File.read(Dir.glob(File.join(f[:state], "receipts/scope_migration_*.json")).first))
    check("completed owner-private receipt and no pending marker", receipt["state"] == "complete" && !File.exist?(File.join(f[:state], "scope-migration-pending.json")) && (File.stat(f[:ledger_path]).mode & 0o077).zero?)
    check("migration cannot silently repeat", !apply_scope(f, preview)["ok"])
    removed_again = f[:make_manifest].call("c", f[:clock].call + 60, [f[:roots].first], [])
    check("ordinary backup still rejects an unreviewed source removal", !ledger.observe_preview(manifest: removed_again)["ok"])
    next_manifest = f[:make_manifest].call("c", f[:clock].call + 60, f[:roots].first(2), [])
    next_preview = ledger.observe_preview(manifest: next_manifest)
    check("approved scope is accepted by ordinary observation", next_preview["ok"])
    next_result = ledger.observe_execute(manifest: next_manifest, confirmation: next_preview.dig("data", "confirmation_phrase"), expected_digest: next_preview.dig("data", "expected_digest"))
    check("first new snapshot completes without rewriting historical evidence", next_result["ok"] && ledger.checkpoint["ok"])
    final = JSON.parse(File.binread(f[:ledger_path]))
    check("old hold survives byte-equivalent and retired content gets new holds", final["holds"].include?(before["holds"].first) && final["holds"].any? { |hold| hold["path"] == f[:old] && hold["protective_snapshot_id"] == "b" * 64 })
    retention = ledger.retention_preview(candidate_snapshot_ids: ["a" * 64, "b" * 64])
    check("both old snapshots remain protected", retention["ok"] && retention.dig("data", "protected_candidate_snapshot_ids") == ["a" * 64, "b" * 64])
    extra_root = File.join(f[:root], "new-source")
    additive_manifest = f[:make_manifest].call("d", f[:clock].call + 120, f[:roots].first(2) + [extra_root], [])
    additive = ledger.observe_preview(manifest: additive_manifest)
    added = ledger.observe_execute(manifest: additive_manifest, confirmation: additive.dig("data", "confirmation_phrase"), expected_digest: additive.dig("data", "expected_digest"))
    check("ordinary additions retain migration history and hold protection", added["ok"] && JSON.parse(File.read(f[:ledger_path]))["scope_migration_receipts"] == final["scope_migration_receipts"])
    remove_added = f[:make_manifest].call("e", f[:clock].call + 180, f[:roots].first(2), [])
    check("later removal of an added root still needs explicit migration", !ledger.observe_preview(manifest: remove_added)["ok"])
    corrupted = Marshal.load(Marshal.dump(final))
    corrupted["retired_source_roots"] = []
    File.write(f[:ledger_path], JSON.generate(corrupted))
    check("removing retired-root protection corrupts the ledger and blocks retention", !ledger.retention_preview(candidate_snapshot_ids: ["a" * 64])["ok"])
  end
end

fixture("soul", InterruptedScopeMigration) do |f|
  preview = f[:service].scope_migration_preview(retirements: f[:retirements])
  original_sources = File.binread(f[:sources])
  result = apply_scope(f, preview)
  check("partial migration is explicitly reported without retry", !result["ok"] && result["mutation"] == "backup_scope_migration_incomplete" && result.dig("data", "pending_marker"))
  check("partial migration retains original sources and ledger before-image", File.binread(f[:sources]) == original_sources && Dir.glob(File.join(f[:state], "receipts/*.recovery/ledger.before")).one?)
  check("partial migration blocks normal backup before external I/O", f[:service].backup_preview(password: "fixture-only")["reason"].include?("pending scope migration"))
  check("partial migration cannot restart itself", !f[:service].scope_migration_preview(retirements: f[:retirements])["ok"] && !apply_scope(f, preview)["ok"])
end
puts "Backup scope migration deterministic checks passed. No live repository or credential accessed."
