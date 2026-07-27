#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"

require_relative "../lib/soul_core/backup_retention_ledger"

begin
  options = {}
  parser = OptionParser.new do |flags|
    flags.banner = "Usage: ruby scripts/soul-backup-retention.rb COMMAND [options]"
    flags.on("--ledger PATH", "Owner-private retention ledger") { |value| options[:ledger] = value }
    flags.on("--manifest PATH", "Verified snapshot manifest JSON") { |value| options[:manifest] = value }
    flags.on("--candidates PATH", "JSON array of candidate full snapshot IDs") { |value| options[:candidates] = value }
    flags.on("--confirmation TEXT", "Exact observe confirmation phrase") { |value| options[:confirmation] = value }
    flags.on("--expected-digest SHA256", "Digest emitted by observe-preview") { |value| options[:expected_digest] = value }
  end

  command = ARGV.shift
  parser.parse!(ARGV)
  raise OptionParser::MissingArgument, "--ledger" if options[:ledger].to_s.empty?

  service = SoulCore::BackupRetentionLedger.new(ledger_path: options.fetch(:ledger))
  result = case command
  when "observe-preview", "observe-execute"
    raise OptionParser::MissingArgument, "--manifest" if options[:manifest].to_s.empty?
    manifest = JSON.parse(File.binread(options.fetch(:manifest), 32 * 1024 * 1024))
    if command == "observe-preview"
      service.observe_preview(manifest: manifest)
    else
      service.observe_execute(
        manifest: manifest,
        confirmation: options[:confirmation],
        expected_digest: options[:expected_digest]
      )
    end
  when "retention-preview"
    raise OptionParser::MissingArgument, "--candidates" if options[:candidates].to_s.empty?
    candidates = JSON.parse(File.binread(options.fetch(:candidates), 1024 * 1024))
    service.retention_preview(candidate_snapshot_ids: candidates)
  else
    raise OptionParser::InvalidArgument, "command must be observe-preview, observe-execute, or retention-preview"
  end

  puts JSON.pretty_generate(result)
  exit(result["ok"] ? 0 : 1)
rescue OptionParser::ParseError, JSON::ParserError, Errno::ENOENT, Errno::EACCES => error
  warn JSON.generate(
    "ok" => false,
    "lifecycle_state" => "awaiting_input",
    "reason" => error.message,
    "data" => {},
    "mutation" => "none"
  )
  exit 2
end
