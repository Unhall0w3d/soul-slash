# frozen_string_literal: true

require_relative 'cpu_member_calculation'

module SoulCore
  # A deliberately closed grammar: only this invocation supplies operands.
  module CpuMemberNaturalCalculation
    INTEGER = '[+-]?[0-9]+'
    PREFIX = '(?:please\s+)?(?:(?:what\s+is|calculate)\s+)?'
    SUFFIX = '\s*[?.!]?\s*'
    PATTERNS = [
      ["#{PREFIX}(?<a>#{INTEGER})\\s*(?:plus|\\+)\\s*(?<b>#{INTEGER})", 'add', false],
      ["#{PREFIX}(?<a>#{INTEGER})\\s*(?:minus|-)\\s*(?<b>#{INTEGER})", 'subtract', false],
      ["#{PREFIX}(?<a>#{INTEGER})\\s*(?:times|multiplied\\s+by|\\*|×)\\s*(?<b>#{INTEGER})", 'multiply', false],
      ["(?:please\\s+)?add\\s+(?<a>#{INTEGER})\\s+(?:and|to)\\s+(?<b>#{INTEGER})", 'add', false],
      ["(?:please\\s+)?subtract\\s+(?<a>#{INTEGER})\\s+from\\s+(?<b>#{INTEGER})", 'subtract', true],
      ["(?:please\\s+)?multiply\\s+(?<a>#{INTEGER})\\s+by\\s+(?<b>#{INTEGER})", 'multiply', false],
      ["i\\s+have\\s+(?<a>#{INTEGER})\\s+credits\\s+and\\s+(?:i\\s+)?spent\\s+(?<b>#{INTEGER})(?:\\s+credits)?[;,.]?\\s+how\\s+much\\s+is\\s+left", 'subtract', false],
      ["my\\s+budget\\s+is\\s+(?<a>#{INTEGER})\\s+and\\s+my\\s+deposit\\s+is\\s+(?<b>#{INTEGER})[;,.]?\\s+(?:how\\s+much\\s+is\\s+left|what\\s+is\\s+the\\s+remaining\\s+balance)", 'subtract', false]
    ].map { |source, operation, reverse| [Regexp.new("\\A\\s*#{source}#{SUFFIX}\\z", Regexp::IGNORECASE).freeze, operation, reverse].freeze }.freeze
    CLARIFICATION = 'Please give one calculation using two whole numbers between -1000000 and 1000000, such as "847 minus 286", "add 12 and 3", or "multiply 4 by 5".'

    def self.resolve(text)
      return nil unless text.is_a?(String) && text.valid_encoding?
      return nil if text.start_with?('/')
      return clarification if text.bytesize > 2048 && likely_arithmetic?(text)
      return nil if text.bytesize > 2048

      # No quote/code stripping or substring extraction: the entire input must
      # match. Newlines and controls cannot hide additional instructions.
      unless text.match?(/[[:cntrl:]]/)
        PATTERNS.each do |pattern, operation, reverse|
          match = pattern.match(text)
          next unless match
          names = reverse ? %w[b a] : %w[a b]
          spans = names.map do |name|
            # Offsets and lengths count Ruby string characters (Unicode
            # codepoints for UTF-8), not bytes or UTF-16 code units.
            { 'start' => match.begin(name), 'length' => match[name].length, 'text' => match[name] }
          end
          operands = spans.map { |span| Integer(span.fetch('text'), 10) }
          return clarification unless operands.all? { |value| value.between?(-1_000_000, 1_000_000) }
          # Remainder prose is limited to nonnegative counts; signed amounts
          # must be expressed as an explicit operation instead.
          return clarification if text.match?(/\b(?:credits|budget)\b/i) && operands.any?(&:negative?)
          command = {
            'operation' => operation,
            'sources' => { 'operand_1' => operands[0], 'operand_2' => operands[1] },
            'left' => 'operand_1', 'right' => 'operand_2'
          }
          validated = CpuMemberCalculation.parse('/calculate ' + JSON.generate(command))
          return { 'state' => 'complete', 'calculation' => validated, 'source_spans' => spans,
                   'outcome' => CpuMemberCalculation.evaluate(validated) }
        end
      end
      likely_arithmetic?(text) ? clarification : nil
    end

    def self.likely_arithmetic?(text)
      text.match?(/\b(?:calculate|subtract|multiply|divide|plus|minus|multiplied|divided|sum|product|remainder|square\s+root)\b/i) ||
        (text.match?(/\badd\b.*\b(?:and|to)\b/i) && text.match?(/\b(?:[0-9]+|zero|one|two|three|four|five|six|seven|eight|nine|ten)\b/i)) ||
        (text.match?(/\A\s*(?:["'`$+-]?[0-9]|["'`]|(?:please\s+)?what\s+is\b)/i) && text.match?(/[0-9].*[+*×÷\/=%^-].*[0-9]/)) ||
        text.match?(/\bhow\s+much\b.*\b(?:left|remain\w*)\b/i) ||
        text.match?(/\bremaining\s+balance\b/i) ||
        text.match?(/[0-9].*\btimes\b.*[0-9]/i)
    end
    private_class_method :likely_arithmetic?

    def self.clarification
      { 'state' => 'awaiting_input', 'message' => CLARIFICATION }
    end
    private_class_method :clarification
  end
end
