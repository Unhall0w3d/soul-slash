#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/soul_core/conversation_orchestrator"
require_relative "../lib/soul_core/conversation_weather_service"
require_relative "../lib/soul_core/execution_adapter_registry"

class FakeWeatherRunner
  attr_reader :calls

  def initialize
    @calls = []
  end

  def run(name, args:)
    @calls << [name, args]
    detailed = args.include?("--detailed")
    {
      ok: true,
      json: {
        "verification" => { "weather_fetch_ok" => true },
        "resolved_location" => { "name" => "Testville, New York, US" },
        "current" => {
          "location" => "Testville, New York, US",
          "condition" => "Partly cloudy",
          "temperature" => 71.6,
          "humidity_percent" => 54,
          "wind_speed" => 8.4,
          "wind_direction_degrees" => 225,
          "air_quality" => { "us_aqi" => 32, "category" => "Good" }
        },
        "detailed_report" => detailed ? {
          "outlook_days" => [
            {
              "date" => "2026-07-24",
              "condition" => "Partly cloudy",
              "high" => 76,
              "low" => 61,
              "precipitation_probability_percent" => 10,
              "max_wind_speed" => 12
            }
          ]
        } : nil
      }
    }
  end
end

checks = {}
orchestrator = SoulCore::ConversationOrchestrator.new

weather = orchestrator.plan(message: "How is the weather today?", provider_available: true)
checks["natural weather question routes to existing skill"] =
  weather.kind == "skill_only" && weather.tool_ids == ["weather.report"]

conversation = orchestrator.plan(message: "I was thinking about the weather yesterday.", provider_available: true)
checks["weather mention remains conversation"] =
  conversation.kind == "direct_model" && conversation.tool_ids.empty?

runner = FakeWeatherRunner.new
service = SoulCore::ConversationWeatherService.new(
  env: {
    "SOUL_WEATHER_LOCATION" => "Testville, NY",
    "SOUL_WEATHER_UNITS" => "fahrenheit"
  },
  runner: runner
)

brief = service.report(message: "How is the weather today?")
checks["configured home runs without confirmation"] =
  brief["ok"] &&
  runner.calls.first == [
    "weather.report",
    ["--location", "Testville, NY", "--units", "fahrenheit"]
  ]
checks["brief includes requested conversational facts"] =
  brief["content"].include?("Partly cloudy") &&
  brief["content"].include?("72°F") &&
  brief["content"].include?("wind 8.4 mph from SW") &&
  brief["content"].include?("Want the 3-day outlook?")

detailed = service.report(message: "Show the 3-day outlook for London, UK")
checks["explicit detailed location is bounded and forwarded"] =
  detailed["ok"] &&
  runner.calls.last == [
    "weather.report",
    ["--location", "London, UK", "--units", "fahrenheit", "--detailed"]
  ] &&
  detailed["content"].include?("2026-07-24")

followup = service.report(
  message: "yes",
  force_detailed: true,
  location_override: "London, UK"
)
checks["affirmative followup retains location and requests detail"] =
  followup["ok"] &&
  runner.calls.last == [
    "weather.report",
    ["--location", "London, UK", "--units", "fahrenheit", "--detailed"]
  ]

weather_evidence = [{
  "evidence_profile" => "weather_report",
  "status" => "ok",
  "evidence_id" => "ev_weather"
}]
followup_plan = orchestrator.plan(
  message: "yes",
  provider_available: true,
  recent_evidence: weather_evidence
)
checks["plain yes continues offered weather outlook"] =
  followup_plan.kind == "skill_only" &&
  followup_plan.tool_ids == ["weather.report"] &&
  followup_plan.flags["weather_detail_followup"] == true

transcribed_followup = orchestrator.plan(
  message: "- Yeah.",
  provider_available: true,
  recent_evidence: weather_evidence
)
checks["harmless STT bullet prefix still continues offered weather outlook"] =
  transcribed_followup.kind == "skill_only" &&
  transcribed_followup.tool_ids == ["weather.report"] &&
  transcribed_followup.flags["weather_detail_followup"] == true

missing = SoulCore::ConversationWeatherService.new(env: {}, runner: runner).report(message: "How is the weather?")
checks["missing location awaits input"] =
  missing["lifecycle_state"] == "awaiting_input" &&
  missing["content"].include?("Which city")

adapter = SoulCore::ExecutionAdapterRegistry.new.find("weather.report")
checks["weather execution adapter is enabled and read only"] =
  adapter&.enabled? && adapter.risk == "read_only" && adapter.command?

failed = checks.reject { |_name, passed| passed }
checks.each { |name, passed| puts "#{passed ? 'PASS' : 'FAIL'}: #{name}" }
abort "#{failed.length} weather routing checks failed" unless failed.empty?

puts "Conversation weather routing verification passed (#{checks.length} checks)."
