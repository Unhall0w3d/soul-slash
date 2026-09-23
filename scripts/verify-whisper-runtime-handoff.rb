#!/usr/bin/env ruby
require 'tmpdir'
require_relative '../lib/soul_core/whisper_runtime_handoff'

class HandoffFixture
  attr_accessor :mode, :state, :pending_work, :foreign
  attr_reader :commands
  UUID = SoulCore::WhisperRuntimeHandoff::GPU_UUID
  def initialize(mode)
    @mode, @state, @commands = mode, (mode == :free || mode == :amd ? 'inactive' : 'active'), []
  end
  def with_controlled_observation
    return {'reason'=>'model runtime control is busy'} if mode == :lock_busy
    return {'reason'=>'model runtime control is disabled'} if mode == :disabled
    yield({'active_work_count'=>mode == :busy ? 1 : 0, 'active_leases'=>[], 'profile_conflict'=>false,
      'active_profile_count'=>state == 'active' || mode == :amd ? 1 : 0, 'idle_certain'=> mode != :unknown,
      'profiles'=>[{'id'=>'nvidia-fallback','service'=>'llama-server.service','accelerator'=>'NVIDIA CUDA','endpoint'=>'http://127.0.0.1:8082/v1','service_state'=>state}]})
  end
  def observe_nvidia_allocation(*)
    return nil if mode == :cpu || (mode == :restore_cpu && commands.include?('start'))
    {'pid'=>123,'gpu_uuid'=>UUID,'memory_mib'=>5278}
  end
  def observe_service_state(*) = state
  def bounded_http_get(*)
    {status:200,body:JSON.generate({'model_path'=>'/fixture/Qwen3-8B-Q4_K_M.gguf','model_alias'=>mode == :identity && commands.include?('start') ? 'wrong' : 'soul-local-chat','total_slots'=>1})}
  end
  def service_command(action, *)
    @commands << action
    @state = action == 'stop' ? 'inactive' : 'active' unless mode == :stop_unchanged
    result(%i[stop stop_unchanged].include?(mode) ? 'failed' : 'ok')
  end
  def restore_temporary_profile(*)
    @commands << 'start'
    @state = 'active'
    mode == :restore ? 'restore failed' : nil
  end
  def run(*argv, **)
    if argv.any? { |a| a.include?('query-gpu=') }
      result('ok', "#{UUID}, 7900\n")
    else
      rows = foreign ? "999, #{UUID}, 1000\n" : state == 'active' ? "123, #{UUID}, 5278\n" : ''
      result('ok',rows)
    end
  end
  def result(status, stdout='')
    SoulCore::BoundedCommandRunner::Result.new(status:status,stdout:stdout,stderr:'',truncated:false)
  end
end

def check(label, value)
  raise "FAIL: #{label}" unless value
  puts "PASS: #{label}"
end

%i[normal free amd busy lock_busy disabled unknown cpu stop stop_unchanged work cancel cleanup restore restore_cpu identity stale].each do |mode|
  Dir.mktmpdir('whisper-handoff-test-') do |root|
    dir = File.join(root,'Soul/runtime/model_runtime')
    FileUtils.mkdir_p(dir)
    pending = File.join(dir,'whisper-pending.json')
    File.write(pending,'{}') if mode == :stale
    fixture = HandoffFixture.new(mode)
    tick = 0
    handoff = SoulCore::WhisperRuntimeHandoff.new(root:root,env:{},control:fixture,runner:fixture,clock:-> { tick += 5 },sleeper:->(_) {})
    called = false
    error = value = nil
    begin
      value = handoff.run do
        called = true
        check('pending receipt exists before specialist work',File.file?(pending))
        raise 'work failed' if mode == :work
        raise Interrupt if mode == :cancel
        fixture.foreign = true if mode == :cleanup
        :transcript
      end
    rescue StandardError, Interrupt => caught
      error = caught
    end
    if %i[normal free amd].include?(mode)
      check("#{mode} successful recovery returns value", !error && value.first == :transcript && !File.exist?(pending))
      check("#{mode} only changes NVIDIA when required", fixture.commands == (mode == :normal ? %w[stop start] : []))
    else
      check("#{mode} visible error prevents transcript return", !error.nil? && value.nil?)
      if %i[busy lock_busy disabled unknown cpu stale].include?(mode)
        check("#{mode} no mutations", !called && fixture.commands.empty?)
      elsif mode == :stop_unchanged
        check('failed stop with original process intact does not rerun work or restart it', !called && fixture.commands == ['stop'] && !File.exist?(pending))
      elsif mode == :cleanup
        check('cleanup failure never restarts Qwen over another process', fixture.commands == ['stop'] && File.file?(pending))
      elsif %i[restore restore_cpu identity].include?(mode)
        check("#{mode} retains recovery receipt", File.file?(pending))
      else
        check("#{mode} restores Qwen before returning error", fixture.commands == %w[stop start] && !File.exist?(pending))
      end
    end
  end
end
