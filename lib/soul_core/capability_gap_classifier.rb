# frozen_string_literal: true

module SoulCore
  class CapabilityGapClassifier
    TASK_PATTERNS = [
      /\A\s*(?:please\s+)?(?:can|could|would)\s+you\b/i,
      /\A\s*(?:please\s+)?(?:create|build|make|open|launch|play|send|download|upload|transcribe|translate|analy[sz]e|inspect|monitor|connect|control|convert|generate|schedule|search|find|fetch|run|execute|install|remove|delete|edit|update|deploy)\b/i,
      /\bI\s+(?:want|need|would like)\s+you\s+to\b/i
    ].freeze

    INABILITY_PATTERNS = [
      /\bI (?:cannot|can't|am unable to|do not have (?:the )?(?:ability|capability)|don't have (?:the )?(?:ability|capability))\b/i,
      /\bI (?:do not|don't) have (?:access to|a registered skill|a skill|a tool)\b/i,
      /\b(?:that capability|this capability|this path) (?:is not|isn't) (?:available|implemented|built|registered)\b/i,
      /\bno (?:registered )?(?:skill|tool|capability) (?:can|covers|supports|is available)\b/i
    ].freeze

    META_DISCUSSION_PATTERNS = [
      /\b(?:suppose|imagine|hypothetically|in a hypothetical)\b/i,
      /\bwhat (?:would|do|should) you say\b/i,
      /\bhow (?:would|should) you (?:respond|reply|handle|explain)\b/i
    ].freeze

    NON_GAP_PATTERNS = [
      /\b(?:API key|credential|authentication|not configured|configuration|connection|network|timeout|temporar(?:y|ily)|rate limit|service unavailable)\b/i,
      /\b(?:permission denied|requires? (?:your )?(?:approval|confirmation|permission)|waiting for (?:approval|confirmation))\b/i,
      /\b(?:unsafe|harmful|illegal|policy|I (?:cannot|can't) help with)\b/i,
      /\b(?:need more information|need clarification|could you clarify|which .+ do you mean)\b/i
    ].freeze

    def classify(user_message:, assistant_message:)
      request = user_message.to_s.strip
      response = assistant_message.to_s.strip
      return rejected("request discusses a hypothetical response rather than requesting the capability") if META_DISCUSSION_PATTERNS.any? { |pattern| request.match?(pattern) }
      return rejected("request is not task-shaped") unless TASK_PATTERNS.any? { |pattern| request.match?(pattern) }
      return rejected("assistant response does not explicitly report missing capability") unless INABILITY_PATTERNS.any? { |pattern| response.match?(pattern) }
      return rejected("response indicates configuration, permission, safety, ambiguity, or transient failure") if NON_GAP_PATTERNS.any? { |pattern| response.match?(pattern) }

      {
        "candidate" => true,
        "classification" => "model_reported_missing_capability",
        "reason" => "task-shaped request received an explicit missing-capability response"
      }
    end

    private

    def rejected(reason)
      { "candidate" => false, "classification" => "not_a_capability_gap", "reason" => reason }
    end
  end
end
