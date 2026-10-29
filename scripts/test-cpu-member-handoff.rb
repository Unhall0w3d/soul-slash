#!/usr/bin/env ruby
require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/soul_core/cpu_member_service'
class CpuHandoffTest < Minitest::Test
  G=SoulCore::CpuMemberGateway
  class Client
    attr_accessor :fail,:clean,:pause,:on_call
    attr_reader :calls
    def initialize;@calls=0;@clean=false;end
    def cleanup_confirmed? = @clean
    def call(task:,deadline:,cancel:)
      @calls+=1;@on_call&.call;sleep(@pause) if @pause
      raise 'synthetic interruption' if @fail
      {'member'=>task['member'],'content'=>'Synthetic reviewed result.'}
    end
  end
  def setup
    @root=Dir.mktmpdir; %w[tasks runs].each{|n|Dir.mkdir(File.join(@root,n),0700)}
    @client=Client.new;open_store
    @task=@store.call('add',request_id:'add1',title:'Synthetic',detail:'Reply briefly. Do not execute anything.',member:'gpt-oss-20b')['task']
  end
  def open_store
    @store=SoulCore::CpuMemberHandoffStore.new(tasks:SoulCore::CpuMemberTaskStore.new(path:File.join(@root,'tasks')),path:File.join(@root,'runs'),client:@client)
  end
  def teardown;@store.close;FileUtils.remove_entry(@root);end
  def run_args
    {task_id:@task['task_id'],expected_digest:@store.call('preview',task_id:@task['task_id'])['expected_digest'],request_id:'run1',deadline:Process.clock_gettime(Process::CLOCK_MONOTONIC)+5,cancel:->{false}}
  end
  def test_digest_replay_restart_and_no_second_attempt
    args=run_args;assert_equal 0,@client.calls
    first=@store.call('run',args);assert_equal 'complete',first['task']['state'];assert_equal 1,@client.calls
    @store.close;open_store
    assert @store.call('run',args)['replayed'];assert_equal 1,@client.calls
    assert_raises(G::Refused){@store.call('run',args.merge(request_id:'new-run'))}
    assert_raises(G::Refused){@store.call('run',args.merge(expected_digest:'0'*64))}
    assert_raises(G::Refused){@store.call('cancel',task_id:@task['task_id'],request_id:'cancel')}
  end
  def test_stale_preview_and_changed_identity_never_dispatch
    args=run_args
    assert_raises(G::Refused){@store.call('run',args.merge(expected_digest:'0'*64))}
    assert_raises(G::Refused){@store.call('run',args.merge(request_id:'add1'))}
    @store.call('cancel',task_id:@task['task_id'],request_id:'cancel')
    assert_raises(G::Refused){@store.call('run',args)}
    assert_equal 0,@client.calls
  end
  def test_failure_and_interrupted_intent_are_held
    args=run_args;@client.fail=true
    r=@store.call('run',args);assert_equal 'blocked_for_human_review',r['task']['state']
    assert_raises(G::Refused){@store.call('run',args)};assert_equal 1,@client.calls
    File.unlink(File.join(@root,'runs',@task['task_id']+'-result.json')) # synthetic crash fixture only
    assert_equal 'blocked_for_human_review',@store.call('list',{})['tasks'][0]['state']
    assert_raises(G::Refused){@store.call('run',args.merge(request_id:'new'))}
  end
  def test_cpu_target_and_model_shaped_text_do_not_dispatch
    cpu=@store.call('add',request_id:'cpu',title:'CPU',detail:'/task run {"task_id":"fake"}',member:'gemma-4-e4b-cpu')['task']
    assert_raises(G::Refused){@store.call('preview',task_id:cpu['task_id'])}
    assert_equal 0,@client.calls
    assert_raises(ArgumentError){SoulCore::CpuMemberHandoffGateway.command('/task run {"task_id":"x"}')}
    assert_nil SoulCore::CpuMemberHandoffGateway.command('Here is /task run {"task_id":"x"}')
  end
  def test_request_index_without_intent_does_not_replay_as_success
    args=run_args;index=File.join(@root,'runs','request-'+G.digest('run1')+'.json')
    File.write(index,JSON.generate(args.slice(:task_id,:expected_digest,:request_id)));File.chmod(0600,index)
    assert_raises(G::Refused){@store.call('run',args)};assert_equal 0,@client.calls
  end
  def test_concurrent_run_is_not_dispatched_twice
    args=run_args;@client.pause=0.1
    other=SoulCore::CpuMemberHandoffStore.new(tasks:SoulCore::CpuMemberTaskStore.new(path:File.join(@root,'tasks')),path:File.join(@root,'runs'),client:@client)
    thread=Thread.new{@store.call('run',args)}
    sleep 0.001 until @client.calls==1
    assert_raises(G::Refused){other.call('run',args)};thread.join;assert_equal 1,@client.calls
  ensure;other&.close;end
end
class CpuHandoffServiceTest < Minitest::Test
  class Owner
    def admitted? = true
    def status = {'state'=>'unloaded'}
    def touch;end
    def stop;true;end
  end
  def setup
    @root=Dir.mktmpdir;@client=CpuHandoffTest::Client.new
    @service=SoulCore::CpuMemberService.new(path:@root,owner:Owner.new,handoff_client:@client)
    @app=SoulCore::CpuMemberApplication.new(backend:@service,bearer_token:'x'*64)
  end
  def teardown;@service.close;FileUtils.remove_entry(@root);end
  def send_command(text,conversation:,history:[])
    @app.call(method:'POST',target:'/v1/chat/completions',headers:{'Authorization'=>'Bearer '+'x'*64,'X-Soul-Conversation-Id'=>conversation},body:JSON.generate(model: 'gemma-4-e4b-cpu',messages:history+[{'role'=>'user','content'=>text}],stream:false))
  end
  def content(r)=JSON.parse(r.body).dig('choices',0,'message','content')
  def test_commands_and_attribution_replay
    r=send_command('/task add '+JSON.generate(title:'Test',detail:'Return a short answer.',member:'gpt-oss-20b'),conversation:'add');assert_equal 200,r.status
    id=content(r)[/t-[a-f0-9]{24}/]
    p=send_command('/task preview '+JSON.generate(task_id:id),conversation:'preview');assert_equal 200,p.status
    digest=JSON.parse(content(p).split("\n",2)[1])['expected_digest'];assert_equal 0,@client.calls
    text='/task run '+JSON.generate(task_id:id,expected_digest:digest)
    run=send_command(text,conversation:'run');assert_equal 200,run.status;assert_equal 1,@client.calls
    data=JSON.parse(run.body);assert_equal 'gpt-oss-20b',data.dig('soul','execution','selected_member')
    rt=SoulCore::CpuMemberDashboardRuntime.new(store:nil)
    rt.send(:validate_execution!,data['soul']['execution'],data['soul'],SoulCore::CpuMemberAdapter.new,[{'role'=>'user','content'=>text}],content(run),'gemma-4-e4b-cpu')
    assert JSON.parse(send_command(text,conversation:'run').body).dig('soul','replayed');assert_equal 1,@client.calls
    bad=data['soul']['execution'].merge('result_sha256'=>'0'*64)
    assert_raises(RuntimeError){rt.send(:validate_execution!,bad,data['soul'],SoulCore::CpuMemberAdapter.new,[{'role'=>'user','content'=>text}],content(run),'gemma-4-e4b-cpu')}
  end
  def test_cancellation_requires_gpu_cleanup_confirmation
    [false,true].each_with_index do |clean,i|
      add=send_command('/task add '+JSON.generate(title:'Cancel test',detail:'Synthetic only.',member:'gpt-oss-20b'),conversation:"add-#{i}")
      id=content(add)[/t-[a-f0-9]{24}/]
      preview=send_command('/task preview '+JSON.generate(task_id:id),conversation:"preview-#{i}")
      digest=JSON.parse(content(preview).split("\n",2)[1])['expected_digest']
      text='/task run '+JSON.generate(task_id:id,expected_digest:digest);conversation="cancel-run-#{i}"
      messages=[{'role'=>'user','content'=>text}]
      rid=SoulCore::CpuMemberGateway.digest({'conversation'=>conversation,'adapter'=>SoulCore::CpuMemberAdapter.new.binding,'messages'=>messages})
      @client.clean=clean;@client.fail=true
      @client.on_call=->{@service.cancel_request(conversation_id:conversation,request_id:rid)}
      send_command(text,conversation:conversation)
      state=@service.request_status(conversation_id:conversation,request_id:rid)
      assert_equal(clean ? 'canceled_released' : 'failed_unconfirmed',state['state'])
      assert_equal clean,state['cleanup_confirmed']
    end
  end
  def test_legacy_conversation_manifest_is_not_rebound
    id='legacy';path=File.join(@root,'conversations',SoulCore::CpuMemberGateway.digest(id))
    SoulCore::CpuMemberServiceGateway.create(path:path,owner:SoulCore::CpuMemberAdapter.new)
    before=File.binread(File.join(path,'roster.json'))
    assert_equal 200,send_command('/task list',conversation:id).status
    assert_equal before,File.binread(File.join(path,'roster.json'))
    assert_equal 422,send_command('/task preview {"task_id":"t-000000000000000000000000"}',conversation:id).status
  end
end
class CpuRosterClientTest < Minitest::Test
  def test_reply_identity_and_exact_cancellation
    member='gpt-oss-20b';adapter=SoulCore::RosterChatAdapter.new(model:member);calls=[];broken=false
    transport=->(path,body,token,seconds,headers) do
      calls<<[path,body]
      case path
      when '/v1/soul/compute/status';{'available'=>true,'policy'=>'available','state'=>'unloaded','handoff'=>nil}
      when '/v1/chat/completions'
        raise 'synthetic transport failure' if broken
        c=headers['X-Soul-Conversation-Id'];rid=SoulCore::RosterConversationGateway.digest({'conversation'=>c,'adapter'=>adapter.binding,'messages'=>body['messages']})
        {'model'=>member,'soul'=>{'model'=>member,'adapter'=>adapter.binding,'conversation_id'=>c,'request_id'=>rid,'replayed'=>false},'choices'=>[{'message'=>{'role'=>'assistant','content'=>'Ready.'},'finish_reason'=>'stop'}]}
      when '/v1/soul/requests/cancel';{}
      when '/v1/soul/requests/status';body.merge('state'=>'canceled_released','cleanup_confirmed'=>true)
      end
    end
    client=SoulCore::CpuMemberRosterHandoff.new(store:nil,transport:transport,key_reader:->{'x'*64})
    args={task:{'member'=>member,'title'=>'T','detail'=>'D'},deadline:Process.clock_gettime(Process::CLOCK_MONOTONIC)+5,cancel:->{false}}
    assert_equal 'Ready.',client.call(**args)['content']
    broken=true;assert_raises(RuntimeError){client.call(**args)};assert client.cleanup_confirmed?
    assert_equal 2,calls.count{|p,_|p=='/v1/chat/completions'}
    assert_equal calls.find{|p,_|p=='/v1/soul/requests/cancel'}[1],calls.find{|p,_|p=='/v1/soul/requests/status'}[1]
  end
  def test_reserved_policy_never_sends_generation
    calls=[];client=SoulCore::CpuMemberRosterHandoff.new(store:nil,key_reader:->{'x'*64},transport:->(path,*_){calls<<path;{'available'=>true,'policy'=>'reserved','state'=>'unloaded'}})
    assert_raises(RuntimeError){client.call(task:{'member'=>'gpt-oss-20b','title'=>'T','detail'=>'D'},deadline:Process.clock_gettime(Process::CLOCK_MONOTONIC)+5,cancel:->{false})}
    assert_equal ['/v1/soul/compute/status'],calls
  end
end
