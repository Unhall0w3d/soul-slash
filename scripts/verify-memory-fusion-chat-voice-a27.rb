#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../lib/soul_core/memory_fusion_retrieval_service"
require_relative "../lib/soul_core/semantic_conversation_memory_context"

Fixture = Struct.new(:envelope, :calls) do
  def query(query:, limit:)
    calls << [query, limit]
    JSON.parse(JSON.generate(envelope))
  end
end
Policy = Struct.new(:value) { def active = value }

def local_envelope(results, mode: "hybrid")
  {"lifecycle_state" => "complete", "data" => {"results" => results, "retrieval_mode" => mode, "ranking_profile" => "hybrid-a4-v1", "index_available" => mode == "hybrid", "authority" => "approved_memory_context", "mutation" => "none"}}
end

def projection_envelope(results, available: true)
  {"lifecycle_state" => "complete", "schema" => "soul.memory_projection_query.a23.v1", "mutation" => "none", "data" => {"results" => results, "projection_available" => available, "retrieval_mode" => available ? "remote_projection_local_join" : "hybrid", "projection_generation" => "generation_0123456789abcdef0123", "authority" => "approved_memory_context", "content_source" => "canonical_local_ledger", "mutation" => "none"}}
end

def result(id, score)
  {"memory_id" => id, "score" => score, "layer" => "project", "excerpt" => "canonical", "source" => {"kind" => "fixture"}, "approved_at" => "2026-08-25T00:00:00Z"}
end

errors = []
checks = 0
check = lambda { |label, value| checks += 1; errors << label unless value }

local = Fixture.new(local_envelope([result("mem_expected", 0.9), result("mem_distractor", 0.8), result("mem_remote", 0.7)]), [])
projection = Fixture.new(projection_envelope([result("mem_distractor", 0.8), result("mem_expected", 0.75), result("mem_remote", 0.66), result("mem_weak", 0.64)]), [])
policy = Policy.new({"profile" => "projection_gate_local_order_a29", "projection_threshold" => 0.55})
service = SoulCore::MemoryFusionRetrievalService.new(local_retrieval: local, projection_retrieval: projection, policy_store: policy, clock: -> { Time.utc(2026, 8, 25) })
fused = service.query(query: "operator preference", limit: 3)
check.call("qualified policy emits fusion schema", fused["lifecycle_state"] == "complete" && fused["schema"] == "soul.memory_fusion_query.a27.v1")
check.call("projection gate filters weak results", fused.dig("data", "results").map { |item| item["memory_id"] } == %w[mem_expected mem_distractor mem_remote])
check.call("local ordering wins within projection gate", fused.dig("data", "results", 0, "memory_id") == "mem_expected")
check.call("fusion identity is explicit", fused.dig("data", "retrieval_mode") == "projection_gate_local_order" && fused.dig("data", "ranking_profile") == "projection_gate_local_order_a29")
check.call("fusion remains canonical and non-mutating", fused.dig("data", "content_source") == "canonical_local_ledger" && fused["mutation"] == "none")
check.call("collaborators are bounded", local.calls == [["operator preference", 20]] && projection.calls == [["operator preference", 20]])

local_policy = SoulCore::MemoryFusionRetrievalService.new(local_retrieval: local, projection_retrieval: projection, policy_store: Policy.new({"profile" => "local_hybrid_a4", "projection_threshold" => nil}))
check.call("local policy bypasses projection", local_policy.query(query: "x", limit: 2).dig("data", "ranking_profile") == "hybrid-a4-v1")

fallback = SoulCore::MemoryFusionRetrievalService.new(local_retrieval: local, projection_retrieval: Fixture.new(projection_envelope([], available: false), []), policy_store: policy)
check.call("projection fallback preserves local envelope", fallback.query(query: "x", limit: 2).dig("data", "retrieval_mode") == "hybrid")

lexical = Fixture.new(local_envelope([result("mem_expected", 0.8)], mode: "lexical_fallback"), [])
check.call("local embedding loss preserves lexical fallback", SoulCore::MemoryFusionRetrievalService.new(local_retrieval: lexical, projection_retrieval: projection, policy_store: policy).query(query: "x", limit: 2).dig("data", "retrieval_mode") == "lexical_fallback")

MemoryStoreFixture = Struct.new(:records_value) do
  def context_for(query:, chat_id:, limit:) = {"records" => [], "record_ids" => [], "layers" => [], "count" => 0, "rendered" => ""}
  def records(status:) = records_value
  def render_context(records) = records.map { |record| record.fetch("content") }.join("\n")
end
approved = [
  {"id" => "mem_expected", "status" => "approved", "layer" => "project", "content" => "canonical expected", "source" => {"kind" => "fixture"}},
  {"id" => "mem_distractor", "status" => "approved", "layer" => "project", "content" => "canonical distractor", "source" => {"kind" => "fixture"}},
  {"id" => "mem_remote", "status" => "approved", "layer" => "project", "content" => "canonical remote", "source" => {"kind" => "fixture"}}
]
context = SoulCore::SemanticConversationMemoryContext.new(memory_store: MemoryStoreFixture.new(approved), retrieval_service: Fixture.new(fused, [])).context_for(query: "operator preference", chat_id: "chat", limit: 3)
check.call("ordinary context accepts qualified fusion", context["retrieval_mode"] == "projection_gate_local_order" && context["record_ids"] == %w[mem_expected mem_distractor mem_remote])
check.call("ordinary context rereads canonical content", context["rendered"].include?("canonical expected") && !context["rendered"].include?("canonical\n"))
check.call("ordinary context exposes policy diagnostics", context["ranking_profile"] == "projection_gate_local_order_a29" && context["projection_available"] == true)

facade = File.read(File.join(__dir__, "../lib/soul_core/application_facade.rb"))
voice = File.read(File.join(__dir__, "soul-voice-presence-bridge"))
check.call("facade builds the policy router", facade.include?("MemoryFusionRetrievalService.new") && facade.include?("MemoryRetrievalPolicyStore.new"))
check.call("Voice uses the same ApplicationFacade conversation path", voice.include?("ApplicationFacade.new") && voice.include?("chats.send"))

source = File.read(File.join(__dir__, "../lib/soul_core/memory_fusion_retrieval_service.rb"))
check.call("fusion has no persistence or background behavior", !source.match?(/File\.(?:write|rename|delete)|Thread\.new|systemd|setInterval|setTimeout/))

abort "Memory fusion Chat/Voice A27 failed: #{errors.join(', ')}" unless errors.empty?
puts "Memory fusion Chat/Voice A27 passed (#{checks} checks)."
