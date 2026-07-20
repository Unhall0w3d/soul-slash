# frozen_string_literal: true

module SoulCore
  # A deterministic prerequisite for conversational invocation. This class does
  # not decide which capability the Operator means; it only distinguishes an
  # actual request from a topical statement before domain-specific routing runs.
  class ConversationRequestShape
    Result = Struct.new(:kind, :reason, keyword_init: true) do
      def request? = %w[action_request information_request terse_request].include?(kind)
      def action_request? = kind == "action_request"
      def information_request? = kind == "information_request"
      def conversation? = kind == "conversation"

      def to_h
        { "kind" => kind, "reason" => reason, "request" => request? }
      end
    end

    LEAD_IN = "(?:(?:well|okay|ok|alright|so)[, ]+|(?:hey\\s+)?soul(?:\\s*[/\\\\])?[,! ]+)"
    POLITE_ACTION = /\A\s*(?:#{LEAD_IN})?(?:please\s+)?(?:can|could|would|will)\s+you\b/i
    DIRECT_ACTION = /\A\s*(?:#{LEAD_IN})?(?:please\s+)?(?:activate|analy[sz]e|assess|archive|build|change|check|clear|compose|connect|convert|create|delete|deploy|describe|diagnose|discard|do|download|draft|edit|erase|execute|export|fetch|find|forget|generate|give|hide|inspect|install|invoke|launch|list|look\s+up|make|monitor|move|open|organize|play|prepare|produce|purge|remove|render|report|research|review|run|save|scan|schedule|search|send|show|summari[sz]e|switch|take\s+a\s+look|tell|test|transcribe|translate|trash|update|upload|use|write)\b/i
    DESIRE_ACTION = /\b(?:i\s+(?:want|need)|i(?:'d| would)\s+like)\s+you\s+to\b/i
    INFORMATION = /\A\s*(?:#{LEAD_IN})?(?:please\s+)?(?:what|which|who|where|when|why|how|is|are|am|do|does|did|can|could|would|will|have|has)\b/i
    CONVERSATIONAL_OPENING = /\A\s*(?:i(?:'m| am| was| were| have| had)\b|we(?:'re| are| were| have| had)\b|this\b|that\b|it\b|just\b|currently\b|today\b)/i
    TERSE_DOMAIN = /\b(?:status|health|weather|forecast|skills?|capabilities|downloads?|workspace|inbox|artifacts?|history|memory|interests?|core|research)\b/i
    TERSE_DISQUALIFIER = /\b(?:could|would|should|might|may|seems?|sounds?|looks?|useful|interesting|later|someday|yesterday|earlier)\b/i

    def classify(message)
      text = message.to_s.strip
      return result("conversation", "empty text is not an invocation") if text.empty?
      return result("action_request", "the Operator directly asks Soul to act") if action_request?(text)
      return result("information_request", "the Operator asks a direct question") if information_request?(text)
      return result("conversation", "the message is framed as conversational context") if text.match?(CONVERSATIONAL_OPENING)
      return result("terse_request", "a short domain phrase is treated as an explicit foreground request") if terse_request?(text)

      result("conversation", "no deterministic request shape is present")
    end

    def request?(message) = classify(message).request?
    def action_request?(message) = message.to_s.match?(POLITE_ACTION) || message.to_s.match?(DIRECT_ACTION) || message.to_s.match?(DESIRE_ACTION)
    def information_request?(message) = message.to_s.match?(INFORMATION)

    private

    def terse_request?(text)
      words = text.scan(/[[:alnum:]'-]+/)
      words.length.between?(1, 6) && text.match?(TERSE_DOMAIN) && !text.match?(TERSE_DISQUALIFIER)
    end

    def result(kind, reason) = Result.new(kind: kind, reason: reason)
  end
end
