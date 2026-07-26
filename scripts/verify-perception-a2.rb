#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/dashboard_http_application"
require_relative "../lib/soul_core/screen_capture_service"

def check(label, condition)
  raise "FAIL: #{label}" unless condition

  puts "PASS: #{label}"
end

def png(width: 320, height: 180)
  "\x89PNG\r\n\x1A\n".b + [13].pack("N") + "IHDR" + [width, height].pack("NN") + ("\0".b * 16)
end

class FixtureScreenRunner
  Result = SoulCore::ScreenCaptureCommandRunner::Result
  attr_reader :calls

  def initialize(responses: {}, image: png)
    @responses = responses.transform_values { |records| Array(records).dup }
    @image = image
    @calls = []
  end

  def call(arguments, timeout_seconds:)
    @calls << { arguments: arguments, timeout_seconds: timeout_seconds }
    key = arguments.first
    if key == "grim"
      File.binwrite(arguments.last, @image)
      return Result.new(stdout: "", stderr: "", exitstatus: 0)
    end

    response = @responses.fetch(key).shift
    raise response if response.is_a?(Exception)

    Result.new(stdout: response.fetch(:stdout, ""), stderr: response.fetch(:stderr, ""), exitstatus: response.fetch(:exitstatus, 0))
  end
end

class FixtureAuthentication
  def session(_token) = { "password_change_required" => false }
end

class FixtureScreenService
  attr_reader :modes

  def initialize
    @modes = []
  end

  def capture(mode:, selector: nil)
    @modes << [mode, selector]
    {
      "ok" => true, "lifecycle_state" => "complete",
      "capture" => {
        "filename" => "fixture.png", "media_type" => "image/png",
        "image_base64" => Base64.strict_encode64(png), "bytes" => png.bytesize,
        "width" => 320, "height" => 180, "scope" => mode,
        "source_label" => "fixture", "authority" => "untrusted_evidence_only"
      }
    }
  end
end

Dir.mktmpdir("soul-perception-a2-") do |root|
  state_root = File.join(root, "private-screen")
  monitor_runner = FixtureScreenRunner.new(
    responses: {
      "hyprctl" => [{
        stdout: JSON.generate([
          { "name" => "DP-1", "description" => "Primary", "focused" => true },
          { "name" => "DP-3", "description" => "Secondary", "focused" => false }
        ])
      }]
    }
  )
  monitor = SoulCore::ScreenCaptureService.new(root: root, runner: monitor_runner, state_root: state_root).capture(mode: "monitor")
  check("focused monitor resolves to one exact grim output", monitor["lifecycle_state"] == "complete" && monitor_runner.calls[1][:arguments][0, 3] == ["grim", "-o", "DP-1"])
  check("monitor preview is bounded local evidence", monitor.dig("capture", "width") == 320 && monitor.dig("capture", "authority") == "untrusted_evidence_only")
  check("monitor staging is removed before return", Dir.glob(File.join(state_root, "capture-*")).empty?)

  ocr_runner = FixtureScreenRunner.new(
    responses: {
      "hyprctl" => [{ stdout: JSON.generate([{ "name" => "DP-3", "focused" => true }]) }],
      "tesseract" => [{ stdout: "LOCAL VOICE PRESENCE\nSoul /\nPause listening\nRestart presence\nClose presence\n" }]
    }
  )
  ocr_capture = SoulCore::ScreenCaptureService.new(root: root, runner: ocr_runner, state_root: state_root).capture(mode: "monitor")
  check("bounded OCR preserves literal interface labels", ocr_capture.dig("capture", "ocr_engine") == "tesseract" && ocr_capture.dig("capture", "ocr_text").include?("Restart presence"))

  context_runner = FixtureScreenRunner.new(
    responses: {
      "hyprctl" => [
        { stdout: JSON.generate([{ "name" => "DP-3", "focused" => true, "activeWorkspace" => { "id" => 2 } }]) },
        { stdout: JSON.generate([
          { "mapped" => true, "hidden" => false, "class" => "Opera GX", "title" => "The Aero Cascade - YouTube", "workspace" => { "id" => 2 }, "at" => [3450, 48], "size" => [3420, 686] },
          { "mapped" => true, "hidden" => false, "class" => "python3", "title" => "Soul / Voice Presence", "workspace" => { "id" => 2 }, "at" => [3450, 744], "size" => [3420, 686] }
        ]) }
      ],
      "tesseract" => [{ stdout: "" }]
    }
  )
  context_capture = SoulCore::ScreenCaptureService.new(root: root, runner: context_runner, state_root: state_root).capture(mode: "monitor")
  check("compositor context identifies windows actually present", context_capture.dig("capture", "window_context").map { |item| item["title"] } == ["The Aero Cascade - YouTube", "Soul / Voice Presence"])
  check("compositor context preserves local window geometry", context_capture.dig("capture", "window_context").map { |item| item["position"] } == ["3450,48 3420x686", "3450,744 3420x686"])

  inventory = [
    { "name" => "DP-1", "description" => "Left", "focused" => false, "x" => 0, "y" => 0, "activeWorkspace" => { "id" => 2, "name" => "2" } },
    { "name" => "DP-3", "description" => "Right", "focused" => true, "x" => 3440, "y" => 0, "activeWorkspace" => { "id" => 5, "name" => "code" } }
  ]
  left_runner = FixtureScreenRunner.new(responses: { "hyprctl" => [{ stdout: JSON.generate(inventory) }] })
  left = SoulCore::ScreenCaptureService.new(root: root, runner: left_runner, state_root: state_root).capture(
    mode: "monitor", selector: { "kind" => "position", "value" => "left" }
  )
  check("left monitor resolves by compositor position", left["lifecycle_state"] == "complete" && left_runner.calls[1][:arguments][0, 3] == ["grim", "-o", "DP-1"])

  numbered_runner = FixtureScreenRunner.new(responses: { "hyprctl" => [{ stdout: JSON.generate(inventory) }] })
  numbered = SoulCore::ScreenCaptureService.new(root: root, runner: numbered_runner, state_root: state_root).capture(
    mode: "monitor", selector: { "kind" => "index", "value" => 2 }
  )
  check("numbered monitor resolves left to right", numbered["lifecycle_state"] == "complete" && numbered_runner.calls[1][:arguments][0, 3] == ["grim", "-o", "DP-3"])

  all_runner = FixtureScreenRunner.new(responses: { "hyprctl" => [{ stdout: JSON.generate(inventory) }] })
  all = SoulCore::ScreenCaptureService.new(root: root, runner: all_runner, state_root: state_root).capture(
    mode: "monitor", selector: { "kind" => "all" }
  )
  check("all-monitor capture uses one fresh compositor frame", all["lifecycle_state"] == "complete" && all_runner.calls[1][:arguments][0, 2] == ["grim", all_runner.calls[1][:arguments].last])

  workspace_runner = FixtureScreenRunner.new(responses: { "hyprctl" => [{ stdout: JSON.generate(inventory) }] })
  workspace = SoulCore::ScreenCaptureService.new(root: root, runner: workspace_runner, state_root: state_root).capture(
    mode: "monitor", selector: { "kind" => "workspace", "value" => "code" }
  )
  check("visible named workspace resolves without switching", workspace["lifecycle_state"] == "complete" && workspace_runner.calls[1][:arguments][0, 3] == ["grim", "-o", "DP-3"])

  hidden_workspace_runner = FixtureScreenRunner.new(responses: { "hyprctl" => [{ stdout: JSON.generate(inventory) }] })
  hidden_workspace = SoulCore::ScreenCaptureService.new(root: root, runner: hidden_workspace_runner, state_root: state_root).capture(
    mode: "monitor", selector: { "kind" => "workspace", "value" => "9" }
  )
  check("hidden workspace never causes a silent workspace switch", hidden_workspace["lifecycle_state"] == "awaiting_input" && hidden_workspace_runner.calls.length == 1)

  window_runner = FixtureScreenRunner.new(
    responses: {
      "hyprctl" => [{ stdout: JSON.generate({ "at" => [10, 48], "size" => [1705, 1382], "title" => "Soul Dashboard" }) }]
    }
  )
  window = SoulCore::ScreenCaptureService.new(root: root, runner: window_runner, state_root: state_root).capture(mode: "active_window")
  check("active window resolves exact current geometry", window["lifecycle_state"] == "complete" && window_runner.calls[1][:arguments][0, 3] == ["grim", "-g", "10,48 1705x1382"])

  region_runner = FixtureScreenRunner.new(responses: { "slurp" => [{ stdout: "3440,120 800x600\n" }] })
  region = SoulCore::ScreenCaptureService.new(root: root, runner: region_runner, state_root: state_root).capture(mode: "region")
  check("selected region is validated and captured once", region["lifecycle_state"] == "complete" && region_runner.calls[1][:arguments][0, 3] == ["grim", "-g", "3440,120 800x600"])
  check("region selection has a bounded foreground timeout", region_runner.calls.first[:timeout_seconds] == SoulCore::ScreenCaptureService::REGION_TIMEOUT_SECONDS)

  canceled_runner = FixtureScreenRunner.new(responses: { "slurp" => [{ exitstatus: 1 }] })
  canceled = SoulCore::ScreenCaptureService.new(root: root, runner: canceled_runner, state_root: state_root).capture(mode: "region")
  check("canceled selection returns a terminal canceled state", canceled["lifecycle_state"] == "canceled" && canceled_runner.calls.length == 1)

  missing_runner = FixtureScreenRunner.new(responses: { "hyprctl" => [Errno::ENOENT.new("hyprctl")] })
  missing = SoulCore::ScreenCaptureService.new(root: root, runner: missing_runner, state_root: state_root).capture(mode: "monitor")
  check("missing host dependency blocks safely", missing["lifecycle_state"] == "blocked_for_human_review")

  timeout_runner = FixtureScreenRunner.new(responses: { "slurp" => [SoulCore::ScreenCaptureCommandRunner::CommandTimeout.new] })
  timed_out = SoulCore::ScreenCaptureService.new(root: root, runner: timeout_runner, state_root: state_root).capture(mode: "region")
  check("capture timeout terminates as failed", timed_out["lifecycle_state"] == "failed" && timed_out["reason"].include?("timed out"))

  oversized_runner = FixtureScreenRunner.new(
    responses: { "hyprctl" => [{ stdout: JSON.generate([{ "name" => "DP-1", "focused" => true }]) }] },
    image: png(width: 12_001, height: 2)
  )
  oversized = SoulCore::ScreenCaptureService.new(root: root, runner: oversized_runner, state_root: state_root).capture(mode: "monitor")
  check("oversize capture is rejected and cleaned", oversized["lifecycle_state"] == "failed" && Dir.glob(File.join(state_root, "capture-*")).empty?)

  fixture_service = FixtureScreenService.new
  app = SoulCore::DashboardHttpApplication.new(
    root: root, facade: Object.new, bind_host: "127.0.0.1", port: 4567,
    csrf_token: "fixture-csrf", authentication: FixtureAuthentication.new,
    screen_capture: fixture_service
  )
  headers = {
    "host" => "127.0.0.1:4567", "origin" => "http://127.0.0.1:4567",
    "content-type" => "application/json", "x-soul-csrf" => "fixture-csrf"
  }
  response = app.call(method: "POST", target: "/api/v1/perception/screen-capture", headers: headers, body: JSON.generate("mode" => "monitor"))
  check("authenticated screen-capture route returns one preview", response.status == 200 && JSON.parse(response.body).dig("capture", "scope") == "monitor")
  rejected = app.call(method: "POST", target: "/api/v1/perception/screen-capture", headers: headers.except("x-soul-csrf"), body: JSON.generate("mode" => "monitor"))
  check("screen capture requires same-origin CSRF authority", rejected.status == 403 && fixture_service.modes == [["monitor", nil]])

  dashboard = File.read(File.join(__dir__, "../assets/dashboard/dashboard.js"))
  html = File.read(File.join(__dir__, "../assets/dashboard/index.html"))
  service_source = File.read(File.join(__dir__, "../lib/soul_core/screen_capture_service.rb"))
  open_dialog_source = dashboard[/function openScreenCaptureDialog\(\) \{.*?^\}/m].to_s
  check("opening the capture menu does not capture pixels", open_dialog_source.include?("showModal()") && !open_dialog_source.include?("callScreenCapture"))
  check("captured pixels become a removable preview before inference", dashboard.index("async function captureScreenPreview") < dashboard.index("async function sendMessage") && dashboard.include?("picture-attachment-remove"))
  check("screen preview reuses the existing picture-analysis stream", dashboard.include?("state.pictureAttachment") && dashboard.include?("/api/v1/perception/picture-stream"))
  check("Chat exposes explicit monitor, window, and region choices", html.include?('value="monitor"') && html.include?('value="active_window"') && html.include?('value="region"'))
  check("A2 contains no observation or computer-control loop", !service_source.match?(/\b(?:while|loop)\b.*(?:capture|grim)/m) && !service_source.match?(/\b(?:click|type_text|press_key)\b/))
  check("OCR is bounded and optional", SoulCore::ScreenCaptureService::OCR_TIMEOUT_SECONDS <= 15 && SoulCore::ScreenCaptureService::MAX_OCR_BYTES <= 8 * 1024)
end

puts "Perception A2 verification complete."
