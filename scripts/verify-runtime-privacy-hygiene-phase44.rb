
#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"

errors = []

puts "Runtime privacy hygiene phase 44 verification:"

required_files = [
  ".gitignore",
  "docs/RUNTIME_PRIVACY_HYGIENE.md",
  "docs/maintenance/PHASE44_RUNTIME_PRIVACY_HYGIENE.md",
  "scripts/verify-runtime-privacy-hygiene-phase44.rb"
]

required_files.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

gitignore = File.exist?(".gitignore") ? File.read(".gitignore") : ""
ignore_checks = {
  "Soul/runtime ignored" => gitignore.include?("Soul/runtime/"),
  "Soul/codex/tasks ignored" => gitignore.include?("Soul/codex/tasks/"),
  "Soul/codex/responses ignored" => gitignore.include?("Soul/codex/responses/"),
  "Soul/codex/reviews ignored" => gitignore.include?("Soul/codex/reviews/"),
  "local marker ignored" => gitignore.include?("*.soul.local")
}

ignore_checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

tracked_runtime, _stderr, _status = Open3.capture3("git", "ls-files", "Soul/runtime")
tracked_codex_tasks, _stderr2, _status2 = Open3.capture3("git", "ls-files", "Soul/codex/tasks")
tracked_codex_responses, _stderr3, _status3 = Open3.capture3("git", "ls-files", "Soul/codex/responses")
tracked_codex_reviews, _stderr4, _status4 = Open3.capture3("git", "ls-files", "Soul/codex/reviews")

tracked_sensitive = (
  tracked_runtime.lines +
  tracked_codex_tasks.lines +
  tracked_codex_responses.lines +
  tracked_codex_reviews.lines
).map(&:strip).reject(&:empty?)

tracking_ok = tracked_sensitive.empty?
puts "- no tracked private runtime/codex task data: #{tracking_ok ? 'ok' : 'missing'}"
errors << "tracked private runtime/codex task data found: #{tracked_sensitive.join(', ')}" unless tracking_ok

if File.directory?("Soul/runtime/chats")
  ignored, _stderr, status = Open3.capture3("git", "check-ignore", "Soul/runtime/chats")
  ignored_ok = status.success? && ignored.include?("Soul/runtime/chats")
  puts "- Soul/runtime/chats check-ignore: #{ignored_ok ? 'ok' : 'missing'}"
  errors << "Soul/runtime/chats is not ignored" unless ignored_ok
else
  ignored, _stderr, status = Open3.capture3("git", "check-ignore", "Soul/runtime/example.db")
  ignored_ok = status.success? && ignored.include?("Soul/runtime/example.db")
  puts "- Soul/runtime check-ignore pattern: #{ignored_ok ? 'ok' : 'missing'}"
  errors << "Soul/runtime ignore pattern did not match" unless ignored_ok
end

doc = File.exist?("docs/RUNTIME_PRIVACY_HYGIENE.md") ? File.read("docs/RUNTIME_PRIVACY_HYGIENE.md") : ""
doc_checks = {
  "private chat data documented" => doc.include?("private chats"),
  "git-restorable boundary documented" => doc.include?("Restorable from Git"),
  "not git-restorable boundary documented" => doc.include?("Not restorable from Git"),
  "backup future documented" => doc.include?("Backup posture")
}

doc_checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
