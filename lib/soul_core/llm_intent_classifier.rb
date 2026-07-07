# frozen_string_literal: true

require "json"
require_relative "model_client"

module SoulCore
  class LlmIntentClassifier
    ALLOWED_INTENTS = [
      "downloads.cleanup",
      "downloads.restore_last_cleanup",
      "weather.report"
    ].freeze

    def initialize(model_client: ModelClient.new)
      @model_client = model_client
    end

    def classify(text)
      prompt = build_prompt(text)
      result = @model_client.chat(prompt, mode: :fast, max_tokens: 512, temperature: 0.1)
      content = result[:content].to_s.strip
      parsed = parse_json(content)
      validate(parsed, raw_content: content)
    rescue StandardError => e
      {
        ok: false,
        matched: false,
        intent: nil,
        confidence: 0.0,
        parameters: {},
        reason: "LLM intent classification failed: #{e.class}: #{e.message}",
        source: "llm"
      }
    end

    private

    def build_prompt(text)
      <<~PROMPT
        You classify user requests into Soul/ workflow intents.
        Return ONLY valid compact JSON. Do not use markdown.

        Registered workflows:
        [
          {
            "intent": "downloads.cleanup",
            "description": "Plan cleanup of top-level files and folders in the user's Downloads folder. Default age threshold is 30 days when not specified. Execution moves approved items to Trash, not permanent deletion.",
            "examples": [
              "cleanup files in my downloads folder older than 30 days",
              "run a file cleanup in my downloads folder",
              "clear old junk out of Downloads",
              "trash stale downloads"
            ],
            "allowed_target_paths": ["~/Downloads"],
            "default_slots": {
              "target_path": "~/Downloads",
              "older_than_days": 30,
              "include_directories": true,
              "recursive": false
            }
          },
          {
            "intent": "downloads.restore_last_cleanup",
            "description": "Restore files and folders moved to Trash by the most recent successful Downloads cleanup workflow.",
            "examples": [
              "restore the last downloads cleanup",
              "undo the last downloads cleanup",
              "roll back the last downloads cleanup"
            ],
            "default_slots": {
              "restore_scope": "latest_successful_downloads_cleanup"
            }
          },
          {
            "intent": "weather.report",
            "description": "Get today's weather for a location, including temperature, humidity, and air quality. The workflow can optionally provide a 3-day outlook.",
            "examples": [
              "what is the weather today in Syracuse, NY",
              "what's the weather like today",
              "current weather for Buffalo, New York",
              "how is the air quality today in Albany",
              "weather forecast near Rochester"
            ],
            "default_slots": {
              "location": null,
              "units": "fahrenheit"
            }
          }
        ]

        Rules:
        - Match only a registered workflow.
        - For Downloads cleanup, if no age threshold is specified, use 30 days.
        - For Downloads cleanup, do not invent paths outside ~/Downloads.
        - For weather, extract a location if the user provided one after words like in, for, or near.
        - For weather, if no location is present, set location to null. Do not invent one.
        - Do not invent workflows.
        - Return JSON with exactly these keys: matched, intent, confidence, slots, needs_clarification, clarifying_question, reason

        User request: #{text}
      PROMPT
    end

    def parse_json(content)
      start = content.index("{")
      finish = content.rindex("}")
      raise "no JSON object found in model output" unless start && finish && finish >= start

      JSON.parse(content[start..finish])
    end

    def validate(parsed, raw_content:)
      matched = parsed["matched"] == true
      intent = parsed["intent"]
      confidence = parsed["confidence"].to_f
      slots = parsed["slots"].is_a?(Hash) ? parsed["slots"] : {}
      reason = parsed["reason"].to_s.strip
      needs_clarification = parsed["needs_clarification"] == true
      clarifying_question = parsed["clarifying_question"].to_s.strip

      unless matched
        return {
          ok: false,
          matched: false,
          intent: nil,
          confidence: confidence,
          parameters: {},
          needs_clarification: needs_clarification,
          clarifying_question: clarifying_question.empty? ? nil : clarifying_question,
          reason: reason.empty? ? "LLM did not match a workflow." : reason,
          source: "llm",
          raw_content: raw_content
        }
      end

      unless ALLOWED_INTENTS.include?(intent)
        return {
          ok: false,
          matched: false,
          intent: nil,
          confidence: confidence,
          parameters: {},
          reason: "LLM returned unregistered intent: #{intent}",
          source: "llm",
          raw_content: raw_content
        }
      end

      if confidence < 0.60
        return {
          ok: false,
          matched: false,
          intent: nil,
          confidence: confidence,
          parameters: {},
          reason: "LLM confidence too low: #{confidence}",
          source: "llm",
          raw_content: raw_content
        }
      end

      params =
        case intent
        when "downloads.cleanup"
          sanitize_downloads_cleanup_slots(slots)
        when "downloads.restore_last_cleanup"
          { "restore_scope" => "latest_successful_downloads_cleanup" }
        when "weather.report"
          sanitize_weather_slots(slots)
        else
          {}
        end

      {
        ok: true,
        matched: true,
        intent: intent,
        confidence: confidence,
        parameters: params,
        needs_clarification: false,
        clarifying_question: nil,
        reason: reason.empty? ? "LLM matched registered workflow." : reason,
        source: "llm"
      }
    end

    def sanitize_downloads_cleanup_slots(slots)
      target = slots["target_path"].to_s.strip
      target = "~/Downloads" if target.empty?

      unless ["~/Downloads", "Downloads", "$HOME/Downloads"].include?(target)
        raise "unsafe or unsupported target_path from LLM: #{target}"
      end

      days = slots["older_than_days"]
      days = days.to_i if days.is_a?(String) && days.match?(/^\d+$/)
      days = 30 unless days.is_a?(Integer)
      days = 30 if days <= 0
      days = 3650 if days > 3650

      {
        "target_path" => File.join(Dir.home, "Downloads"),
        "older_than_days" => days,
        "include_directories" => true,
        "recursive" => false
      }
    end

    def sanitize_weather_slots(slots)
      location = slots["location"]
      location = nil if location.nil? || location.to_s.strip.empty?

      {
        "location" => location&.to_s&.strip,
        "units" => ENV.fetch("SOUL_WEATHER_UNITS", "fahrenheit")
      }
    end
  end
end
