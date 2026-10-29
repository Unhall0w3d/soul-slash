# frozen_string_literal: true
require_relative '../../lib/soul_core/creative_render_guard'

# Qualification only: reuse the production AMD thermal/memory validator, with
# direct bounded accounting. Never impersonate sd-cli to bypass its dispatch.
class MusicQualificationGuard
  attr_reader :samples, :pids
  def initialize(root:, sampler: nil, runner: SoulCore::BoundedCommandRunner.new, attach: ->(*) {}, canceled: -> { false })
    @validator = SoulCore::CreativeRenderGuard.new(root: root)
    client = SoulCore::GpuAccountingSnapshot.new
    @sample = sampler || -> { @validator.capture(client) }
    @runner, @attach, @canceled = runner, attach, canceled
    @samples, @pids = [], []
  end

  def run(command, **options)
    initial = @sample.call
    @samples << initial
    @validator.validate!(initial, allowed: [], pid: nil, initial_swap: initial.fetch('swap_pages'), admission: true)
    attached = false
    @runner.run(*command, **options, monitor: ->(pid) {
      unless attached
        @pids << pid
        @attach.call(pid)
        attached = true
      end
      raise 'music qualification canceled' if @canceled.call
      row = @sample.call
      @samples << row
      @validator.validate!(row, allowed: [], pid: pid, initial_swap: initial.fetch('swap_pages'), admission: false)
    })
  end
end
