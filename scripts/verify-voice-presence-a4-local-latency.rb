#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "fileutils"
require "securerandom"
require "tmpdir"
require_relative "../lib/soul_core/application_chat_service"
require_relative "../lib/soul_core/chat_store"
require_relative "../lib/soul_core/voice_presence_turn_policy"
require_relative "../lib/soul_core/voice_conversation_inference_policy"

ROOT = File.expand_path("..", __dir__)
failures = []
check = lambda do |label, condition|
  failures << label unless condition
end

policy = SoulCore::VoicePresenceTurnPolicy.new
%w[repeat\ that say\ that\ again].each do |phrase|
  check.call("exact replay intent #{phrase}", policy.repeat_request?(phrase))
end

inference_policy = SoulCore::VoiceConversationInferencePolicy.new
responsive = inference_policy.decide(
  interface: "voice_presence", message: "How are you today?",
  provider_supports_reasoning_control: true, default_max_output_tokens: 1_024
)
deliberate = inference_policy.decide(
  interface: "voice_presence", message: "Think carefully and analyze in depth.",
  provider_supports_reasoning_control: true, default_max_output_tokens: 1_024
)
dashboard = inference_policy.decide(
  interface: "dashboard", message: "How are you today?",
  provider_supports_reasoning_control: true, default_max_output_tokens: 1_024
)
unsupported = inference_policy.decide(
  interface: "voice_presence", message: "How are you today?",
  provider_supports_reasoning_control: false, default_max_output_tokens: 1_024
)
check.call("ordinary voice disables hidden reasoning", responsive.reasoning_mode == "disabled")
check.call("ordinary voice has a spoken-response ceiling", responsive.max_output_tokens == 384)
check.call("explicit voice deliberation retains reasoning", deliberate.reasoning_mode == "default" && deliberate.max_output_tokens == 1_024)
check.call("Dashboard inference remains unchanged", dashboard.reasoning_mode == "default" && dashboard.max_output_tokens == 1_024)
check.call("unsupported providers fail open to their reviewed default", unsupported.reasoning_mode == "default")

Dir.mktmpdir("voice-interface-verifier-") do |root|
  store = SoulCore::ChatStore.new(root: root)
  chat = store.create_chat(initial_title: "Voice interface verifier")
  result_type = Struct.new(:content, :mode, :provider_id, :fallback_reason, :metadata, keyword_init: true)
  runtime = Class.new do
    attr_reader :received_interface

    define_method(:initialize) { |type| @type = type }
    define_method(:respond) do |chat_id:, message:, interface:, progress: nil|
      @received_interface = interface
      @type.new(content: "ready", mode: "model", provider_id: "fixture", metadata: {})
    end
  end.new(result_type)
  service = SoulCore::ApplicationChatService.new(root: root, store: store, runtime: runtime)
  service.send(
    chat_id: chat.fetch("id"), message: "Hello Soul", request_id: "voice-#{SecureRandom.uuid}",
    interface: "voice_presence"
  )
  check.call("application service preserves the voice interface", runtime.received_interface == "voice_presence")
end
[
  "Please repeat that.", "Could you repeat that please?", "Can you say that again?",
  "Would you repeat your last response please"
].each do |phrase|
  check.call("natural replay intent #{phrase}", policy.repeat_request?(phrase))
end
[
  "Repeat the system status", "Rephrase that", "Regenerate the voice",
  "Repeat that and then reboot", "What did you say?"
].each do |phrase|
  check.call("non-replay intent #{phrase}", !policy.repeat_request?(phrase))
end

manifest = JSON.parse(File.binread(File.join(ROOT, "config", "voice_presence_models.json"), 256 * 1024))
transcription_manifest = JSON.parse(File.binread(File.join(ROOT, "config", "music_transcription_models.json"), 256 * 1024))
check.call("wake boost is easier but bounded", manifest.dig("keyword", "boosting_score").to_f.between?(2.5, 4.0))
check.call("wake threshold is easier but bounded", manifest.dig("keyword", "trigger_threshold").to_f.between?(0.10, 0.24))
check.call("wake aliases remain exact and bounded", manifest.fetch("keyword_aliases").all? { |entry| entry.fetch("boosting_score").to_f.between?(2.5, 4.0) && entry.fetch("trigger_threshold").to_f.between?(0.10, 0.24) })
check.call("operator pronunciation variants remain exact and bounded", manifest.fetch("keyword_variants").all? { |entry| entry.fetch("boosting_score").to_f.between?(2.5, 4.0) && entry.fetch("trigger_threshold").to_f.between?(0.10, 0.24) && entry.fetch("symbol").match?(/\AHEY_(?:SOUL|SLASH)_[A-Z_]+\z/) })
check.call("wake cue delay covers the static cue", manifest.dig("capture", "post_wake_capture_delay_seconds").to_f.between?(0.16, 0.30))
check.call("trailing silence preserves natural mid-sentence pauses", manifest.dig("capture", "trailing_silence_seconds").to_f.between?(0.9, 1.1))
check.call("voice model is separately pinned", transcription_manifest.dig("models", "ggml-base.en.bin", "sha256") == "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002")
check.call("voice and music defaults remain separate", File.read(File.join(ROOT, "Makefile")).include?("MUSIC_TRANSCRIPTION_MODEL ?= ggml-small.en.bin") && File.read(File.join(ROOT, "Makefile")).include?("VOICE_TRANSCRIPTION_MODEL ?= ggml-base.en.bin"))

worker = File.read(File.join(ROOT, "scripts", "soul-voice-presence-worker.py"), encoding: "UTF-8")
bridge = File.read(File.join(ROOT, "scripts", "soul-voice-presence-bridge"), encoding: "UTF-8")
app = File.read(File.join(ROOT, "scripts", "soul-voice-presence-app.py"), encoding: "UTF-8")
synthesis_worker = File.read(File.join(ROOT, "scripts", "soul-voice-synthesis-worker.py"), encoding: "UTF-8")
application_chat = File.read(File.join(ROOT, "lib", "soul_core", "application_chat_service.rb"), encoding: "UTF-8")
conversation_runtime = File.read(File.join(ROOT, "lib", "soul_core", "conversation_runtime.rb"), encoding: "UTF-8")
check.call("capture emits content-free timing", worker.include?('timing=timing') && worker.include?('turn_started_monotonic=turn_started'))
check.call("bridge records bounded stage timings", %w[transcription_ms route_ms synthesis_ms audio_ready_ms].all? { |key| bridge.include?(key) })
check.call("repeat exits before chat and synthesis", bridge.index("if repeat_request") < bridge.index("facade = SoulCore::ApplicationFacade") && bridge.index("if repeat_request") < bridge.index("VoiceSynthesisService.new"))
check.call("repeat requires a private regular cached file", bridge.include?('File.file?(replay_path)') && bridge.include?('!File.symlink?(replay_path)'))
check.call("application preserves only latest response", app.include?('self.session / "last-response.wav"') && app.include?('for path in self.session.glob("utterance-*.wav")'))
check.call("application deletes private session on close", app.include?("shutil.rmtree(self.session, ignore_errors=True)"))
check.call("playback reports first-audio timing", app.include?("def playback_started") && app.include?("First audio"))
check.call("warm synthesis is a visible-app child", app.include?("def start_synthesis_worker") && app.include?("self.stop_synthesis_worker()"))
check.call("warm synthesis has no listener", !synthesis_worker.match?(/(?:import|from)\s+socket|socket\.socket|http\.server|WebSocket|EventSource|\.listen\(/i))
check.call("warm synthesis accepts one private output name", synthesis_worker.include?('path.name not in {"response.wav"}'))
check.call("warm synthesis removes partial output on failure", synthesis_worker.include?('output.unlink(missing_ok=True)'))
check.call("warm synthesis validates exact assets before ready", synthesis_worker.include?("validate_assets(model_dir, manifest)") && synthesis_worker.index("validate_assets(model_dir, manifest)") < synthesis_worker.index('emit(type="ready"'))
check.call("no web or cloud voice dependency", ![worker, bridge, app, synthesis_worker].any? { |source| source.match?(/WebSocket|EventSource|openai\.com|api_key/i) })
check.call("voice interface reaches the conversation runtime", application_chat.include?('runtime_options[:interface] = interface if runtime_accepts_interface?'))
check.call("voice inference policy reaches the provider request", conversation_runtime.include?('reasoning_mode: inference.reasoning_mode') && conversation_runtime.include?('max_output_tokens: inference.max_output_tokens'))

abort("Voice Presence A4 verification failed:\n- #{failures.join("\n- ")}") unless failures.empty?

puts JSON.pretty_generate(
  "lifecycle_state" => "complete",
  "deterministic_tests" => 40,
  "exact_replay_without_regeneration" => true,
  "latency_evidence_retained" => false,
  "cloud_voice_dependency" => false,
  "warm_synthesis_worker_implemented" => true,
  "warm_transcription_worker_implemented" => false
)
