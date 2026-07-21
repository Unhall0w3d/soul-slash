#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../lib/soul_core/conversation_visual_revision_planner"

Contract = SoulCore::ConversationProviderContract

class FixtureClient
  attr_accessor :content
  attr_reader :requests
  def initialize(content)
    @content = content
    @requests = []
  end
  def chat(provider:, request:, timeout_seconds:)
    @requests << { provider: provider, request: request, timeout_seconds: timeout_seconds }
    Contract::ResponseEnvelope.new(request_id: request.request_id, provider_id: provider.id, model: provider.model,
      content: @content, finish_reason: "stop", latency_ms: 1.0)
  end
end

def provider(privacy: "local_only", configured: true)
  Contract::ProviderDefinition.new(id: "fixture", label: "fixture", transport: "openai_compatible",
    endpoint: "http://127.0.0.1:1/v1", model: "fixture", privacy_class: privacy,
    capabilities: %w[chat structured_output reasoning_control], configured: configured)
end

project = {
  "title" => "Signal Loom Cover", "intent" => "a poised signal in deep space",
  "prompt" => "A poised machine figure mapping cerulean signals in an abyssal observatory.",
  "negative_prompt" => "text, watermark", "aspect_ratio" => "landscape", "seed" => 84
}
candidate = {
  "candidate_id" => "visual_candidate_4444444444444444", "kind" => "text_to_image", "seed" => 84,
  "review" => { "rating" => 4, "disposition" => "revise", "notes" => "Preserve the figure and palette; deepen the void and add distant architecture." }
}
valid = JSON.generate({
  "instruction" => "Preserve the poised figure and cerulean illumination while deepening the surrounding abyss and adding subtle distant suspended architecture without text.",
  "seed" => 424_242,
  "rationale" => "This retains the successful subject and palette while applying the requested environmental depth."
})
client = FixtureClient.new(valid)
planner = SoulCore::ConversationVisualRevisionPlanner.new(provider_client: client)
checks = {}

draft = planner.draft(project: project, candidate: candidate, provider: provider)
checks["valid_local_draft_stops_at_human_gate"] = draft["ok"] && draft["lifecycle_state"] == "blocked_for_human_review" && !draft.dig("data", "automatic_generation")
checks["complete_instruction_seed_and_digest_are_returned"] = draft.dig("data", "instruction").include?("deepening") && draft.dig("data", "seed") == 424_242 && draft.dig("data", "packet_digest").match?(/\A[a-f0-9]{64}\z/)
request = client.requests.first.fetch(:request)
checks["request_is_bounded_and_structured"] = client.requests.first.fetch(:timeout_seconds) == 60.0 && request.response_format && request.max_output_tokens == 1_500
checks["prompt_denies_pixel_vision_and_authority"] = request.messages.first.fetch("content").include?("not seen the image pixels") && request.messages.first.fetch("content").include?("infer authority")

cloud = planner.draft(project: project, candidate: candidate, provider: provider(privacy: "cloud"))
checks["cloud_provider_is_blocked_before_request"] = !cloud["ok"] && cloud["lifecycle_state"] == "blocked_for_human_review" && client.requests.length == 1
missing_review = planner.draft(project: project, candidate: candidate.merge("review" => nil), provider: provider)
checks["missing_review_awaits_input"] = !missing_review["ok"] && missing_review["lifecycle_state"] == "awaiting_input" && client.requests.length == 1

client.content = "```json\n#{valid}\n```"
markdown = planner.draft(project: project, candidate: candidate, provider: provider)
checks["markdown_wrapped_json_fails_safely"] = !markdown["ok"] && markdown["lifecycle_state"] == "failed"
client.content = JSON.generate({ "instruction" => "Make the void deeper around the figure.", "seed" => -1, "rationale" => "Requested." })
bad_seed = planner.draft(project: project, candidate: candidate, provider: provider)
checks["invalid_seed_is_rejected"] = !bad_seed["ok"] && bad_seed["lifecycle_state"] == "awaiting_input"
client.content = JSON.generate({ "instruction" => "x" * 2_001, "seed" => 4, "rationale" => "Requested." })
oversized = planner.draft(project: project, candidate: candidate, provider: provider)
checks["oversized_instruction_is_rejected"] = !oversized["ok"] && oversized["lifecycle_state"] == "awaiting_input"

failed = checks.reject { |_name, value| value }
puts checks.map { |name, value| "#{value ? 'PASS' : 'FAIL'} #{name}" }
abort("#{failed.length} visual revision planner checks failed") unless failed.empty?
puts "PASS #{checks.length} visual revision planner checks"
