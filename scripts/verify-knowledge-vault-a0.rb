#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/application_contract"
require_relative "../lib/soul_core/application_facade"
require_relative "../lib/soul_core/conversation_memory_store"
require_relative "../lib/soul_core/conversation_orchestrator"
require_relative "../lib/soul_core/knowledge_vault_chat_controls"
require_relative "../lib/soul_core/knowledge_vault_service"

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

def execute_initialization(service)
  preview = service.initialize_preview
  service.initialize_execute(
    confirmation: preview.dig("data", "confirmation_phrase"),
    expected_digest: preview.dig("data", "expected_digest")
  )
end

puts "Knowledge Vault A0 + Knowledge Reflection A1 verification:"

Dir.mktmpdir("soul-knowledge-vault-") do |root|
  vault = File.join(root, "external-vault")
  missing = SoulCore::KnowledgeVaultService.new(root: root, process_env: {})
  check.call("missing configuration waits without mutation",
             missing.status["lifecycle_state"] == "awaiting_input" && !File.exist?(vault))

  memory_path = File.join(root, "Soul/private/memory/conversation_memory.jsonl")
  memory = SoulCore::ConversationMemoryStore.new(root: root, path: memory_path, clock: -> { Time.utc(2026, 7, 24, 12) })
  service = SoulCore::KnowledgeVaultService.new(
    root: root,
    process_env: { "SOUL_KNOWLEDGE_VAULT_PATH" => vault },
    memory_store: memory,
    clock: -> { Time.utc(2026, 7, 24, 13) }
  )

  preview = service.initialize_preview
  check.call("initialization preview is content-bounded and review-gated",
             preview["lifecycle_state"] == "blocked_for_human_review" &&
               preview.dig("data", "confirmation_phrase") == SoulCore::KnowledgeVaultService::INITIALIZE_CONFIRMATION &&
               preview.dig("data", "files").length == 4 &&
               !File.exist?(vault))

  wrong = service.initialize_execute(
    confirmation: "INITIALIZE",
    expected_digest: preview.dig("data", "expected_digest")
  )
  check.call("wrong initialization confirmation creates nothing",
             wrong["lifecycle_state"] == "blocked_for_human_review" && !File.exist?(vault))

  stale_preview = service.initialize_preview
  FileUtils.mkdir_p(vault)
  FileUtils.mkdir_p(File.join(vault, "Research"))
  stale = service.initialize_execute(
    confirmation: stale_preview.dig("data", "confirmation_phrase"),
    expected_digest: stale_preview.dig("data", "expected_digest")
  )
  check.call("changed initialization scope invalidates the preview",
             stale["lifecycle_state"] == "blocked_for_human_review" &&
               !File.exist?(File.join(vault, "Index.md")))

  initialized = execute_initialization(service)
  check.call("exact initialization creates the portable Markdown structure",
             initialized["lifecycle_state"] == "complete" &&
               File.file?(File.join(vault, "Index.md")) &&
               File.file?(File.join(vault, "Templates/Knowledge Note.md")) &&
               File.directory?(File.join(vault, "Research")) &&
               initialized.dig("data", "obsidian_required") == false)

  FileUtils.mkdir_p(File.join(vault, ".obsidian"))
  File.write(File.join(vault, "Research", "Local Models.md"), <<~MARKDOWN)
    ---
    title: Local Model Notes
    tags:
      - models
    ---

    # Local Models

    Gemma serves the daily Core. Qwen remains the NVIDIA fallback.
  MARKDOWN
  File.write(File.join(vault, "Projects", "Music.md"), "# Music\n\nACE-Step produces bounded local music candidates.\n")
  File.write(File.join(vault, ".obsidian", "Secret.md"), "# Hidden\n\nGemma should not find this.\n")
  File.write(File.join(vault, "Projects", "ignored.txt"), "Gemma is not Markdown.\n")

  search = service.search(query: "Gemma daily", limit: 5)
  check.call("bounded search ranks visible Markdown and excludes hidden/non-Markdown files",
             search["lifecycle_state"] == "complete" &&
               search.dig("data", "count") == 1 &&
               search.dig("data", "records", 0, "relative_path") == "Research/Local Models.md" &&
               search.dig("data", "content_trusted") == false &&
               search.dig("data", "records").none? { |row| row["relative_path"].include?(".obsidian") })

  reflection_inputs = {
    title: "Core Runtime Decision",
    body: "The reviewed Daily Core uses Gemma on AMD while Qwen remains the NVIDIA fallback.",
    knowledge_kind: "decision",
    evidence_status: "repository_documentation",
    source_reference: "repo:docs/CURRENT_STATE.md",
    tags: %w[models runtime]
  }
  reflection = service.reflection_preview(**reflection_inputs)
  check.call("reviewed durable knowledge produces an exact gated vault preview",
             reflection["lifecycle_state"] == "blocked_for_human_review" &&
               reflection.dig("data", "recommended_destination") == "knowledge_vault" &&
               reflection.dig("data", "relative_path") == "Decisions/Core Runtime Decision.md" &&
               reflection.dig("data", "confirmation_phrase") == SoulCore::KnowledgeVaultService::REFLECTION_CONFIRMATION &&
               reflection.dig("data", "markdown").include?("source_reference: \"repo:docs/CURRENT_STATE.md\"") &&
               !File.exist?(File.join(vault, "Decisions", "Core Runtime Decision.md")))

  preference = service.reflection_preview(
    title: "Operator Color Preference",
    body: "The Operator prefers low-glare interfaces.",
    knowledge_kind: "preference",
    evidence_status: "operator_confirmed",
    source_reference: "conversation:test"
  )
  unverified = service.reflection_preview(
    title: "Possible Runtime Finding",
    body: "A model guessed that a runtime might be faster.",
    knowledge_kind: "research",
    evidence_status: "unverified",
    source_reference: "conversation:test"
  )
  studio = service.reflection_preview(
    title: "Candidate One",
    body: "One music candidate omitted its final line.",
    knowledge_kind: "studio_candidate",
    evidence_status: "verified_evidence",
    source_reference: "music:test"
  )
  check.call("non-vault kinds route to their canonical destinations without mutation",
             preference.dig("data", "recommended_destination") == "shared_memory_candidate" &&
               unverified.dig("data", "recommended_destination") == "conversation_only" &&
               studio.dig("data", "recommended_destination") == "studio_archive" &&
               [preference, unverified, studio].all? { |item| item["lifecycle_state"] == "complete" })

  secret = service.reflection_preview(
    title: "Provider setup",
    body: "api_key=abcdefghijklmnopqrstuvwxyz123456",
    knowledge_kind: "environment",
    evidence_status: "operator_confirmed",
    source_reference: "conversation:test"
  )
  check.call("likely secret material is classified never-store",
             secret["lifecycle_state"] == "complete" &&
               secret.dig("data", "recommended_destination") == "never_store" &&
               secret.dig("data", "secret_material_detected") == true)

  wrong_reflection = service.reflection_execute(
    **reflection_inputs,
    confirmation: "WRITE_NOTE",
    expected_digest: reflection.dig("data", "expected_digest")
  )
  check.call("wrong reflection confirmation writes nothing",
             wrong_reflection["lifecycle_state"] == "blocked_for_human_review" &&
               !File.exist?(File.join(vault, "Decisions", "Core Runtime Decision.md")))

  written_reflection = service.reflection_execute(
    **reflection_inputs,
    confirmation: reflection.dig("data", "confirmation_phrase"),
    expected_digest: reflection.dig("data", "expected_digest")
  )
  reflection_path = File.join(vault, "Decisions", "Core Runtime Decision.md")
  check.call("exact reflection approval writes only the reviewed note",
             written_reflection["lifecycle_state"] == "complete" &&
               File.file?(reflection_path) &&
               File.read(reflection_path).include?("generated_by: soul-knowledge-reflection") &&
               written_reflection.dig("data", "canonical_memory_changed") == false &&
               written_reflection.dig("data", "git_mutation") == false)

  update_inputs = reflection_inputs.merge(
    body: "The reviewed Daily Core uses Gemma on AMD. Qwen remains the NVIDIA fallback for AMD-free work.",
    target_relative_path: "Decisions/Core Runtime Decision.md"
  )
  update_preview = service.reflection_preview(**update_inputs)
  File.open(reflection_path, "a") { |file| file.puts("\nHuman edit after preview.") }
  stale_update = service.reflection_execute(
    **update_inputs,
    confirmation: update_preview.dig("data", "confirmation_phrase"),
    expected_digest: update_preview.dig("data", "expected_digest")
  )
  check.call("target drift invalidates a knowledge-note update",
             stale_update["lifecycle_state"] == "blocked_for_human_review" &&
               File.read(reflection_path).include?("Human edit after preview."))

  update_preview = service.reflection_preview(**update_inputs)
  updated = service.reflection_execute(
    **update_inputs,
    confirmation: update_preview.dig("data", "confirmation_phrase"),
    expected_digest: update_preview.dig("data", "expected_digest")
  )
  check.call("reviewed update replaces the exact selected note",
             updated["lifecycle_state"] == "complete" &&
               updated.dig("data", "write_mode") == "replace_reviewed_note" &&
               File.read(reflection_path).include?("fallback for AMD-free work") &&
               !File.read(reflection_path).include?("Human edit after preview."))

  unsafe_reflection = service.reflection_preview(
    **reflection_inputs,
    target_relative_path: "../outside.md"
  )
  check.call("knowledge reflection update traversal fails closed",
             unsafe_reflection["lifecycle_state"] == "failed")

  candidate = memory.propose(
    layer: "project",
    content: "Soul uses a reviewed external Markdown knowledge vault.",
    source: { "kind" => "test", "reference" => "fixture" },
    confidence: 1.0
  )
  memory.approve(candidate.fetch("id"))
  memory.propose(
    layer: "semantic",
    content: "This candidate must not be exported.",
    source: { "kind" => "test", "reference" => "fixture" },
    confidence: 1.0
  )

  export_preview = service.memory_export_preview
  check.call("memory export previews approved records only",
             export_preview["lifecycle_state"] == "blocked_for_human_review" &&
               export_preview.dig("data", "record_count") == 1 &&
               export_preview.dig("data", "canonical_memory_changed") == false)
  export = service.memory_export_execute(
    confirmation: export_preview.dig("data", "confirmation_phrase"),
    expected_digest: export_preview.dig("data", "expected_digest")
  )
  exported = File.read(File.join(vault, "Generated", "Approved Memory.md"))
  check.call("memory export is marked as a projection and excludes candidates",
             export["lifecycle_state"] == "complete" &&
               exported.include?("generated_by: soul") &&
               exported.include?("reviewed external Markdown knowledge vault") &&
               !exported.include?("candidate must not be exported"))

  import_preview = service.memory_import_preview(relative_path: "Research/Local Models.md", layer: "project")
  File.open(File.join(vault, "Research", "Local Models.md"), "a") { |file| file.puts("\nChanged after preview.") }
  stale = service.memory_import_execute(
    relative_path: "Research/Local Models.md",
    layer: "project",
    confirmation: import_preview.dig("data", "confirmation_phrase"),
    expected_digest: import_preview.dig("data", "expected_digest")
  )
  check.call("changed note invalidates memory import preview",
             stale["lifecycle_state"] == "blocked_for_human_review")

  import_preview = service.memory_import_preview(relative_path: "Research/Local Models.md", layer: "project")
  imported = service.memory_import_execute(
    relative_path: "Research/Local Models.md",
    layer: "project",
    confirmation: import_preview.dig("data", "confirmation_phrase"),
    expected_digest: import_preview.dig("data", "expected_digest")
  )
  imported_record = memory.find(imported.dig("data", "memory_id"))
  check.call("vault import creates a shared-memory candidate with provenance",
             imported["lifecycle_state"] == "complete" &&
               imported_record["status"] == "candidate" &&
               imported_record.dig("source", "kind") == "knowledge_vault" &&
               imported_record.dig("metadata", "requires_separate_approval") == true)

  traversal = service.memory_import_preview(relative_path: "../outside.md", layer: "semantic")
  check.call("unsafe traversal fails closed", traversal["lifecycle_state"] == "failed")

  File.symlink(File.join(vault, "Research", "Local Models.md"), File.join(vault, "Research", "Linked.md"))
  linked = service.memory_import_preview(relative_path: "Research/Linked.md", layer: "semantic")
  check.call("symlinked note import fails closed", linked["lifecycle_state"] == "failed")

  request = {
    "schema_version" => SoulCore::ApplicationContract::SCHEMA_VERSION,
    "request_id" => "knowledge-vault-status-001",
    "operation" => "knowledge_vault.status",
    "parameters" => {},
    "context" => { "interface" => "internal" }
  }
  facade = SoulCore::ApplicationFacade.new(root: root, process_env: { "SOUL_KNOWLEDGE_VAULT_PATH" => vault }, knowledge_vault_service: service)
  envelope = facade.call(request)
  reflection_envelope = facade.call({
    "schema_version" => SoulCore::ApplicationContract::SCHEMA_VERSION,
    "request_id" => "knowledge-vault-reflection-001",
    "operation" => "knowledge_vault.reflection.preview",
    "parameters" => {
      "title" => "Vault Facade Decision",
      "body" => "Typed application requests preserve the same reflection policy boundary.",
      "knowledge_kind" => "decision",
      "evidence_status" => "verified_evidence",
      "source_reference" => "test:facade",
      "tags" => ["contract"]
    },
    "context" => { "interface" => "internal" }
  })
  required_operations = %w[
    knowledge_vault.status
    knowledge_vault.search
    knowledge_vault.initialize.preview
    knowledge_vault.initialize.execute
    knowledge_vault.memory_export.preview
    knowledge_vault.memory_export.execute
    knowledge_vault.memory_import.preview
    knowledge_vault.memory_import.execute
    knowledge_vault.reflection.preview
    knowledge_vault.reflection.execute
  ]
  check.call("typed application facade exposes only explicit vault operations",
             required_operations.all? { |operation| SoulCore::ApplicationContract::OPERATIONS.key?(operation) } &&
               envelope["lifecycle_state"] == "complete" &&
               envelope.dig("data", "watcher") == false &&
               reflection_envelope["lifecycle_state"] == "blocked_for_human_review" &&
               reflection_envelope.dig("data", "recommended_destination") == "knowledge_vault")

  chat = SoulCore::KnowledgeVaultChatControls.new(root: root, service: service)
  chat_search = chat.respond("search knowledge vault for Gemma daily")
  orchestrator = SoulCore::ConversationOrchestrator.new
  routed = orchestrator.plan(message: "knowledge vault status", provider_available: true)
  casual = orchestrator.plan(message: "I am thinking about a knowledge vault", provider_available: true)
  check.call("precise conversational controls expose bounded status and search only",
             chat.match?("knowledge vault status") &&
               chat.match?("search knowledge vault for Gemma daily") &&
               !chat.match?("I am thinking about a knowledge vault") &&
               routed.kind == "deterministic_passthrough" &&
               routed.flags["knowledge_vault_control"] == true &&
               casual.kind != "deterministic_passthrough" &&
               chat_search.include?("Research/Local Models.md") &&
               chat_search.include?("not authority"))
end

Dir.mktmpdir("soul-knowledge-vault-conflict-") do |root|
  vault = File.join(root, "vault")
  FileUtils.mkdir_p(vault)
  File.write(File.join(vault, "Index.md"), "personal content\n")
  service = SoulCore::KnowledgeVaultService.new(root: root, process_env: { "SOUL_KNOWLEDGE_VAULT_PATH" => vault })
  conflict = service.initialize_preview
  check.call("starter-file conflict is not overwritten", conflict["lifecycle_state"] == "failed" && File.read(File.join(vault, "Index.md")) == "personal content\n")
end

source = File.read(File.join(__dir__, "../lib/soul_core/knowledge_vault_service.rb"))
check.call("implementation contains no watcher, network, scheduler, or automatic promotion",
           !source.match?(/\b(Net::HTTP|TCPSocket|inotify|listen|cron|systemctl|Thread\.new|fork)\b/) &&
             source.include?("\"automatic_approval\" => false") &&
             source.include?("\"watcher\" => false"))

if errors.empty?
  puts "PASS: 24 checks"
  exit 0
end

warn "FAIL: #{errors.length} checks failed: #{errors.join(', ')}"
exit 1
