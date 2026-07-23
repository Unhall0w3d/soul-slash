#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require "time"
require_relative "../lib/soul_core/visual_studio_service"
require_relative "../lib/soul_core/application_contract"

checks = 0
failures = []
check = lambda do |label, condition|
  checks += 1
  failures << label unless condition
end

class VisualA2Runner
  attr_reader :commands
  def initialize = (@commands = [])
  def run(command, **)
    @commands << command
    output = command[command.index("-o") + 1]
    File.binwrite(output, "\x89PNG\r\n\x1a\n".b + ("visual-a2" * 300))
    SoulCore::BoundedCommandRunner::Result.new(stdout: "ok", stderr: "", exit_status: 0, status: "ok", truncated: false)
  end
end

class VisualA2Companion
  attr_reader :calls
  def initialize = (@calls = [])
  def generated_import_preview(**arguments)
    @calls << ["preview", arguments]
    { "ok" => true, "lifecycle_state" => "blocked_for_human_review", "message" => "approval required", "mutation" => "none", "data" => { "confirmation_phrase" => "BIND_VISUAL_COMPANION", "expected_digest" => "f" * 64 } }
  end
  def generated_import_execute(**arguments)
    @calls << ["execute", arguments]
    { "ok" => true, "lifecycle_state" => "blocked_for_human_review", "message" => "bound", "mutation" => "music_visual_bound", "data" => { "visual" => { "stage" => "base_bound" } } }
  end
end

class CountingVisualA2Service < SoulCore::VisualStudioService
  attr_reader :sha256_calls

  def initialize(**arguments)
    @sha256_calls = 0
    super
  end

  private

  def file_sha256(path)
    @sha256_calls += 1
    super
  end
end

Dir.mktmpdir("soul-visual-a2-") do |root|
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
  File.write(manifest, JSON.generate({ "schema_version" => "soul.visual_studio.models.v1", "runtime" => {}, "profiles" => { "test" => { "label" => "Test visual", "accelerator" => "AMD Vulkan", "steps" => 4, "cfg_scale" => 1.0, "files" => files } }, "motion_candidates" => {} }))
  ids = (1..20).map { |number| number.to_s(16).rjust(16, "0") }
  clock_ticks = (0..20).map { |number| Time.utc(2026, 7, 18, 12, 0, number) }
  runner = VisualA2Runner.new
  companion = VisualA2Companion.new
  service = SoulCore::VisualStudioService.new(root: root, visual_root: File.join(root, "Soul", "visual", "projects"), runtime_root: runtime, manifest_path: manifest, runner: runner, id_generator: -> { ids.shift }, clock: -> { clock_ticks.shift || Time.utc(2026, 7, 18, 13) }, music_visual_companion: companion)

  fields = { title: "First light", intent: "One coherent visual identity", prompt: "A dark observatory over still water", negative_prompt: "text", aspect_ratio: "landscape", seed: 42 }
  project = service.create(fields).dig("data", "project")
  project_id = project.fetch("project_id")
  preview = service.generation_preview(project_id: project_id).fetch("data")
  service.generation_execute(project_id: project_id, candidate_id: preview.fetch("candidate_id"), confirmation: preview.fetch("confirmation_phrase"), expected_digest: preview.fetch("expected_digest"))
  source_candidate_id = preview.fetch("candidate_id")

  revised = fields.merge(title: "First light revised", prompt: "A dark observatory over still water with low mist", seed: 84)
  update = service.update(project_id: project_id, attributes: revised)
  revisions = Dir.glob(File.join(root, "Soul", "visual", "projects", project_id, "revisions", "*.json"))
  candidate_input = JSON.parse(File.read(File.join(root, "Soul", "visual", "projects", project_id, "generations", source_candidate_id, "input.json")))
  check.call("brief revision archives prior exact record", update["lifecycle_state"] == "complete" && revisions.one?)
  check.call("existing candidate retains immutable original input", candidate_input["prompt"] == fields.fetch(:prompt) && update.dig("data", "project", "prompt") == revised.fetch(:prompt))

  first_review = service.record_review(project_id: project_id, candidate_id: source_candidate_id, review: { rating: 4, disposition: "revise", notes: "Preserve geometry; refine mist." })
  second_review = service.record_review(project_id: project_id, candidate_id: source_candidate_id, review: { rating: 5, disposition: "keep", notes: "Ready to bind." })
  history = Dir.glob(File.join(root, "Soul", "visual", "projects", project_id, "generations", source_candidate_id, "review-history", "*.json"))
  inspected = service.inspect(project_id: project_id)
  check.call("review replacement preserves immutable history", first_review["ok"] && second_review["ok"] && history.one?)
  check.call("current review is projected with candidate", inspected.dig("data", "project", "candidates", 0, "review", "rating") == 5)

  edit_preview = service.edit_preview(project_id: project_id, source_candidate_id: source_candidate_id, instruction: "Preserve the scene; refine low mist and horizon.", seed: "120").fetch("data")
  wrong_edit = service.edit_execute(project_id: project_id, source_candidate_id: source_candidate_id, candidate_id: edit_preview.fetch("candidate_id"), instruction: "Preserve the scene; refine low mist and horizon.", seed: "120", confirmation: "WRONG", expected_digest: edit_preview.fetch("expected_digest"))
  check.call("wrong edit gate creates no output", wrong_edit["ok"] == false && runner.commands.length == 1)
  edit = service.edit_execute(project_id: project_id, source_candidate_id: source_candidate_id, candidate_id: edit_preview.fetch("candidate_id"), instruction: "Preserve the scene; refine low mist and horizon.", seed: "120", confirmation: edit_preview.fetch("confirmation_phrase"), expected_digest: edit_preview.fetch("expected_digest"))
  check.call("image-guided edit records exact source lineage", edit.dig("data", "candidate", "generation_kind") == "image_edit" && edit.dig("data", "candidate", "source_candidate_id") == source_candidate_id)
  check.call("image-guided renderer receives private source image", runner.commands.last.include?("-r") && runner.commands.last[runner.commands.last.index("-r") + 1].end_with?("/image.png"))

  promotion = service.promotion_preview(project_id: project_id, candidate_id: source_candidate_id, music_project_id: "music_#{'a' * 16}", music_candidate_id: "candidate_#{'b' * 16}")
  service.promotion_execute(project_id: project_id, candidate_id: source_candidate_id, music_project_id: "music_#{'a' * 16}", music_candidate_id: "candidate_#{'b' * 16}", confirmation: "BIND_VISUAL_COMPANION", expected_digest: "f" * 64)
  check.call("promotion remains an explicit exact human gate", promotion["lifecycle_state"] == "blocked_for_human_review" && companion.calls.map(&:first) == %w[preview execute])
  check.call("promotion binds selected visual and music identities", companion.calls.last.last.values_at(:source_candidate_id, :project_id, :candidate_id) == [source_candidate_id, "music_#{'a' * 16}", "candidate_#{'b' * 16}"])

  delete_preview = service.candidate_delete_preview(project_id: project_id, candidate_id: edit_preview.fetch("candidate_id")).fetch("data")
  wrong_delete = service.candidate_delete_execute(project_id: project_id, candidate_id: edit_preview.fetch("candidate_id"), confirmation: "WRONG", expected_digest: delete_preview.fetch("expected_digest"))
  check.call("wrong candidate deletion preserves exact target", wrong_delete["ok"] == false && service.artifact_path(project_id: project_id, candidate_id: edit_preview.fetch("candidate_id")))
  exact_delete = service.candidate_delete_execute(project_id: project_id, candidate_id: edit_preview.fetch("candidate_id"), confirmation: delete_preview.fetch("confirmation_phrase"), expected_digest: delete_preview.fetch("expected_digest"))
  check.call("exact candidate deletion reaches complete terminal state", exact_delete["lifecycle_state"] == "complete" && service.inspect(project_id: project_id).dig("data", "project", "candidates").length == 1)

  project_preview = service.project_delete_preview(project_id: project_id).fetch("data")
  wrong_project_delete = service.project_delete_execute(project_id: project_id, confirmation: "WRONG", expected_digest: project_preview.fetch("expected_digest"))
  check.call("wrong project deletion preserves archive", wrong_project_delete["ok"] == false && service.inspect(project_id: project_id)["ok"])
  exact_project_delete = service.project_delete_execute(project_id: project_id, confirmation: project_preview.fetch("confirmation_phrase"), expected_digest: project_preview.fetch("expected_digest"))
  check.call("exact project deletion removes only inventoried archive", exact_project_delete["lifecycle_state"] == "complete" && service.inspect(project_id: project_id)["ok"] == false)
end

Dir.mktmpdir("soul-visual-resource-cache-") do |root|
  runtime = File.join(root, "runtime")
  binary_directory = File.join(runtime, "stable-diffusion.cpp", "bin")
  models = File.join(runtime, "models")
  FileUtils.mkdir_p(binary_directory)
  FileUtils.mkdir_p(models)
  binary = File.join(binary_directory, "sd-cli")
  File.write(binary, "#!/bin/sh\n")
  File.chmod(0o700, binary)
  model_files = { "diffusion_model" => "diff.gguf", "text_encoder" => "text.gguf", "vae" => "vae.safetensors" }.map do |role, name|
    path = File.join(models, name)
    File.binwrite(path, "#{role}-fixture")
    { "role" => role, "repository" => "test/models", "revision" => "b" * 40, "filename" => name, "bytes" => File.size(path), "sha256" => Digest::SHA256.file(path).hexdigest }
  end
  manifest = File.join(root, "manifest.json")
  File.write(manifest, JSON.generate({ "schema_version" => "soul.visual_studio.models.v1", "runtime" => {}, "profiles" => { "test" => { "label" => "Test visual", "accelerator" => "AMD Vulkan", "steps" => 4, "cfg_scale" => 1.0, "files" => model_files } }, "motion_candidates" => {} }))
  service = CountingVisualA2Service.new(root: root, visual_root: File.join(root, "Soul", "visual", "projects"), runtime_root: runtime, manifest_path: manifest)

  first = service.resources
  first_call_count = service.sha256_calls
  second = service.resources
  check.call("first resource inspection verifies every pinned model", first.dig("data", "models_ready") && first_call_count == model_files.length)
  check.call("unchanged resource inspection reuses in-process verification", second.dig("data", "models_ready") && service.sha256_calls == first_call_count)

  changed = model_files.first
  changed_path = File.join(models, changed.fetch("filename"))
  original = File.binread(changed_path)
  replacement = original.sub(original[0], original[0] == "x" ? "y" : "x")
  File.binwrite(changed_path, replacement)
  invalidated = service.resources
  check.call("changed model identity invalidates cached verification", service.sha256_calls == first_call_count + 1 && invalidated.dig("data", "models_ready") == false && invalidated.dig("data", "missing_roles") == [changed.fetch("role")])
end

operations = SoulCore::ApplicationContract::OPERATIONS
required = %w[visual.projects.update visual.projects.delete.preview visual.projects.delete.execute visual.candidates.review visual.candidates.delete.preview visual.candidates.delete.execute visual.edit.preview visual.edit.execute visual.promotion.preview visual.promotion.execute]
check.call("application contract exposes complete A2 operation set", required.all? { |operation| operations.key?(operation) })
html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
js = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
check.call("dashboard exposes revision review edit deletion and promotion", %w[update-visual-project visual.candidates.review visual.edit.preview visual.candidates.delete.preview visual.promotion.preview preview-visual-project-delete].all? { |value| html.include?(value) || js.include?(value) })
check.call("slow visual actions expose immediate bounded progress", ["Verifying the pinned visual runtime and model files", "Saving the revised brief", "Revalidating the exact visual project"].all? { |message| js.include?(message) } && %w[refresh-visual-resources update-visual-project preview-visual-generation].all? { |id| js.include?(%Q{byId("#{id}")}) })
check.call("Music binding selector reads the canonical generation projection", js.include?('dataOf(envelope).generations || []'))
check.call("A2 motion boundary is explicitly superseded by the reviewed A4 lane", html.include?("Qualified locally") && operations.key?("visual.motion.execute"))

if failures.empty?
  puts "PASS: #{checks} Visual Studio A2 checks"
else
  warn "FAIL: #{failures.length}/#{checks} checks"
  failures.each { |label| warn "- #{label}" }
  exit 1
end
