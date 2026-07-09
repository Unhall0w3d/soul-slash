
#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def run_cmd(*cmd)
  Open3.capture3(*cmd)
end

puts "skill registry to_h repair verification:"

path = "lib/soul_core/skill_registry.rb"
exists = File.exist?(path)
syntax_ok = exists && system("ruby", "-c", path, out: File::NULL, err: File::NULL)
has_to_h = exists && File.read(path).include?("def to_h")

puts "- #{path}: #{exists ? 'ok' : 'missing'}"
puts "- syntax: #{syntax_ok ? 'ok' : 'missing'}"
puts "- SkillRegistry#to_h: #{has_to_h ? 'ok' : 'missing'}"

errors << "#{path} missing" unless exists
errors << "#{path} syntax failed" unless syntax_ok
errors << "SkillRegistry#to_h missing" unless has_to_h

stdout, stderr, status = run_cmd("ruby", "bin/soul", "skills")
skills_json = JSON.parse(stdout) rescue nil
skills_ok =
  status.success? &&
  skills_json &&
  (skills_json.is_a?(Hash) || skills_json.is_a?(Array))

puts "- ruby bin/soul skills: #{skills_ok ? 'ok' : 'missing'}"
errors << "ruby bin/soul skills failed: #{stderr} #{stdout}" unless skills_ok

stdout, stderr, status = run_cmd("ruby", "bin/soul", "doctor", "--json")
doctor_json = JSON.parse(stdout) rescue nil
doctor_ok = status.success? && doctor_json

puts "- ruby bin/soul doctor --json: #{doctor_ok ? 'ok' : 'missing'}"
errors << "ruby bin/soul doctor --json failed: #{stderr} #{stdout}" unless doctor_ok

makefile = File.exist?("Makefile") ? File.read("Makefile") : ""
if makefile.include?("test-soul")
  stdout, stderr, status = run_cmd("make", "test-soul")
  make_ok = status.success?
  puts "- make test-soul: #{make_ok ? 'ok' : 'missing'}"
  errors << "make test-soul failed: #{stderr} #{stdout}" unless make_ok
else
  puts "- make test-soul: skipped"
end

stdout, stderr, status = run_cmd("ruby", "bin/soul", "assess", "repo-curation", "--json")
curation = JSON.parse(stdout) rescue nil
allowed_untracked = ["scripts/verify-skill-registry-to-h-repair.rb"]
untracked = curation && curation["untracked_review_candidates"].is_a?(Array) ? curation["untracked_review_candidates"] : []
unexpected_untracked = untracked - allowed_untracked

curation_ok =
  status.success? &&
  curation &&
  curation.dig("counts", "tracked_overlay_notes").to_i == 0 &&
  curation.dig("counts", "untracked_generated_local").to_i == 0 &&
  unexpected_untracked.empty?

puts "- repo curation remains clean apart from current repair verifier: #{curation_ok ? 'ok' : 'missing'}"
errors << "repo curation has unexpected candidates: #{stderr} #{stdout}" unless curation_ok

if (untracked & allowed_untracked).any?
  puts "- current repair verifier pending commit: ok"
end

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
