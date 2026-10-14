# frozen_string_literal: true

require_relative "retrieval"

module SoulCore
  module ContinuityLab
    # Journal-derived observations, not authored memory or verified source facts.
    module RecentDialogue
      MAX_EXCHANGES = 3
      MAX_BYTES = 4096
      FIELDS = %w[lineage_id collection id revision content_digest provenance span text].freeze

      def self.candidates(state, event_id)
        prior = state.fetch("events").values.take_while { |event| event.fetch("event_id") != event_id }
        prior.select { |event| event["state"] == "complete" && event["reason"] == "reply" }
          .last(MAX_EXCHANGES).map do |event|
            text = ContinuityLab.encode("user" => event.fetch("content"), "assistant" => event.fetch("reply"))
            doc = { "id" => event.fetch("event_id"), "revision" => 1, "content" => text,
                    "provenance" => "observed_exchange_not_verified_fact" }
            Retrieval.source(state, "history", doc, 0, text.length)
          end
      end

      def self.select(state, event_id)
        sources = candidates(state, event_id)
        sources.shift while ContinuityLab.encode(sources).bytesize > MAX_BYTES
        sources
      end

      def self.validate_envelope!(envelope)
        sources = envelope["recent_dialogue"]
        unless envelope["recent_dialogue_policy"] == Config::RECENT_DIALOGUE && sources.is_a?(Array) &&
               sources.length <= MAX_EXCHANGES && ContinuityLab.encode(sources).bytesize <= MAX_BYTES &&
               sources.all? do |source|
                 source.is_a?(Hash) && source.keys.sort == FIELDS.sort &&
                   source["lineage_id"] == envelope["lineage_id"] && source["collection"] == "history" &&
                   Actions.valid_id?(source["id"]) && source["id"] != envelope.dig("user", "event_id") &&
                   source["revision"] == 1 && source["provenance"] == "observed_exchange_not_verified_fact" &&
                   source["text"].is_a?(String) && source["span"] == [0, source["text"].length] &&
                   source["content_digest"] == Digest::SHA256.hexdigest(source["text"]) && valid_text?(source["text"])
               end
          raise ValidationError, "invalid recent dialogue envelope"
        end
        raise ValidationError, "duplicate recent exchange" unless sources.map { |s| s["id"] }.uniq.length == sources.length
      end

      def self.valid_text?(text)
        pair = ContinuityLab.parse(text)
        pair.is_a?(Hash) && pair.keys.sort == %w[assistant user] && pair.values.all? { |value| value.is_a?(String) } &&
          ContinuityLab.encode(pair) == text
      rescue JSON::ParserError
        false
      end
    end
  end
end
