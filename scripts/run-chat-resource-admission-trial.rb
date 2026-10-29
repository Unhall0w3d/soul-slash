#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative 'support/roster_service_driver'
require_relative '../lib/soul_core/shared_compute_service'
require 'yaml'

sequence=case ARGV
when ['--approved-bounded-chat-resource-test'] then %w[gpt-oss-20b gpt-oss-20b gemma-4-26b-a4b qwen3.8-27b]
when ['--approved-bounded-qwen-resource-test'] then %w[qwen3.8-27b]
else abort 'Expected explicit bounded chat or Qwen resource-test flag'
end
File.umask(0077)
root=ChatReplacementTrial::ROOT
output=Dir.mktmpdir('chat-resource-admission-',ChatReplacementTrial::QUALIFICATION)
driver=RosterServiceDriver.new(output:output)
clock=-> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
save=->(name,data) { File.write(File.join(output,name),JSON.pretty_generate(data),mode:'wx',perm:0600) }
started=clock.call
state='failed'
results=[]
gateway=nil
before=nil
signals=%w[INT TERM].to_h { |signal| [signal,Signal.trap(signal) { raise ChatReplacementTrial::Abort,'trial canceled' }] }
begin
  before=driver.send(:protected_state)
  policy=SoulCore::SharedComputeService.new.status
  raise 'coordinator must be available, unloaded and without handoff' unless policy['ok'] &&
    policy['data'].values_at('policy','state','handoff')==['available','unloaded',nil]
  raise 'existing runtime lease' unless driver.runtime_lease_store.active_leases.empty?
  hw=Dir.glob('/sys/bus/pci/devices/0000:0a:00.0/hwmon/hwmon*').first
  raise 'expected 281 W' unless Integer(File.read(File.join(hw,'power1_cap')))==281_000_000
  clocks=File.read('/sys/bus/pci/devices/0000:0a:00.0/pp_od_clk_voltage')
  raise 'clock/voltage changed' unless clocks.include?('1: 2400Mhz') && clocks.include?('-50mV')
  lact_sha=Digest::SHA256.file('/etc/lact/config.yaml').hexdigest
  prompt='Synthetic check: the current cabinet is 9. Reply with only the digit 9.'
  save.call('frozen-packet.json',{sequence:sequence,prompt:prompt,max_replies:sequence.length,seconds:600,request_seconds:180,
    scope:'production driver, fresh synthetic journal, explicit model sequence and replay; no HTTP/UI or quality ranking',
    binding:driver.roster_binding,policy:policy,lact_sha256:lact_sha,clocks:clocks,protected_before:before,
    paging_policy:'host-wide paging is recorded only; no abort threshold',
    runner_sha256:Digest::SHA256.file(__FILE__).hexdigest,
    guards:'unchanged per-card budgets, thermal, available RAM, fresh ownership, leases, cancellation and cleanup'})
  owner=SoulCore::RosterWarmSession.new(leases:driver.runtime_lease_store,
    driver:RosterWarmLibreChatTrial::WarmDriver.new(driver),isolated_models:driver.isolated_models)
  owner.session(seconds:600) do
    journal=File.join(output,'journal')
    SoulCore::RosterConversationGateway.create(path:journal,owner:owner)
    gateway=SoulCore::RosterConversationGateway.new(path:journal,owner:owner)
    sequence.each_with_index do |model,index|
      puts JSON.generate(state:'starting',model:model,index:index,output:output); $stdout.flush
      args={conversation_id:"resource#{index}",request_id:"r#{index}",adapter:driver.roster_adapter(model),
        messages:[{'role'=>'user','content'=>prompt}],deadline:[clock.call+180,started+600].min}
      request_start=clock.call
      result=gateway.complete(**args)
      replay=gateway.complete(**args.merge(deadline:[clock.call+180,started+600].min))
      raise 'replay mismatch' unless replay['replayed'] && replay['content']==result['content']
      row={model:model,index:index,seconds:clock.call-request_start,answer:result['content'],
        owned_pid:driver.instance_variable_get(:@pid),replay_verified:true}
      results << row
      save.call("request-#{index}.json",row)
      save.call("resources-#{index}.json",driver.instance_variable_get(:@samples))
      puts JSON.generate(row); $stdout.flush
    end
  end
  state='completed_pending_review'
rescue ChatReplacementTrial::Abort, StandardError => error
  failure="#{error.class}: #{error.message}".slice(0,1024)
ensure
  gateway&.close
  begin
    # The warm owner owns teardown; do not retry an uncertain release here.
    after=driver.send(:protected_state)
    cleanup={owned_pid:driver.instance_variable_get(:@pid),port_closed:driver.send(:port_closed?),
      collector_alive:!!driver.instance_variable_get(:@telemetry_thread)&.alive?,
      monitor_alive:!!driver.instance_variable_get(:@monitor)&.alive?,leases:driver.runtime_lease_store.active_leases}
    raise 'cleanup or protected-state verification failed' unless cleanup.values_at(:owned_pid,:port_closed,:collector_alive,:monitor_alive,:leases)==[nil,true,false,false,[]] && before==after
    raise 'LACT settings changed' unless lact_sha && Digest::SHA256.file('/etc/lact/config.yaml').hexdigest==lact_sha
  rescue ChatReplacementTrial::Abort, StandardError => cleanup_error
    state='failed'
    failure=[failure,"cleanup: #{cleanup_error.class}: #{cleanup_error.message}"].compact.join('; ')
  end
  save.call('final-resources.json',driver.instance_variable_get(:@samples))
  save.call('receipt.json',{state:state,error:failure,elapsed_seconds:clock.call-started,results:results,
    cleanup:cleanup,protected_before:before,protected_after:after})
  puts JSON.generate(state:state,error:failure,output:output)
  signals.each { |signal,handler| Signal.trap(signal,handler) }
end
exit(state=='completed_pending_review' ? 0 : 1)
