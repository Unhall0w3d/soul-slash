#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require_relative "../lib/soul_core/backup_administration_service"

ledger_class = SoulCore::BackupRetentionLedger
backup_class = SoulCore::BackupAdministrationService
raise "path ceiling drift" unless ledger_class::MAX_PATHS == 1_000_000
raise "hold ceiling must support a complete inventory deletion" unless ledger_class::MAX_HOLDS == ledger_class::MAX_PATHS
raise "inventory ceiling drift" unless backup_class::MAX_INVENTORY_BYTES == 256 * 1024 * 1024
raise "ledger ceiling drift" unless ledger_class::MAX_LEDGER_BYTES == 512 * 1024 * 1024

Dir.mktmpdir("soul-inventory-capacity-") do |directory|
  path = File.join(directory, "ledger.json")
  ledger = ledger_class.new(ledger_path: path)
  root = "/fixture"
  paths = [root] + 170_000.times.map { |i| format("%s/%06d-%s", root, i, "x" * 220) }
  manifest = {
    "schema_version" => ledger_class::MANIFEST_SCHEMA_VERSION,
    "snapshot_id" => "a" * 64, "repository_id" => "b" * 64,
    "verified_at" => Time.now.utc.iso8601, "source_roots" => [root],
    "paths" => paths, "verification" => {"check_mode" => "metadata", "result" => "passed"}
  }
  preview = ledger.observe_preview(manifest: manifest)
  raise preview["reason"] unless preview["ok"]
  result = ledger.observe_execute(manifest: manifest,
    confirmation: ledger_class::OBSERVE_CONFIRMATION,
    expected_digest: preview.dig("data", "expected_digest"))
  raise result["reason"] unless result["ok"]
  raise "fixture must exceed former ledger limit" unless File.size(path) > 32 * 1024 * 1024
  raise "large ledger replay failed" unless ledger.observe_preview(manifest: manifest)["ok"]
  before = Digest::SHA256.file(path).hexdigest
  rejected = ledger.observe_preview(manifest: manifest.merge("paths" => Array.new(ledger_class::MAX_PATHS + 1, root)))
  raise "overflow accepted or mutated" if rejected["ok"] || Digest::SHA256.file(path).hexdigest != before

  deleted = manifest.merge("snapshot_id" => "c" * 64,
    "verified_at" => (Time.iso8601(manifest.fetch("verified_at")) + 60).iso8601,
    "paths" => [root])
  deletion_preview = ledger.observe_preview(manifest: deleted)
  raise deletion_preview["reason"] unless deletion_preview["ok"]
  raise "large deletion lost holds" unless deletion_preview.dig("data", "total_hold_count_after") == 170_000
  deleted_result = ledger.observe_execute(manifest: deleted,
    confirmation: ledger_class::OBSERVE_CONFIRMATION,
    expected_digest: deletion_preview.dig("data", "expected_digest"))
  raise deleted_result["reason"] unless deleted_result["ok"]
  retained = JSON.parse(File.read(path))
  raise "large hold ledger did not persist" unless retained.fetch("holds").length == 170_000 && ledger.checkpoint["ok"]
  raise "deletion clocks or lineage changed" unless retained.fetch("holds").all? { |hold|
    hold.fetch("protective_snapshot_id") == "a" * 64 &&
      hold.fetch("detected_by_snapshot_id") == "c" * 64 &&
      Time.iso8601(hold.fetch("hold_until")) - Time.iso8601(hold.fetch("detected_at")) == ledger_class::HOLD_SECONDS
  }
  before = Digest::SHA256.file(path).hexdigest
  begin
    ledger.send(:validate_ledger!, retained.merge("holds" => Array.new(ledger_class::MAX_HOLDS + 1)))
    raise "hold overflow accepted"
  rescue RuntimeError => error
    raise if error.message == "hold overflow accepted"
  end
  raise "hold overflow mutated ledger" unless Digest::SHA256.file(path).hexdigest == before
  reappeared = deleted.merge("snapshot_id" => "d" * 64,
    "verified_at" => (Time.iso8601(deleted.fetch("verified_at")) + 60).iso8601,
    "paths" => paths.first(5_001))
  reappearance = ledger.observe_preview(manifest: reappeared)
  raise reappearance["reason"] unless reappearance["ok"]
  raise "large reappearance miscounted" unless reappearance.dig("data", "reappeared_path_count") == 5_000 &&
    reappearance.dig("data", "total_hold_count_after") == 165_000 &&
    Digest::SHA256.file(path).hexdigest == before

  service = backup_class.allocate
  captured = []
  truncated = false
  runner = lambda do |*args, **options, &projection|
    captured << options
    raise "missing path projection" unless projection.call({"struct_type" => "node", "path" => root}) == root
    SoulCore::BoundedCommandRunner::Result.new(exit_status: 0, status: "ok", stdout: "", stderr: "",
      truncated: truncated, records: paths)
  end
  service.define_singleton_method(:restic, &runner)
  service.define_singleton_method(:replica_restic, &runner)
  [:snapshot_paths, :replica_snapshot_paths].each do |method|
    raise "inventory changed" unless service.send(method, "fixture", "a" * 64) == paths
    options = captured.last
    raise "bounds not propagated" unless options[:output] == backup_class::MAX_INVENTORY_BYTES &&
      options[:max_records] == ledger_class::MAX_PATHS && options[:capture_mode] == :json_lines
    truncated = true
    begin
      service.send(method, "fixture", "a" * 64)
      raise "truncated inventory accepted"
    rescue RuntimeError => error
      raise unless error.message.include?("inventory is too large")
    ensure
      truncated = false
    end
  end
end
puts "Backup inventory capacity verification passed: large persisted inventory/holds, clocks/lineage, reappearance, overflow refusal, and both inventory readers."
