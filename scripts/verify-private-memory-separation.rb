#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/conversation_memory_store"
require_relative "../lib/soul_core/memory_paths"
require_relative "../lib/soul_core/private_memory_migration"
require_relative "../lib/soul_core/reflection_review"

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

def fixture(root)
  memory = File.join(root, "Soul/memory")
  FileUtils.mkdir_p(File.join(memory, "exports"))
  {
    "aliases.yaml" => "aliases:\n  workstation: host\n",
    "approved_lessons.md" => "# Approved lessons\n\n- retain provenance\n",
    "approved_rules.md" => "# Approved rules\n\n- ask first\n",
    "conversation_memory.jsonl" => "{\"event\":\"created\"}\n",
    "lessons.md" => "# Lessons\n",
    "projects.yaml" => "projects:\n  soul:\n    display_name: Soul\n",
    "user.yaml" => "user:\n  name: Operator\n"
  }.each { |name, content| File.write(File.join(memory, name), content) }
  File.write(File.join(memory, "exports/snapshot.json"), "{\"snapshot\":true}\n")
end

puts "Soul private-memory separation verification:"

Dir.mktmpdir("soul-private-memory-") do |root|
  fixture(root)
  paths = SoulCore::MemoryPaths.new(root: root)
  migration = SoulCore::PrivateMemoryMigration.new(root: root, paths: paths, clock: -> { Time.utc(2026, 7, 18, 12) })
  preview = migration.preview
  private_root = File.join(root, "Soul/private")
  preview_text = JSON.generate(preview)

  check.call("preview is bounded, review-gated, content-free, and read-only",
             preview["lifecycle_state"] == "blocked_for_human_review" &&
               preview.dig("data", "file_count") == 8 &&
               preview.dig("data", "source_files_retained") == true &&
               preview.dig("data", "repository_sanitization_included") == false &&
               !File.exist?(private_root) &&
               !preview_text.include?("Operator") && !preview_text.include?("ask first"))
  check.call("compatibility resolver remains on legacy state before cutover",
             paths.read_path("user.yaml") == File.join(root, "Soul/memory/user.yaml") &&
               paths.write_path("approved_rules.md") == File.join(root, "Soul/memory/approved_rules.md"))

  digest = preview.dig("data", "expected_digest")
  wrong = migration.execute(confirmation: "COPY", expected_digest: digest)
  check.call("wrong confirmation creates no private state",
             wrong["lifecycle_state"] == "blocked_for_human_review" && !File.exist?(private_root))

  File.open(File.join(root, "Soul/memory/user.yaml"), "a") { |file| file.puts("changed: true") }
  stale = migration.execute(confirmation: SoulCore::PrivateMemoryMigration::CONFIRMATION, expected_digest: digest)
  check.call("source mutation invalidates the exact preview",
             stale["lifecycle_state"] == "blocked_for_human_review" && !File.exist?(private_root))
  File.write(File.join(root, "Soul/memory/user.yaml"), "user:\n  name: Operator\n")

  preview = migration.preview
  completed = migration.execute(
    confirmation: SoulCore::PrivateMemoryMigration::CONFIRMATION,
    expected_digest: preview.dig("data", "expected_digest")
  )
  rows = preview.dig("data", "files")
  copies_match = rows.all? do |row|
    source = File.join(root, row.fetch("source"))
    destination = File.join(root, row.fetch("destination"))
    File.file?(source) && File.file?(destination) && File.binread(source) == File.binread(destination) &&
      (File.stat(destination).mode & 0o777) == 0o600
  end
  check.call("execution copies every file byte-for-byte, verifies it, and retains sources",
             completed["lifecycle_state"] == "complete" && completed.dig("data", "verified") && copies_match)
  check.call("verified marker cuts compatibility reads and writes over to private memory",
             paths.migrated? &&
               paths.read_path("user.yaml") == File.join(root, "Soul/private/memory/user.yaml") &&
               paths.write_path("approved_rules.md") == File.join(root, "Soul/private/memory/approved_rules.md") &&
               (File.stat(paths.marker_path).mode & 0o777) == 0o600)

  store = SoulCore::ConversationMemoryStore.new(root: root)
  review = SoulCore::ReflectionReview.new(
    root: root,
    pending_root: File.join(root, "pending"),
    approved_root: File.join(root, "approved"),
    rejected_root: File.join(root, "rejected")
  )
  check.call("shared-memory writers follow the verified private cutover",
             store.path == File.join(root, "Soul/private/memory/conversation_memory.jsonl") &&
               review.instance_variable_get(:@approved_lessons_path) == File.join(root, "Soul/private/memory/approved_lessons.md"))

  replay = migration.preview
  check.call("completed migration is idempotently blocked from replay",
             replay["lifecycle_state"] == "blocked_for_human_review" && replay.dig("data", "migrated") == true)
end

Dir.mktmpdir("soul-private-memory-fresh-") do |root|
  FileUtils.mkdir_p(File.join(root, "Soul/memory"))
  File.write(File.join(root, "Soul/memory/.public_seed_v1"), "public seed\n")
  File.write(File.join(root, "Soul/memory/user.yaml"), "user: {}\npreferences: {}\n")
  paths = SoulCore::MemoryPaths.new(root: root)
  store = SoulCore::ConversationMemoryStore.new(root: root)
  check.call("fresh public-seed clones read defaults but write only to ignored private memory",
             paths.read_path("user.yaml") == File.join(root, "Soul/memory/user.yaml") &&
             paths.write_path("user.yaml") == File.join(root, "Soul/private/memory/user.yaml") &&
               store.path == File.join(root, "Soul/private/memory/conversation_memory.jsonl"))
end

Dir.mktmpdir("soul-private-memory-symlink-") do |root|
  fixture(root)
  FileUtils.rm_f(File.join(root, "Soul/memory/user.yaml"))
  File.symlink("projects.yaml", File.join(root, "Soul/memory/user.yaml"))
  result = SoulCore::PrivateMemoryMigration.new(root: root).preview
  check.call("symlinked legacy memory fails closed",
             result["lifecycle_state"] == "failed" && result["message"].include?("non-symlink"))
end

Dir.mktmpdir("soul-private-memory-parent-symlink-") do |root|
  fixture(root)
  FileUtils.mkdir_p(File.join(root, "elsewhere"))
  FileUtils.mkdir_p(File.join(root, "Soul"))
  File.symlink(File.join(root, "elsewhere"), File.join(root, "Soul/private"))
  result = SoulCore::PrivateMemoryMigration.new(root: root).preview
  check.call("symlinked private destination ancestry fails closed",
             result["lifecycle_state"] == "failed" && result["message"].include?("ancestry"))
end

gitignore = File.read(File.join(__dir__, "../.gitignore"))
downloads = File.read(File.join(__dir__, "../Soul/skills/downloads/inspect.rb"))
check.call("private memory is ignored and project-aware skill reads use the resolver",
           gitignore.lines.map(&:strip).include?("Soul/private/") && downloads.include?("MemoryPaths"))

if errors.empty?
  puts "PASS: 12 checks"
  exit 0
end

warn "FAIL: #{errors.length} checks failed: #{errors.join(', ')}"
exit 1
