#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/bounded_command_runner"
require_relative "../lib/soul_core/speech_presentation_service"
require_relative "../lib/soul_core/voice_synthesis_service"

def check(label, condition)
  raise "FAIL: #{label}" unless condition

  puts "PASS: #{label}"
end

class WeatherSpeechFixtureRunner
  attr_reader :inputs, :speeds

  def initialize
    @inputs = []
    @speeds = []
  end

  def run(*command, **_options)
    argv = command.flatten.map(&:to_s)
    input = argv.fetch(argv.index("--input") + 1)
    output = argv.fetch(argv.index("--output") + 1)
    @inputs << File.read(input)
    @speeds << Float(argv.fetch(argv.index("--speed") + 1))
    File.binwrite(output, "RIFF" + ("\0" * 4) + "WAVE" + ("\0" * 64))
    SoulCore::BoundedCommandRunner::Result.new(
      stdout: "", stderr: "", exit_status: 0, status: "ok", truncated: false
    )
  end
end

presentation = SoulCore::SpeechPresentationService.new
weather = presentation.prepare(
  "In Syracuse, New York, US: Mainly clear, 84°F, humidity 42%, wind 2.7 mph from SW, air quality 57 US AQI (Moderate). Want the 3-day outlook?",
  context: "weather_report"
)
check("weather facts become measured spoken sentences", weather["text"].include?("Mainly clear. 84 degrees Fahrenheit. humidity 42 percent."))
check("decimal wind speed remains intact", weather["text"].include?("2.7 miles per hour"))
check("compass and AQI abbreviations become pronounceable", weather["text"].include?("from southwest") && weather["text"].include?("U S air quality index"))
check("weather offer is spoken naturally", weather["text"].end_with?("Would you like the three-day outlook?"))
check("weather uses a modestly slower bounded rate", weather["speed_factor"] == 0.9)
check("general prose is not weather-rewritten", presentation.prepare("A short response.")["text"] == "A short response.")
begin
  presentation.prepare("No.", context: "invented")
  raise "FAIL: unknown speech context fails closed"
rescue ArgumentError
  puts "PASS: unknown speech context fails closed"
end

Dir.mktmpdir("soul-weather-speech-") do |root|
  runtime_root = File.join(root, "runtime")
  python = File.join(runtime_root, ".venv", "bin", "python")
  FileUtils.mkdir_p(File.dirname(python))
  File.write(python, "#!/bin/sh\nexit 0\n")
  File.chmod(0o700, python)
  model_dir = File.join(runtime_root, "supertonic-3")
  asset = File.join(model_dir, "onnx", "fixture.onnx")
  FileUtils.mkdir_p(File.dirname(asset))
  File.binwrite(asset, "fixture-model")
  manifest = File.join(root, "manifest.json")
  File.write(manifest, JSON.generate({
    "schema_version" => "soul.voice_synthesis.models.v1",
    "runtime" => { "name" => "Supertonic", "release" => "3", "package_version" => "1.3.1", "revision" => "fixture", "cpu_only" => true },
    "defaults" => { "voice" => "F3", "language" => "en", "steps" => 10, "speed" => 1.0 },
    "voices" => { "F3" => {} },
    "assets" => { "onnx/fixture.onnx" => Digest::SHA256.file(asset).hexdigest }
  }))
  runner = WeatherSpeechFixtureRunner.new
  service = SoulCore::VoiceSynthesisService.new(
    root: File.expand_path("..", __dir__), runtime_root: runtime_root,
    manifest_path: manifest, runner: runner
  )
  result = service.synthesize(
    text: "In Testville: Cloudy, 71°F, wind 8.4 mph from W.",
    speech_context: "weather_report"
  )
  check("responsive synthesis receives weather-safe prose", result["ok"] && runner.inputs.last.include?("71 degrees Fahrenheit"))
  check("responsive runner receives weather rate", runner.speeds.last == 0.9 && result["speed"] == 0.9)
end

dashboard = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
bridge = File.read(File.expand_path("soul-voice-presence-bridge", __dir__))
check("dashboard derives speech context from actual weather tool metadata", dashboard.include?("speechContextForMessage") && dashboard.include?('toolIds.includes("weather.report")'))
check("Voice Presence derives speech context from actual weather tool metadata", bridge.include?('tool_ids.include?("weather.report")'))

puts "Weather speech presentation A1 verification complete."
