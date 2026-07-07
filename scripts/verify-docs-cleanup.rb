#!/usr/bin/env ruby
# frozen_string_literal: true

errors = []

errors << "README.md missing docs/SKILLS.md link" unless File.read("README.md").include?("docs/SKILLS.md")
errors << "docs/SKILLS.md missing" unless File.exist?("docs/SKILLS.md")
errors << "docs/overlays/archive missing" unless Dir.exist?("docs/overlays/archive")
errors << ".gitignore missing /README_*.md" unless File.read(".gitignore").include?("/README_*.md")

root_overlay_readmes = Dir.glob("README_*.md")
errors << "Root overlay README files still present: #{root_overlay_readmes.join(', ')}" unless root_overlay_readmes.empty?

skills = File.read("docs/SKILLS.md")
%w[
  downloads.inspect
  downloads.cleanup_plan
  downloads.move_to_trash
  downloads.restore_last_cleanup
  weather.report
  cloud.providers.list
  cloud.providers.test
  skill.brief.draft
  skill.brief.review
].each do |name|
  errors << "docs/SKILLS.md missing #{name}" unless skills.include?(name)
end

puts "Documentation cleanup verification:"
puts "- README links docs/SKILLS.md: #{File.read('README.md').include?('docs/SKILLS.md') ? 'ok' : 'missing'}"
puts "- docs/SKILLS.md exists: #{File.exist?('docs/SKILLS.md') ? 'ok' : 'missing'}"
puts "- docs/overlays/archive exists: #{Dir.exist?('docs/overlays/archive') ? 'ok' : 'missing'}"
puts "- root README_*.md files archived: #{root_overlay_readmes.empty? ? 'ok' : 'missing'}"
puts "- root overlay README ignore rule: #{File.read('.gitignore').include?('/README_*.md') ? 'ok' : 'missing'}"

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
