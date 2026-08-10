#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "yaml"

ROOT = File.expand_path("..", __dir__)
read = ->(path) { File.read(File.join(ROOT, path), encoding: "UTF-8") }
templates = JSON.parse(read.call("config/blender_scene_templates.json"))
catalog = YAML.safe_load(read.call("config/operator_capability_catalog.yaml"))
registry = YAML.safe_load(read.call("Soul/skills/registry.yaml"))
companion = read.call("lib/soul_core/music_visual_companion_service.rb")
guide = read.call("docs/guides/VISUAL_STUDIO.md")
review = read.call("docs/assessments/BLENDER_VISUAL_PIPELINE_A1_A5_REVIEW.md")
html = read.call("assets/dashboard/index.html")
dashboard = read.call("assets/dashboard/dashboard.js")

checks = []
check = lambda do |label, condition|
  raise "FAIL: #{label}" unless condition
  checks << label
  puts "PASS: #{label}"
end

expected = %w[abstract liminal architectural audio_reactive bioluminescent_grove void_sanctuary signal_forge]
check.call("reviewed template catalog remains closed and complete", templates.fetch("templates").keys.sort == expected.sort)
check.call("every A5 template contains geometry lights and animation", templates.fetch("templates").values.all? { |item| item.fetch("objects").length >= 2 && item.fetch("lights").any? && item.fetch("animation").is_a?(Hash) })
check.call("Visual Studio capability catalog names Blender inputs and operations", catalog.fetch("surfaces").find { |item| item["id"] == "visual_studio" }.then { |item| item["inputs"].include?("exact kept song") && item.fetch("operations").include?("visual.blender.execute") })
check.call("creative skills preserve Dashboard Blender construction boundary", registry.dig("skills", "creative.visual_production", "description").include?("without implying") && registry.dig("skills", "creative.companion_production", "description").include?("Dashboard-gated"))
check.call("A4 full-duration path treats Blender as reviewed motion", companion.include?('%w[generated_motion blender_scene]') && companion.include?('loop_name = record["source_kind"] == "generated_motion" ? "loop.webm" : "loop.mp4"'))
check.call("Music Studio advances reviewed Blender loops instead of retiring them", dashboard.include?('const blenderScene = visual.source_kind === "blender_scene"') && dashboard.include?("const reviewedMotion = generatedMotion || blenderScene") && dashboard.include?("Preview full-duration Blender render"))
check.call("A4 publication validation is covered by exact existing verifier", read.call("scripts/verify-music-publication-package.rb").include?("Blender companion produces the same exact private YouTube package boundary"))
check.call("Dashboard truthfully states retained direction does not rewrite geometry", html.include?("it does not silently rewrite template geometry"))
check.call("Visual guide documents source editable whole bar workflow", guide.include?("Build an editable Blender scene") && guide.include?("8- or 12-musical-bar") && guide.include?("arbitrary add-ons"))
check.call("review packet contains required human review sections", ["## Candidate status", "## Live production evidence", "## Known limits", "## Risk classification", "## Human review checklist"].all? { |heading| review.include?(heading) })
check.call("A4 and A5 add no recurring or listener primitive", [companion, read.call("lib/soul_core/blender_scene_service.rb")].none? { |source| source.match?(/setInterval|setTimeout|Thread\.new|daemon\b|cron\b|WebSocket|EventSource/) })

puts "Blender Scene A4/A5 verifier complete: #{checks.length} checks passed"
