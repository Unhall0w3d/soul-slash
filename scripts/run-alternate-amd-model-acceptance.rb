#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require_relative "../lib/soul_core/alternate_model_acceptance_harness"

options = {}
OptionParser.new do |parser|
  parser.banner = "Usage: ruby scripts/run-alternate-amd-model-acceptance.rb --server PATH --model PATH --server-sha256 SHA --model-sha256 SHA"
  parser.on("--server PATH") { |value| options[:server_path] = value }
  parser.on("--model PATH") { |value| options[:model_path] = value }
  parser.on("--server-sha256 SHA") { |value| options[:expected_server_sha256] = value }
  parser.on("--model-sha256 SHA") { |value| options[:expected_model_sha256] = value }
end.parse!

required = %i[server_path model_path expected_server_sha256 expected_model_sha256]
missing = required.reject { |key| !options[key].to_s.empty? }
unless missing.empty?
  warn "Missing required options: #{missing.join(', ')}"
  exit 2
end

result = SoulCore::AlternateModelAcceptanceHarness.new(**options).run
puts JSON.pretty_generate(result)
exit(result["ok"] ? 0 : 1)
