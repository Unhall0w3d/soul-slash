#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

cmd = ["ruby", "Soul/skills/cloud/providers/test.rb", "--provider", "mistral"]
stdout, stderr, status = Open3.capture3(*cmd)

unless stderr.to_s.strip.empty?
  warn stderr
end

begin
  parsed = JSON.parse(stdout)
rescue JSON::ParserError => e
  warn "cloud.providers.test did not return valid JSON: #{e.message}"
  warn stdout
  exit 1
end

test = Array(parsed["tests"]).first || {}

checks = {
  "skill name" => parsed["skill"] == "cloud.providers.test",
  "status present" => !parsed["status"].to_s.empty?,
  "test record present" => !test.empty?,
  "provider is mistral" => test["provider"] == "mistral",
  "secrets not printed" => parsed.dig("verification", "secrets_printed") == false,
  "api key values not printed" => parsed.dig("verification", "api_key_values_printed") == false,
  "private repo content not sent" => parsed.dig("verification", "private_repo_content_sent") == false,
  "user memory not sent" => parsed.dig("verification", "user_memory_sent") == false,
  "tiny prompt only" => parsed.dig("verification", "tiny_test_prompt_only") == true
}

puts "cloud.providers.test verification:"
checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
end

# The provider may be disabled or missing a key at this stage. That is acceptable.
acceptable = %w[ok warning error].include?(parsed["status"].to_s)
if checks.values.all? && acceptable && status.success?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed."
  exit 1
end
