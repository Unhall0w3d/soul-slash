# frozen_string_literal: true

require_relative "conversation_request_shape"

module SoulCore
  class ConversationArtifactDecisionPolicy
    Result = Struct.new(:mode, :reason, :signals, keyword_init: true) do
      def artifact?
        mode != "chat"
      end

      def required?
        mode == "artifact_required"
      end

      def to_h
        {
          "mode" => mode,
          "reason" => reason,
          "signals" => signals,
          "artifact_requested" => artifact?
        }
      end
    end

    CREATION_VERBS = /\b(create|write|draft|generate|produce|build|make|prepare|export|package|deliver|save)\b/i
    ARTIFACT_NOUNS = /\b(report|document|overlay|zip|package|csv|spreadsheet|workbook|presentation|slides?|deck|code bundle|script|research notes?|implementation plan|artifact)\b/i
    LONG_FORM_CUES = /\b(detailed|complete|full|comprehensive|long-form|multi-file|downloadable)\b/i

    def classify(message)
      text = message.to_s.strip
      return result("chat", "empty messages do not request artifacts", []) if text.empty?

      signals = []
      signals << "creation_verb" if text.match?(CREATION_VERBS)
      signals << "artifact_noun" if text.match?(ARTIFACT_NOUNS)
      signals << "long_form_cue" if text.match?(LONG_FORM_CUES)
      signals << "large_prompt" if text.length >= 1_200 || text.lines.length >= 20

      if signals.include?("creation_verb") && signals.include?("artifact_noun")
        if ConversationRequestShape.new.action_request?(text)
          return result("artifact_required", "the user explicitly requested a deliverable", signals)
        end

        return result("chat", "a deliverable was mentioned without an explicit creation request", signals)
      end

      if signals.include?("artifact_noun") && signals.include?("long_form_cue") && signals.include?("large_prompt")
        return result("artifact_candidate", "the request may be clearer as a bounded artifact", signals)
      end

      result("chat", "the request can remain in conversation", signals)
    end

    private

    def result(mode, reason, signals)
      Result.new(mode: mode, reason: reason, signals: signals.freeze)
    end
  end
end
