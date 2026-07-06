# frozen_string_literal: true

module SoulCore
  class ConfirmationParser
    Result = Struct.new(:confirmed, :cancelled, :message, keyword_init: true)

    YES_PATTERNS = [
      /\byes\b/,
      /\byeah\b/,
      /\byep\b/,
      /\byup\b/,
      /\bdo it\b/,
      /\bgo ahead\b/,
      /\bconfirm\b/,
      /\bapproved?\b/,
      /\bmove (it|them)\b/,
      /\btrash (it|them)\b/,
      /\brestore (it|them)\b/,
      /\brestore all\b/
    ].freeze

    NO_PATTERNS = [
      /\bno\b/,
      /\bnope\b/,
      /\bcancel\b/,
      /\bstop\b/,
      /\bnever mind\b/,
      /\bdon'?t\b/
    ].freeze

    def parse(text)
      normalized = text.to_s.downcase.strip

      if NO_PATTERNS.any? { |pattern| normalized.match?(pattern) }
        return Result.new(
          confirmed: false,
          cancelled: true,
          message: "Cancelled."
        )
      end

      if YES_PATTERNS.any? { |pattern| normalized.match?(pattern) }
        return Result.new(
          confirmed: true,
          cancelled: false,
          message: "Confirmed."
        )
      end

      Result.new(
        confirmed: false,
        cancelled: false,
        message: "I could not tell whether that was confirmation. Please say yes, do it, confirm, restore them, or cancel."
      )
    end
  end
end
