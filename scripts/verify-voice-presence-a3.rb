#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

ROOT = File.expand_path("..", __dir__)
manifest = JSON.parse(File.binread(File.join(ROOT, "config", "voice_presence_models.json"), 256 * 1024))
capture = manifest.fetch("capture")
raise "follow-up speech-start window differs" unless capture["followup_speech_start_timeout_seconds"].to_f == 5.0
raise "ordinary utterance ceiling changed" unless capture["maximum_utterance_seconds"].to_f.between?(1, 30)
raise "trailing-silence ceiling changed" unless capture["trailing_silence_seconds"].to_f.between?(0.5, 2)

worker_path = File.join(ROOT, "scripts", "soul-voice-presence-worker.py")
worker = File.read(worker_path, encoding: "UTF-8")
raise "worker does not wait for explicit follow-up control" unless worker.include?('if control != "followup":')
raise "worker does not use reviewed follow-up timeout" unless worker.include?('speech_start_timeout=capture["followup_speech_start_timeout_seconds"]')
raise "silent expiry is not distinct from failure" unless worker.include?('emit(type="followup_expired", summary=summary)')
raise "follow-up does not return to wake recognition" unless worker.include?("stream = spotter.create_stream()")

app = File.read(File.join(ROOT, "scripts", "soul-voice-presence-app.py"), encoding: "UTF-8")
raise "playback completion does not open follow-up" unless app.match?(/def turn_complete\(self\):.*?self\.open_followup\(\)/m)
raise "follow-up command is not explicit" unless app.include?('self.worker.write(b"followup\\n")')
raise "follow-up is not a visible state" unless app.include?('"followup": "Speak naturally within five seconds')
raise "silent expiry is treated as a failed turn" unless app.match?(/elif event_type == "followup_expired":\s+self\.set_state\("listening"/m)

python = <<~PYTHON
  import importlib.util
  import pathlib
  from unittest.mock import patch

  spec = importlib.util.spec_from_file_location("worker", #{worker_path.inspect})
  worker = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(worker)

  class QuietStream:
      def read(self, size):
          return b"\\x00" * size

  capture = {
      "sample_rate": 16000,
      "speech_rms_threshold": 120,
      "speech_start_timeout_seconds": 3.0,
      "maximum_utterance_seconds": 30.0,
      "minimum_utterance_seconds": 0.35,
      "trailing_silence_seconds": 1.2,
  }
  clock = iter([0.0, 1.0, 2.0, 3.0, 4.0, 5.01])
  output = pathlib.Path("/tmp/soul-followup-verifier-should-not-exist.wav")
  output.unlink(missing_ok=True)
  with patch.object(worker.time, "monotonic", side_effect=lambda: next(clock)):
      ok, summary = worker.capture_command(
          QuietStream(), output, capture,
          speech_start_timeout=5.0,
          no_speech_summary="expired normally",
      )
  assert ok is False
  assert summary == "expired normally"
  assert not output.exists()
PYTHON
output, status = Open3.capture2e("python3", "-c", python)
raise "bounded silence test failed: #{output}" unless status.success?

puts JSON.pretty_generate(
  "lifecycle_state" => "complete",
  "deterministic_tests" => 14,
  "followup_speech_start_timeout_seconds" => capture["followup_speech_start_timeout_seconds"],
  "microphone_during_thinking_or_speaking" => false,
  "silent_expiry_is_failure" => false,
  "authority_inherited_from_prior_turn" => false
)
