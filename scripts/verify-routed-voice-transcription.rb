#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "tmpdir"
require_relative "../lib/soul_core/routed_voice_transcription_service"

errors = []
check = lambda do |name, condition|
  puts "#{condition ? 'PASS' : 'FAIL'}: #{name}"
  errors << name unless condition
end

class RoutedVoiceFixtureCoordinator
  attr_accessor :blocker
  attr_reader :status_calls

  def initialize(blocker: nil)
    @blocker = blocker
    @status_calls = 0
  end

  def status_blocker
    @status_calls += 1
    @blocker
  end
end

class RoutedVoiceFixtureAdapter
  attr_accessor :status_result, :transcribe_result
  attr_reader :status_calls, :transcribe_calls

  def initialize(status_result:, transcribe_result:)
    @status_result = status_result
    @transcribe_result = transcribe_result
    @status_calls = 0
    @transcribe_calls = []
  end

  def status
    @status_calls += 1
    @status_result
  end

  def transcribe(audio_bytes:, content_type:)
    @transcribe_calls << { audio_bytes: audio_bytes, content_type: content_type }
    @transcribe_result
  end
end

def envelope(state:, ok:, message:, data: {})
  {
    "schema_version" => "soul.application.v1",
    "lifecycle_state" => state,
    "mutation" => "none",
    "ok" => ok,
    "data" => data.merge("message" => message),
    "errors" => ok ? [] : [{ "code" => "voice_transcription", "message" => message }]
  }
end

Dir.mktmpdir("soul-routed-voice-test-") do |root|
  complete_status = envelope(
    state: "complete", ok: true, message: "AMD transcription is ready",
    data: { "available" => true, "runtime" => { "vulkan" => true } }
  )
  complete_transcription = envelope(
    state: "complete", ok: true, message: "transcription is ready for Operator review",
    data: { "transcript" => "Move the fixture to Trash.", "automatically_sent" => false }
  )
  failed_transcription = envelope(
    state: "failed", ok: false, message: "AMD recovery failed; transcript withheld",
    data: { "source_audio_retained" => false, "automatically_sent" => false }
  )

  coordinator = RoutedVoiceFixtureCoordinator.new(blocker: "Free Core disables transcription; select a chat Core first")
  adapter = RoutedVoiceFixtureAdapter.new(status_result: complete_status, transcribe_result: complete_transcription)
  service = SoulCore::RoutedVoiceTranscriptionService.new(root: root, process_env: {}, coordinator: coordinator, adapter: adapter)

  blocked_status = service.status
  check.call(
    "Free Core status is blocked before adapter access",
    blocked_status["lifecycle_state"] == "blocked_for_human_review" &&
      blocked_status["ok"] == false &&
      blocked_status.dig("data", "available") == false &&
      blocked_status.dig("data", "cpu_fallback") == false &&
      adapter.status_calls.zero?
  )
  blocked_transcription = service.transcribe(audio_bytes: "private-audio".b, content_type: "audio/wav")
  check.call(
    "Free Core transcription is blocked without adapter access or mutation",
    blocked_transcription["reason"] == coordinator.blocker &&
      blocked_transcription["mutation"] == "none" &&
      blocked_transcription.dig("data", "source_audio_retained") == false &&
      adapter.transcribe_calls.empty?
  )

  [
    "runtime control is busy",
    "Core selection cannot be verified: unknown persisted selection"
  ].each do |problem|
    coordinator.blocker = problem
    refused = service.transcribe(audio_bytes: "busy-or-unknown".b, content_type: "audio/wav")
    check.call(
      "#{problem} is refused before adapter access",
      refused["lifecycle_state"] == "blocked_for_human_review" &&
        refused["reason"] == problem &&
        refused.dig("data", "cpu_fallback") == false &&
        adapter.transcribe_calls.empty?
    )
  end

  coordinator.blocker = nil
  forwarded_status = service.status
  forwarded_transcription = service.transcribe(audio_bytes: "bounded-audio".b, content_type: "audio/webm;codecs=opus")
  check.call("clear policy forwards status to the injected adapter", forwarded_status.equal?(complete_status) && adapter.status_calls == 1)
  check.call(
    "clear policy forwards exact audio arguments and preserves adapter result",
    forwarded_transcription.equal?(complete_transcription) &&
      adapter.transcribe_calls == [{ audio_bytes: "bounded-audio".b, content_type: "audio/webm;codecs=opus" }]
  )

  calls_before_policy_change = adapter.transcribe_calls.length
  coordinator.blocker = "Free Core disables transcription; select a chat Core first"
  changed_policy = service.transcribe(audio_bytes: "policy-changed".b, content_type: "audio/wav")
  check.call(
    "a policy change between calls is rechecked and blocks the next request",
    changed_policy["lifecycle_state"] == "blocked_for_human_review" &&
      adapter.transcribe_calls.length == calls_before_policy_change
  )

  coordinator.blocker = nil
  adapter.transcribe_result = failed_transcription
  failed = service.transcribe(audio_bytes: "adapter-failure".b, content_type: "audio/wav")
  check.call(
    "failed adapter responses are preserved without router rewriting",
    failed.equal?(failed_transcription) &&
      failed["lifecycle_state"] == "failed" &&
      failed.dig("data", "message") == "AMD recovery failed; transcript withheld" &&
      failed["mutation"] == "none"
  )
  check.call("every routed request rechecks coordinator policy", coordinator.status_calls == 8)
end

production_entrypoints = {
  "Dashboard command" => "lib/soul_core/dashboard_command.rb",
  "Dashboard HTTP application" => "lib/soul_core/dashboard_http_application.rb",
  "Voice Presence bridge" => "scripts/soul-voice-presence-bridge",
  "standalone voice transcription check" => "scripts/soul-voice-transcription"
}

legacy_constructor = /(?:^|::)(?:VoiceTranscriptionService|CudaVoiceTranscriptionService|AmdVoiceTranscriptionService)\.new/
production_entrypoints.each do |label, relative_path|
  source = File.read(File.expand_path("../#{relative_path}", __dir__))
  check.call("#{label} uses shared routed transcription", source.include?("RoutedVoiceTranscriptionService"))
  check.call("#{label} has no direct CPU/CUDA/AMD transcription constructor", !source.match?(legacy_constructor))
  check.call("#{label} has no legacy transcription backend selector", !source.include?("SOUL_VOICE_TRANSCRIPTION_BACKEND"))
end

abort "Routed voice transcription verification failed: #{errors.join(', ')}" unless errors.empty?
puts "Routed voice transcription verification passed."
