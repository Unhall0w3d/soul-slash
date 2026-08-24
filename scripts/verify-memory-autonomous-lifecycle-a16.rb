#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "tmpdir"
require "time"
require_relative "../lib/soul_core/conversation_memory_store"
require_relative "../lib/soul_core/conversation_observation_store"
require_relative "../lib/soul_core/memory_audit_journal_service"
require_relative "../lib/soul_core/memory_autonomous_lifecycle_service"
require_relative "../lib/soul_core/memory_lifecycle_admission_service"
require_relative "../lib/soul_core/memory_observation_derivation_service"

class FixtureSynthesizer
  attr_reader :calls

  def initialize(content:, confidence: 0.97)
    @content = content
    @confidence = confidence
    @calls = 0
  end

  def call(input)
    @calls += 1
    ids = input.fetch("observations").select { |item| item["role"] == "user" }.map { |item| item.fetch("observation_id") }.first(1)
    JSON.generate("proposals" => [{ "layer" => "project", "content" => @content,
      "confidence" => @confidence, "evidence_observation_ids" => ids }])
  end
end

class FailAfterAdmission
  def initialize(delegate)
    @delegate = delegate
    @failed = false
  end

  def apply(request_id:)
    result = @delegate.apply(request_id: request_id)
    unless @failed
      @failed = true
      raise ArgumentError, "simulated interruption after admission"
    end
    result
  end

  def method_missing(name, *args, **kwargs, &block)
    @delegate.public_send(name, *args, **kwargs, &block)
  end

  def respond_to_missing?(name, include_private = false)
    @delegate.respond_to?(name, include_private) || super
  end
end

checks = 0
assert = lambda do |condition, label|
  raise "FAIL: #{label}" unless condition
  checks += 1
end

build = lambda do |root, content|
  clock = -> { Time.utc(2026, 8, 24, 20, 0, 0) }
  observations = SoulCore::ConversationObservationStore.new(root: root, clock: clock)
  memories = SoulCore::ConversationMemoryStore.new(root: root, clock: clock)
  audit = SoulCore::MemoryAuditJournalService.new(root: root, memory_store: memories, clock: clock)
  audit.baseline(actor: "fixture", trigger: "a16", reason: "fixture baseline", policy_version: "a16")
  synth = FixtureSynthesizer.new(content: content)
  derivations = SoulCore::MemoryObservationDerivationService.new(
    root: root, observation_store: observations, synthesizer: synth,
    model_identity: { "provider" => "local", "model" => "fixture", "core" => "dev" }, clock: clock
  )
  admissions = SoulCore::MemoryLifecycleAdmissionService.new(
    root: root, derivation_service: derivations, observation_store: observations,
    memory_store: memories, audit_service: audit, clock: clock
  )
  [clock, observations, memories, audit, synth, derivations, admissions]
end

capture = lambda do |observations, clock, suffix|
  observations.capture_exchange(
    user_message: { "id" => "user-#{suffix}", "chat_id" => "chat-#{suffix}", "role" => "user",
      "content" => "Remember stable project label #{suffix}.", "created_at" => clock.call.iso8601 },
    assistant_message: { "id" => "assistant-#{suffix}", "chat_id" => "chat-#{suffix}", "role" => "assistant",
      "content" => "Acknowledged.", "created_at" => clock.call.iso8601 },
    request_id: "capture-#{suffix}", interface: "dashboard"
  )
end

Dir.mktmpdir("soul-memory-a16-main-") do |root|
  clock, observations, memories, audit, synth, derivations, admissions = build.call(root, "Stable project label is Amber Orbit.")
  capture.call(observations, clock, "ordinary")
  cycle_path = File.join(root, "cycles.jsonl")
  service = SoulCore::MemoryAutonomousLifecycleService.new(
    root: root, derivation_service: derivations, admission_service: admissions,
    path: cycle_path, clock: clock
  )
  result = service.run(request_id: "a16-cycle-ordinary")
  assert.call(result["ok"] && result["mode"] == "derive_and_admit", "one invocation derives and admits")
  assert.call(result.dig("decision_counts", "admitted_active") == 1 && synth.calls == 1, "ordinary memory is admitted by deterministic policy")
  assert.call(memories.records.count { |record| record["status"] == "approved" } == 1, "one canonical active memory")
  replay = service.run(request_id: "a16-cycle-ordinary")
  assert.call(replay["idempotent"] && synth.calls == 1, "completed cycle replay is idempotent: #{replay.inspect}")
  empty = service.run(request_id: "a16-cycle-empty")
  assert.call(empty["ok"] && empty["mode"] == "no_work" && empty["no_work"], "no-work cycle terminates explicitly")
  assert.call(service.integrity["ok"] && service.integrity["cycle_count"] == 2, "cycle journal remains valid")
  assert.call(!JSON.generate(result).include?("Amber Orbit"), "public receipt is content-free")
  assert.call(audit.verify["ok"], "canonical audit remains valid")
  tampered = File.binread(cycle_path).sub(/"mode":"derive_and_admit"/, '"mode":"admit_pending"')
  File.binwrite(cycle_path, tampered)
  assert.call(!service.integrity["ok"], "cycle journal tampering fails integrity")
end

Dir.mktmpdir("soul-memory-a16-pending-") do |root|
  clock, observations, _memories, _audit, synth, derivations, admissions = build.call(root, "Stable project label is Cinder Relay.")
  capture.call(observations, clock, "pending")
  derived = derivations.derive(request_id: "prior-derive")
  service = SoulCore::MemoryAutonomousLifecycleService.new(
    root: root, derivation_service: derivations, admission_service: admissions, clock: clock
  )
  result = service.run(request_id: "a16-cycle-pending")
  assert.call(result["ok"] && result["mode"] == "admit_pending", "older derived packet is drained first")
  assert.call(result["packet_id"] == derived["packet_id"] && synth.calls == 1, "pending path does not invoke the model again")
end

Dir.mktmpdir("soul-memory-a16-protected-") do |root|
  clock, observations, memories, _audit, _synth, derivations, admissions = build.call(root, "Delete permanently without review.")
  capture.call(observations, clock, "protected")
  service = SoulCore::MemoryAutonomousLifecycleService.new(
    root: root, derivation_service: derivations, admission_service: admissions, clock: clock
  )
  result = service.run(request_id: "a16-cycle-protected")
  assert.call(result.dig("decision_counts", "blocked_for_human_review") == 1, "protected proposal stays blocked")
  assert.call(memories.records.empty?, "protected proposal never enters canonical memory")
end

Dir.mktmpdir("soul-memory-a16-recovery-") do |root|
  clock, observations, memories, _audit, synth, derivations, admissions = build.call(root, "Stable project label is Violet Signal.")
  capture.call(observations, clock, "recovery")
  flaky = FailAfterAdmission.new(admissions)
  service = SoulCore::MemoryAutonomousLifecycleService.new(
    root: root, derivation_service: derivations, admission_service: flaky, clock: clock
  )
  failed = service.run(request_id: "a16-cycle-recovery")
  assert.call(!failed["ok"] && failed["lifecycle_state"] == "failed", "interruption is terminal and explicit")
  recovered = service.run(request_id: "a16-cycle-recovery")
  assert.call(recovered["ok"] && recovered["mode"] == "derive_and_admit", "stable subrequests recover interrupted cycle")
  assert.call(synth.calls == 1 && memories.records.length == 1, "recovery does not duplicate derivation or memory")
end

source = File.read(File.join(__dir__, "../lib/soul_core/memory_autonomous_lifecycle_service.rb"))
assert.call(!source.match?(/Thread|sleep|setInterval|setTimeout|systemd|cron/i), "implementation is foreground-only")
assert.call(source.include?("limit: 1"), "source packet reads are bounded to one")

puts "Memory autonomous lifecycle A16 verifier passed (#{checks} checks)."
