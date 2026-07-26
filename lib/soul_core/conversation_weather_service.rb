# frozen_string_literal: true

require_relative "skill_registry"
require_relative "skill_runner"

module SoulCore
  class ConversationWeatherService
    DETAILED_PATTERN = /\b(?:3[- ]day|three[- ]day|detailed report|detailed forecast|outlook)\b/i
    LOCATION_PATTERN = /\b(?:in|for|near)\s+(.+?)\s*[?.!]*\z/i
    TRAILING_TIME_PATTERN = /\s+(?:today|right now|now|please)\s*\z/i
    CARDINAL_DIRECTIONS = %w[N NE E SE S SW W NW].freeze

    def initialize(env: ENV, runner: nil)
      @env = env
      @runner = runner || SkillRunner.new(registry: SkillRegistry.new)
    end

    def report(message:, force_detailed: false, location_override: nil)
      text = message.to_s.strip
      location, source = resolve_location(text, location_override)
      return awaiting_location unless location

      detailed = force_detailed || text.match?(DETAILED_PATTERN)
      args = ["--location", location, "--units", units]
      args << "--detailed" if detailed
      result = @runner.run("weather.report", args: args)
      report = result[:json] || {}

      unless result[:ok] && report.dig("verification", "weather_fetch_ok") == true
        return {
          "ok" => false,
          "lifecycle_state" => "failed",
          "content" => "I couldn't retrieve the weather safely just now. The provider returned no usable current conditions.",
          "report" => report,
          "location_source" => source
        }
      end

      {
        "ok" => true,
        "lifecycle_state" => "complete",
        "content" => detailed ? render_detailed(report) : render_brief(report),
        "report" => report,
        "location_source" => source
      }
    rescue StandardError => error
      {
        "ok" => false,
        "lifecycle_state" => "failed",
        "content" => "I couldn't retrieve the weather safely just now (#{error.class}).",
        "report" => {},
        "location_source" => source
      }
    end

    private

    def resolve_location(text, location_override)
      explicit = text.match(LOCATION_PATTERN)&.captures&.first.to_s.strip
      explicit = explicit.sub(TRAILING_TIME_PATTERN, "").strip
      return [explicit, "explicit"] unless explicit.empty?

      override = location_override.to_s.strip
      return [override, "weather_followup"] unless override.empty?

      home = @env.fetch("SOUL_WEATHER_LOCATION", "").to_s.strip
      return [home, "configured_home"] unless home.empty?

      [nil, "missing"]
    end

    def awaiting_location
      {
        "ok" => false,
        "lifecycle_state" => "awaiting_input",
        "content" => "I can check. Which city or location should I use?",
        "report" => {},
        "location_source" => "missing"
      }
    end

    def units
      value = @env.fetch("SOUL_WEATHER_UNITS", "fahrenheit").to_s.downcase
      value == "celsius" ? "celsius" : "fahrenheit"
    end

    def render_brief(report)
      current = report.fetch("current", {})
      parts = [
        "#{current["condition"] || "Conditions unavailable"}",
        format_temperature(current),
        ("humidity #{current["humidity_percent"].round}%" if current["humidity_percent"]),
        format_wind(current),
        format_air_quality(current["air_quality"])
      ].compact

      "In #{current["location"] || report.dig("resolved_location", "name")}: #{parts.join(", ")}. Want the 3-day outlook?"
    end

    def render_detailed(report)
      current = report.fetch("current", {})
      lines = [render_brief(report).sub(/ Want the 3-day outlook\?\z/, "")]
      Array(report.dig("detailed_report", "outlook_days")).first(3).each do |day|
        lines << [
          day["date"],
          day["condition"],
          ("high #{format_temperature_value(day["high"])}" if day["high"]),
          ("low #{format_temperature_value(day["low"])}" if day["low"]),
          ("precipitation #{day["precipitation_probability_percent"].round}%" if day["precipitation_probability_percent"]),
          ("wind up to #{format_wind_speed(day["max_wind_speed"])}" if day["max_wind_speed"])
        ].compact.join(" — ")
      end
      lines.join("\n")
    end

    def format_temperature(current)
      value = current["temperature"]
      value.nil? ? nil : format_temperature_value(value)
    end

    def format_temperature_value(value)
      suffix = units == "celsius" ? "°C" : "°F"
      "#{value.to_f.round}#{suffix}"
    end

    def format_wind(current)
      speed = current["wind_speed"]
      return nil if speed.nil?

      direction = cardinal_direction(current["wind_direction_degrees"])
      "wind #{format_wind_speed(speed)}#{direction ? " from #{direction}" : ""}"
    end

    def format_wind_speed(value)
      "#{value.to_f.round(1)} #{units == "celsius" ? "km/h" : "mph"}"
    end

    def cardinal_direction(degrees)
      return nil if degrees.nil?

      CARDINAL_DIRECTIONS[((degrees.to_f + 22.5) / 45).floor % 8]
    end

    def format_air_quality(value)
      air = value.is_a?(Hash) ? value : {}
      return nil unless air["us_aqi"]

      "air quality #{air["us_aqi"].to_f.round} US AQI (#{air["category"]})"
    end
  end
end
