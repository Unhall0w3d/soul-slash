# frozen_string_literal: true

module SoulCore
  class SpeechPresentationService
    CONTEXTS = %w[general weather_report].freeze
    WEATHER_SPEED_FACTOR = 0.90
    CARDINALS = {
      "N" => "north", "NE" => "northeast", "E" => "east", "SE" => "southeast",
      "S" => "south", "SW" => "southwest", "W" => "west", "NW" => "northwest"
    }.freeze

    def prepare(value, context: nil)
      selected = context.to_s.strip
      selected = "general" if selected.empty?
      raise ArgumentError, "unsupported speech context" unless CONTEXTS.include?(selected)

      text = strip_non_prose(value)
      text = selected == "weather_report" ? weather_text(text) : compact(text)
      {
        "text" => text,
        "context" => selected,
        "speed_factor" => selected == "weather_report" ? WEATHER_SPEED_FACTOR : 1.0
      }
    end

    private

    def strip_non_prose(value)
      text = value.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: " ")
      text = text.gsub(/```.*?```/m, " ")
      text = text.gsub(/`[^`\n]+`/, " ")
      text = text.gsub(%r{https?://\S+}, " ")
      text = text.gsub(/^\s{0,3}\#{1,6}\s+/, "")
      text = text.gsub(/^\s*[-*+]\s+/, "")
      text.gsub(/[*_~>|]/, "")
    end

    def weather_text(value)
      lines = value.lines.map(&:strip).reject(&:empty?)
      return compact(value) if lines.empty?

      spoken = lines.map.with_index do |line, index|
        index.zero? ? weather_brief(line) : forecast_line(line)
      end.join(" ")
      spoken = expand_weather_terms(spoken)
      punctuate(spoken)
    end

    def weather_brief(line)
      match = line.match(/\AIn\s+(.+?):\s*(.+)\z/i)
      return forecast_line(line) unless match

      location = match[1].strip
      remainder = match[2].strip
      question = remainder.slice!(/\s*Want the 3-day outlook\?\s*\z/i)
      clauses = remainder.split(/,\s+/).map(&:strip).reject(&:empty?)
      parts = ["In #{location}.", clauses.join(". ")]
      parts << "Would you like the three-day outlook?" if question
      parts.join(" ")
    end

    def forecast_line(line)
      line.split(/\s+—\s+/).map(&:strip).reject(&:empty?).join(". ")
    end

    def expand_weather_terms(value)
      text = value.dup
      text.gsub!(/(-?\d+(?:\.\d+)?)\s*°\s*F\b/i, '\1 degrees Fahrenheit')
      text.gsub!(/(-?\d+(?:\.\d+)?)\s*°\s*C\b/i, '\1 degrees Celsius')
      text.gsub!(/(-?\d+(?:\.\d+)?)\s*%/, '\1 percent')
      text.gsub!(/(\d+(?:\.\d+)?)\s*mph\b/i, '\1 miles per hour')
      text.gsub!(/(\d+(?:\.\d+)?)\s*km\/h\b/i, '\1 kilometers per hour')
      text.gsub!(/\bUS AQI\b/i, "U S air quality index")
      text.gsub!(/\b3[- ]day\b/i, "three-day")
      text.gsub!(/\bfrom\s+(NE|NW|SE|SW|N|E|S|W)\b/i) do
        "from #{CARDINALS.fetch(Regexp.last_match(1).upcase)}"
      end
      text.gsub!(/\(([^()\n]{1,80})\)/, '. \1')
      text
    end

    def punctuate(value)
      text = compact(value)
      text = text.gsub(/(\d)\.(\d)/, '\1<decimal>\2')
      text = text.gsub(/\s*\.\s*/, ". ")
      text = text.gsub(/\.{2,}/, ".")
      text = text.gsub(/\s+([?.!])/, '\1')
      text = text.gsub("<decimal>", ".")
      text = "#{text}." unless text.end_with?(".", "?", "!")
      text.strip
    end

    def compact(value)
      value.to_s.gsub(/\s+/, " ").strip
    end
  end
end
