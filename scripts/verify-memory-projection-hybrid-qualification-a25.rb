#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "digest"
require_relative "../lib/soul_core/memory_projection_hybrid_fusion_qualification_service"

AGGREGATE_KEYS = %w[mean_recall mean_precision mean_reciprocal_rank mean_positive_recall
                    mean_positive_precision mean_positive_reciprocal_rank hit_count
                    correct_decision_count negative_abstention_count forbidden_hit_count
                    returned_result_count case_count scored_positive_count].freeze

def metric(expected, forbidden, returned)
  position = returned.index { |id| expected.include?(id) }
  {
    "positive_case" => expected.any?, "returned_memory_ids" => returned,
    "hit" => !position.nil?,
    "recall" => expected.empty? ? 1.0 : ((returned & expected).length.to_f / expected.length).round(6),
    "precision" => returned.empty? ? (expected.empty? ? 1.0 : 0.0) : ((returned & expected).length.to_f / returned.length).round(6),
    "reciprocal_rank" => position ? (1.0 / (position + 1)).round(6) : 0.0,
    "forbidden_hit" => !(returned & forbidden).empty?, "abstained" => returned.empty?,
    "decision_correct" => expected.empty? ? returned.empty? : !position.nil?,
    "abstention_correct" => expected.empty? ? returned.empty? : nil
  }
end

def aggregate(case_count: 2, positives: 1)
  AGGREGATE_KEYS.to_h do |key|
    [key, key.start_with?("mean_") ? 0.5 : (key == "case_count" ? case_count : (key == "scored_positive_count" ? positives : 0))]
  end
end

def a24_case(id, expected, forbidden, local_ids, projection_ids)
  thresholds = %w[0.50 0.55 0.60 0.65 0.70 0.75 0.80]
  scores = thresholds.to_h { |threshold| [threshold, metric(expected, forbidden, projection_ids)] }
  {
    "case_id" => id, "query_sha256" => Digest::SHA256.hexdigest(id),
    "expected_memory_ids" => expected, "forbidden_memory_ids" => forbidden,
    "local" => metric(expected, forbidden, local_ids), "projection" => scores
  }
end

cases = [
  a24_case("positive", ["mem_expected"], ["mem_forbidden"], ["mem_expected", "mem_other"], ["mem_other", "mem_expected"]),
  a24_case("negative", [], ["mem_forbidden"], [], ["mem_forbidden"])
]
envelope = {
  "lifecycle_state" => "complete", "schema" => "soul.memory_projection_qualification.a24.v1", "mutation" => "none",
  "data" => {
    "case_file_digest" => "a" * 64, "case_count" => 2, "positive_case_count" => 1, "negative_case_count" => 1,
    "thresholds" => [0.50, 0.55, 0.60, 0.65, 0.70, 0.75, 0.80], "local" => aggregate,
    "projection_thresholds" => %w[0.50 0.55 0.60 0.65 0.70 0.75 0.80].to_h { |threshold| [threshold, aggregate] },
    "cases" => cases, "decision" => "human_review_required", "production_profile_changed" => false,
    "chat_voice_routing_changed" => false, "content_included" => false, "authority" => "evaluation_only",
    "mutation" => "none", "qualified_at" => "2026-08-25T00:00:00.000000Z"
  }
}

errors = []
checks = 0
check = lambda { |label, value| checks += 1; errors << label unless value }
service = SoulCore::MemoryProjectionHybridFusionQualificationService.new(envelope: envelope, clock: -> { Time.utc(2026, 8, 25) })
result = service.qualify
encoded = JSON.generate(result)
check.call("A25 completes", result["lifecycle_state"] == "complete")
check.call("A24 source is preserved", result.dig("data", "source_case_file_digest") == "a" * 64 && result.dig("data", "source_case_count") == 2)
check.call("exact fixed threshold is exposed", result.dig("data", "projection_threshold") == 0.65)
check.call("all three closed profiles are present", result.dig("data", "profile_order") == %w[projection_baseline_a25 projection_gate_local_order_a25 projection_gate_weighted_rrf_a25])
check.call("projection baseline preserves projection order", result.dig("data", "profiles", "projection_baseline_a25", "cases", 0, "returned_memory_ids") == %w[mem_other mem_expected])
check.call("local ordering is projection gated", result.dig("data", "profiles", "projection_gate_local_order_a25", "cases", 0, "returned_memory_ids") == %w[mem_expected mem_other])
check.call("weighted RRF is local dominant", result.dig("data", "profiles", "projection_gate_weighted_rrf_a25", "cases", 0, "returned_memory_ids") == %w[mem_expected mem_other] && result.dig("data", "constants", "local_weight") > result.dig("data", "constants", "projection_weight"))
check.call("negative case remains visible and forbidden", result.dig("data", "profiles", "projection_baseline_a25", "cases", 1, "forbidden_hit") == true)
check.call("fusion scores are deterministic", result.dig("data", "profiles", "projection_gate_weighted_rrf_a25", "cases", 0, "fusion_scores", "mem_expected") == 0.016314119513)
check.call("content is withheld", !encoded.include?("known operator preference") && !encoded.include?("unknown purple recipe"))
check.call("no profile is selected", result.dig("data", "winner_selected") == false && result.dig("data", "decision") == "human_review_required")
check.call("Chat and Voice remain unchanged", result.dig("data", "chat_voice_routing_changed") == false)
check.call("no mutation is advertised", result["mutation"] == "none" && result.dig("data", "mutation") == "none")

malformed = JSON.parse(JSON.generate(envelope))
malformed["schema"] = "wrong"
check.call("wrong A24 schema fails closed", SoulCore::MemoryProjectionHybridFusionQualificationService.new(envelope: malformed).qualify["lifecycle_state"] == "failed")
malformed = JSON.parse(JSON.generate(envelope))
malformed["data"]["cases"][0]["expected_memory_ids"] = ["bad id"]
check.call("malformed IDs fail closed", SoulCore::MemoryProjectionHybridFusionQualificationService.new(envelope: malformed).qualify["lifecycle_state"] == "failed")
malformed = JSON.parse(JSON.generate(envelope))
malformed["data"]["mutation"] = "write"
check.call("mutation-bearing input fails closed", SoulCore::MemoryProjectionHybridFusionQualificationService.new(envelope: malformed).qualify["lifecycle_state"] == "failed")
malformed = JSON.parse(JSON.generate(envelope))
malformed["data"]["cases"] = [malformed["data"]["cases"].first]
check.call("too few cases fail closed", SoulCore::MemoryProjectionHybridFusionQualificationService.new(envelope: malformed).qualify["lifecycle_state"] == "failed")

source = File.read(File.expand_path("../lib/soul_core/memory_projection_hybrid_fusion_qualification_service.rb", __dir__))
check.call("service has no persistence or process execution", !source.match?(/File\.(?:write|rename|delete)|\b(?:system|exec|spawn|fork|popen)\s*\(/))
check.call("service has no background execution", !source.match?(/Thread\.new|setInterval|setTimeout|systemd|retry/))

abort "Memory projection hybrid qualification A25 failed: #{errors.join(', ')}" unless errors.empty?
puts "Memory projection hybrid qualification A25 passed (#{checks} checks)."
