#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/conversation_observation_store"
require_relative "../lib/soul_core/memory_observation_derivation_service"

checks = 0
check = lambda do |label, condition|
  raise "FAIL: #{label}" unless condition
  checks += 1
end

Synthesizer = Struct.new(:outputs, :inputs, keyword_init: true) do
  def call(input)
    inputs << input
    value = outputs.shift
    raise IOError, "fixture unavailable" if value == :fail
    value
  end
end

def message(id, role, content, chat: "chat:a12")
  { "id" => id, "chat_id" => chat, "role" => role, "content" => content,
    "created_at" => "2026-08-24T14:00:00Z" }
end

Dir.mktmpdir("soul-memory-derivation-a12") do |root|
  observations = SoulCore::ConversationObservationStore.new(root: root, clock: -> { Time.utc(2026, 8, 24, 14, 0, 0) })
  observations.capture_exchange(
    user_message: message("msg:u1", "user", "I prefer concise weather reports."),
    assistant_message: message("msg:a1", "assistant", "I will keep weather reports concise."),
    request_id: "req:capture:1", interface: "dashboard"
  )
  source_before = Dir.glob(File.join(observations.path, "segment_*.jsonl")).to_h { |path| [path, File.binread(path)] }
  output = JSON.generate("proposals" => [
    { "layer" => "preference", "content" => "The operator prefers concise weather reports.",
      "confidence" => 0.96, "evidence_observation_ids" => ["obs_#{Digest::SHA256.hexdigest('msg:u1')[0, 24]}"] },
    { "layer" => "semantic", "content" => "Never reveal the API key or password.",
      "confidence" => 0.99, "evidence_observation_ids" => ["obs_#{Digest::SHA256.hexdigest('msg:u1')[0, 24]}"] }
  ])
  synth = Synthesizer.new(outputs: [output, JSON.generate("proposals" => [])], inputs: [])
  path = File.join(root, "private", "derivations.jsonl")
  service = SoulCore::MemoryObservationDerivationService.new(
    root: root, observation_store: observations, synthesizer: synth,
    model_identity: { "provider" => "local", "model" => "fixture-model", "core" => "dev-core" },
    path: path, clock: -> { Time.utc(2026, 8, 24, 14, 5, 0) }
  )
  result = service.derive(request_id: "req:derive:1")
  check.call("bounded local derivation completes", result["ok"] && result["proposal_count"] == 2)
  check.call("receipt remains content-free", result["content_included"] == false && !JSON.generate(result).include?("weather reports"))
  check.call("deterministic protection overrides model omission", result["protected_review_count"] == 1)
  check.call("source observations remain byte-identical", source_before.all? { |file, bytes| File.binread(file) == bytes })
  check.call("local synthesizer receives bounded exact evidence", synth.inputs.first.fetch("observations").length == 2 && synth.inputs.first.dig("observations", 0, "content") == "I prefer concise weather reports.")
  packet = JSON.parse(File.readlines(path).first)
  check.call("private packet retains proposals and exact provenance", packet.fetch("proposals").length == 2 && packet["observation_count"] == 2 && packet["model_identity"]["provider"] == "local")
  check.call("protected proposal is not retrieval active", packet.dig("proposals", 1, "protection_class") == "protected_review_required" && packet.dig("proposals", 0, "protection_class") == "ordinary_candidate")
  check.call("packet chain integrity verifies", service.integrity["ok"] && service.integrity["packet_count"] == 1)

  replay = service.derive(request_id: "req:derive:1")
  check.call("request replay is idempotent without another model call", replay["idempotent"] && synth.inputs.length == 1)
  no_work = service.derive(request_id: "req:derive:2")
  check.call("completed cursor reports no work", no_work["ok"] && no_work["no_work"] && synth.inputs.length == 1)

  observations.capture_exchange(
    user_message: message("msg:u2", "user", "Thanks.", chat: "chat:a12:2"),
    assistant_message: message("msg:a2", "assistant", "You're welcome.", chat: "chat:a12:2"),
    request_id: "req:capture:2", interface: "voice_presence"
  )
  empty = service.derive(request_id: "req:derive:3")
  check.call("valid empty result advances observation cursor", empty["ok"] && empty["proposal_count"] == 0 && JSON.parse(File.readlines(path).last)["last_observation_id"] == "obs_#{Digest::SHA256.hexdigest('msg:a2')[0, 24]}")
  check.call("empty completed batch is not synthesized again", service.derive(request_id: "req:derive:4")["no_work"] && synth.inputs.length == 2)
end

Dir.mktmpdir("soul-memory-derivation-a12-failure") do |root|
  observations = SoulCore::ConversationObservationStore.new(root: root)
  observations.capture_exchange(
    user_message: message("msg:fu", "user", "Remember this ordinary preference."),
    assistant_message: message("msg:fa", "assistant", "Understood."),
    request_id: "req:failure:capture", interface: "dashboard"
  )
  path = File.join(root, "derivations.jsonl")
  synth = Synthesizer.new(outputs: ["not-json", :fail], inputs: [])
  service = SoulCore::MemoryObservationDerivationService.new(
    root: root, observation_store: observations, synthesizer: synth,
    model_identity: { "provider" => "local", "model" => "fixture", "core" => "soul-core" }, path: path
  )
  malformed = service.derive(request_id: "req:malformed")
  check.call("malformed output fails without advancing", !malformed["ok"] && (!File.exist?(path) || File.zero?(path)))
  unavailable = service.derive(request_id: "req:unavailable")
  check.call("unavailable synthesis fails without advancing", !unavailable["ok"] && (!File.exist?(path) || File.zero?(path)))

  outside = "obs_#{Digest::SHA256.hexdigest('not-selected')[0, 24]}"
  invalid = Synthesizer.new(outputs: [JSON.generate("proposals" => [
    { "layer" => "semantic", "content" => "Unsupported evidence", "confidence" => 0.5,
      "evidence_observation_ids" => [outside] }
  ])], inputs: [])
  invalid_service = SoulCore::MemoryObservationDerivationService.new(
    root: root, observation_store: observations, synthesizer: invalid,
    model_identity: { "provider" => "local", "model" => "fixture", "core" => "soul-core" }, path: path
  )
  check.call("out-of-batch evidence fails closed", !invalid_service.derive(request_id: "req:outside")["ok"] && (!File.exist?(path) || File.zero?(path)))
end

Dir.mktmpdir("soul-memory-derivation-a12-safety") do |root|
  synth = Synthesizer.new(outputs: [], inputs: [])
  begin
    SoulCore::MemoryObservationDerivationService.new(
      root: root, synthesizer: synth,
      model_identity: { "provider" => "cloud", "model" => "remote", "core" => "cloud-core" }
    )
    raise "FAIL: cloud synthesizer accepted"
  rescue ArgumentError
    checks += 1
  end
  outside = File.join(root, "outside.jsonl")
  File.write(outside, "")
  symlink = File.join(root, "derivations.jsonl")
  File.symlink(outside, symlink)
  begin
    SoulCore::MemoryObservationDerivationService.new(
      root: root, synthesizer: synth,
      model_identity: { "provider" => "local", "model" => "fixture", "core" => "dev-core" }, path: symlink
    )
    raise "FAIL: symlinked proposal ledger accepted"
  rescue ArgumentError
    checks += 1
  end
end

Dir.mktmpdir("soul-memory-derivation-a12-tamper") do |root|
  observations = SoulCore::ConversationObservationStore.new(root: root)
  observations.capture_exchange(
    user_message: message("msg:tu", "user", "A stable project fact."),
    assistant_message: message("msg:ta", "assistant", "Recorded."),
    request_id: "req:tamper:capture", interface: "dashboard"
  )
  path = File.join(root, "derivations.jsonl")
  synth = Synthesizer.new(outputs: [JSON.generate("proposals" => [])], inputs: [])
  service = SoulCore::MemoryObservationDerivationService.new(
    root: root, observation_store: observations, synthesizer: synth,
    model_identity: { "provider" => "local", "model" => "fixture", "core" => "dev-core" }, path: path
  )
  service.derive(request_id: "req:tamper")
  original = File.binread(path)
  File.binwrite(path, original.sub("req:tamper", "req:changed"))
  check.call("packet tampering fails integrity", !service.integrity["ok"])
  malformed_shape = JSON.parse(original)
  malformed_shape.delete("observation_ids")
  malformed_shape["packet_sha256"] = service.send(:packet_digest, malformed_shape)
  File.write(path, JSON.generate(malformed_shape) + "\n")
  check.call("recomputed digest cannot authorize an invalid packet shape", !service.integrity["ok"])
  File.binwrite(path, original.sub(/\n\z/, ""))
  check.call("partial packet write fails integrity", !service.integrity["ok"])
end

puts "MEMORY_OBSERVATION_DERIVATION_A12=PASS (#{checks} checks)"
