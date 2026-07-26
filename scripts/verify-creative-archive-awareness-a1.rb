#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "fileutils"
require "tmpdir"
require_relative "../lib/soul_core/conversation_creative_archive_service"
require_relative "../lib/soul_core/conversation_orchestrator"

def check(label, condition)
  raise "FAIL: #{label}" unless condition

  puts "PASS: #{label}"
end

def png
  "\x89PNG\r\n\x1A\n".b + [13].pack("N") + "IHDR" + [32, 24].pack("NN") + ("\0".b * 16)
end

class FixtureVisualStudio
  attr_reader :calls

  def initialize(image_path)
    @image_path = image_path
    @calls = []
    @project = {
      "schema_version" => "soul.visual.project.v1",
      "project_id" => "visual_project_aaaaaaaaaaaaaaaa",
      "title" => "The Rooms Remember Me — Habitat",
      "intent" => "An oppressive yellow maze with a distant void organism.",
      "prompt" => "Wide yellow liminal maze; distant black presence; architecture dominates.",
      "negative_prompt" => "bright daylight, close-up portrait",
      "aspect_ratio" => "landscape",
      "seed" => 42,
      "created_at" => "2026-07-24T19:38:16Z",
      "updated_at" => "2026-07-24T19:38:16Z"
    }
  end

  def list(limit:)
    @calls << ["list", limit]
    { "ok" => true, "data" => { "projects" => [@project] } }
  end

  def inspect(project_id:)
    @calls << ["inspect", project_id]
    candidate = {
      "candidate_id" => "visual_candidate_bbbbbbbbbbbbbbbb",
      "generation_kind" => "text_to_image",
      "created_at" => "2026-07-24T20:00:00Z",
      "width" => 32,
      "height" => 24,
      "review" => { "disposition" => "keep", "rating" => 5 }
    }
    { "ok" => true, "data" => { "project" => @project.merge("candidates" => [candidate], "motions" => []) } }
  end

  def artifact_path(project_id:, candidate_id:)
    @calls << ["artifact_path", project_id, candidate_id]
    @image_path
  end
end

class FixtureMusicStore
  def initialize
    @project = {
      "schema_version" => "soul.music.project.v1",
      "project_id" => "music_cccccccccccccccc",
      "title" => "Compiler Bloom",
      "intent" => "Music to code a local intelligence to.",
      "target_duration_seconds" => 180,
      "vocal_mode" => "instrumental",
      "rights_status" => "original",
      "caption" => "Technical liquid drum and bass with restrained melodic movement.",
      "lyrics" => "",
      "bpm" => 110,
      "keyscale" => "D minor",
      "timesignature" => "4",
      "language" => "en",
      "seed" => 7,
      "created_at" => "2026-07-21T22:46:27Z",
      "updated_at" => "2026-07-21T22:46:27Z"
    }
  end

  def list(limit:) = [@project].first(limit)
  def read(project_id) = project_id == @project["project_id"] ? @project : raise("unexpected fixture project")
end

class FixtureVision
  attr_reader :calls

  def initialize
    @calls = []
  end

  def status = { "ready" => true }

  def analyze(**arguments)
    @calls << arguments
    {
      "content" => "The yellow maze matches, but the distant black presence is absent.",
      "provider_id" => "fixture.local.vision",
      "model" => "Fixture Gemma",
      "profile_id" => "amd-gemma",
      "latency_ms" => 21,
      "usage" => {}
    }
  end
end

Dir.mktmpdir("soul-creative-archive-a1-") do |root|
  image_path = File.join(root, "candidate.png")
  File.binwrite(image_path, png)
  visual = FixtureVisualStudio.new(image_path)
  vision = FixtureVision.new
  service = SoulCore::ConversationCreativeArchiveService.new(
    root: root,
    visual_studio: visual,
    music_store: FixtureMusicStore.new,
    vision_client: vision
  )

  brief = service.inspect(message: "Please refer to the Visual Brief The Rooms Remember Me — Habitat")
  check("exact Visual Studio title resolves locally", brief["ok"] && brief.dig("collected", "creative_archive", "project", "project_id") == "visual_project_aaaaaaaaaaaaaaaa")
  check("brief-only lookup does not inspect pixels", vision.calls.empty? && brief["not_collected"].any? { |item| item.include?("pixels") })

  comparison = service.inspect(message: "Compare the visual project The Rooms Remember Me — Habitat with its existing candidate and brief")
  evidence = comparison.dig("collected", "creative_archive", "visual_evidence")
  check("existing visual candidate is inspected without upload", comparison["ok"] && evidence["candidate_id"] == "visual_candidate_bbbbbbbbbbbbbbbb" && vision.calls.length == 1)
  check("vision receives exact brief and Operator request", vision.calls.first[:question].include?("The Rooms Remember Me") && vision.calls.first[:question].include?("Operator request"))
  check("candidate evidence remains non-authorizing", evidence["authority"] == "untrusted_evidence_only" && comparison.dig("verification", "no_project_or_candidate_modified"))

  music = service.inspect(message: "Inspect the Music Studio project Compiler Bloom")
  check("Music Studio brief resolves by exact title", music["ok"] && music.dig("collected", "creative_archive", "project", "title") == "Compiler Bloom")

  catalog = service.inspect(message: "Show my visual projects")
  check("bounded creative project catalog is available", catalog["ok"] && catalog.dig("collected", "creative_archive", "count") == 1)

  orchestrator = SoulCore::ConversationOrchestrator.new
  routed = orchestrator.plan(message: "Please refer to the Visual Brief The Rooms Remember Me — Habitat", provider_available: true)
  check("natural brief reference routes through archive evidence", routed.kind == "skill_then_model" && routed.tool_ids == ["creative.archive.inspect"])
  comparison_route = orchestrator.plan(message: "Compare the visual project The Rooms Remember Me — Habitat against its candidate", provider_available: true)
  check("candidate comparison routes through archive evidence", comparison_route.tool_ids == ["creative.archive.inspect"])
  ordinary = orchestrator.plan(message: "I am working on visual projects today.", provider_available: true)
  check("ordinary creative conversation does not invoke archive inspection", ordinary.kind == "direct_model" && ordinary.tool_ids.empty?)

  source = File.read(File.join(__dir__, "../lib/soul_core/conversation_creative_archive_service.rb"))
  check("archive service contains no creative mutation calls", !source.match?(/\.(?:create|update|generation_execute|edit_execute|delete_execute|promotion_execute)\s*\(/))
end

puts "Creative Archive awareness A1 verification complete."
