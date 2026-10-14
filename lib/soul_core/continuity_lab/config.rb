# frozen_string_literal: true

require "json"
require "digest"

module SoulCore
  module ContinuityLab
    class Error < StandardError; end
    class ValidationError < Error; end
    class Conflict < Error; end
    class IntegrityError < Error; end
    class Busy < Error; end
    class QuotaExceeded < Error; end
    class ContextBudgetExceeded < Error; end
    STRICT_JSON_SUPPORTED = begin
      JSON.parse('{"key":1,"key":2}', allow_duplicate_key: false)
      false
    rescue JSON::ParserError
      true
    end

    def self.parse(value)
      raise ValidationError, "strict JSON support required; use repository-pinned Ruby" unless STRICT_JSON_SUPPORTED
      JSON.parse(value, max_nesting: 24, allow_duplicate_key: false)
    end

    def self.canonical(value)
      case value
      when Hash then value.keys.sort.to_h { |key| [key, canonical(value.fetch(key))] }
      when Array then value.map { |entry| canonical(entry) }
      else value
      end
    end

    def self.encode(value)
      JSON.generate(canonical(value))
    end

    def self.digest(value)
      Digest::SHA256.hexdigest(encode(value))
    end

    class Config
      STREAM_PROFILE = "qwen_stream_diagnostics_v1"
      RECEIPT_POLICY = "current_event_receipts_v1"
      RANKED_RETRIEVAL = "ranked_lexical_v2"
      RECENT_DIALOGUE = "recent_dialogue_v1"
      DIRECT_EVIDENCE = "direct_evidence_v1"
      LIMITS = {
        "max_model_calls" => [9, 1..16], "max_tool_calls" => [8, 0..16],
        "max_invalid_actions" => [1, 0..2], "max_event_bytes" => [16_384, 1..65_536],
        "max_response_bytes" => [16_384, 64..65_536], "max_note_bytes" => [4096, 1..16_384],
        "max_notes" => [64, 1..128], "max_total_note_bytes" => [65_536, 1..1_048_576],
        "max_transactions" => [512, 8..8192], "max_journal_bytes" => [4_194_304, 4096..67_108_864],
        "max_seconds" => [30, 1..60], "context_tokens" => [4096, 128..4096],
        "output_tokens" => [768, 1..2048], "context_margin" => [256, 0..1024]
      }.freeze
      DISABLED = %w[autonomy browser code_execution training fallback].freeze

      def initialize(overrides = {})
        raise ValidationError, "strict JSON support required; use repository-pinned Ruby" unless STRICT_JSON_SUPPORTED
        raise ValidationError, "configuration must be a string-keyed object" unless overrides.is_a?(Hash) && overrides.keys.all? { |key| key.is_a?(String) }
        defaults = LIMITS.to_h { |key, (default, _)| [key, default] }
        defaults.merge!(DISABLED.to_h { |key| [key, false] }).merge!("backend" => "fake", "context_mode" => "raw_fixture")
        raise ValidationError, "unknown configuration key" unless (overrides.keys - defaults.keys - %w[failed_action_policy context_preparation execution_profile context_policy retrieval_policy recent_dialogue_policy answer_policy]).empty?
        @values = defaults.merge(overrides)
        if @values.key?("failed_action_policy") && @values["failed_action_policy"] != "consecutive_equivalent_failure_v1"
          raise ValidationError, "unsupported failed action policy"
        end
        raise ValidationError, "unsupported experimental backend" unless %w[fake fixture_pipe qwen_pipe].include?(@values["backend"])
        raise ValidationError, "invalid context mode" unless %w[raw_fixture explicit_v1].include?(@values["context_mode"])
        if @values.key?("context_preparation") &&
           (@values["context_preparation"] != "qwen_tokenized_v1" || @values["backend"] != "qwen_pipe" || @values["context_mode"] != "explicit_v1")
          raise ValidationError, "unsupported context preparation"
        end
        raise ValidationError, "optional capabilities must be disabled" unless DISABLED.all? { |key| @values[key] == false }
        if @values.key?("execution_profile") &&
           (@values["execution_profile"] != STREAM_PROFILE || !tokenized_context? || @values["max_model_calls"] != (direct_evidence? ? 1 : 6) ||
            @values["max_seconds"] != 420 || @values["output_tokens"] != 768 || @values["context_margin"] != 256 ||
            ![3072, 4096].include?(@values["context_tokens"]))
          raise ValidationError, "invalid streaming execution profile"
        end
        if @values.key?("context_policy") && (@values["context_policy"] != RECEIPT_POLICY || !stream_diagnostics?)
          raise ValidationError, "unsupported context policy"
        end
        { "retrieval_policy" => RANKED_RETRIEVAL, "recent_dialogue_policy" => RECENT_DIALOGUE }.each do |key, policy|
          if @values.key?(key) && (@values[key] != policy || !receipt_context?)
            raise ValidationError, "unsupported #{key}"
          end
        end
        if @values.key?("answer_policy") &&
           (!direct_evidence? || !recent_dialogue? || !receipt_context? || @values["max_tool_calls"] != 0 || @values["max_invalid_actions"] != 0)
          raise ValidationError, "unsupported direct evidence profile"
        end
        LIMITS.each do |key, (_, range)|
          range = 420..420 if key == "max_seconds" && stream_diagnostics?
          raise ValidationError, "invalid bound: #{key}" unless @values[key].is_a?(Integer) && range.cover?(@values[key])
        end
        unless @values["output_tokens"] + @values["context_margin"] < @values["context_tokens"]
          raise ValidationError, "context reserves exhaust input budget"
        end
        @values = JSON.parse(JSON.generate(@values))
        @values.each_value(&:freeze)
        @values.freeze
      end

      def [](key) = @values.fetch(key)

      def self.qwen_qualification
        new("backend" => "qwen_pipe", "context_mode" => "explicit_v1", "max_seconds" => 60, "max_model_calls" => 6)
      end

      # Optional key stays absent for old manifests, preserving their digests.
      def repeated_failure_guard? = @values["failed_action_policy"] == "consecutive_equivalent_failure_v1"

      def self.qwen_v3_qualification(rollover: false)
        new(qwen_qualification.to_h.merge("failed_action_policy" => "consecutive_equivalent_failure_v1",
                                         "context_tokens" => rollover ? 2048 : 4096))
      end
      def tokenized_context? = @values["context_preparation"] == "qwen_tokenized_v1"
      def stream_diagnostics? = @values["execution_profile"] == STREAM_PROFILE
      def receipt_context? = @values["context_policy"] == RECEIPT_POLICY
      def ranked_retrieval? = @values["retrieval_policy"] == RANKED_RETRIEVAL
      def recent_dialogue? = @values["recent_dialogue_policy"] == RECENT_DIALOGUE
      def direct_evidence? = @values["answer_policy"] == DIRECT_EVIDENCE

      def self.qwen_v4_qualification(rollover: false)
        new(qwen_v3_qualification.to_h.merge("context_preparation" => "qwen_tokenized_v1",
                                            "context_tokens" => rollover ? 3072 : 4096))
      end
      def self.qwen_v5_qualification(rollover: false)
        new(qwen_v4_qualification(rollover: rollover).to_h.merge("execution_profile" => STREAM_PROFILE, "max_seconds" => 420))
      end
      def self.qwen_v6_qualification(rollover: false)
        new(qwen_v5_qualification(rollover: rollover).to_h.merge("context_policy" => RECEIPT_POLICY))
      end
      def self.qwen_v7_qualification
        new(qwen_v6_qualification.to_h.merge("retrieval_policy" => RANKED_RETRIEVAL))
      end
      def self.qwen_v8_qualification
        new(qwen_v7_qualification.to_h.merge("recent_dialogue_policy" => RECENT_DIALOGUE))
      end
      def self.qwen_v9_qualification
        new(qwen_v8_qualification.to_h.merge("answer_policy" => DIRECT_EVIDENCE,
          "max_model_calls" => 1, "max_tool_calls" => 0, "max_invalid_actions" => 0))
      end
      def to_h = JSON.parse(JSON.generate(@values))
      def digest = ContinuityLab.digest(@values)
    end
  end
end
