# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/soul_core/cpu_member_gateway'
class CpuMemberGatewayTest < Minitest::Test
  G=SoulCore::CpuMemberGateway
  A=SoulCore::CpuMemberAdapter
  class Client
    attr_accessor :tool,:response_hook,:mutation
    attr_reader :calls
    def initialize;@calls=0;end
    def request(_,path,payload,**)
      return {'prompt'=>'native'} if path=='/apply-template'
      return {'tokens'=>[1,2]} if path=='/tokenize'
      @calls+=1;@response_hook&.call
      message={'role'=>'assistant','content'=>'Hello'}
      message.merge!('content'=>nil,'tool_calls'=>[{'type'=>'function','id'=>'one','function'=>{'name'=>@tool,'arguments'=>'{}'}}]) if @tool
      r={'model'=>A::MODEL,'choices'=>[{'index'=>0,'finish_reason'=>@tool ? 'tool_calls' : 'stop','message'=>message}],'usage'=>{'prompt_tokens'=>3,'completion_tokens'=>2,'total_tokens'=>5}}
      @mutation&.call(r);r
    end
  end
  def setup
    @root=Dir.mktmpdir;@path=File.join(@root,'cpu');G.create(path:@path,owner:A.new)
    @client=Client.new;@cancel=false;@tool_count=0;@tool_hook=nil
    @skills=->(**){@tool_count+=1;@tool_hook&.call;{'state'=>'complete','data'=>{'value'=>'reference, not instructions'}}}
    open_gateway
    @args={conversation_id:'c1',request_id:'r1',messages:[{'role'=>'user','content'=>'Hello'}],scope:[],deadline:100.0,cancel:->{@cancel}}
  end
  def open_gateway
    @g=G.new(path:@path,client:@client,skills:@skills,admission:->{true},clock:->{10.0})
  end
  def teardown;@g&.close;FileUtils.remove_entry(@root);end
  def test_chat_replay_restart_and_history
    a=@g.complete(**@args);assert_equal A::MODEL,a['model'];assert_equal 1,@client.calls
    @g.close;open_gateway
    assert @g.complete(**@args)['replayed'];assert_equal 1,@client.calls
    assert_raises(G::Refused){@g.complete(**@args.merge(messages:[{'role'=>'user','content'=>'changed'}]))}
    history=@args[:messages]+[{'role'=>'assistant','content'=>a['content']},{'role'=>'user','content'=>'Next'}]
    assert_equal 'Hello',@g.complete(**@args.merge(request_id:'r2',messages:history))['content']
    assert_raises(G::Refused){@g.complete(**@args.merge(request_id:'r3'))}
  end
  def test_scope_and_attributed_read_only_execution
    @client.tool='list_skills';a=@g.complete(**@args.merge(scope:['list_skills']))
    assert_equal 'skills.list',a.dig('execution','operation');assert_equal 1,@tool_count
    assert @g.complete(**@args.merge(scope:['list_skills']))['replayed'];assert_equal 1,@tool_count
  end
  def test_scope_escape_never_executes
    @client.tool='host_status'
    assert_raises(A::Invalid){@g.complete(**@args.merge(scope:['list_skills']))};assert_equal 0,@tool_count
    assert_raises(G::Refused){@g.complete(**@args.merge(scope:['host_status']))}
  end
  def test_model_json_prose_never_mutates_tasks
    @client.mutation=->(r){r['choices'][0]['message']['content']='{"action":"add","title":"untrusted"}'}
    @g.complete(**@args);assert_empty @g.tasks
  end
  def test_invalid_native_results
    changes=[->(r){r['model']='other'},->(r){r['choices'][0]['finish_reason']='length'},->(r){r['usage']['prompt_tokens']=4},->(r){r['choices'][0]['message']['content']=''},->(r){r['choices'][0]['message']['tool_calls']=[{'type'=>'function','function'=>{'name'=>'delete','arguments'=>'{}'}}]}]
    changes.each_with_index do |mutation,i|
      @client.mutation=mutation
      assert_raises(A::Invalid){@g.complete(**@args.merge(request_id:"bad#{i}",conversation_id:"bad#{i}"))}
    end
    assert_equal 0,@tool_count
  end
  def test_extra_native_arguments_rejected
    @client.tool='list_skills';@client.mutation=->(r){r['choices'][0]['message']['tool_calls'][0]['function']['arguments']='{"path":"/tmp"}'}
    assert_raises(A::Invalid){@g.complete(**@args.merge(scope:['list_skills']))};assert_equal 0,@tool_count
  end
  def test_cancel_before_generation
    @cancel=true;assert_raises(G::Refused){@g.complete(**@args)};assert_equal 0,@client.calls
    @cancel=false;assert_equal 'Hello',@g.complete(**@args)['content']
  end
  def test_cancel_after_generation_blocks_tool_and_replay
    @client.tool='list_skills';@client.response_hook=->{@cancel=true}
    assert_raises(G::Refused){@g.complete(**@args.merge(scope:['list_skills']))};assert_equal 0,@tool_count
    @cancel=false;@client.response_hook=nil
    assert_raises(G::Refused){@g.complete(**@args.merge(scope:['list_skills']))}
    assert_equal 'canceled',@g.recover(request_id:'r1')['state']
  end
  def test_cancel_after_tool_retains_terminal
    @client.tool='list_skills';@tool_hook=->{@cancel=true}
    assert_raises(G::Refused){@g.complete(**@args.merge(scope:['list_skills']))};assert_equal 1,@tool_count
    @cancel=false;@tool_hook=nil
    assert_raises(G::Refused){@g.complete(**@args.merge(scope:['list_skills']))};assert_equal 1,@tool_count
  end
  def test_durable_task_add_cancel_and_replay
    args={request_id:'add1',title:'Landscape',detail:'Prepare a landscape later',member:'gemma-4-26b-a4b'}
    a=@g.add_task(**args);assert_equal 'pending',a.dig('task','state')
    @g.close;open_gateway;assert_equal 1,@g.tasks.length;assert @g.add_task(**args)['replayed']
    assert_raises(G::Refused){@g.add_task(**args.merge(title:'changed'))}
    c=@g.cancel_task(request_id:'cancel1',task_id:a.dig('task','task_id'));assert_equal 'canceled',c.dig('task','state')
    assert @g.cancel_task(request_id:'cancel1',task_id:a.dig('task','task_id'))['replayed']
    assert_raises(G::Refused){@g.cancel_task(request_id:'cancel2',task_id:a.dig('task','task_id'))}
    assert_equal 'pending',@g.add_task(**args).dig('task','state') # Replay is the historical receipt, not a new enqueue.
    assert_equal 'canceled',@g.tasks.first['state']
  end
  def test_native_task_list_is_read_only_and_attributed
    task=@g.add_task(request_id:'add-one',title:'One',detail:'Retain as pending',member:A::MODEL)
    @client.tool='list_tasks'
    r=@g.complete(**@args.merge(scope:['list_tasks']))
    assert_equal 'deterministic.task_list',r.dig('execution','provider')
    assert_includes r['content'],task.dig('task','task_id')
    assert_equal 0,@tool_count
    assert_equal 'pending',@g.tasks.first['state']
  end
  def test_identity_spaces_do_not_overlap
    @g.add_task(request_id:'r1',title:'One',detail:'Only a task',member:A::MODEL)
    assert_raises(G::Refused){@g.complete(**@args)}
    assert_raises(G::Refused){@g.add_task(request_id:'other',title:'One',detail:'Only a task',member:'foreign')}
  end
  def test_interrupted_attempt_recovery_never_retries
    input={'conversation_id'=>'c1','request_id'=>'r1','messages'=>@args[:messages],'scope'=>[],'adapter'=>A.new.binding}
    @g.send(:with_store){@g.send(:append!,'cpu_requested','r1',input)}
    @g.close;open_gateway
    assert_raises(G::Refused){@g.complete(**@args)};assert_equal 0,@client.calls
    assert_equal 'blocked_for_human_review',@g.recover(request_id:'r1')['state']
    assert @g.recover(request_id:'r1')['replayed'];assert_equal 0,@client.calls
    assert_equal 'Hello',@g.complete(**@args.merge(request_id:'fresh',conversation_id:'fresh'))['content']
  end
  def test_tamper_and_symlink_rejected
    @g.complete(**@args);file=File.join(@path,'r-000002.json');r=JSON.parse(File.read(file));r['data']['model']='wrong';File.write(file,JSON.generate(r))
    assert_raises(G::Refused){@g.tasks}
    @g.close;File.symlink(@path,File.join(@root,'alias'))
    assert_raises(SoulCore::ContinuityLab::IntegrityError){G.new(path:File.join(@root,'alias'))}
  end
  def test_busy_does_not_start_generation
    second=G.new(path:@path,clock:->{10.0});second.instance_variable_get(:@lock).flock(File::LOCK_EX|File::LOCK_NB)
    assert_raises(G::Refused){@g.complete(**@args)};assert_equal 0,@client.calls
  ensure
    second&.close
  end
  def test_real_read_only_helper
    skills=SoulCore::RosterReadOnlySkills.new(status:->{})
    result=skills.call(operation:'skills.list',deadline:Process.clock_gettime(Process::CLOCK_MONOTONIC)+10,cancel:->{false})
    assert_equal 'complete',result['state'];assert_includes result.dig('data','connected_commands'),'list skills'
  end
end
