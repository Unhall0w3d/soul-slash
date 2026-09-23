#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require_relative "../lib/soul_core/backup_administration_service"

ledger_class = SoulCore::BackupRetentionLedger
backup_class = SoulCore::BackupAdministrationService
raise "path ceiling drift" unless ledger_class::MAX_PATHS == 1_000_000
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
puts "Backup inventory capacity verification passed: large persisted ledger, replay, overflow refusal, and both inventory readers."
