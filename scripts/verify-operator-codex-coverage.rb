#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"
require_relative "../lib/soul_core/operator_backup_manifest_policy"

# Synthetic bytes only: this checks selection using native Restic, not SQLite
# consistency or restoration of an active Codex instance.
Dir.mktmpdir("operator-codex-coverage-") do |root|
  home = File.join(root, "home")
  included = %w[
    .codex/auth.json .codex/config.toml .codex/.codex-global-state.json
    .codex/sessions/current.jsonl .codex/archived_sessions/old.jsonl
    .codex/attachments/fixture.txt .codex/worktrees/example/dirty.txt
    .codex/automations/example/automation.toml .codex/plugins/example/skill.txt
    .codex/state_5.sqlite .codex/state_5.sqlite-wal .codex/state_5.sqlite-shm
    .codex/thread_history_1.sqlite .codex/sqlite/codex-dev.db
    .config/Codex/Local\ State .config/Codex/Default/History
    .config/Codex/Default/Local\ Storage/leveldb/000001.log
    Projects/example/Gemfile.lock Projects/example/Cargo.lock Projects/example/uv.lock
    Projects/example/package-lock.json
  ]
  excluded = [
    ".codex/packages/download.bin", ".codex/cache/cache.bin",
    ".codex/.tmp/partial.bin", ".codex/tmp/partial.bin",
    ".codex/thread-writer-locks/session.lock", ".codex/.sqlite-maintenance.lock",
    ".config/Codex/Default/Cache/cache.bin", ".config/Codex/GPUCache/cache.bin",
    ".config/Codex/Default/Code Cache/code.bin",
    ".config/Codex/Default/Service Worker/CacheStorage/cache.bin",
    ".config/Codex/SingletonLock", "Projects/example/.git/index.lock",
    "Projects/example/node_modules/reproducible.js", "Projects/example/target/output.bin"
  ]
  (included + excluded).each do |relative|
    path = File.join(home, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "synthetic coverage fixture\n")
  end
  policy = SoulCore::OperatorBackupManifestPolicy.new(root: root, home: home, system_root: File.join(root, "system"))
  sources = policy.sources
  abort "older child roots lost" unless sources.include?(File.join(home, ".codex", "auth.json")) &&
    sources.include?(File.join(home, ".codex", "archived_sessions")) && sources.include?(File.join(home, ".codex"))
  source_file, exclude_file = %w[sources excludes].map { |name| File.join(root, name) }
  File.write(source_file, sources.join("\n") + "\n")
  File.write(exclude_file, policy.exclusions.join("\n") + "\n")
  env = {"RESTIC_REPOSITORY" => File.join(root, "repo"), "RESTIC_PASSWORD" => "synthetic-test-password", "RESTIC_CACHE_DIR" => File.join(root, "cache")}
  run = lambda do |*args|
    stdout, stderr, status = Open3.capture3(env, "restic", *args)
    abort "Restic fixture failed: #{args.first}: #{stderr}" unless status.success?
    stdout
  end
  run.call("init")
  run.call("backup", "--quiet", "--files-from", source_file, "--exclude-file", exclude_file)
  nodes = run.call("ls", "--json", "latest").lines.map { |line| JSON.parse(line) }.select { |item| item["struct_type"] == "node" }
  paths = nodes.map { |item| item["path"] }
  missing = included.reject { |relative| paths.include?(File.join(home, relative)) }
  unwanted = excluded.select { |relative| paths.include?(File.join(home, relative)) }
  abort "coverage mismatch: missing=#{missing.inspect} unwanted=#{unwanted.inspect}" unless missing.empty? && unwanted.empty?
  abort "overlapping root omitted" unless sources.all? { |source| paths.include?(source) }
  run.call("check")
  puts "PASS: #{included.length} required files, #{excluded.length} transient exclusions, overlapping legacy roots, native Restic metadata check."
  puts "Application consistency and live recovery are not established by this fixture."
end
