
#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "Intent router MVP phase 45 verification:"

paths = [
  "lib/soul_core/app.rb",
  "lib/soul_core/intent_router.rb",
  "lib/soul_core/intent_router_assessor.rb",
  "lib/soul_core/chat_responder.rb",
  "scripts/verify-intent-router-mvp-phase45.rb",
  "docs/maintenance/PHASE45_INTENT_ROUTER_MVP.md",
  "docs/INTENT_ROUTER_MVP.md"
]

paths.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

app = File.exist?("lib/soul_core/app.rb") ? File.read("lib/soul_core/app.rb") : ""
{
  "app requires intent router" => app.include?('require_relative "intent_router"'),
  "app requires intent router assessor" => app.include?('require_relative "intent_router_assessor"'),
  "app exposes intent router assessment" => app.include?('"intent-router", "intent-router-mvp", "chat-intents"'),
  "app help includes intent router" => app.include?("ruby bin/soul assess intent-router")
}.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "intent-router", "--json")
json = JSON.parse(stdout) rescue nil
json_ok =
  status.success? &&
  json &&
  json["assessment"] == "intent_router_mvp" &&
  json["ok"] == true &&
  json["status"] == "ready" &&
  json["samples"].is_a?(Array) &&
  json["samples"].all? { |sample| sample["matched"] } &&
  json.dig("verification", "no_skill_execution") == true &&
  json.dig("verification", "no_llm_calls") == true
puts "- JSON intent-router assessment: #{json_ok ? 'ok' : 'missing'}"
errors << "JSON intent-router assessment failed: #{stderr} #{stdout}" unless json_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "intent-router")
text_ok = status.success? && stdout.include?("Soul Intent Router MVP Assessment") && stdout.include?("Status: ready")
puts "- text intent-router assessment: #{text_ok ? 'ok' : 'missing'}"
errors << "text intent-router assessment failed: #{stderr} #{stdout}" unless text_ok

{
  "downloads inspect routing" => ["inspect my downloads", "downloads.inspect"],
  "weather routing" => ["what is the weather?", "weather.report"],
  "provider routing" => ["test cloud providers", "cloud provider"],
  "unknown fallback changed" => ["tell me a strange story", "Phase 45 intent"]
}.each do |name, (message, expected)|
  stdout, stderr, status = run_cmd("ruby", "bin/soul", "chat", message)
  ok = status.success? && stdout.downcase.include?(expected.downcase)
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} failed: #{stderr} #{stdout}" unless ok
end

doc_ok =
  File.read("docs/INTENT_ROUTER_MVP.md").include?("deterministic intent router") &&
  File.read("docs/maintenance/PHASE45_INTENT_ROUTER_MVP.md").include?("Phase 45")
puts "- phase 45 docs: #{doc_ok ? 'ok' : 'missing'}"
errors << "phase 45 docs missing expected content" unless doc_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
curation = JSON.parse(stdout) rescue nil
allowed_untracked = [
  "scripts/verify-intent-router-mvp-phase45.rb",
  "scripts/verify-chat-session-controls-phase42.rb"
]
untracked = curation && curation["untracked_review_candidates"].is_a?(Array) ? curation["untracked_review_candidates"] : []
unexpected_untracked = untracked - allowed_untracked
curation_ok = status.success? && curation && curation.dig("counts", "tracked_overlay_notes").to_i == 0 && unexpected_untracked.empty?
puts "- repo curation remains clean apart from current/open phase verifiers: #{curation_ok ? 'ok' : 'missing'}"
errors << "repo curation has unexpected candidates: #{stderr} #{stdout}" unless curation_ok

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
