#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

cmd = ["ruby", "Soul/skills/cloud/providers/list.rb"]
stdout, stderr, status = Open3.capture3(*cmd)

unless stderr.to_s.strip.empty?
  warn stderr
end

begin
  parsed = JSON.parse(stdout)
rescue JSON::ParserError => e
  warn "cloud.providers.list did not return valid JSON: #{e.message}"
  warn stdout
  exit 1
end

checks = {
  "skill name" => parsed["skill"] == "cloud.providers.list",
  "status present" => !parsed["status"].to_s.empty?,
  "outcome complete" => parsed["outcome"] == "complete",
  "providers array" => parsed["providers"].is_a?(Array),
  "network not used" => parsed.dig("verification", "network_used") == false,
  "secrets not printed" => parsed.dig("verification", "secrets_printed") == false,
  "api key values not printed" => parsed.dig("verification", "api_key_values_printed") == false,
  "final state complete" => parsed.dig("verification", "final_state") == "complete"
}

puts "cloud.providers.list verification:"
checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
end

if checks.values.all? && status.success?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed."
  exit 1
end
