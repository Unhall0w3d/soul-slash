# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require_relative "bounded_command_runner"

module SoulCore
  class BlenderAudioAnalyzer
    SAMPLE_RATE = 8_000
    MAX_DURATION_SECONDS = 180.0
    MAX_POINTS = 256

    def initialize(runner: BoundedCommandRunner.new)
      @runner = runner
      @ffmpeg = @runner.which("ffmpeg")
    end

    def analyze(path:, bpm:, beats_per_bar:, bars: nil, fps:, duration_seconds: nil)
      raise ArgumentError, "ffmpeg is required for Blender audio analysis" unless @ffmpeg
      bpm = Float(bpm)
      beats_per_bar = Integer(beats_per_bar)
      bars = bars.nil? ? nil : Integer(bars)
      fps = Integer(fps)
      raise ArgumentError, "bpm must be 30..240" unless bpm.between?(30, 240)
      raise ArgumentError, "beats_per_bar must be 2..12" unless beats_per_bar.between?(2, 12)
      study = !duration_seconds.nil?
      raise ArgumentError, "choose whole bars or one bounded duration, not both" if study && bars
      raise ArgumentError, "bars must be 8 or 12" unless study || [8, 12].include?(bars)
      raise ArgumentError, "fps must be 12..60" unless fps.between?(12, 60)
      raise ArgumentError, "music artifact is invalid" unless File.file?(path) && !File.symlink?(path)

      nominal_duration = study ? Float(duration_seconds) : bars * beats_per_bar * 60.0 / bpm
      raise ArgumentError, "bounded study duration must be exactly 30 seconds" if study && nominal_duration != 30.0
      raise ArgumentError, "bounded Blender duration exceeds analyzer limit" if nominal_duration > MAX_DURATION_SECONDS
      frame_count = [(nominal_duration * fps).round, 2].max
      rendered_duration = frame_count.to_f / fps

      Dir.mktmpdir("soul-blender-audio-") do |temporary|
        raw_path = File.join(temporary, "audio.f32le")
        decode!(path, raw_path, rendered_duration)
        samples = File.binread(raw_path).unpack("e*")
        raise ArgumentError, "music artifact did not yield usable audio" if samples.length < SAMPLE_RATE
        curves = extract_curves(samples, point_count: [frame_count, MAX_POINTS].min)
        frames = evenly_spaced_frames(frame_count, curves.fetch("energy").length)
        curves.each_value { |values| values[-1] = values[0] } unless study
        {
          "schema_version" => "soul.blender.audio_analysis.v1",
          "source_audio_sha256" => Digest::SHA256.file(path).hexdigest,
          "bpm" => bpm,
          "beats_per_bar" => beats_per_bar,
          "bars" => bars,
          "temporal_mode" => study ? "thirty_second_study" : "whole_bar_loop",
          "fps" => fps,
          "frame_count" => frame_count,
          "nominal_duration_seconds" => nominal_duration.round(6),
          "rendered_duration_seconds" => rendered_duration.round(6),
          "bar_frames" => study ? [] : (0..bars).map { |bar| 1 + ((bar.to_f / bars) * (frame_count - 1)).round },
          "curve_frames" => frames,
          "curves" => curves,
          "loop_state_equal" => !study && curves.values.all? { |values| (values.first - values.last).abs <= 1e-9 },
          "analysis_process" => "ffmpeg mono 8kHz decode plus deterministic bounded three-band envelope extraction"
        }
      end
    end

    private

    def decode!(input, output, duration)
      result = @runner.run(
        @ffmpeg, "-y", "-nostdin", "-hide_banner", "-loglevel", "error",
        "-i", input, "-t", duration.to_s, "-ac", "1", "-ar", SAMPLE_RATE.to_s,
        "-f", "f32le", output,
        timeout_seconds: 60, max_output_bytes: 64 * 1024
      )
      raise ArgumentError, "bounded music analysis decode failed safely: #{result.status}" unless result.success? && File.file?(output) && File.size(output).positive?
    end

    def extract_curves(samples, point_count:)
      low = Array.new(samples.length, 0.0)
      mid_low = Array.new(samples.length, 0.0)
      low_alpha = one_pole_alpha(180.0)
      mid_alpha = one_pole_alpha(2_000.0)
      samples.each_index do |index|
        previous_low = index.zero? ? 0.0 : low[index - 1]
        previous_mid = index.zero? ? 0.0 : mid_low[index - 1]
        low[index] = previous_low + low_alpha * (samples[index] - previous_low)
        mid_low[index] = previous_mid + mid_alpha * (samples[index] - previous_mid)
      end

      window = [(samples.length.to_f / point_count).ceil, 1].max
      raw = { "low_band" => [], "mid_band" => [], "high_band" => [], "energy" => [] }
      point_count.times do |point|
        first = point * window
        last = [first + window, samples.length].min
        break if first >= last
        count = last - first
        sums = { "low_band" => 0.0, "mid_band" => 0.0, "high_band" => 0.0, "energy" => 0.0 }
        (first...last).each do |index|
          low_value = low[index]
          mid_value = mid_low[index] - low_value
          high_value = samples[index] - mid_low[index]
          sums["low_band"] += low_value * low_value
          sums["mid_band"] += mid_value * mid_value
          sums["high_band"] += high_value * high_value
          sums["energy"] += samples[index] * samples[index]
        end
        sums.each { |name, sum| raw.fetch(name) << Math.sqrt(sum / count) }
      end
      normalized = raw.transform_values { |values| normalize(values) }
      energy = normalized.fetch("energy")
      normalized["kick"] = energy.each_index.map do |index|
        previous = index.zero? ? energy[index] : energy[index - 1]
        [[(energy[index] - previous) * 3.5, 0.0].max, 1.0].min.round(6)
      end
      normalized
    end

    def normalize(values)
      ceiling = values.sort.fetch([(values.length * 0.95).floor, values.length - 1].min)
      ceiling = values.max.to_f if ceiling <= 1e-9
      ceiling = 1.0 if ceiling <= 1e-9
      values.map { |value| [[value / ceiling, 0.0].max, 1.0].min.round(6) }
    end

    def evenly_spaced_frames(frame_count, count)
      return [1] if count == 1
      count.times.map { |index| 1 + ((index.to_f / (count - 1)) * (frame_count - 1)).round }
    end

    def one_pole_alpha(cutoff)
      delta = 1.0 / SAMPLE_RATE
      rc = 1.0 / (2.0 * Math::PI * cutoff)
      delta / (rc + delta)
    end
  end
end
