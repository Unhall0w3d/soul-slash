#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/perception_readiness_assessor"

def check(label, condition)
  raise "FAIL: #{label}" unless condition

  puts "PASS: #{label}"
end

Dir.mktmpdir("soul-perception-a0-") do |root|
  home = File.join(root, "home")
  bin = File.join(root, "bin")
  manifest = File.join(home, ".ollama", "models", "manifests", "registry.ollama.ai", "library", "soul-local-chat", "latest")
  state = File.join(root, "Soul", "runtime", "model_runtime", "core_selection.json")
  FileUtils.mkdir_p(File.dirname(manifest))
  FileUtils.mkdir_p(File.dirname(state))
  FileUtils.mkdir_p(bin)

  %w[grim slurp hyprctl tesseract].each do |name|
    path = File.join(bin, name)
    File.write(path, "#!/bin/sh\nexit 99\n")
    File.chmod(0o755, path)
  end
  File.write(
    manifest,
    JSON.generate(
      "schemaVersion" => 2,
      "layers" => [
        { "mediaType" => "application/vnd.ollama.image.model", "size" => 7_381_382_048 },
        { "mediaType" => "application/vnd.ollama.image.projector", "size" => 175_115_584 }
      ]
    )
  )
  File.write(state, JSON.generate("active_core_id" => "music"))

  report = SoulCore::PerceptionReadinessAssessor.new(root: root, home: home, path: bin).assess
  check("assessment is explicitly read only", report["read_only"] && report["captured_images"].zero?)
  check("installed projector makes picture Beta ready", report.dig("picture_understanding", "status") == "ready_for_beta")
  check("non-Daily Core requires an explicit transition", report.dig("picture_understanding", "access") == "requires_daily_core_transition")
  check("Wayland capture and OCR requirements are detected", report.dig("screen_understanding", "status") == "ready_for_beta" && report["missing"].empty?)
  check("image contents never grant mutation authority", report.dig("boundaries", "image_content_authority") == "untrusted_evidence" && report.dig("boundaries", "mutation_authority") == false)
  check("assessment executes none of the discovered tools", Dir.children(bin).length == 4)

  File.write(manifest, JSON.generate("schemaVersion" => 2, "layers" => []))
  missing = SoulCore::PerceptionReadinessAssessor.new(root: root, home: home, path: bin).assess
  check("missing projector blocks the vision recommendation", missing.dig("picture_understanding", "status") == "missing_vision_model" && missing["missing"].include?("vision_model_projector"))
end

puts "Perception A0 verification complete."
