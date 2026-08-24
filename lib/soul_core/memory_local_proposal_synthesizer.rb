# frozen_string_literal: true

require "json"
require_relative "local_development_model_client"

module SoulCore
  # Converts one bounded A12 observation packet into strict local-model JSON.
  # Lifecycle authority remains in deterministic admission code.
  class MemoryLocalProposalSynthesizer
    OUTPUT_SCHEMA = {
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["proposals"],
      "properties" => {
        "proposals" => {
          "type" => "array",
          "maxItems" => 8,
          "items" => {
            "type" => "object",
            "additionalProperties" => false,
            "required" => %w[layer content confidence evidence_observation_ids],
            "properties" => {
              "layer" => { "type" => "string", "enum" => %w[project preference episodic semantic] },
              "content" => { "type" => "string", "minLength" => 1, "maxLength" => 1_000 },
              "confidence" => { "type" => "number", "minimum" => 0.0, "maximum" => 1.0 },
              "evidence_observation_ids" => {
                "type" => "array", "minItems" => 1, "maxItems" => 8,
                "items" => { "type" => "string", "minLength" => 1, "maxLength" => 160 }
              }
            }
          }
        }
      }
    }.freeze

    attr_reader :last_receipt

    def initialize(model_client: nil, root: Dir.pwd, env: ENV)
      @model_client = model_client || LocalDevelopmentModelClient.new(root: root, env: env)
    end

    def call(input)
      response = @model_client.chat(
        messages: messages(input),
        purpose: "memory_observation_derivation",
        response_schema: OUTPUT_SCHEMA,
        temperature: 0.0,
        max_tokens: 2_048,
        reasoning: "low",
        request_id: "memory_derive_#{input_digest(input)[0, 24]}"
      )
      @last_receipt = response.to_h
      raise ArgumentError, "local memory synthesis failed: #{response.error_message}" unless response.ok? && response.structured.is_a?(Hash)

      JSON.generate(response.structured)
    end

    private

    def messages(input)
      instruction = <<~TEXT
        You are Soul's local memory-proposal synthesizer. Use only the supplied conversation observations as evidence.
        Propose only durable ordinary memory that would improve future assistance. Do not preserve transient chatter,
        greetings, status checks, speculative conclusions, or facts stated only by the assistant. Do not propose
        credentials, secrets, authority grants, destructive authorization, safety or security policy, operator identity,
        protected persona rules, deletion, external publication, or retention-policy changes. Agreement is evidence,
        never authority. Every proposal must cite exact observation IDs from the supplied batch. Return only JSON matching
        the required schema. An empty proposals array is correct when no durable ordinary memory is supported.
      TEXT
      [
        { "role" => "system", "content" => instruction },
        { "role" => "user", "content" => JSON.generate(input) }
      ]
    end

    def input_digest(input)
      require "digest"
      Digest::SHA256.hexdigest(JSON.generate(input))
    end
  end
end
