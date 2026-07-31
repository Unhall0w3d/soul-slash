#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require "time"

require_relative "../lib/soul_core/backup_retention_ledger"

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

snapshot_id = ->(character) { character * 64 }
repository_id = "e" * 64
root = "/home/operator/Projects/soul/Soul"
paths = {
  tracker: "#{root}/private/project_tracker/state.json",
  chat: "#{root}/runtime/chats/chat_1/messages.jsonl",
  music: "#{root}/music/projects/music_aaaaaaaaaaaaaaaa/project.json"
}

manifest = lambda do |id:, at:, entries:, roots: [root], result: "passed"|
  {
    "schema_version" => SoulCore::BackupRetentionLedger::MANIFEST_SCHEMA_VERSION,
    "snapshot_id" => snapshot_id.call(id),
    "verified_at" => at.utc.iso8601,
    "repository_id" => repository_id,
    "source_roots" => roots.sort,
    "paths" => (entries + roots).uniq.sort,
    "verification" => { "check_mode" => "metadata", "result" => result }
  }
end

Dir.mktmpdir("soul-backup-retention-") do |sandbox|
  ledger_path = File.join(sandbox, "retention.json")
  current_time = Time.utc(2026, 7, 1, 12, 0, 0)
  service = SoulCore::BackupRetentionLedger.new(ledger_path: ledger_path, clock: -> { current_time })

  operator_roots = 117.times.map { |index| format("/home/operator/source-%03d", index) }
  operator_manifest = manifest.call(id: "f", at: current_time, entries: operator_roots, roots: operator_roots)
  default_root_limit = service.observe_preview(manifest: operator_manifest)
  operator_service = SoulCore::BackupRetentionLedger.new(
    ledger_path: File.join(sandbox, "operator-retention.json"),
    clock: -> { current_time },
    max_roots: SoulCore::BackupRetentionLedger::MAX_CONFIGURABLE_ROOTS
  )
  configured_root_limit = operator_service.observe_preview(manifest: operator_manifest)
  check.call("the default Soul root ceiling remains 64 while a bounded Operator ledger accepts 117 roots",
    default_root_limit["lifecycle_state"] == "awaiting_input" &&
      default_root_limit["reason"].include?("source roots exceed 64") &&
      configured_root_limit["lifecycle_state"] == "complete")

  initial = manifest.call(id: "a", at: current_time, entries: paths.values)
  preview = service.observe_preview(manifest: initial)
  check.call("first verified manifest prepares an exact approval gate",
    preview["lifecycle_state"] == "complete" &&
      preview.dig("data", "confirmation_phrase") == SoulCore::BackupRetentionLedger::OBSERVE_CONFIRMATION &&
      preview.dig("data", "expected_digest").match?(/\A[a-f0-9]{64}\z/) &&
      !File.exist?(ledger_path))

  wrong_confirmation = service.observe_execute(manifest: initial, confirmation: "yes", expected_digest: preview.dig("data", "expected_digest"))
  check.call("wrong confirmation cannot initialize the ledger",
    wrong_confirmation["lifecycle_state"] == "awaiting_input" && !File.exist?(ledger_path))

  stale_digest = service.observe_execute(
    manifest: initial,
    confirmation: SoulCore::BackupRetentionLedger::OBSERVE_CONFIRMATION,
    expected_digest: "0" * 64
  )
  check.call("stale digest fails closed before mutation",
    stale_digest["lifecycle_state"] == "blocked_for_human_review" && !File.exist?(ledger_path))

  initialized = service.observe_execute(
    manifest: initial,
    confirmation: preview.dig("data", "confirmation_phrase"),
    expected_digest: preview.dig("data", "expected_digest")
  )
  mode = File.stat(ledger_path).mode & 0o777
  check.call("approved initialization writes one owner-only atomic ledger",
    initialized["lifecycle_state"] == "complete" &&
      initialized["mutation"] == "backup_retention_ledger_initialized" &&
      mode == 0o600)

  replay_preview = service.observe_preview(manifest: initial)
  replay = service.observe_execute(
    manifest: initial,
    confirmation: replay_preview.dig("data", "confirmation_phrase"),
    expected_digest: replay_preview.dig("data", "expected_digest")
  )
  check.call("exact manifest replay is idempotent",
    replay["ok"] && replay["mutation"] == "none" && replay.dig("data", "new_deletion_count").zero?)

  altered_replay = initial.merge("paths" => (initial.fetch("paths") - [paths[:chat]]))
  altered_replay_result = service.observe_preview(manifest: altered_replay)
  check.call("an altered manifest cannot replay a recorded snapshot ID",
    altered_replay_result["lifecycle_state"] == "awaiting_input" &&
      altered_replay_result["reason"].include?("snapshot replay differs"))

  second_time = current_time + (5 * 24 * 60 * 60)
  second = manifest.call(id: "b", at: second_time, entries: [paths[:tracker], paths[:music]])
  deletion_preview = service.observe_preview(manifest: second)
  public_hold = deletion_preview.dig("data", "new_holds", 0)
  check.call("deletion preview protects the immediately preceding verified snapshot without exposing its path",
    deletion_preview.dig("data", "new_deletion_count") == 1 &&
      public_hold["protective_snapshot_id"] == snapshot_id.call("a") &&
      !public_hold.key?("path") &&
      public_hold["path_sha256"].match?(/\A[a-f0-9]{64}\z/))

  deletion = service.observe_execute(
    manifest: second,
    confirmation: deletion_preview.dig("data", "confirmation_phrase"),
    expected_digest: deletion_preview.dig("data", "expected_digest")
  )
  ledger = JSON.parse(File.read(ledger_path))
  hold = ledger.fetch("holds").first
  check.call("approved deletion starts one exact 30-day hold at verified detection time",
    deletion["ok"] &&
      Time.iso8601(hold.fetch("hold_until")) - Time.iso8601(hold.fetch("detected_at")) == 30 * 24 * 60 * 60 &&
      hold.fetch("detected_at") == second_time.iso8601)

  current_time = second_time + (29 * 24 * 60 * 60)
  protected = service.retention_preview(candidate_snapshot_ids: [snapshot_id.call("a"), snapshot_id.call("b")])
  check.call("day 29 protects the prior snapshot and exposes no deletion execution",
    protected.dig("data", "protected_candidate_snapshot_ids") == [snapshot_id.call("a")] &&
      protected.dig("data", "hold_clear_candidate_snapshot_ids") == [snapshot_id.call("b")] &&
      protected.dig("data", "execution_available") == false &&
      protected.dig("data", "next").include?("No forget or prune"))

  third_time = second_time + (10 * 24 * 60 * 60)
  third = manifest.call(id: "c", at: third_time, entries: [paths[:tracker], paths[:music]])
  third_preview = service.observe_preview(manifest: third)
  third_result = service.observe_execute(
    manifest: third,
    confirmation: third_preview.dig("data", "confirmation_phrase"),
    expected_digest: third_preview.dig("data", "expected_digest")
  )
  unchanged_hold = JSON.parse(File.read(ledger_path)).fetch("holds").first
  check.call("later missing snapshots do not reset the deletion clock",
    third_result["ok"] &&
      third_result.dig("data", "new_deletion_count").zero? &&
      unchanged_hold.fetch("detected_at") == second_time.iso8601 &&
      unchanged_hold.fetch("protective_snapshot_id") == snapshot_id.call("a"))

  current_time = second_time + (30 * 24 * 60 * 60)
  expired = service.retention_preview(candidate_snapshot_ids: [snapshot_id.call("a")])
  check.call("exactly 30 full days makes the snapshot hold-clear but not approved for deletion",
    expired.dig("data", "active_hold_count").zero? &&
      expired.dig("data", "expired_hold_count") == 1 &&
      expired.dig("data", "hold_clear_candidate_snapshot_ids") == [snapshot_id.call("a")] &&
      expired.dig("data", "execution_available") == false)

  fourth_time = third_time + (25 * 24 * 60 * 60)
  fourth = manifest.call(id: "d", at: fourth_time, entries: paths.values)
  fourth_preview = service.observe_preview(manifest: fourth)
  fourth_result = service.observe_execute(
    manifest: fourth,
    confirmation: fourth_preview.dig("data", "confirmation_phrase"),
    expected_digest: fourth_preview.dig("data", "expected_digest")
  )
  check.call("a verified reappearance resolves the old hold",
    fourth_result.dig("data", "reappeared_path_count") == 1 &&
      JSON.parse(File.read(ledger_path)).fetch("holds").empty?)

  fifth_time = fourth_time + 60
  fifth = manifest.call(id: "f", at: fifth_time, entries: [paths[:tracker], paths[:music]])
  fifth_preview = service.observe_preview(manifest: fifth)
  service.observe_execute(
    manifest: fifth,
    confirmation: fifth_preview.dig("data", "confirmation_phrase"),
    expected_digest: fifth_preview.dig("data", "expected_digest")
  )
  new_hold = JSON.parse(File.read(ledger_path)).fetch("holds").first
  check.call("a later deletion starts a fresh hold against the new prior snapshot",
    new_hold.fetch("detected_at") == fifth_time.iso8601 &&
      new_hold.fetch("protective_snapshot_id") == snapshot_id.call("d"))

  added_root = "/home/operator/.config/soul"
  added_path = "#{added_root}/runtime.env"
  sixth_time = fifth_time + 60
  expanded = manifest.call(
    id: "1",
    at: sixth_time,
    entries: [paths[:tracker], paths[:music], added_path],
    roots: [root, added_root]
  )
  expanded_preview = service.observe_preview(manifest: expanded)
  prior_ledger = JSON.parse(File.read(ledger_path))
  prior_hold = prior_ledger.fetch("holds").first
  check.call("strict source-root additions are disclosed and bound into preview",
    expanded_preview["ok"] &&
      expanded_preview.dig("data", "source_root_addition_count") == 1 &&
      expanded_preview.dig("data", "source_root_addition_digests") == [Digest::SHA256.hexdigest(added_root)] &&
      expanded_preview.dig("data", "expected_digest").match?(/\A[a-f0-9]{64}\z/))

  expanded_result = service.observe_execute(
    manifest: expanded,
    confirmation: expanded_preview.dig("data", "confirmation_phrase"),
    expected_digest: expanded_preview.dig("data", "expected_digest")
  )
  expanded_ledger = JSON.parse(File.read(ledger_path))
  check.call("approved additive expansion advances roots without resetting deletion holds",
    expanded_result["ok"] &&
      expanded_result.dig("data", "source_root_addition_count") == 1 &&
      expanded_ledger.dig("last_verified_snapshot", "source_roots") == [added_root, root].sort &&
      expanded_ledger.fetch("holds").first == prior_hold)

  seventh_time = sixth_time + 60
  added_root_deletion = manifest.call(
    id: "8",
    at: seventh_time,
    entries: [paths[:tracker], paths[:music]],
    roots: [root, added_root]
  )
  added_root_deletion_preview = service.observe_preview(manifest: added_root_deletion)
  added_root_deletion_result = service.observe_execute(
    manifest: added_root_deletion,
    confirmation: added_root_deletion_preview.dig("data", "confirmation_phrase"),
    expected_digest: added_root_deletion_preview.dig("data", "expected_digest")
  )
  expanded_ledger = JSON.parse(File.read(ledger_path))
  added_path_hold = expanded_ledger.fetch("holds").find { |hold| hold.fetch("path") == added_path }
  check.call("a later deletion inside the added root receives the normal 30-day protection",
    added_root_deletion_result["ok"] &&
      added_path_hold.fetch("protective_snapshot_id") == snapshot_id.call("1") &&
      Time.iso8601(added_path_hold.fetch("hold_until")) - Time.iso8601(added_path_hold.fetch("detected_at")) == 30 * 24 * 60 * 60)

  removal = manifest.call(
    id: "6",
    at: seventh_time + 60,
    entries: [paths[:tracker], paths[:music]],
    roots: [root]
  )
  root_result = service.observe_preview(manifest: removal)
  check.call("source-root removal cannot be interpreted as deletion",
    root_result["lifecycle_state"] == "awaiting_input" &&
      root_result["reason"].include?("removed or replaced") &&
      JSON.parse(File.read(ledger_path)) == expanded_ledger)

  replacement_root = "/home/operator/.local/share/soul"
  replacement = manifest.call(
    id: "7",
    at: seventh_time + 60,
    entries: [paths[:tracker], paths[:music], "#{replacement_root}/state.json"],
    roots: [root, replacement_root]
  )
  replacement_result = service.observe_preview(manifest: replacement)
  check.call("source-root replacement remains blocked even when root count is unchanged",
    replacement_result["lifecycle_state"] == "awaiting_input" &&
      replacement_result["reason"].include?("removed or replaced") &&
      JSON.parse(File.read(ledger_path)) == expanded_ledger)

  failed_check = manifest.call(id: "2", at: seventh_time + 60, entries: [paths[:tracker]], result: "failed")
  verification_result = service.observe_preview(manifest: failed_check)
  check.call("unverified snapshots cannot advance deletion detection",
    verification_result["lifecycle_state"] == "awaiting_input" && verification_result["reason"].include?("verification"))

  rollback = manifest.call(id: "3", at: fourth_time, entries: paths.values)
  rollback_result = service.observe_preview(manifest: rollback)
  check.call("clock rollback cannot advance the ledger",
    rollback_result["lifecycle_state"] == "awaiting_input" && rollback_result["reason"].include?("monotonically"))

  outside = manifest.call(id: "4", at: seventh_time + 60, entries: ["/etc/shadow"])
  outside_result = service.observe_preview(manifest: outside)
  check.call("paths outside the verified source roots are rejected",
    outside_result["lifecycle_state"] == "awaiting_input" && outside_result["reason"].include?("escapes"))

  changed_repository = manifest.call(id: "5", at: seventh_time + 60, entries: paths.values, roots: [root, added_root]).merge("repository_id" => "9" * 64)
  repository_result = service.observe_preview(manifest: changed_repository)
  check.call("repository identity changes cannot join one deletion ledger",
    repository_result["lifecycle_state"] == "awaiting_input" && repository_result["reason"].include?("repository identity changed"))

  File.write(ledger_path, "{broken")
  corrupt = service.retention_preview(candidate_snapshot_ids: [])
  check.call("a corrupt ledger blocks retention instead of permitting prune",
    corrupt["lifecycle_state"] == "blocked_for_human_review")

  missing_service = SoulCore::BackupRetentionLedger.new(ledger_path: File.join(sandbox, "missing.json"), clock: -> { current_time })
  missing = missing_service.retention_preview(candidate_snapshot_ids: [])
  check.call("a missing ledger keeps pruning disabled",
    missing["lifecycle_state"] == "blocked_for_human_review" && missing["reason"].include?("pruning must remain disabled"))
end

source = File.read(File.join(__dir__, "../lib/soul_core/backup_retention_ledger.rb"))
cli = File.read(File.join(__dir__, "soul-backup-retention.rb"))
check.call("production surface contains no restic forget or prune execution",
  !source.match?(/system\s*\(|spawn\s*\(|`.*restic|Open3/) &&
    !cli.match?(/system\s*\(|spawn\s*\(|`.*restic|Open3/) &&
    source.include?('"execution_available" => false'))

abort(errors.map { |error| "- #{error}" }.join("\n")) unless errors.empty?
puts "Backup deletion-aware retention ledger is candidate-ready for human review."
