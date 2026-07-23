#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/visual_studio_service"
require_relative "../lib/soul_core/application_contract"

checks = 0
failures = []
check = lambda do |label, condition|
  checks += 1
  failures << label unless condition
end

class VisualFakeRunner
  attr_reader :commands
  def initialize = (@commands = [])
  def run(command, **)
    @commands << command
    output = command[command.index("-o") + 1]
    File.binwrite(output, "\x89PNG\r\n\x1a\n".b + ("visual" * 300))
    SoulCore::BoundedCommandRunner::Result.new(stdout: "ok", stderr: "", exit_status: 0, status: "ok", truncated: false)
  end
end

Dir.mktmpdir("soul-visual-a1-") do |root|
  runtime = File.join(root, "runtime")
  source = File.join(runtime, "stable-diffusion.cpp", "bin")
  models = File.join(runtime, "models")
  FileUtils.mkdir_p(source); FileUtils.mkdir_p(models)
  binary = File.join(source, "sd-cli"); File.write(binary, "#!/bin/sh\n"); File.chmod(0o700, binary)
  files = { "diffusion_model" => "diff.gguf", "text_encoder" => "text.gguf", "vae" => "vae.safetensors" }.map do |role, name|
    path = File.join(models, name); File.binwrite(path, role)
    { "role" => role, "repository" => "test/models", "revision" => "a" * 40, "filename" => name, "bytes" => File.size(path), "sha256" => Digest::SHA256.file(path).hexdigest }
  end
  manifest = File.join(root, "manifest.json")
  File.write(manifest, JSON.generate({ "schema_version" => "soul.visual_studio.models.v1", "runtime" => { "repository" => "https://example.invalid/runtime.git", "revision" => "b" * 40, "build" => "vulkan" }, "profiles" => { "test" => { "label" => "Test visual", "accelerator" => "AMD Vulkan", "steps" => 4, "cfg_scale" => 1.0, "files" => files } }, "motion_candidates" => { "ltx" => { "status" => "qualification_required" } } }))
  runner = VisualFakeRunner.new
  service = SoulCore::VisualStudioService.new(root: root, visual_root: File.join(root, "Soul", "visual", "projects"), runtime_root: runtime, manifest_path: manifest, runner: runner, id_generator: -> { "1" * 16 })

  check.call("exact runtime and models report ready", service.resources.dig("data", "ready") == true)
  guarded = SoulCore::VisualStudioService.new(root: root, visual_root: File.join(root, "Soul", "visual-guarded"), runtime_root: runtime, manifest_path: manifest, runner: runner, core_status: -> { { "data" => { "active_core_id" => "daily", "selected_core_id" => "daily", "active_profile_id" => "amd-gemma" } } })
  check.call("Daily Core blocks competing AMD visual work", guarded.resources.dig("data", "ready") == false && guarded.resources.dig("data", "core", "allowed") == false)
  created = service.create({ title: "First light", intent: "Bounded visual proof", prompt: "A coherent dark observatory", negative_prompt: "text", aspect_ratio: "landscape", seed: 42 })
  project = created.dig("data", "project")
  check.call("private project reaches complete terminal state", created["lifecycle_state"] == "complete" && project["project_id"].match?(SoulCore::VisualStudioService::PROJECT_ID))
  preview = service.generation_preview(project_id: project.fetch("project_id"))
  check.call("generation requires exact human review", preview["lifecycle_state"] == "blocked_for_human_review" && preview.dig("data", "confirmation_phrase") == "GENERATE_VISUAL_DRAFT")
  bad = service.generation_execute(project_id: project.fetch("project_id"), candidate_id: preview.dig("data", "candidate_id"), confirmation: "WRONG", expected_digest: preview.dig("data", "expected_digest"))
  check.call("wrong approval produces no candidate", bad["ok"] == false && project.fetch("candidates").empty?)
  data = preview.fetch("data")
  generated = service.generation_execute(project_id: project.fetch("project_id"), candidate_id: data.fetch("candidate_id"), confirmation: data.fetch("confirmation_phrase"), expected_digest: data.fetch("expected_digest"))
  check.call("one bounded draft terminates for review", generated["lifecycle_state"] == "blocked_for_human_review" && generated.dig("data", "candidate", "human_review_required") == true)
  check.call("renderer is Vulkan foreground CLI with fixed profile", runner.commands.one? && runner.commands.first.include?("--diffusion-model") && runner.commands.first.include?("--offload-to-cpu") && runner.commands.first.include?("--diffusion-fa"))
  inspected = service.inspect(project_id: project.fetch("project_id"))
  check.call("candidate is retained in newest-first project inventory", inspected.dig("data", "project", "candidates").length == 1)
end

contract = SoulCore::ApplicationContract::OPERATIONS
check.call("application contract exposes bounded visual vertical slice", %w[visual.resources.status visual.projects.list visual.projects.create visual.projects.get visual.generation.preview visual.generation.execute].all? { |operation| contract.key?(operation) })
html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
js = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
check.call("Creative Studios groups Music and Visual Studio", %w[creative-navigation creative-tab creative-menu music-tab visual-tab visual-panel].all? { |id| html.include?(id) })
check.call("dashboard performs create preview execute and review", %w[visual.projects.create visual.generation.preview visual.generation.execute visual-candidate-list].all? { |value| js.include?(value) || html.include?(value) })
check.call("A1 motion qualification boundary is explicitly superseded", html.include?("Qualified locally") && File.file?(File.expand_path("../config/visual_motion_models.json", __dir__)))

if failures.empty?
  puts "PASS: #{checks} Visual Studio A1 checks"
else
  warn "FAIL: #{failures.length}/#{checks} checks"
  failures.each { |label| warn "- #{label}" }
  exit 1
end
