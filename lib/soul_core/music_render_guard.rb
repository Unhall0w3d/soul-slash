# frozen_string_literal: true
require_relative 'creative_render_guard'
require_relative 'music_generation_service'

module SoulCore
  # Foreground music process adapter. Shared limits and telemetry decoding stay
  # in CreativeRenderGuard; the music runner retains cancellation and child reaping.
  class MusicRenderGuard
    def initialize(root:, control:, runner: MusicGenerationService::ForegroundProcessRunner.new, sampler: nil)
      @root, @control, @runner, @sampler = root, control, runner, sampler
      @validator = CreativeRenderGuard.new(root: root, control: control)
    end

    def run(command, **options)
      return @runner.run(command, **options) unless %w[ace-lm ace-synth].include?(File.basename(command.first.to_s))
      samples = []
      if options.fetch(:canceled).call
        return result = MusicGenerationService::ProcessResult.new(status: 'canceled', stdout: '', stderr: 'canceled before admission')
      end
      client = GpuAccountingSnapshot.new
      handoff = @control&.status&.dig('data', 'handoff', 'handoff_id')
      sample = @sampler || (@control ? -> { @validator.remote_capture(client, handoff) } : -> { @validator.capture(client) })
      initial = sample.call
      samples << initial
      baseline = initial.fetch('swap_pages')
      @validator.validate!(initial, allowed: [], pid: nil, initial_swap: baseline, admission: true)
      result = @runner.run(command, **options, monitor: ->(pid) {
        row = sample.call
        samples << row
        @validator.validate!(row, allowed: [], pid: pid, initial_swap: baseline, admission: false)
      })
    rescue StandardError => error
      result = MusicGenerationService::ProcessResult.new(status: 'failed', stdout: '', stderr: "Music guard: #{error.class}: #{error.message}")
    ensure
      if samples
        directory = File.join(@root, 'Soul/runtime/qualification/music-monitor')
        FileUtils.mkdir_p(directory, mode: 0o700)
        path = File.join(directory, "#{Time.now.utc.strftime('%Y%m%dT%H%M%S')}-#{SecureRandom.hex(8)}.json")
        File.write(path, JSON.pretty_generate({program: File.basename(command.first.to_s), handoff_id: handoff,
          status: result&.status, error: result&.stderr, samples: samples}), mode: 'wx', perm: 0o600)
      end
    end
  end
end
