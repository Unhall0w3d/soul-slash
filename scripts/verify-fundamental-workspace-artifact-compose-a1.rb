#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "yaml"
require_relative "../lib/soul_core/application_contract"
require_relative "../lib/soul_core/conversation_artifact_creation_service"
require_relative "../lib/soul_core/conversation_orchestrator"

ROOT = File.expand_path("..", __dir__)
checks = []

def check(checks, label, condition)
  raise label unless condition
  checks << label
end

registry = YAML.safe_load_file(File.join(ROOT, "Soul/skills/registry.yaml"), permitted_classes: [], aliases: false).fetch("skills")
skill = registry.fetch("workspace.artifact.compose")
invocations = YAML.safe_load_file(File.join(ROOT, "config/invocation_catalog.yaml"), permitted_classes: [], aliases: false).fetch("entries")
invocation = invocations.find { |entry| entry["id"] == "artifact-compose" }
capabilities = YAML.safe_load_file(File.join(ROOT, "config/operator_capability_catalog.yaml"), permitted_classes: [], aliases: false).fetch("surfaces")
chat = capabilities.find { |surface| surface["id"] == "chat" }
instructions = File.read(File.join(ROOT, "Soul/skills/workspace/compose-artifact/SKILL.md"))
authority = File.read(File.join(ROOT, "Soul/skills/workspace/compose-artifact/references/authority.md"))
service_source = File.read(File.join(ROOT, "lib/soul_core/conversation_artifact_creation_service.rb"))

check(checks, "public skill maps to the sole existing conversational artifact handler",
  skill["internal_handler"] == "conversation_artifact_creation" &&
  skill["instruction_path"] == "Soul/skills/workspace/compose-artifact/SKILL.md" &&
  skill["risk"] == "write_local_state" && skill["requires_approval"] == true && skill["writes_files"] == true)
check(checks, "historical internal token identity remains unchanged for pending-operation compatibility",
  SoulCore::ConversationArtifactCreationService::SKILL_ID == "artifact.create_revision" &&
  authority.include?("pending Phase 11C operations") && !instructions.include?("SKILL_ID ="))
check(checks, "package requires the established service and exact single-use confirmation",
  instructions.include?("ConversationArtifactCreationService") &&
  instructions.include?("create artifact <token> confirm") &&
  instructions.include?("never create a second") && authority.include?("Do not introduce a second"))
check(checks, "writer retains exclusive no-follow verified creation and bounded local providers",
  service_source.include?("File::EXCL | File::NOFOLLOW") &&
  service_source.include?("verify_created_file") &&
  service_source.include?("LOCAL_PROVIDER_CLASSES") &&
  service_source.include?("MAX_FILE_BYTES = 262_144") && service_source.include?("MAX_LINES = 4_000"))
check(checks, "public catalog describes one bounded approval-gated workspace result",
  invocation && invocation["skill_ids"] == ["workspace.artifact.compose"] &&
  invocation["approval"].include?("exact create artifact token confirm") &&
  invocation["boundary"].include?("No cloud drafting") &&
  chat["skills"].include?("workspace.artifact.compose") && chat["invocations"].include?("artifact-compose"))
check(checks, "artifact composition intentionally remains on chats.send rather than adding a second application operation",
  SoulCore::ApplicationContract::OPERATIONS.key?("chats.send") &&
  !SoulCore::ApplicationContract::OPERATIONS.key?("workspace.artifact.compose"))

orchestrator = SoulCore::ConversationOrchestrator.new
creation = orchestrator.plan(message: "Create a project report at artifacts/status.md covering the reviewed findings.", provider_available: true)
revision = orchestrator.plan(message: "Can you revise artifact art_example into artifacts/status-v2.md with project privacy?", provider_available: true)
discussion = orchestrator.plan(message: "I created an artifact yesterday.", provider_available: true)
token = "a" * 32
execution = orchestrator.plan(message: "create artifact #{token} confirm", provider_available: true)
cancellation = orchestrator.plan(message: "cancel artifact operation #{token}", provider_available: true)
check(checks, "explicit creation and revision route to the existing preview",
  creation.kind == "artifact_creation_preview" && revision.kind == "artifact_creation_preview")
check(checks, "ordinary artifact discussion remains ordinary conversation",
  discussion.kind == "direct_model" && discussion.flags["artifact_creation_preview"] != true)
check(checks, "exact execution and cancellation route to the existing deterministic control",
  execution.kind == "artifact_creation_control" && cancellation.kind == "artifact_creation_control")

stdout, stderr, status = Open3.capture3("ruby", "bin/soul", "assess", "phase11c-bounded-artifact-creation", "--json", chdir: ROOT)
report = JSON.parse(stdout) rescue nil
check(checks, "original Phase 11C end-to-end assessor remains candidate-ready",
  status.success? && report && report["ok"] == true && report["status"] == "candidate_ready" &&
  report.fetch("verification", {}).values.all?(true) && report["human_review_required"] == true)
warn(stderr) unless status.success?

puts "Fundamental workspace.artifact.compose A1 verification:"
checks.each { |label| puts "PASS: #{label}" }
puts "#{checks.length} checks passed."
