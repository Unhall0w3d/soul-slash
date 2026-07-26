# frozen_string_literal: true

require "securerandom"
require_relative "chat_store"
require_relative "picture_understanding_service"
require_relative "screen_capture_service"

module SoulCore
  class VoiceScreenRequest
    INTENT = /
      \b(?:look\s+at|inspect|analy[sz]e|check|examine|describe|explain|identify|interpret|read|review|scan|summari[sz]e|view)\b |
      \b(?:tell|show)\s+me\b.{0,40}\b(?:screen|window|monitor|display|workspace)\b |
      \b(?:refresh|update)\s+(?:your\s+)?(?:view|screen|display)\b |
      \bwhat(?:'s|\s+is)\s+on\b |
      \bwhat(?:'s|\s+is)\s+(?:happening|showing|displayed|visible)\b |
      \bwhat(?:'s|\s+is)\s+this\s+dashboard\b |
      \bwhat\s+am\s+i\s+look(?:ing)?\s+at\b |
      \bwhat\s+do\s+you\s+see\b |
      \bwhat\b.{0,30}\byou\s+(?:can\s+)?see\b |
      \b(?:can|could|would)\s+you\s+see\b
    /ix
    CAPABILITY_DISCUSSION = /\b(?:how|why)\b.{0,80}\b(?:screen|window|monitor|display)\b.{0,80}\b(?:works?|capabilit|understanding|code|implementation)\b/i

    def self.parse(text)
      value = text.to_s.strip
      return nil if value.empty? || !value.match?(INTENT)
      return nil if value.match?(CAPABILITY_DISCUSSION)

      mode, selector =
        if value.match?(/\bwhat(?:'s|\s+is)\s+this\s+dashboard\b/i) ||
            value.match?(/\bwhat\s+am\s+i\s+look(?:ing)?\s+at\b/i)
          ["active_window", nil]
        elsif value.match?(/\b(?:(?:selected|screen)\s+region|(?:selected|this)\s+area)\b/i)
          ["region", nil]
        elsif value.match?(/\b(?:(?:active|current|focused|this)\s+window|window\s+(?:under|beneath)\s+(?:my\s+)?(?:mouse|pointer|cursor)|window\s+on\s+my\s+screen)\b/i)
          ["active_window", nil]
        elsif value.match?(/\b(?:all|both|every)\s+(?:available\s+)?(?:screens?|monitors?|displays?)\b/i)
          ["monitor", { "kind" => "all" }]
        elsif (match = value.match(/\b(left|right)(?:[- ]hand)?\s+(?:screen|monitor|display)\b/i))
          ["monitor", { "kind" => "position", "value" => match[1].downcase }]
        elsif (match = value.match(/\b(?:screen|monitor|display)\s*(?:number\s*)?([1-9])\b/i))
          ["monitor", { "kind" => "index", "value" => Integer(match[1]) }]
        elsif (match = value.match(/\bworkspace\s+([A-Za-z0-9_.:-]{1,40})\b/i))
          ["monitor", { "kind" => "workspace", "value" => match[1] }]
        elsif value.match?(/\b(?:current|this|visible)\s+workspace\b/i)
          ["monitor", { "kind" => "current_workspace" }]
        elsif value.match?(/\b(?:my\s+|current\s+|this\s+|focused\s+)?(?:screen|monitor|display)\b/i)
          ["monitor", nil]
        end
      return nil unless mode

      { "mode" => mode, "selector" => selector, "question" => value }
    end
  end

  class VoiceScreenUnderstandingService
    DASHBOARD_MARKERS = [
      "Self Improvement",
      "Creative Studios",
      "Voice Presence",
      "Transmissions",
      "Skill Studio",
      "Self Assessment",
      "Self Augmentation",
      "Music Studio",
      "Visual Studio",
      "Review Center"
    ].freeze
    DASHBOARD_SURFACE_GUIDE = <<~TEXT.strip.freeze
      Reviewed local interface identity: this is Soul / — Machine Soul Interface,
      Soul's authenticated local dashboard.
      Reviewed dashboard map:
      - Chat is the conversational surface and transmission archive.
      - Self Improvement opens Skill Studio, Self Assessment, and Self Augmentation.
      - Skill Studio reviews capability proposals, Beta candidates, and production skills.
      - Self Assessment presents bounded host, runtime, and capability evidence.
      - Self Augmentation presents reviewed architectural proposals and experiments.
      - Creative Studios opens Music Studio and Visual Studio.
      - Music Studio manages composition briefs, generated candidates, listening evidence, revisions, and exports.
      - Visual Studio manages still and motion briefs, candidates, reviews, and music companions.
      - Review Center is a read-only view of pending approvals and recent bounded activity.
      - Core selects the reviewed runtime profile; Voice Presence opens the local hands-free voice surface.
      Use this map to explain the dashboard, but identify the currently visible panel and
      control state only from fresh pixels and exact OCR. Do not claim that a hidden menu,
      panel, project, approval, or action is currently visible merely because it exists in
      this reviewed map.
    TEXT

    def initialize(root: Dir.pwd, chat_store: nil, readiness: nil, capture: nil, picture: nil)
      @root = File.expand_path(root)
      @chat_store = chat_store || ChatStore.new(root: @root)
      @readiness = readiness || LocalVisionClient.new(root: @root)
      @capture = capture || ScreenCaptureService.new(root: @root)
      @picture = picture || PictureUnderstandingService.new(root: @root, chat_store: @chat_store)
    end

    def handle(chat_id:, transcript:, request_id: "voice-screen-#{SecureRandom.uuid}", on_progress: nil)
      parsed = VoiceScreenRequest.parse(transcript)
      return { "matched" => false } unless parsed
      raise ArgumentError, "unknown chat ID" unless @chat_store.chat(chat_id)

      emit(on_progress, "context", "Checking the local vision Core before capturing any pixels.")
      ready = @readiness.status
      unless ready["ready"]
        return terminal_exchange(
          chat_id: chat_id, transcript: transcript, state: ready.fetch("lifecycle_state", "awaiting_input"),
          reason: ready.fetch("reason", "Daily Core is required for screen understanding"),
          mode: parsed.fetch("mode")
        )
      end

      emit(on_progress, "capturing", capture_summary(parsed.fetch("mode")))
      captured = @capture.capture(mode: parsed.fetch("mode"), selector: parsed["selector"])
      unless captured["lifecycle_state"] == "complete"
        return terminal_exchange(
          chat_id: chat_id, transcript: transcript,
          state: captured.fetch("lifecycle_state", "failed"),
          reason: captured.fetch("reason", "Screen capture stopped safely"),
          mode: parsed.fetch("mode")
        )
      end

      image = captured.fetch("capture")
      emit(on_progress, "inspecting", "Gemma is inspecting one ephemeral voice-requested screenshot.")
      result = @picture.analyze(
        chat_id: chat_id,
        question: parsed.fetch("question"),
        analysis_context: analysis_context(image),
        image_base64: image.fetch("image_base64"),
        media_type: image.fetch("media_type"),
        filename: image.fetch("filename"),
        retain: false,
        response_policy: "fresh_screen",
        request_id: request_id,
        on_progress: on_progress
      )
      if result["lifecycle_state"] == "complete"
        {
          "matched" => true,
          "ok" => true,
          "lifecycle_state" => "complete",
          "reply" => result.dig("assistant_message", "content").to_s,
          "chat_id" => chat_id,
          "capture_scope" => parsed.fetch("mode"),
          "capture_selector" => parsed["selector"],
          "image_retained" => false
        }
      else
        terminal_exchange(
          chat_id: chat_id, transcript: transcript,
          state: result.fetch("lifecycle_state", "failed"),
          reason: result.fetch("reason", "Screen understanding stopped safely"),
          mode: parsed.fetch("mode")
        )
      end
    rescue ArgumentError => error
      {
        "matched" => true, "ok" => false, "lifecycle_state" => "failed",
        "reply" => error.message, "chat_id" => chat_id, "image_retained" => false
      }
    rescue StandardError => error
      terminal_exchange(
        chat_id: chat_id, transcript: transcript, state: "failed",
        reason: "Voice screen understanding failed safely: #{error.class}",
        mode: parsed&.fetch("mode", "unknown")
      )
    end

    private

    def terminal_exchange(chat_id:, transcript:, state:, reason:, mode:)
      metadata = {
        "interface" => "voice_presence",
        "mode" => "voice_screen_understanding",
        "runtime" => {
          "perception" => {
            "capture_scope" => mode,
            "retained" => false,
            "authority" => "untrusted_evidence_only",
            "lifecycle_state" => state
          }
        }
      }
      @chat_store.add_message(chat_id, role: "user", content: transcript.to_s.strip, metadata: metadata)
      assistant = @chat_store.add_message(chat_id, role: "assistant", content: reason.to_s, metadata: metadata)
      {
        "matched" => true,
        "ok" => false,
        "lifecycle_state" => state,
        "reply" => assistant.fetch("content"),
        "chat_id" => chat_id,
        "capture_scope" => mode,
        "image_retained" => false
      }
    end

    def capture_summary(mode)
      case mode
      when "monitor" then "Capturing one current-monitor screenshot."
      when "active_window" then "Capturing one active-window screenshot."
      when "region" then "Waiting for one foreground screen-region selection."
      end
    end

    def analysis_context(image)
      lines = [
        "Fresh compositor source: #{image.fetch('source_label', 'screen capture')}",
        "Freshness requirement: describe only this capture. Do not use or repeat any prior conversation, archive item, earlier screen description, or remembered title.",
        "Literal interface labels, application names, channel names, media titles, and button names must be supported by the fresh OCR or compositor metadata below. Omit unsupported names instead of guessing."
      ]
      windows = Array(image["window_context"])
      unless windows.empty?
        lines << "Hyprland reports these visible windows in the captured target:"
        windows.each do |window|
          lines << "- position=#{window['position']} application=#{window['application']} title=#{window['title']}"
        end
        lines << "Use those positions to keep text and content associated with the correct window."
      end
      ocr = image["ocr_text"].to_s.strip
      unless ocr.empty?
        lines << "Bounded local OCR transcription:"
        lines << ocr
      end
      if ocr.match?(/\bLOCAL VOICE PRESENCE\b/i) && ocr.match?(/\bSoul\s*\//i)
        lines << "Reviewed local interface identity: this is Soul / Voice Presence."
        lines << "Its exact reviewed controls are Pause listening, Restart presence, and Close presence."
      elsif dashboard_visible?(ocr, windows)
        lines << DASHBOARD_SURFACE_GUIDE
      end
      lines.join("\n")
    end

    def dashboard_visible?(ocr, windows)
      titled = windows.any? do |window|
        window["title"].to_s.match?(/\bSoul\s*\/\s*(?:—|-)\s*Machine Soul Interface\b/i)
      end
      markers = DASHBOARD_MARKERS.count { |marker| ocr.match?(/\b#{Regexp.escape(marker)}\b/i) }
      soul_mark = ocr.match?(/\bSoul\s*\//i)
      titled || (soul_mark && markers >= 2)
    end

    def emit(callback, state, summary)
      callback&.call("state" => state, "summary" => summary)
    end
  end
end
