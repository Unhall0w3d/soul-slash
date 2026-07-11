# frozen_string_literal: true

module SoulCore
  class ConversationOrchestrationContract
    KINDS = %w[
      direct_model
      deterministic_passthrough
      skill_only
      skill_then_model
      evidence_followup
      capability_gap
      deterministic_fallback
    ].freeze

    Decision = Struct.new(
      :kind,
      :reason,
      :tools,
      :requires_model,
      :synthesize,
      :max_steps,
      :flags,
      keyword_init: true
    ) do
      def initialize(**arguments)
        super
        self.tools ||= []
        self.flags ||= {}
        self.max_steps ||= 0
        validate!
      end

      def tool_ids
        tools.map(&:id)
      end

      def to_h
        {
          "kind" => kind,
          "reason" => reason,
          "tool_ids" => tool_ids,
          "requires_model" => requires_model == true,
          "synthesize" => synthesize == true,
          "max_steps" => max_steps,
          "flags" => flags
        }
      end

      private

      def validate!
        raise ArgumentError, "Unsupported orchestration kind: #{kind}" unless KINDS.include?(kind.to_s)
        raise ArgumentError, "max_steps must be non-negative" if max_steps.to_i.negative?
      end
    end
  end
end
