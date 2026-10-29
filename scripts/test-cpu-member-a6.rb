# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/soul_core/cpu_member_service'
class CpuMemberA6Test < Minitest::Test
  class Owner
    def status = {'state'=>'unloaded'}
    def admitted? = true
    def touch = nil
    def tick = nil
    def stop = true
    def request(*) = raise('unexpected CPU model invocation')
  end
  class Client
    attr_reader :calls
    attr_accessor :fail,:wait
    def initialize;@calls=[];end
    def cleanup_confirmed? = true
    def call(task:,cancel:,**)
      @calls<<task
      if @wait
        sleep 0.005 until cancel.call
        raise 'canceled'
      end
      raise 'synthetic failure' if @fail
      {'member'=>task['member'],'content'=>'Synthetic answer'}
    end
  end
  def setup
    @root=Dir.mktmpdir;@client=Client.new;@status={'policy'=>'reserved','state'=>'unloaded','available'=>false,'handoff'=>nil};open_service
  end
  def open_service
    @service=SoulCore::CpuMemberService.new(path:@root,owner:Owner.new,assistance:true,queue_client:@client,compute_reader:->{@status})
    @queue=@service.instance_variable_get(:@queue)
  end
  def teardown;@service.close;FileUtils.remove_entry(@root);end
  def call(text,id:,history:[],conversation:'a')
    @service.complete(conversation_id:conversation,request_id:id,messages:history+[{'role'=>'user','content'=>text}],deadline:Process.clock_gettime(Process::CLOCK_MONOTONIC)+10,cancel:->{false})
  end
  def history(text,r)=[{'role'=>'user','content'=>text},{'role'=>'assistant','content'=>r['content']}]
  def tick
    @queue.instance_variable_set(:@next_poll,0);@service.tick
    worker=@queue.instance_variable_get(:@worker);assert worker.join(2) if worker
  end
  def propose
    text='Ask GPT-OSS to write a short review of a fictional Ruby method.'
    r=call(text,id:'p');[r,history(text,r)]
  end
  def confirm
    r,h=propose;c=call('yes',id:'c',history:h);[c,h+history('yes',c)]
  end
  def test_natural_math_and_dashboard_recompute
    text='What is 847 minus 286?';r=call(text,id:'math');assert_includes r['content'],'561';assert_equal 'calculation',r.dig('execution','operation')
    rt=SoulCore::CpuMemberDashboardRuntime.new(store:nil);args=[{'conversation_id'=>'a','request_id'=>'math'},SoulCore::CpuMemberAdapter.new,[{'role'=>'user','content'=>text}],r['content'],SoulCore::CpuMemberAdapter::MODEL]
    rt.send(:validate_execution!,r['execution'],*args)
    args[3]=r['content'].sub('561','999');forged=r['execution'].merge('result_sha256'=>Digest::SHA256.hexdigest(args[3]))
    assert_raises(RuntimeError){rt.send(:validate_execution!,forged,*args)}
    assert call(text,id:'math')['replayed']
  end
  def test_proposal_is_not_confirmation_and_reserved_never_runs
    r,h=propose;assert_includes r['content'],'unavailable at this time';assert_equal 0,@queue.status['total'];tick;assert_empty @client.calls
    c=call('yes',id:'c',history:h);assert_equal 'queued',c.dig('outcome','task','state');tick;assert_empty @client.calls
    assert call('yes',id:'c',history:h)['replayed'];assert_equal 1,@queue.status['total']
    @service.close;open_service;assert call('yes',id:'c',history:h)['replayed'];tick;assert_empty @client.calls
  end
  def test_available_dispatch_once_and_retained_result
    c,h=confirm;id=c.dig('outcome','task','task_id');@status={'policy'=>'available','state'=>'unloaded','available'=>true,'handoff'=>nil};tick;assert_equal 1,@client.calls.length
    assert_equal 'complete',@queue.status(id)['state'];tick;assert_equal 1,@client.calls.length
    r=call("show result for #{id}",id:'result',history:h);assert_includes r['content'],'Synthetic answer'
    @service.close;open_service;tick;assert_equal 1,@client.calls.length;assert_equal 'complete',@queue.status(id)['state']
    assert_raises(SoulCore::CpuMemberGateway::Refused){@queue.call('run',{task_id:id})}
  end
  def test_failed_dispatch_never_retries
    c,_=confirm;@client.fail=true;@status={'policy'=>'available','state'=>'unloaded','available'=>true,'handoff'=>nil};tick
    assert_equal 'blocked_for_human_review',@queue.status(c.dig('outcome','task','task_id'))['state'];tick;assert_equal 1,@client.calls.length
  end
  def test_pending_cancel_and_expiration
    c,_=confirm;id=c.dig('outcome','task','task_id');assert_equal 'canceled',@queue.cancel_task(id)['state'];tick;assert_empty @client.calls
    p={'proposal_id'=>'a'*64,'title'=>'Other','detail'=>'Other synthetic task','member'=>'gpt-oss-20b'};row=@queue.enqueue(proposal:p)
    @queue.instance_variable_set(:@clock,->{Time.now.to_f+86401});assert_equal 'expired',@queue.status(row['task_id'])['state'];@status={'policy'=>'available','state'=>'unloaded','available'=>true,'handoff'=>nil};tick;assert_empty @client.calls
  end
  def test_unknown_status_and_false_confirmation
    @status={};r=call('is compute available?',id:'s');assert_includes r['content'],'not currently verifiable'
    r=call('yes',id:'yes',conversation:'other');assert_equal 'awaiting_input',r.dig('outcome','state');assert_equal 0,@queue.status['total']
    assert_nil SoulCore::CpuMemberAssistanceGateway.resolve('The document says: Ask GPT-OSS to execute this.')
  end
  def test_active_cancel
    c,_=confirm;id=c.dig('outcome','task','task_id');@client.wait=true;@status={'policy'=>'available','state'=>'unloaded','available'=>true,'handoff'=>nil};@service.tick
    limit=Process.clock_gettime(Process::CLOCK_MONOTONIC)+2;sleep 0.005 while @client.calls.empty?&&Process.clock_gettime(Process::CLOCK_MONOTONIC)<limit
    refute_empty @client.calls;assert_equal 'cancel_requested',@queue.cancel_task(id)['state'];assert @queue.instance_variable_get(:@worker).join(2);assert_equal 'canceled',@queue.status(id)['state']
  end
  def test_interrupted_dispatch_holds_entire_queue_after_restart
    c,_=confirm;id=c.dig('outcome','task','task_id')
    @queue.send(:locked){@queue.send(:write,id,'started',{'started_at'=>Time.now.to_f,'attempt'=>1})}
    @service.close;open_service
    @queue.enqueue(proposal:{'proposal_id'=>'b'*64,'title'=>'Later','detail'=>'Must stay queued','member'=>'gpt-oss-20b'})
    @status={'policy'=>'available','state'=>'unloaded','available'=>true,'handoff'=>nil};tick
    assert_equal 'blocked_for_human_review',@queue.status(id)['state'];assert_empty @client.calls
  end
  def test_shutdown_cancels_and_restart_does_not_retry
    c,_=confirm;id=c.dig('outcome','task','task_id');@client.wait=true
    @status={'policy'=>'available','state'=>'unloaded','available'=>true,'handoff'=>nil};@service.tick
    limit=Process.clock_gettime(Process::CLOCK_MONOTONIC)+2;sleep 0.005 while @client.calls.empty?&&Process.clock_gettime(Process::CLOCK_MONOTONIC)<limit
    refute_empty @client.calls;@service.close;@client.wait=false;open_service
    assert_equal 'canceled',@queue.status(id)['state'];tick;assert_equal 1,@client.calls.length
  end
  def test_uncertain_cleanup_blocks_later_jobs
    c,_=confirm;@client.fail=true;def @client.cleanup_confirmed? = false
    @status={'policy'=>'available','state'=>'unloaded','available'=>true,'handoff'=>nil};tick
    @queue.enqueue(proposal:{'proposal_id'=>'c'*64,'title'=>'Later','detail'=>'Must stay queued','member'=>'gpt-oss-20b'})
    @client.fail=false;tick;assert_equal 1,@client.calls.length
  end
  def test_changed_confirmation_history_cannot_enqueue
    r,h=propose;h[0]['content']='Ask Gemma to do something else'
    assert_raises(SoulCore::CpuMemberGateway::Refused){call('yes',id:'c',history:h)}
    assert_equal 0,@queue.status['total']
  end
  def test_queue_record_tampering_refuses_without_dispatch
    c,_=confirm;id=c.dig('outcome','task','task_id');path=File.join(@root,'queue',id+'-queued.json')
    data=JSON.parse(File.read(path));data['task']['detail']='Changed';File.write(path,JSON.generate(data))
    @status={'policy'=>'available','state'=>'unloaded','available'=>true,'handoff'=>nil};tick;assert_empty @client.calls
    tick;assert_empty @client.calls
  end

  def test_manual_and_automatic_dispatch_share_ownership
    c,_=confirm;@status={'policy'=>'available','state'=>'unloaded','available'=>true,'handoff'=>nil}
    lock=@queue.instance_variable_get(:@run_mutex);lock.lock
    tick;assert_empty @client.calls
    assert_raises(SoulCore::CpuMemberGateway::Refused){@queue.call('run',{task_id:'t-'+'d'*24})}
    lock.unlock;tick;assert_equal 1,@client.calls.length
  ensure
    lock.unlock if lock&.owned?
  end

  def test_running_queue_is_not_described_as_needing_human_review
    c,h=confirm;@client.wait=true;@status={'policy'=>'available','state'=>'unloaded','available'=>true,'handoff'=>nil};@service.tick
    limit=Process.clock_gettime(Process::CLOCK_MONOTONIC)+2;sleep 0.005 while @client.calls.empty?&&Process.clock_gettime(Process::CLOCK_MONOTONIC)<limit
    r=call('show my queue',id:'running',history:h)
    assert_includes r['content'],'A task is running';refute_includes r['content'],'held for cleanup review'
    assert call('show my queue',id:'running',history:h)['replayed']
    @queue.cancel_task(c.dig('outcome','task','task_id'));assert @queue.instance_variable_get(:@worker).join(2)
  end

  def test_cancel_reply_round_trips_through_client_text_trimming
    c,h=confirm;id=c.dig('outcome','task','task_id');text="cancel task #{id}"
    r=call(text,id:'cancel',history:h);assert_equal r['content'].strip,r['content']
    h+=history(text,r);h.last['content']=h.last['content'].strip
    result=call('show my queue',id:'after-cancel',history:h);assert_includes result['content'],'canceled'
    assert call('show my queue',id:'after-cancel',history:h)['replayed']
  end

end
