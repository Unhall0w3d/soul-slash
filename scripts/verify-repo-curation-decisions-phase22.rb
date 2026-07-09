
#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"

errors = []
warnings = []

def capture(*cmd)
  Open3.capture3(*cmd)
end

def git_ls_files
  stdout, stderr, status = capture("git", "ls-files")
  raise "git ls-files failed: #{stderr}" unless status.success?
  stdout.lines.map(&:strip).reject(&:empty?)
end

def git_status_porcelain
  stdout, stderr, status = capture("git", "status", "--porcelain")
  raise "git status failed: #{stderr}" unless status.success?
  stdout.lines.map(&:chomp)
end

puts "repo curation decisions phase 22 verification:"

required_files = [
  "docs/maintenance/CURATION_DECISIONS.md",
  "docs/maintenance/PHASE22_REPO_CURATION_DECISIONS.md",
  "scripts/verify-repo-curation-decisions-phase22.rb"
]

required_files.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  puts "- #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

decision_text = File.exist?("docs/maintenance/CURATION_DECISIONS.md") ? File.read("docs/maintenance/CURATION_DECISIONS.md") : ""
decision_checks = {
  "decision log names tracked overlay notes" => "README_WEATHER_REFLECTION_HANDLER_REPAIR.md",
  "decision log names alpha review verifier" => "verify-alpha-review-phase18.rb",
  "decision log forbids git add dot" => "Do not use `git add .`",
  "decision log documents git rm" => "git rm docs/overlays/README_WEATHER_REFLECTION_HANDLER_REPAIR.md"
}

decision_checks.each do |name, needle|
  ok = decision_text.include?(needle)
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing expected text" unless ok
end

tracked = git_ls_files

removed_overlay_notes = [
  "docs/overlays/README_WEATHER_REFLECTION_HANDLER_REPAIR.md",
  "docs/overlays/README_YOUTUBE_VIDEO_RESOLVE_ERROR_DETAIL_REPAIR.md",
  "docs/overlays/README_YOUTUBE_VIDEO_RESOLVE_ERROR_DETAIL_REPAIR_V2.md"
]

removed_overlay_notes.each do |path|
  tracked_now = tracked.include?(path)
  exists_now = File.exist?(path)
  ok = !tracked_now && !exists_now
  puts "- removed tracked overlay note #{path}: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} is still tracked or present" unless ok
end

durable_verifiers = [
  "scripts/verify-alpha-review-phase18.rb",
  "scripts/verify-repo-curation-phase21.rb",
  "scripts/verify-repo-curation-decisions-phase22.rb"
]

durable_verifiers.each do |path|
  exists = File.exist?(path)
  syntax = exists && system("ruby", "-c", path, out: File::NULL, err: File::NULL)
  puts "- durable verifier #{path}: #{syntax ? 'ok' : 'missing'}"
  errors << "#{path} missing or syntax invalid" unless syntax
end

status = git_status_porcelain
untracked_verifiers = status.select { |line| line.start_with?("?? scripts/verify-") }
if untracked_verifiers.empty?
  puts "- untracked durable verifiers: ok"
else
  puts "- untracked durable verifiers: warning"
  warnings << "Durable verifier(s) remain untracked: #{untracked_verifiers.join('; ')}"
end

tracked_overlay_notes = tracked.grep(%r{\Adocs/overlays/README_.*(PHASE|REPAIR).*\.md\z})
if tracked_overlay_notes.empty?
  puts "- tracked overlay phase/repair notes: ok"
else
  puts "- tracked overlay phase/repair notes: warning"
  warnings << "Some tracked overlay phase/repair notes remain for future curation: #{tracked_overlay_notes.join(', ')}"
end

warnings.each { |warning| puts "- warning: #{warning}" }

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
