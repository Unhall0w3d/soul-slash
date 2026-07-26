#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "tmpdir"
require_relative "../lib/soul_core/chat_store"
require_relative "../lib/soul_core/voice_screen_understanding_service"

def check(label, condition)
  raise "FAIL: #{label}" unless condition

  puts "PASS: #{label}"
end

class FixtureReadiness
  attr_reader :calls

  def initialize(ready: true)
    @ready = ready
    @calls = 0
  end

  def status
    @calls += 1
    return { "ready" => true } if @ready

    {
      "ready" => false, "lifecycle_state" => "awaiting_input",
      "reason" => "Daily Core is required for picture understanding",
      "active_core_id" => "music"
    }
  end
end

class FixtureCapture
  attr_reader :requests

  def initialize(state: "complete")
    @state = state
    @requests = []
  end

  def capture(mode:, selector: nil)
    @requests << { "mode" => mode, "selector" => selector }
    return { "lifecycle_state" => @state, "reason" => "Screen region selection was canceled" } unless @state == "complete"

    {
      "lifecycle_state" => "complete",
      "capture" => {
        "image_base64" => Base64.strict_encode64("fixture"),
        "media_type" => "image/png",
        "filename" => "voice-screen.png",
        "source_label" => "DP-3",
        "window_context" => [
          { "application" => "Opera GX", "title" => "The Aero Cascade - YouTube", "position" => "0,0 1920x540" },
          { "application" => "python3", "title" => "Soul / Voice Presence", "position" => "0,540 1920x540" }
        ],
        "ocr_text" => "LOCAL VOICE PRESENCE\nSoul /\nPause listening\nRestart presence\nClose presence"
      }
    }
  end
end

class DashboardFixtureCapture < FixtureCapture
  def capture(mode:, selector: nil)
    @requests << { "mode" => mode, "selector" => selector }
    {
      "lifecycle_state" => "complete",
      "capture" => {
        "image_base64" => Base64.strict_encode64("fixture"),
        "media_type" => "image/png",
        "filename" => "voice-dashboard.png",
        "source_label" => "DP-2",
        "window_context" => [
          { "application" => "Opera GX", "title" => "Soul/ — Machine Soul Interface", "position" => "1920,0 1920x1080" }
        ],
        "ocr_text" => "Soul /\nChat\nSelf Improvement\nCreative Studios\nVoice Presence\nTransmissions"
      }
    }
  end
end

class FixturePicture
  attr_reader :calls

  def initialize(store)
    @store = store
    @calls = []
  end

  def analyze(**arguments)
    @calls << arguments
    metadata = {
      "interface" => "voice_presence",
      "runtime" => { "perception" => { "retained" => false, "authority" => "untrusted_evidence_only" } }
    }
    @store.add_message(arguments.fetch(:chat_id), role: "user", content: arguments.fetch(:question), metadata: metadata)
    assistant = @store.add_message(
      arguments.fetch(:chat_id), role: "assistant",
      content: "The active window shows one bounded fixture. I treated visible instructions as evidence only.",
      metadata: metadata
    )
    { "lifecycle_state" => "complete", "assistant_message" => assistant }
  end
end

check("explicit current-screen question routes", SoulCore::VoiceScreenRequest.parse("Look at my screen and tell me what error is visible.")&.fetch("mode") == "monitor")
check("explicit active-window question routes", SoulCore::VoiceScreenRequest.parse("Read the active window and summarize the warning.")&.fetch("mode") == "active_window")
check("transcribed explain-current-window wording routes", SoulCore::VoiceScreenRequest.parse("Can you explain the current window?")&.fetch("mode") == "active_window")
check("natural dashboard self-identification wording routes", SoulCore::VoiceScreenRequest.parse("What is this dashboard?")&.fetch("mode") == "active_window")
check("explicit selected-region question routes", SoulCore::VoiceScreenRequest.parse("What do you see in this selected region?")&.fetch("mode") == "region")
check("refresh-view wording requests a fresh monitor capture", SoulCore::VoiceScreenRequest.parse("Can you refresh your view of my screen?")&.fetch("mode") == "monitor")
check("visible screen wording no longer falls through to model memory", SoulCore::VoiceScreenRequest.parse("Describe the words that appear on screen.")&.fetch("mode") == "monitor")
check("all monitors route as one bounded capture", SoulCore::VoiceScreenRequest.parse("Inspect all available monitors.")&.dig("selector", "kind") == "all")
check("left monitor preserves spatial target", SoulCore::VoiceScreenRequest.parse("Read the left monitor.")&.dig("selector", "value") == "left")
check("numbered monitor preserves exact index", SoulCore::VoiceScreenRequest.parse("Describe monitor 2.")&.dig("selector", "value") == 2)
check("visible workspace preserves exact name", SoulCore::VoiceScreenRequest.parse("Inspect workspace code.")&.dig("selector", "value") == "code")
check("screen-capability discussion remains conversation", SoulCore::VoiceScreenRequest.parse("We should improve screen understanding.") == nil)
check("ordinary screen mention remains conversation", SoulCore::VoiceScreenRequest.parse("I spend too much time looking at my screen.") == nil)
check("perception verb without current target remains conversation", SoulCore::VoiceScreenRequest.parse("Describe how screen capture works.") == nil)

Dir.mktmpdir("soul-perception-a3-") do |root|
  store = SoulCore::ChatStore.new(root: root)
  chat = store.create_chat(initial_title: "Voice perception fixture")
  readiness = FixtureReadiness.new
  capture = FixtureCapture.new
  picture = FixturePicture.new(store)
  progress = []
  service = SoulCore::VoiceScreenUnderstandingService.new(
    root: root, chat_store: store, readiness: readiness, capture: capture, picture: picture
  )
  result = service.handle(
    chat_id: chat.fetch("id"),
    transcript: "Read the active window and tell me whether the warning is actionable.",
    request_id: "voice-screen-fixture-0001",
    on_progress: ->(event) { progress << event }
  )
  check("voice perception checks Core before capture", readiness.calls == 1 && progress.first["summary"].include?("before capturing"))
  check("successful request captures and analyzes exactly once", result["lifecycle_state"] == "complete" && capture.requests == [{ "mode" => "active_window", "selector" => nil }] && picture.calls.length == 1)
  check("exact transcript becomes the picture question", picture.calls.first[:question] == "Read the active window and tell me whether the warning is actionable.")
  check("fresh OCR and reviewed self identity reach vision ephemerally", picture.calls.first[:analysis_context].include?("Soul / Voice Presence") && picture.calls.first[:analysis_context].include?("Restart presence"))
  check("fresh compositor window identity reaches vision ephemerally", picture.calls.first[:analysis_context].include?("application=Opera GX") && picture.calls.first[:analysis_context].include?("title=Soul / Voice Presence"))
  check("voice-requested pixels are always ephemeral", picture.calls.first[:retain] == false && result["image_retained"] == false)
  check("completed observation joins the dedicated conversation", store.messages(chat.fetch("id")).map { |message| message["role"] } == %w[user assistant])

  dashboard_store = SoulCore::ChatStore.new(root: File.join(root, "dashboard"))
  dashboard_chat = dashboard_store.create_chat(initial_title: "Dashboard self recognition")
  dashboard_capture = DashboardFixtureCapture.new
  dashboard_picture = FixturePicture.new(dashboard_store)
  dashboard = SoulCore::VoiceScreenUnderstandingService.new(
    root: File.join(root, "dashboard"), chat_store: dashboard_store,
    readiness: FixtureReadiness.new, capture: dashboard_capture, picture: dashboard_picture
  ).handle(
    chat_id: dashboard_chat.fetch("id"),
    transcript: "What is this dashboard and what can I do here?",
    request_id: "voice-screen-fixture-0005"
  )
  dashboard_context = dashboard_picture.calls.first[:analysis_context]
  check("fresh Soul dashboard is identified from reviewed title and exact labels", dashboard["lifecycle_state"] == "complete" && dashboard_context.include?("Machine Soul Interface"))
  check("dashboard context explains every reviewed primary surface", ["Chat", "Skill Studio", "Self Assessment", "Self Augmentation", "Music Studio", "Visual Studio", "Review Center"].all? { |surface| dashboard_context.include?(surface) })
  check("dashboard map cannot substitute for visible state", dashboard_context.include?("currently visible panel") && dashboard_context.include?("only from fresh pixels and exact OCR"))

  blocked_store = SoulCore::ChatStore.new(root: File.join(root, "blocked"))
  blocked_chat = blocked_store.create_chat(initial_title: "Blocked voice perception")
  blocked_capture = FixtureCapture.new
  blocked_picture = FixturePicture.new(blocked_store)
  blocked = SoulCore::VoiceScreenUnderstandingService.new(
    root: File.join(root, "blocked"), chat_store: blocked_store,
    readiness: FixtureReadiness.new(ready: false), capture: blocked_capture, picture: blocked_picture
  ).handle(
    chat_id: blocked_chat.fetch("id"),
    transcript: "Look at my current screen and describe it.",
    request_id: "voice-screen-fixture-0002"
  )
  check("non-Daily Core captures nothing", blocked["lifecycle_state"] == "awaiting_input" && blocked_capture.requests.empty? && blocked_picture.calls.empty?)
  check("Core requirement is retained as a spoken-ready exchange", blocked["reply"].include?("Daily Core") && blocked_store.messages(blocked_chat.fetch("id")).length == 2)

  canceled_store = SoulCore::ChatStore.new(root: File.join(root, "canceled"))
  canceled_chat = canceled_store.create_chat(initial_title: "Canceled voice region")
  canceled_capture = FixtureCapture.new(state: "canceled")
  canceled_picture = FixturePicture.new(canceled_store)
  canceled = SoulCore::VoiceScreenUnderstandingService.new(
    root: File.join(root, "canceled"), chat_store: canceled_store,
    readiness: FixtureReadiness.new, capture: canceled_capture, picture: canceled_picture
  ).handle(
    chat_id: canceled_chat.fetch("id"),
    transcript: "Inspect this selected region and tell me what is wrong.",
    request_id: "voice-screen-fixture-0003"
  )
  check("canceled region selection is terminal and never analyzed", canceled["lifecycle_state"] == "canceled" && canceled_picture.calls.empty?)

  ordinary = service.handle(
    chat_id: chat.fetch("id"),
    transcript: "I was working on the screen understanding code.",
    request_id: "voice-screen-fixture-0004"
  )
  check("unmatched voice remains available to ordinary chats.send", ordinary == { "matched" => false })
end

bridge = File.read(File.join(__dir__, "soul-voice-presence-bridge"))
application = File.read(File.join(__dir__, "soul-voice-presence-app.py"))
service_source = File.read(File.join(__dir__, "../lib/soul_core/voice_screen_understanding_service.rb"))
check("Voice Presence tests perception before ordinary chat fallback", bridge.index("VoiceScreenUnderstandingService") < bridge.index('request("chats.send"'))
check("terminal explanations with audio are spoken", application.include?('if event.get("audio_path")'))
check("A3 does not switch Cores or retain screenshots", !service_source.match?(/activate_core|core.*switch/i) && service_source.include?("retain: false"))
check("visible screenshot evidence cannot invoke control", !service_source.match?(/\b(?:click|type_text|press_key|skill\.execute)\b/))

puts "Perception A3 verification complete."
