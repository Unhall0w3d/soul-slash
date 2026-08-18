#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "tempfile"
require_relative "../lib/soul_core/blender_scene_manifest"

ROOT = File.expand_path("..", __dir__)
ADAPTER = File.join(ROOT, "scripts", "blender", "soul_scene_adapter.py")
TEMPLATES = JSON.parse(File.binread(File.join(ROOT, "config", "blender_scene_templates.json"))).fetch("templates")

def copy(value)
  JSON.parse(JSON.generate(value))
end

def expect_rejected_by_both(raw)
  begin
    SoulCore::BlenderSceneManifest.new(copy(raw))
  rescue SoulCore::BlenderSceneManifest::ValidationError
    # Rejection here is required before checking equivalent adapter behavior.
  else
    raise "Ruby manifest validation accepted invalid organics"
  end

  Tempfile.create(["soul-a7-invalid-", ".json"]) do |file|
    file.write(JSON.generate(raw))
    file.flush
    _output, status = Open3.capture2e("python3", ADAPTER, "--manifest", file.path, "--blend-path", "ignored.blend", "--dry-run")
    raise "Python adapter validation accepted invalid organics" if status.success?
  end
end

def validate_with_python(raw)
  Tempfile.create(["soul-a7-valid-", ".json"]) do |file|
    file.write(JSON.generate(raw))
    file.flush
    output, status = Open3.capture2e("python3", ADAPTER, "--manifest", file.path, "--blend-path", "ignored.blend", "--dry-run")
    raise "Python adapter validation failed: #{output}" unless status.success?

    line = output.lines.find { |entry| entry.start_with?("SOUL_SCENE_ADAPTER_DRYRUN=") }
    raise "Python adapter did not return normalized manifest" unless line
    JSON.parse(line.delete_prefix("SOUL_SCENE_ADAPTER_DRYRUN="))
  end
end

def willow(material_id)
  {
    "id" => "willow_a7",
    "archetype" => "willow_tree",
    "location" => [0.0, 0.0, 0.0],
    "rotation_euler" => [0.0, 0.0, 0.0],
    "scale" => [1.0, 1.0, 1.0],
    "seed" => 73,
    "materials" => { "bark" => material_id, "foliage" => material_id },
    "parameters" => {
      "branch_depth" => 3, "primary_branches" => 6, "strands_per_branch" => 5,
      "leaf_density" => 4, "trunk_segments" => 8, "sway" => "restrained"
    }
  }
end

def mushrooms(material_id)
  {
    "id" => "mushrooms_a7",
    "archetype" => "mushroom_cluster",
    "location" => [1.0, 0.0, 0.0],
    "rotation_euler" => [0.0, 0.0, 0.0],
    "scale" => [1.0, 1.0, 1.0],
    "seed" => 91,
    "materials" => { "stem" => material_id, "cap" => material_id, "gill" => material_id },
    "parameters" => {
      "count" => 7, "cap_profile" => "bell", "gill_segments" => 20,
      "spread" => 1.5, "height_variation" => 0.35
    }
  }
end

checks = []
check = lambda do |label, &block|
  block.call
  checks << label
  puts "PASS: #{label}"
rescue StandardError => error
  warn "FAIL: #{label}: #{error.message}"
  exit 1
end

base = copy(TEMPLATES.fetch("abstract"))
material_id = base.fetch("materials").first.fetch("id")

check.call("legacy A1-A6 manifests normalize organics to an empty array") do
  legacy = copy(base)
  legacy.delete("organics")
  ruby_normalized = SoulCore::BlenderSceneManifest.new(legacy).to_h
  raise "Ruby default changed" unless ruby_normalized.fetch("organics") == []
  python_normalized = validate_with_python(legacy)
  raise "Python default changed" unless python_normalized.fetch("organics") == []
end

check.call("both reviewed organic archetypes validate in Ruby and Python") do
  candidate = copy(base)
  candidate["organics"] = [willow(material_id), mushrooms(material_id)]
  ruby_normalized = SoulCore::BlenderSceneManifest.new(candidate).to_h
  python_normalized = validate_with_python(candidate)
  raise "Ruby changed archetypes" unless ruby_normalized.fetch("organics").map { |entry| entry.fetch("archetype") }.sort == %w[mushroom_cluster willow_tree]
  raise "Python changed archetypes" unless python_normalized.fetch("organics").map { |entry| entry.fetch("archetype") }.sort == %w[mushroom_cluster willow_tree]
end

check.call("unknown organic keys fail closed") do
  invalid = copy(base)
  invalid["organics"] = [willow(material_id).merge("script" => "unsafe")]
  expect_rejected_by_both(invalid)
end

check.call("unknown archetypes fail closed") do
  invalid = copy(base)
  invalid["organics"] = [willow(material_id).merge("archetype" => "downloaded_tree")]
  expect_rejected_by_both(invalid)
end

check.call("archetype material roles and parameter maps are exact") do
  invalid_role = copy(base)
  invalid_role["organics"] = [willow(material_id).merge("materials" => { "bark" => material_id, "leaf" => material_id })]
  expect_rejected_by_both(invalid_role)
  invalid_parameter = copy(base)
  invalid_parameter["organics"] = [mushrooms(material_id).tap { |entry| entry.fetch("parameters")["asset_path"] = "unsafe.blend" }]
  expect_rejected_by_both(invalid_parameter)
end

check.call("bounded counts, ranges, and reviewed enums fail closed") do
  invalid_willow = copy(base)
  invalid_willow["organics"] = [willow(material_id).tap { |entry| entry.fetch("parameters")["branch_depth"] = 5 }]
  expect_rejected_by_both(invalid_willow)
  invalid_mushrooms = copy(base)
  invalid_mushrooms["organics"] = [mushrooms(material_id).tap { |entry| entry.fetch("parameters")["count"] = 13 }]
  expect_rejected_by_both(invalid_mushrooms)
  invalid_profile = copy(base)
  invalid_profile["organics"] = [mushrooms(material_id).tap { |entry| entry.fetch("parameters")["cap_profile"] = "sphere" }]
  expect_rejected_by_both(invalid_profile)
end

check.call("trusted deterministic builders own A7 construction") do
  source = File.binread(ADAPTER)
  required = %w[
    validate_organics build_organics build_willow_tree build_mushroom_cluster
    append_tapered_tube add_curve_spline append_revolved_cap cap_profile_points
    add_willow_sway trusted_a7_willow trusted_a7_mushroom random.Random
  ]
  missing = required.reject { |token| source.include?(token) }
  raise "missing trusted builder markers: #{missing.join(', ')}" unless missing.empty?
end

check.call("adapter retains no forbidden runtime capabilities") do
  source = File.binread(ADAPTER)
  forbidden = %w[
    subprocess socket requests urllib
    bpy.ops.wm.append bpy.ops.wm.link
    bpy.ops.script.python_file_run bpy.ops.preferences.addon_enable autoexec
  ]
  found = forbidden.select { |token| source.include?(token) }
  raise "forbidden runtime capability: #{found.join(', ')}" unless found.empty?
  raise "curated library loader count changed" unless source.scan("bpy.data.libraries.load").length == 1
  loader_scope = source[/def build_curated_assets\(.*?\n\n\ndef /m]
  raise "curated library loader escaped reviewed function" unless loader_scope&.include?("bpy.data.libraries.load")
end

puts "Blender Scene A7 checks passed: #{checks.length}"
