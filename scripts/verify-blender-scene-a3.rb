#!/usr/bin/env ruby
# frozen_string_literal: true

root = File.expand_path("..", __dir__)
files = {
  contract: File.binread(File.join(root, "lib/soul_core/application_contract.rb")),
  facade: File.binread(File.join(root, "lib/soul_core/application_facade.rb")),
  http: File.binread(File.join(root, "lib/soul_core/dashboard_http_application.rb")),
  studio: File.binread(File.join(root, "lib/soul_core/visual_studio_service.rb")),
  html: File.binread(File.join(root, "assets/dashboard/index.html")),
  javascript: File.binread(File.join(root, "assets/dashboard/dashboard.js")),
  css: File.binread(File.join(root, "assets/dashboard/dashboard.css"))
}

failures = []
check = lambda do |label, condition|
  puts "#{condition ? 'PASS' : 'FAIL'}: #{label}"
  failures << label unless condition
end

operations = %w[
  visual.blender.resources visual.blender.templates visual.blender.list
  visual.blender.preview visual.blender.execute visual.blender.resume.preview
  visual.blender.resume.execute visual.blender.review visual.blender.delete.preview
  visual.blender.delete.execute visual.blender.promotion.preview visual.blender.promotion.execute
]
check.call("closed application contract and facade expose every Blender scene operation", operations.all? { |operation| files[:contract].include?(operation) && files[:facade].include?(operation) })
check.call("stream transport admits only bounded Blender execute operations", files[:http].include?("visual.blender.execute") && files[:http].include?("visual.blender.resume.execute"))
check.call("authenticated private media route exposes preview still blend and evidence", files[:http].include?("/api/v1/visual/blender/") && files[:http].include?("def visual_blender") && files[:facade].include?("def visual_blender_artifact_path"))
check.call("Visual Studio projection keeps Blender candidates additive", files[:studio].include?('"blender_scenes"') && files[:studio].include?("blender_scene_service"))

ids = %w[
  visual-blender-card visual-blender-resource-state visual-blender-template
  visual-blender-music-project visual-blender-music-candidate visual-blender-bars
  visual-blender-quality visual-blender-seed visual-blender-direction
  preview-visual-blender visual-blender-confirm visual-blender-scope
  execute-visual-blender visual-blender-progress visual-blender-status
]
check.call("Visual Studio contains the complete procedural scene control surface", ids.all? { |id| files[:html].include?(%(id="#{id}")) })
check.call("whole-bar choices are explicit and closed", files[:html].include?('value="8">8 musical bars') && files[:html].include?('value="12">12 musical bars') && !files[:html].include?('id="visual-blender-bars" type="number"'))
check.call("dashboard filters to retained keep music candidates", files[:javascript].include?('candidate.review?.disposition === "keep"'))
check.call("preview execute review revision binding deletion and resume are wired", %w[previewVisualBlender executeVisualBlender renderVisualBlenderCandidate executeVisualBlenderResume].all? { |name| files[:javascript].include?(name) })
check.call("editable blend download remains private and candidate-scoped", files[:javascript].include?("Download editable .blend") && files[:javascript].include?("/api/v1/visual/blender/${project.project_id}/${scene.scene_id}/blend"))
check.call("procedural lane receives dedicated responsive styling", %w[.visual-blender-card .visual-blender-form-grid .visual-blender-candidate .visual-blender-lineage].all? { |selector| files[:css].include?(selector) })

abort "Blender Scene A3 verifier failed: #{failures.join(', ')}" unless failures.empty?
puts "Blender Scene A3 verifier complete: 10 checks passed"
