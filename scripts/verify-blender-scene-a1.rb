#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"

ROOT = File.expand_path("..", __dir__)
$LOAD_PATH.unshift(File.join(ROOT, "lib"))
require "soul_core/blender_scene_manifest"

checks = 0
failures = []

def run_check(checks, failures, label)
  checks += 1
  begin
    yield
  rescue StandardError => error
    failures << "#{label}: #{error.message}"
    return checks
  end
  puts "PASS: #{label}"
  checks
end

def expect_validation_error(label, checks, failures)
  checks += 1
  begin
    yield
    failures << "#{label}: expected validation error"
  rescue SoulCore::BlenderSceneManifest::ValidationError
    puts "PASS: #{label}"
  rescue StandardError => error
    failures << "#{label}: wrong failure type #{error.class} #{error.message}"
  end
  checks
end

def normalize_manifest(raw)
  json = JSON.generate(raw)
  copy = JSON.parse(json)
  SoulCore::BlenderSceneManifest.new(copy)
end

def read_json(path)
  JSON.parse(File.read(path))
end

def source_text(path)
  File.read(path)
end

checks = run_check(checks, failures, "load valid template manifest and compute deterministic digest") do
  manifest = read_json(File.join(ROOT, "config", "blender_scene_templates.json"))
  templates = manifest.fetch("templates")
  template_keys = %w[abstract liminal architectural audio_reactive bioluminescent_grove void_sanctuary signal_forge willow_fungal_grove]
  template_keys.each do |template_name|
    parsed = normalize_manifest(templates.fetch(template_name))
    raise "template #{template_name} schema version mismatch" unless parsed.normalized_manifest.fetch("schema_version") == SoulCore::BlenderSceneManifest::SCHEMA_VERSION
    raise "template #{template_name} missing identity" if parsed.normalized_manifest.fetch("identity").empty?
    parsed.sha256
  end
end

checks = expect_validation_error("reject top-level unknown key", checks, failures) do
  raw = read_json(File.join(ROOT, "config", "blender_scene_templates.json")).fetch("templates").fetch("abstract")
  bad = JSON.parse(JSON.generate(raw))
  bad["unexpected_root"] = "disallowed"
  SoulCore::BlenderSceneManifest.new(bad)
end

checks = expect_validation_error("reject object-level forbidden key", checks, failures) do
  raw = read_json(File.join(ROOT, "config", "blender_scene_templates.json")).fetch("templates").fetch("abstract")
  bad = JSON.parse(JSON.generate(raw))
  bad["objects"].first["import_path"] = "data.blend"
  SoulCore::BlenderSceneManifest.new(bad)
end

checks = expect_validation_error("reject unsafe output filename with directory separator", checks, failures) do
  raw = read_json(File.join(ROOT, "config", "blender_scene_templates.json")).fetch("templates").fetch("abstract")
  bad = JSON.parse(JSON.generate(raw))
  bad["output"]["still_name"] = "../escape.png"
  SoulCore::BlenderSceneManifest.new(bad)
end

checks = expect_validation_error("reject audio binding target mismatch", checks, failures) do
  raw = read_json(File.join(ROOT, "config", "blender_scene_templates.json")).fetch("templates").fetch("abstract")
  bad = JSON.parse(JSON.generate(raw))
  bad["audio_binding"]["tracks"] = [
    {
      "target_type" => "camera",
      "target_id" => "does_not_exist",
      "property" => "lens",
      "curve" => "kick",
      "gain" => 0.3,
      "offset" => 0
    }
  ]
  SoulCore::BlenderSceneManifest.new(bad)
end

checks = expect_validation_error("reject empty materials list", checks, failures) do
  raw = read_json(File.join(ROOT, "config", "blender_scene_templates.json")).fetch("templates").fetch("abstract")
  bad = JSON.parse(JSON.generate(raw))
  bad["materials"] = []
  SoulCore::BlenderSceneManifest.new(bad)
end

checks = run_check(checks, failures, "validate canonical digest is stable under key-order changes") do
  raw = read_json(File.join(ROOT, "config", "blender_scene_templates.json")).fetch("templates").fetch("abstract")
  mutated = JSON.parse(JSON.generate(raw))
  mutated["lights"] = mutated["lights"].reverse
  mutated["materials"] = mutated["materials"].reverse
  mutated["objects"] = mutated["objects"].reverse
  mutated["animation"]["objects"] = mutated["animation"]["objects"].reverse if mutated["animation"]["objects"].is_a?(Array)
  canonical_one = SoulCore::BlenderSceneManifest.new(raw).sha256
  canonical_two = SoulCore::BlenderSceneManifest.new(mutated).sha256
  raise "canonical digest changed after list reorder" unless canonical_one == canonical_two
end

adapter_path = File.join(ROOT, "scripts", "blender", "soul_scene_adapter.py")
checks = run_check(checks, failures, "adapter python syntax is valid") do
  status = system("python3", "-m", "py_compile", adapter_path, exception: true)
  raise "py_compile failed" unless status
end

checks = run_check(checks, failures, "adapter has no forbidden runtime capabilities") do
  source = source_text(adapter_path)
  forbidden_tokens = %w[
    subprocess
    socket
    requests
    urllib
    bpy.data.libraries.load
    bpy.ops.wm.append
    bpy.ops.wm.link
    autoexec
  ]
  forbidden_tokens.each do |token|
    if token.is_a?(String) && source.include?(token)
      raise "found forbidden token: #{token}"
    end
  end
  missing_required = [
    "def run(manifest",
    "def validate_manifest(manifest)",
    "def clear_scene()",
    "SOUL_SCENE_ADAPTER_DRYRUN",
    "bpy.ops.wm.save_as_mainfile",
    "bpy.ops.render.render(write_still=True)"
  ]
  missing_required.each do |token|
    raise "adapter missing expected marker: #{token}" unless source.include?(token)
  end
end

checks = run_check(checks, failures, "template catalog is closed and exact") do
  catalog = read_json(File.join(ROOT, "config", "blender_scene_templates.json"))
  raise "catalog root schema wrong" unless catalog.fetch("schema_version") == "soul.blender.scene.templates.v1"
  templates = catalog.fetch("templates")
  raise "catalog templates must be object" unless templates.is_a?(Hash)
  unless (templates.keys - %w[abstract liminal architectural audio_reactive bioluminescent_grove void_sanctuary signal_forge willow_fungal_grove]).empty?
    raise "catalog contains unknown templates: #{(templates.keys - %w[abstract liminal architectural audio_reactive bioluminescent_grove void_sanctuary signal_forge willow_fungal_grove]).join(', ')}"
  end
end

if failures.empty?
  puts "PASS: structural and restriction checks complete"
else
  $stderr.puts("FAIL: #{failures.length} check(s) failed")
  failures.each { |failure| $stderr.puts("- #{failure}") }
  abort("Blender A1 verifier failed: #{failures.join(', ')}")
end

puts "Blender Scene A1 verifier complete: #{checks} checks passed"
