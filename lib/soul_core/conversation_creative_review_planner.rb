# frozen_string_literal: true

require "json"
require_relative "conversation_provider_contract"

module SoulCore
  class ConversationCreativeReviewPlanner
    Contract = ConversationProviderContract
    KEYS = %w[related music_disposition music_rating musical_quality prompt_adherence vocal_adherence lyric_adherence music_notes visual_disposition visual_rating visual_notes next_question].freeze
    VALUES = %w[passed partial failed].freeze
    FORMAT = {
      "type" => "json_object", "schema" => {
        "type" => "object", "additionalProperties" => false, "required" => KEYS,
        "properties" => {
          "related" => { "type" => "boolean" },
          "music_disposition" => { "type" => "string" }, "music_rating" => { "type" => "integer" },
          "musical_quality" => { "type" => "string" }, "prompt_adherence" => { "type" => "string" },
          "vocal_adherence" => { "type" => "string" }, "lyric_adherence" => { "type" => "string" },
          "music_notes" => { "type" => "string" }, "visual_disposition" => { "type" => "string" },
          "visual_rating" => { "type" => "integer" }, "visual_notes" => { "type" => "string" },
          "next_question" => { "type" => "string" }
        }
      }
    }.freeze
    PROMPT = <<~TEXT.freeze
      Translate the newest user message into a review of the exact generated creative candidates described in prior_workflow. Return only the required JSON.
      A casual comment is not a review. Set related=false unless the user is clearly evaluating, keeping, revising, or rejecting one of these candidates.
      Music disposition is keep, revise, reject, or empty. Music rating is 1..5 or 0 when missing. Map musical quality, prompt adherence, vocal adherence, and lyric adherence to passed, partial, failed, or empty. For an instrumental candidate with no expected vocals or lyrics, use passed for vocal and lyric adherence. Preserve the user's meaning; do not improve a rating or turn criticism into approval. Put their rationale in music_notes.
      Visual disposition is keep, revise, or empty; visual rating is 1..5 or 0; preserve their rationale in visual_notes.
      Ask one concise next_question for the first blocking review value. Do not generate, revise, delete, bind, render, export, publish, authorize, or claim an action occurred.
    TEXT

    def initialize(provider_client:) = (@provider_client = provider_client)

    def draft(provider:, chat_id:, message:, flow:)
      return failed("a configured local model is required to interpret creative review") unless provider&.configured?
      request = Contract::RequestEnvelope.new(conversation_id: "creative-review-#{chat_id}", model: provider.model,
        messages: [{ "role" => "system", "content" => PROMPT }, { "role" => "user", "content" => JSON.generate({ "prior_workflow" => flow, "newest_user_message" => message }) }],
        temperature: 0.0, max_output_tokens: 1_500, response_format: provider.supports?("structured_output") ? FORMAT : nil,
        reasoning_mode: provider.supports?("reasoning_control") ? "disabled" : "default", privacy_requirement: provider.privacy_class,
        metadata: { "purpose" => "conversation_creative_review" })
      response = @provider_client.chat(provider: provider, request: request, timeout_seconds: 60)
      return failed("local creative review planner failed") unless response.success?
      { "ok" => true, "review" => validate(JSON.parse(response.content)) }
    rescue JSON::ParserError
      failed("local creative review planner returned invalid JSON")
    rescue ArgumentError => error
      failed(error.message)
    end

    private

    def validate(value)
      raise ArgumentError, "creative review must be an object" unless value.is_a?(Hash) && value.keys.sort == KEYS.sort
      raise ArgumentError, "creative review related is invalid" unless [true, false].include?(value["related"])
      %w[music_notes visual_notes next_question].each { |key| raise ArgumentError, "creative review #{key} is invalid" unless value[key].is_a?(String) && value[key].valid_encoding? }
      raise ArgumentError, "music disposition is invalid" unless %w[keep revise reject].include?(value["music_disposition"]) || value["music_disposition"].empty?
      raise ArgumentError, "visual disposition is invalid" unless %w[keep revise].include?(value["visual_disposition"]) || value["visual_disposition"].empty?
      %w[musical_quality prompt_adherence vocal_adherence lyric_adherence].each { |key| raise ArgumentError, "#{key} is invalid" unless VALUES.include?(value[key]) || value[key].empty? }
      %w[music_rating visual_rating].each { |key| raise ArgumentError, "#{key} is invalid" unless value[key].is_a?(Integer) && value[key].between?(0, 5) }
      value
    end

    def failed(reason) = { "ok" => false, "reason" => reason }
  end
end
