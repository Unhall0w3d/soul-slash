#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../lib/soul_core/blender_scene_manifest"

root = File.expand_path("..", __dir__)
catalog = JSON.parse(File.binread(File.join(root, "config/blender_scene_templates.json"))).fetch("templates")
adapter = File.binread(File.join(root, "scripts/blender/soul_scene_adapter.py"))
expected = %w[abstract liminal architectural audio_reactive bioluminescent_grove void_sanctuary signal_forge]
checks = []

check = lambda do |label, &block|
  block.call
  checks << label
  puts "PASS: #{label}"
rescue StandardError => error
  warn "FAIL: #{label}: #{error.message}"
  exit 1
end

check.call("catalog exposes the exact A6 scene families") do
  raise "template set changed" unless catalog.keys.sort == expected.sort
end

check.call("every template carries a closed normalized look") do
  catalog.each_value do |template|
    look = SoulCore::BlenderSceneManifest.new(template).to_h.fetch("look")
    raise "look keys changed" unless look.keys.sort == %w[atmosphere camera glow grade surface]
  end
end

check.call("persisted A1 manifests receive safe clean defaults") do
  legacy = Marshal.load(Marshal.dump(catalog.fetch("abstract")))
  legacy.delete("look")
  look = SoulCore::BlenderSceneManifest.new(legacy).to_h.fetch("look")
  raise "legacy defaults changed" unless look == SoulCore::BlenderSceneManifest::LOOK_DEFAULTS
end

check.call("unknown look values fail closed") do
  invalid = Marshal.load(Marshal.dump(catalog.fetch("abstract")))
  invalid.fetch("look")["surface"] = "downloaded_node_graph"
  begin
    SoulCore::BlenderSceneManifest.new(invalid)
  rescue SoulCore::BlenderSceneManifest::ValidationError
    next
  end
  raise "unknown surface was accepted"
end

check.call("unknown look keys fail closed") do
  invalid = Marshal.load(Marshal.dump(catalog.fetch("abstract")))
  invalid.fetch("look")["script"] = "unsafe"
  begin
    SoulCore::BlenderSceneManifest.new(invalid)
  rescue SoulCore::BlenderSceneManifest::ValidationError
    next
  end
  raise "unknown key was accepted"
end

check.call("trusted adapter owns bounded look construction") do
  required = %w[apply_surface_look apply_atmosphere apply_camera_look apply_glow apply_grade ShaderNodeTexNoise ShaderNodeVolumeScatter CompositorNodeGlare]
  missing = required.reject { |token| adapter.include?(token) }
  raise "missing adapter controls: #{missing.join(', ')}" unless missing.empty?
  forbidden = %w[exec( eval( subprocess socket requests urllib addon_enable]
  found = forbidden.select { |token| adapter.include?(token) }
  raise "forbidden adapter tokens: #{found.join(', ')}" unless found.empty?
end

puts "Blender Scene A6 checks passed: #{checks.length}"
