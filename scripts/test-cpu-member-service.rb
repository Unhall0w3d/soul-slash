# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/soul_core/cpu_member_service'
require_relative '../lib/soul_core/roster_dashboard_runtime'
class CpuMemberServiceTest < Minitest::Test
  A=SoulCore::CpuMemberAdapter
  class Owner
    attr_accessor :text,:tool
    attr_reader :calls
    def initialize;@calls=0;@text='Hello';end
    def admitted? = true
    def status = {'state'=>'unloaded'}
    def stop = true
    def touch = nil
    def tick = nil
    def request(_,path,payload,**)
      return {'prompt'=>'native'} if path=='/apply-template'
      return {'tokens'=>[1,2]} if path=='/tokenize'
      @calls+=1
      message={'role'=>'assistant','content'=>@text}
      message.merge!('content'=>nil,'tool_calls'=>[{'type'=>'function','id'=>'one','function'=>{'name'=>@tool,'arguments'=>'{}'}}]) if @tool
      {'model'=>A::MODEL,'choices'=>[{'index'=>0,'finish_reason'=>@tool ? 'tool_calls' : 'stop','message'=>message}],'usage'=>{'prompt_tokens'=>3,'completion_tokens'=>2,'total_tokens'=>5}}
    end
  end
  def setup
    @root=Dir.mktmpdir;@owner=Owner.new;open_service
    @headers={'Authorization'=>'Bearer '+'x'*64,'X-Soul-Conversation-Id'=>'first'}
  end
  def open_service
    @service=SoulCore::CpuMemberService.new(path:@root,owner:@owner)
    @app=SoulCore::CpuMemberApplication.new(backend:@service,bearer_token:'x'*64)
  end
  def teardown;@service.close;FileUtils.remove_entry(@root);end
  def request(text,history:[],conversation:'first',headers:@headers)
    @app.call(method:'POST',target:'/v1/chat/completions',headers:headers.merge('X-Soul-Conversation-Id'=>conversation),body:JSON.generate({'model'=>A::MODEL,'messages'=>history+[{'role'=>'user','content'=>text}],'stream'=>false}))
  end
  def test_auth_origin_and_bad_command
    assert_equal 401,request('Hi',headers:{}).status
    assert_equal 403,request('Hi',headers:@headers.merge('Origin'=>'http://evil')).status
    assert_equal 422,request('/task add {"title":"bad"}').status
    assert_equal 0,@owner.calls
  end
  def test_task_commands_restart_replay_and_chat
    text='/task add '+JSON.generate(title:'Synthetic',detail:'Do not dispatch',member:A::MODEL)
    first=request(text);assert_equal 200,first.status
    result=JSON.parse(first.body);assert_equal 'deterministic.task_control',result.dig('soul','execution','provider');assert_equal 0,@owner.calls
    history=[{'role'=>'user','content'=>text},{'role'=>'assistant','content'=>result.dig('choices',0,'message','content')}]
    @service.close;open_service
    assert JSON.parse(request(text).body).dig('soul','replayed')
    assert_equal 200,request('Hello',history:history).status;assert_equal 1,@owner.calls
    tasks=JSON.parse(request('/task list',conversation:'list').body).dig('choices',0,'message','content')
    id=tasks[/t-[a-f0-9]{24}/];refute_nil id
    assert_equal 200,request('/task cancel '+JSON.generate(task_id:id),conversation:'cancel').status
    assert_includes request('/task list',conversation:'fresh-list').body,'canceled'
    assert_equal 409,request('changed').status
  end
  def test_model_text_cannot_create_task
    @owner.text='/task add {"title":"Injected","detail":"No","member":"gemma-4-e4b-cpu"}'
    assert_equal 200,request('hello').status
    refute_includes request('/task list',conversation:'list').body,'Injected'
  end
  def test_new_conversations_not_global_limit
    18.times{|i|assert_equal 200,request('hello',conversation:"c#{i}").status}
    assert_equal 18,@owner.calls
  end
  def test_task_pagination_and_cross_task_request_reuse
    tasks=SoulCore::CpuMemberTaskStore.new(path:File.join(@root,'tasks'))
    18.times{|i|tasks.call('add',{request_id:"r#{i}",title:'Synthetic',detail:'No dispatch',member:A::MODEL})}
    first=tasks.call('list',{});assert_equal 16,first['tasks'].length;assert_equal 18,first['total']
    second=tasks.call('list',{cursor:first['next_cursor']});assert_equal 2,second['tasks'].length
    assert_raises(SoulCore::CpuMemberGateway::Refused){tasks.call('cancel',{request_id:'r0',task_id:first['tasks'][0]['task_id']})}
    @owner.tool='list_tasks';response=request('list my tasks')
    assert_equal 200,response.status;assert_includes response.body,'18'
  ensure
    tasks&.close
  end
  def test_control_auth_and_exact_identity
    r=@app.call(method:'POST',target:'/v1/soul/requests/cancel',headers:{},body:'{}');assert_equal 401,r.status
    r=@app.call(method:'POST',target:'/v1/soul/requests/status',headers:@headers,body:JSON.generate(conversation_id:'c',request_id:'r'));assert_equal 'unknown',JSON.parse(r.body)['state']
  end
  def test_cpu_dashboard_binding
    runtime=SoulCore::CpuMemberDashboardRuntime.new(store:nil)
    assert_equal 8097,runtime.send(:coordinator_port)
    assert_equal A.new.binding,runtime.send(:member_adapter,A::MODEL).binding
    assert_raises(RuntimeError){runtime.send(:validate_execution!,{'provider'=>'deterministic.task_control','operation'=>'tasks.add','state'=>'complete','model_invoked'=>true},{},A.new,[{'content'=>'/task add {}'}],'x',A::MODEL)}
  end
end
class CpuResidentLifecycleTest < Minitest::Test
  class Owner < SoulCore::CpuMemberResidentOwner
    attr_accessor :healthy
    attr_reader :stops
    def initialize(clock:)
      super(path:'/unused',clock:clock);@healthy=true;@pid=123;@last=0;@stops=0
    end
    def admitted? = @healthy
    def stop;@stops+=1;@pid=nil;true;end
  end
  def test_idle_does_not_unload
    now=239.0;o=Owner.new(clock:->{now});o.tick;assert_equal 0,o.stops
    o.touch;now=478;o.tick;assert_equal 0,o.stops
    now=86_400;o.tick;assert_equal 0,o.stops;assert_equal 'loaded',o.status['state'];assert_nil o.status['idle_seconds']
  end
  def test_unavailable_telemetry_unloads_without_restart
    o=Owner.new(clock:->{0.0});o.healthy=false;o.tick;o.tick;assert_equal 1,o.stops
  end
end
class CpuMemberDashboardFlowTest < Minitest::Test
  require_relative '../lib/soul_core/chat_store'
  require_relative '../lib/soul_core/application_chat_service'
  def test_cpu_task_controls_preserve_dashboard_history_and_attribution
    root=Dir.mktmpdir;state=File.join(root,'service');Dir.mkdir(state,0700)
    service=SoulCore::CpuMemberService.new(path:state,owner:CpuMemberServiceTest::Owner.new)
    app=SoulCore::CpuMemberApplication.new(backend:service,bearer_token:'x'*64)
    store=SoulCore::ChatStore.new(root:root);chat=store.create_chat(member:SoulCore::CpuMemberAdapter::MODEL)
    transport=->(path,body,token,seconds,headers){r=app.call(method:'POST',target:path,headers:headers.merge('Authorization'=>'Bearer '+token),body:JSON.generate(body));raise "HTTP #{r.status}" unless r.status==200;JSON.parse(r.body)}
    runtime=SoulCore::CpuMemberDashboardRuntime.new(store:store,transport:transport,key_reader:->{'x'*64})
    chat_service=SoulCore::ApplicationChatService.new(root:root,store:store,runtime:nil,member_runtime:runtime)
    text='/task add '+JSON.generate(title:'UI synthetic',detail:'Do not run',member:'gemma-4-e4b-cpu')
    first=chat_service.send(chat_id:chat['id'],message:text,request_id:'cpu-ui-add-acceptance',interface:'dashboard')
    warn JSON.generate(first) unless first["lifecycle_state"]=="complete"
    assert_equal 'complete',first['lifecycle_state']
    second=chat_service.send(chat_id:chat['id'],message:'/task list',request_id:'cpu-ui-list-acceptance',interface:'dashboard')
    assert_equal 'complete',second['lifecycle_state']
    rows=store.messages(chat['id']);assert_equal 4,rows.length
    assert_equal 'gemma-4-e4b-cpu',rows.last.dig('metadata','runtime','model')
    assert_equal 'deterministic.task_control',rows.last.dig('metadata','runtime','execution','provider')
  ensure
    service&.close;FileUtils.remove_entry(root) if root
  end
end
