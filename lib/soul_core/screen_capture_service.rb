# frozen_string_literal: true

require "base64"
require "digest"
require "fileutils"
require "json"
require "open3"
require "securerandom"
require "timeout"
require "tmpdir"

module SoulCore
  class ScreenCaptureCommandRunner
    Result = Struct.new(:stdout, :stderr, :exitstatus, keyword_init: true)
    class CommandTimeout < StandardError; end

    def call(arguments, timeout_seconds:)
      stdout = +""
      stderr = +""
      status = nil
      Open3.popen3(*arguments, pgroup: true) do |stdin, out, err, wait|
        stdin.close
        readers = [
          Thread.new { out.read },
          Thread.new { err.read }
        ]
        begin
          Timeout.timeout(timeout_seconds) do
            status = wait.value
            stdout = readers[0].value
            stderr = readers[1].value
          end
        rescue Timeout::Error
          terminate_group(wait.pid)
          readers.each { |reader| reader.join(1) }
          raise CommandTimeout, "screen capture command timed out"
        ensure
          readers.each { |reader| reader.kill if reader.alive? }
        end
      end
      Result.new(stdout: stdout, stderr: stderr, exitstatus: status.exitstatus)
    end

    private

    def terminate_group(pid)
      Process.kill("TERM", -pid)
      sleep(0.1)
      Process.kill("KILL", -pid)
    rescue Errno::ESRCH
      nil
    ensure
      begin
        Process.wait(pid, Process::WNOHANG)
      rescue Errno::ECHILD
        nil
      end
    end
  end

  class ScreenCaptureService
    MAX_CAPTURE_BYTES = 10 * 1024 * 1024
    MAX_DIMENSION = 12_000
    MAX_PIXELS = 48_000_000
    CAPTURE_TIMEOUT_SECONDS = 30
    REGION_TIMEOUT_SECONDS = 120
    OCR_TIMEOUT_SECONDS = 15
    MAX_OCR_BYTES = 8 * 1024
    MODES = %w[monitor active_window region].freeze
    GEOMETRY = /\A-?\d+,-?\d+ \d+x\d+\z/

    def initialize(root: Dir.pwd, env: ENV, runner: ScreenCaptureCommandRunner.new, state_root: nil)
      @root = File.expand_path(root)
      @runner = runner
      configured = env["SOUL_PERCEPTION_STATE_ROOT"].to_s.strip
      perception_root = configured.empty? ? File.join(@root, "Soul/private/perception") : configured
      @state_root = File.expand_path(state_root || File.join(perception_root, "screen_capture"))
    end

    def capture(mode:, selector: nil)
      requested_mode = mode.to_s
      return outcome("failed", "screen capture mode must be monitor, active_window, or region") unless MODES.include?(requested_mode)
      return outcome("failed", "screen selector is valid only for monitor capture") if requested_mode != "monitor" && selector

      FileUtils.mkdir_p(@state_root, mode: 0o700)
      temporary_directory = Dir.mktmpdir("capture-", @state_root)
      File.chmod(0o700, temporary_directory)
      capture_path = File.join(temporary_directory, "screen.png")
      source = resolve_source(requested_mode, selector)
      return source if source["lifecycle_state"] && source["lifecycle_state"] != "complete"

      command = source.fetch("grim_arguments") + [capture_path]
      result = @runner.call(command, timeout_seconds: source.fetch("timeout_seconds"))
      return outcome("failed", bounded_reason("grim failed", result.stderr)) unless result.exitstatus.zero?
      return outcome("failed", "screen capture produced no image") unless File.file?(capture_path) && !File.symlink?(capture_path)

      bytes = File.binread(capture_path)
      width, height = validate_png!(bytes)
      ocr_text = extract_ocr(capture_path)
      window_context = source["window_context"] || visible_window_context(
        source["workspace_ids"], capture_origin: source["capture_origin"]
      )
      {
        "ok" => true,
        "lifecycle_state" => "complete",
        "mutation" => "ephemeral_screen_preview_created",
        "capture" => {
          "filename" => "Soul Screen #{requested_mode.tr('_', ' ')}.png",
          "media_type" => "image/png",
          "image_base64" => Base64.strict_encode64(bytes),
          "bytes" => bytes.bytesize,
          "width" => width,
          "height" => height,
          "sha256" => Digest::SHA256.hexdigest(bytes),
          "scope" => requested_mode,
          "selector" => selector,
          "source_label" => source.fetch("source_label"),
          "ocr_text" => ocr_text,
          "ocr_engine" => (ocr_text ? "tesseract" : nil),
          "window_context" => window_context,
          "retention" => "browser_preview_only",
          "authority" => "untrusted_evidence_only"
        }
      }
    rescue ScreenCaptureCommandRunner::CommandTimeout
      outcome("failed", "screen capture timed out and stopped safely")
    rescue Errno::ENOENT => error
      outcome("blocked_for_human_review", "screen capture dependency is unavailable: #{File.basename(error.message.split(' - ').last.to_s)}")
    rescue JSON::ParserError
      outcome("failed", "Hyprland returned malformed screen metadata")
    rescue ArgumentError => error
      outcome("failed", error.message)
    rescue StandardError => error
      outcome("failed", "screen capture failed safely: #{error.class}")
    ensure
      FileUtils.remove_entry_secure(temporary_directory) if defined?(temporary_directory) && temporary_directory && Dir.exist?(temporary_directory)
    end

    private

    def resolve_source(mode, selector)
      case mode
      when "monitor" then monitor_source(selector)
      when "active_window" then active_window
      when "region" then selected_region
      end
    end

    def monitor_source(selector)
      result = @runner.call(%w[hyprctl -j monitors], timeout_seconds: CAPTURE_TIMEOUT_SECONDS)
      return outcome("failed", bounded_reason("Hyprland monitor inventory failed", result.stderr)) unless result.exitstatus.zero?

      monitors = JSON.parse(result.stdout)
      monitors = Array(monitors)
      return outcome("awaiting_input", "Hyprland did not report any available monitors") if monitors.empty?

      kind = selector.is_a?(Hash) ? selector["kind"].to_s : ""
      if kind == "all"
        return {
          "lifecycle_state" => "complete",
          "grim_arguments" => ["grim"],
          "source_label" => "All available monitors",
          "workspace_ids" => monitors.filter_map { |record| record.dig("activeWorkspace", "id") },
          "capture_origin" => [
            monitors.map { |record| Integer(record["x"] || 0) }.min,
            monitors.map { |record| Integer(record["y"] || 0) }.min
          ],
          "timeout_seconds" => CAPTURE_TIMEOUT_SECONDS
        }
      end

      monitor = select_monitor(monitors, selector)
      return monitor if monitor.is_a?(Hash) && monitor["lifecycle_state"]

      name = monitor["name"].to_s
      return outcome("failed", "focused monitor name is invalid") unless name.match?(/\A[A-Za-z0-9_.:-]{1,80}\z/)

      {
        "lifecycle_state" => "complete",
        "grim_arguments" => ["grim", "-o", name],
        "source_label" => "#{name} · #{monitor['description'].to_s.strip}".sub(/ · \z/, ""),
        "workspace_ids" => [monitor.dig("activeWorkspace", "id")].compact,
        "capture_origin" => [Integer(monitor["x"] || 0), Integer(monitor["y"] || 0)],
        "timeout_seconds" => CAPTURE_TIMEOUT_SECONDS
      }
    end

    def select_monitor(monitors, selector)
      kind = selector.is_a?(Hash) ? selector["kind"].to_s : ""
      ordered = monitors.sort_by { |record| [Integer(record["x"] || 0), Integer(record["y"] || 0)] }
      case kind
      when ""
        monitors.find { |record| record["focused"] == true } ||
          outcome("awaiting_input", "Hyprland did not report a focused monitor")
      when "position"
        position = selector["value"].to_s
        return outcome("failed", "screen monitor selector is invalid") unless %w[left right].include?(position)

        position == "right" ? ordered.last : ordered.first
      when "index"
        requested = Integer(selector["value"])
        return outcome("awaiting_input", "The requested monitor is not currently available") unless requested.between?(1, ordered.length)

        index = requested - 1
        ordered[index] || outcome("awaiting_input", "The requested monitor is not currently available")
      when "current_workspace"
        monitors.find { |record| record["focused"] == true } ||
          outcome("awaiting_input", "Hyprland did not report a focused workspace")
      when "workspace"
        value = selector["value"].to_s
        found = monitors.find do |record|
          workspace = record["activeWorkspace"].is_a?(Hash) ? record["activeWorkspace"] : {}
          workspace["id"].to_s == value || workspace["name"].to_s.casecmp?(value)
        end
        found || outcome(
          "awaiting_input",
          "Workspace #{value} is not currently visible; Soul will not switch workspaces automatically"
        )
      else
        outcome("failed", "screen monitor selector is invalid")
      end
    rescue ArgumentError, TypeError
      outcome("failed", "screen monitor selector is invalid")
    end

    def active_window
      result = @runner.call(%w[hyprctl -j activewindow], timeout_seconds: CAPTURE_TIMEOUT_SECONDS)
      return outcome("failed", bounded_reason("Hyprland active-window lookup failed", result.stderr)) unless result.exitstatus.zero?

      window = JSON.parse(result.stdout)
      at = Array(window["at"])
      size = Array(window["size"])
      return outcome("awaiting_input", "Hyprland did not report an active window") unless at.length == 2 && size.length == 2

      geometry = geometry(at[0], at[1], size[0], size[1])
      title = window["title"].to_s.strip
      label = title.empty? ? window["class"].to_s.strip : title
      label = "Active window" if label.empty?
      {
        "lifecycle_state" => "complete",
        "grim_arguments" => ["grim", "-g", geometry],
        "source_label" => label.byteslice(0, 160),
        "window_context" => [{
          "application" => window["class"].to_s.byteslice(0, 120),
          "title" => label.byteslice(0, 240),
          "position" => "0,0 #{size[0]}x#{size[1]}"
        }],
        "timeout_seconds" => CAPTURE_TIMEOUT_SECONDS
      }
    end

    def selected_region
      result = @runner.call(["slurp"], timeout_seconds: REGION_TIMEOUT_SECONDS)
      return outcome("canceled", "screen region selection was canceled") unless result.exitstatus.zero?

      selected = result.stdout.to_s.strip
      return outcome("canceled", "screen region selection was canceled") if selected.empty?
      raise ArgumentError, "selected screen geometry is invalid" unless selected.match?(GEOMETRY)

      validate_geometry!(selected)
      {
        "lifecycle_state" => "complete",
        "grim_arguments" => ["grim", "-g", selected],
        "source_label" => "Selected region · #{selected}",
        "timeout_seconds" => CAPTURE_TIMEOUT_SECONDS
      }
    end

    def geometry(x, y, width, height)
      values = [x, y, width, height].map { |value| Integer(value) }
      result = "#{values[0]},#{values[1]} #{values[2]}x#{values[3]}"
      validate_geometry!(result)
      result
    rescue TypeError, ArgumentError
      raise ArgumentError, "active window geometry is invalid"
    end

    def validate_geometry!(value)
      match = value.match(/\A-?\d+,-?\d+ (\d+)x(\d+)\z/)
      raise ArgumentError, "screen geometry is invalid" unless match

      width = Integer(match[1])
      height = Integer(match[2])
      raise ArgumentError, "screen geometry dimensions are invalid" unless width.positive? && height.positive?
      raise ArgumentError, "screen geometry exceeds the bounded limit" if width > MAX_DIMENSION || height > MAX_DIMENSION || width * height > MAX_PIXELS
    end

    def validate_png!(bytes)
      raise ArgumentError, "screen capture is empty" if bytes.empty?
      raise ArgumentError, "screen capture exceeds #{MAX_CAPTURE_BYTES} bytes" if bytes.bytesize > MAX_CAPTURE_BYTES
      raise ArgumentError, "screen capture is not a valid PNG" unless bytes.start_with?("\x89PNG\r\n\x1A\n".b) && bytes.bytesize >= 24 && bytes.byteslice(12, 4) == "IHDR"

      width, height = bytes.byteslice(16, 8).unpack("NN")
      raise ArgumentError, "screen capture dimensions are invalid" unless width.positive? && height.positive?
      raise ArgumentError, "screen capture dimensions exceed the bounded limit" if width > MAX_DIMENSION || height > MAX_DIMENSION || width * height > MAX_PIXELS

      [width, height]
    end

    def extract_ocr(path)
      result = @runner.call(
        ["tesseract", path, "stdout", "--psm", "11"],
        timeout_seconds: OCR_TIMEOUT_SECONDS
      )
      return nil unless result.exitstatus.zero?

      value = result.stdout.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
      value = value.lines.map(&:strip).reject(&:empty?).first(160).join("\n")
      return nil if value.empty?

      value.byteslice(0, MAX_OCR_BYTES)
    rescue StandardError
      nil
    end

    def visible_window_context(workspace_ids, capture_origin: nil)
      ids = Array(workspace_ids).map(&:to_s).reject(&:empty?)
      return [] if ids.empty?

      result = @runner.call(%w[hyprctl -j clients], timeout_seconds: CAPTURE_TIMEOUT_SECONDS)
      return [] unless result.exitstatus.zero?

      Array(JSON.parse(result.stdout)).filter_map do |window|
        next if window["mapped"] == false || window["hidden"] == true
        next unless ids.include?(window.dig("workspace", "id").to_s)

        application = window["class"].to_s.strip.byteslice(0, 120)
        title = window["title"].to_s.strip.byteslice(0, 240)
        next if application.empty? && title.empty?

        at = Array(window["at"])
        size = Array(window["size"])
        origin = Array(capture_origin)
        position = if at.length == 2 && size.length == 2 && origin.length == 2
          "#{Integer(at[0]) - Integer(origin[0])},#{Integer(at[1]) - Integer(origin[1])} #{Integer(size[0])}x#{Integer(size[1])}"
        end
        { "application" => application, "title" => title, "position" => position }.compact
      end.first(16)
    rescue StandardError
      []
    end

    def bounded_reason(prefix, stderr)
      detail = stderr.to_s.strip.gsub(/\s+/, " ").byteslice(0, 240)
      detail.empty? ? prefix : "#{prefix}: #{detail}"
    end

    def outcome(state, reason)
      {
        "ok" => false,
        "lifecycle_state" => state,
        "mutation" => "none",
        "reason" => reason
      }
    end
  end
end
