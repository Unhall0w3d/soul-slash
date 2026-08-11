#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

root = File.expand_path("..", __dir__)
service = File.binread(File.join(root, "lib", "soul_core", "blender_scene_service.rb"))
html = File.binread(File.join(root, "assets", "dashboard", "index.html"))
guide = File.binread(File.join(root, "docs", "guides", "VISUAL_STUDIO.md"))
brief = File.binread(File.join(root, "docs", "soul", "BLENDER_PROCEDURAL_ORGANICS_A7_BRIEF.md"))
catalog = JSON.parse(File.binread(File.join(root, "config", "blender_scene_templates.json")))

checks = {
  "service closes the catalog over the willow fungal family" => service.include?("willow_fungal_grove"),
  "Visual Studio exposes the reviewed organic family" => html.include?('value="willow_fungal_grove"'),
  "organic family uses exactly the first two trusted archetypes" => catalog.dig("templates", "willow_fungal_grove", "organics").map { |entry| entry.fetch("archetype") }.uniq.sort == %w[mushroom_cluster willow_tree],
  "organic family removes the old trunk crown and mushroom primitive assemblies" => catalog.dig("templates", "willow_fungal_grove", "objects").none? { |entry| entry.fetch("id").match?(/trunk|crown|mushroom/) },
  "operator guide distinguishes trusted generated geometry from arbitrary Blender code" => guide.include?("bounded tapered curves") && guide.include?("revolved cap profiles") && guide.include?("repository-owned"),
  "human brief preserves foreground and approval boundaries" => brief.include?("one foreground Blender job") && brief.include?("blocked_for_human_review") && brief.include?("adds no service")
}

checks.each do |label, passed|
  raise "FAIL: #{label}" unless passed
  puts "PASS: #{label}"
end

puts "Blender Scene A7 Dashboard checks passed: #{checks.length}"
