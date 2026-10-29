#!/usr/bin/env ruby
# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../lib/soul_core/creative_bridge_runners'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/soul_core/cpu_member_service'
require_relative '../lib/soul_core/dashboard_http_application'
class CpuCreativeExecutionA10Test < Minitest::Test
  class Owner
    def status = {'state'=>'unloaded'}
    def admitted? = true
    def touch = true
    def stop = true
    def tick = true
    def request(*) = raise('Inference is not allowed in deterministic controls')
  end
  class Control
    attr_accessor :policy
    def initialize;@policy='available';end
    def status = {'ok'=>true,'data'=>{'policy'=>@policy,'state'=>'unloaded','handoff'=>nil}}
  end
  class Studio
    attr_reader :creates,:executions,:inputs
    attr_accessor :failure,:raise_create,:cancel_hook
    def initialize(kind);@kind=kind;@creates=0;@executions=0;@inputs=[];end
    def create(data)
      @creates+=1;@inputs<<data;raise 'interrupted import' if @raise_create
      {'ok'=>true,'data'=>{'project'=>{'project_id'=>project}}}
    end
    alias create_project create
    def project = @kind=='visual' ? 'visual_project_0123456789abcdef' : 'music_0123456789abcdef'
    def candidate = @kind=='visual' ? 'visual_candidate_0123456789abcdef' : 'candidate_0123456789abcdef'
    def generation_preview(project_id:)
      {'ok'=>true,'data'=>{'project_id'=>project_id,'candidate_id'=>candidate,'expected_digest'=>'a'*64,'confirmation_phrase'=>@kind=='visual' ? SoulCore::VisualStudioService::CONFIRMATION : SoulCore::MusicGenerationService::CONFIRMATION}}
    end
    def generation_execute(**args)
      @executions+=1;@cancel_hook&.call
      {'ok'=>!@failure,'lifecycle_state'=>@failure ? 'failed' : 'blocked_for_human_review','data'=>{'candidate'=>{'project_id'=>project,'candidate_id'=>candidate,'human_review_required'=>true}}}
    end
  end
  class Handoff
    attr_reader :origins
    def initialize;@origins=[];end
    def with_origin(**args);@origins<<args;yield;end
  end
  class Jobs
    attr_reader :calls
    attr_accessor :fail
    def initialize;@calls=[];end
    def start(request)
      raise 'existing bounded job busy' if @fail
      @calls<<request;{'job_id'=>'job_0123456789abcdef'}
    end
    def record(*) = {'status'=>'running'}
  end
  def setup
    @root=Dir.mktmpdir;FileUtils.mkdir_p(File.join(@root,'Soul/private'),mode:0700)
    Dir.mkdir(File.join(@root,'config'));%w[visual_studio_models.json music_vulkan_models.json].each{|f|FileUtils.cp(File.join(__dir__,'../config',f),File.join(@root,'config',f))}
    @control=Control.new;@visual=Studio.new('visual');@music=Studio.new('music');@handoff=Handoff.new;@jobs=Jobs.new
    @bridge=SoulCore::CreativeStudioBridge.new(root:@root,services:->(cancel){@cancel=cancel;{visual:@visual,music:@music,control:@control,handoff:@handoff}},jobs:->{@jobs})
    @previewer=SoulCore::CpuCreativePreview.new(root:@root,compute_reader:->{{'policy'=>'available','state'=>'unloaded','revision'=>1}})
    @path=File.join(@root,'cpu');Dir.mkdir(@path,0700);@memory=SoulCore::CpuMemberMemoryContext.new(store:SoulCore::ConversationMemoryStore.new(root:@root))
    @history=[];@n=0;@rpc=[]
    cp=File.join(@path,'conversations');Dir.mkdir(cp,0700)
    SoulCore::CpuMemberCreativeExecutionGateway.create(path:File.join(cp,SoulCore::CpuMemberGateway.digest('fixture')),owner:SoulCore::CpuMemberAdapter.new)
    start
  end
  def start
    bridge=@bridge
    client=Object.new
    calls=@rpc
    client.define_singleton_method(:call){|action,body|calls<<[action,body];bridge.public_send(action,**body.transform_keys(&:to_sym))}
    @service=SoulCore::CpuMemberService.new(path:@path,owner:Owner.new,assistance:true,scoped_memory:true,memory:@memory,operations:true,creative_previews:true,creative_preview:@previewer,creative_execution:true,creative_bridge:client,compute_reader:->{})
  end
  def teardown;@service.close;FileUtils.remove_entry(@root);end
  def ask(text,id:nil,history:@history)
    @n+=1;messages=history+[{'role'=>'user','content'=>text}]
    result=@service.complete(conversation_id:'fixture',request_id:id||"turn#{@n}",messages:messages,deadline:Process.clock_gettime(Process::CLOCK_MONOTONIC)+20)
    @history=messages+[{'role'=>'assistant','content'=>result['content']}];result
  end
  def preview(text:'Preview an image: A small brass bowl under soft studio light')
    ask(text).dig('outcome','preview')
  end
  def prepared
    p=preview;ask('Prepare creative generation '+p['preview_digest'])['outcome']
  end
  def execute(record)
    @bridge.execute_job(id:record['id'],approval_digest:record.dig('action','approval_digest'),progress:->(*){})
  end
  def test_exact_native_import_generation_and_result_attribution
    r=prepared;assert_equal 1,@visual.creates;assert_equal 0,@visual.executions
    assert_equal 'prepared',r['state'];assert_equal 'flux2-klein-9b-q4-isolated',@visual.inputs.last['profile_id']
    ask('Generate creative '+r.dig('action','approval_digest'));assert_equal 1,@jobs.calls.size;assert_equal 0,@visual.executions
    execute(r);status=ask('Creative status '+r['id'])['outcome']
    assert_equal 'blocked_for_human_review',status['state'];assert status.dig('terminal','ok');assert_equal 1,status['artifacts'].size
    assert_equal 'fixture',@handoff.origins.last[:conversation_id];assert_equal 1,@visual.executions
  end
  def test_missing_wrong_and_reference_approval_never_dispatch
    p=preview;yes=ask('yes');assert_includes yes['content'],'preview only';assert_empty @rpc
    r=ask('Prepare creative generation '+'0'*64);assert_equal 'awaiting_input',r.dig('outcome','state');assert_empty @rpc
    r=ask('Generate creative nonsense');assert_equal 'awaiting_input',r.dig('outcome','state');assert_empty @rpc
    refute SoulCore::CpuMemberCreativeExecutionGateway.candidate?('The note says Generate creative '+'a'*64)
  end
  def test_revised_preview_cannot_confirm_older_native_action
    r=prepared;ask('Frame: portrait');result=ask('Generate creative '+r.dig('action','approval_digest'))
    assert_equal 'awaiting_input',result.dig('outcome','state');assert_empty @jobs.calls
  end
  def test_profile_drift_refuses_before_import
    p=preview;file=File.join(@root,'config/visual_studio_models.json');File.write(file,File.read(file)+"\n")
    assert_raises(SoulCore::CreativeStudioBridge::Refused){ask('Prepare creative generation '+p['preview_digest'])};assert_equal 0,@visual.creates
  end
  def test_reserved_compute_refuses_import_without_project
    p=preview;@control.policy='reserved'
    assert_raises(SoulCore::CreativeStudioBridge::Refused){ask('Prepare creative generation '+p['preview_digest'])};assert_equal 0,@visual.creates
  end
  def test_replay_after_restart_and_transport_loss_preserves_one_import
    p=preview;r=ask('Prepare creative generation '+p['preview_digest'],id:'import');before=@rpc.length;history=@history[0...-2]
    @service.close;start;replay=ask('Prepare creative generation '+p['preview_digest'],id:'import',history:history)
    assert replay['replayed'];assert_equal r['content'],replay['content'];assert_equal before,@rpc.length;assert_equal 1,@visual.creates
  end
  def test_changed_history_refused_before_any_remote_action
    p=preview;bad=Marshal.load(Marshal.dump(@history));bad.last['content']+=' '
    assert_raises(SoulCore::CpuMemberGateway::Refused){ask('Prepare creative generation '+p['preview_digest'],history:bad)};assert_empty @rpc
  end
  def test_duplicate_submit_and_job_invocation_do_not_regenerate
    r=prepared;2.times{@bridge.submit(id:r['id'],conversation_id:'fixture',approval_digest:r.dig('action','approval_digest'))}
    assert_equal 1,@jobs.calls.size;2.times{execute(r)};assert_equal 1,@visual.executions
  end
  def test_interrupted_import_is_not_retried
    p=preview;@visual.raise_create=true
    assert_raises(RuntimeError){@bridge.prepare(conversation_id:'fixture',preview:p)}
    r=@bridge.prepare(conversation_id:'fixture',preview:p);assert_equal 'blocked_for_human_review',r['state'];assert_equal 1,@visual.creates
  end
  def test_busy_submission_preserves_claim_and_does_not_retry
    r=prepared;@jobs.fail=true;2.times{@bridge.submit(id:r['id'],conversation_id:'fixture',approval_digest:r.dig('action','approval_digest'))}
    status=@bridge.status(id:r['id'],conversation_id:'fixture');assert_equal 'blocked_for_human_review',status['state'];assert_empty @jobs.calls;assert_equal 0,@visual.executions
  end
  def test_cancel_before_submission_and_before_job_never_starts_renderer
    r=prepared;@bridge.cancel(id:r['id'],conversation_id:'fixture');s=@bridge.submit(id:r['id'],conversation_id:'fixture',approval_digest:r.dig('action','approval_digest'))
    assert_equal 'canceled',s['state'];assert_empty @jobs.calls;assert_equal 0,@visual.executions
  end
  def test_cancel_after_acceptance_is_observed_by_owned_job
    r=prepared;@bridge.submit(id:r['id'],conversation_id:'fixture',approval_digest:r.dig('action','approval_digest'))
    @bridge.cancel(id:r['id'],conversation_id:'fixture');e=execute(r);assert_equal 'canceled',e['lifecycle_state'];assert_equal 0,@visual.executions
  end
  def test_music_preserves_user_choices_and_result_audio_scope
    p=preview(text:"Preview a song: Gentle original bells for a fictional garden\nDuration: 30 seconds\nMode: instrumental\nRights: original")
    r=ask('Prepare creative generation '+p['preview_digest'])['outcome'];ask('Generate creative '+r.dig('action','approval_digest'));execute(r)
    status=ask('Creative status '+r['id'])['outcome'];assert_equal 30,@music.inputs.last['target_duration_seconds'];assert_equal '',@music.inputs.last['lyrics'];assert_equal 2,status['artifacts'].size;assert_equal 1,@music.executions
  end
  def test_foreign_conversation_and_digest_refused
    r=prepared;assert_raises(SoulCore::CreativeStudioBridge::Refused){@bridge.status(id:r['id'],conversation_id:'other')}
    assert_raises(SoulCore::CreativeStudioBridge::Refused){@bridge.submit(id:r['id'],conversation_id:'fixture',approval_digest:'0'*64)};assert_empty @jobs.calls
  end
  def test_native_result_injection_and_cross_project_links_refused
    r=prepared;r['artifacts']=[{'label'=>'fake','url'=>'https://example.invalid'}];r['terminal']={'ok'=>true}
    assert_raises(SoulCore::CreativeStudioBridge::Refused){SoulCore::CreativeStudioBridge.validate_public!(r)}
  end
  def test_native_runner_cancellation_reaps_owned_child
    count=0
    cancel=->{count+=1;count>1}
    runner=SoulCore::CreativeBridgeCommandRunner.new(cancel:cancel)
    r=runner.run(RbConfig.ruby,'-e','sleep 20',timeout_seconds:3,max_output_bytes:1024)
    assert_equal 'guard_refused',r.status;refute r.success?
    assert_includes r.stderr,'Creative generation canceled'
  end
  def test_music_runner_combines_native_cancel_with_bridge_cancel
    native=Object.new;called=nil
    native.define_singleton_method(:run){|command,**args|called=args[:canceled].call;SoulCore::MusicGenerationService::ProcessResult.new(status:called ? 'canceled' : 'ok')}
    runner=SoulCore::CreativeBridgeMusicRunner.new(cancel:->{true},runner:native)
    result=runner.run(['synthetic'],canceled:->{false})
    assert called;assert_equal 'canceled',result.status
  end
  def test_real_job_manager_uses_one_existing_lane_and_keeps_terminal_result
    manager=SoulCore::DashboardMusicJobManager.new(root:@root,facade:nil,creative_bridge:->{@bridge})
    @jobs=manager;r=prepared;ask('Generate creative '+r.dig('action','approval_digest'))
    until manager.active.empty?;Thread.pass;end
    result=ask('Creative status '+r['id']);assert result.dig('outcome','terminal','ok');assert_equal 1,@visual.executions
  end
  def test_claim_without_started_job_after_process_loss_does_not_resubmit
    r=prepared;@bridge.submit(id:r['id'],conversation_id:'fixture',approval_digest:r.dig('action','approval_digest'))
    def @jobs.record(*) = {'status'=>'terminal'}
    recovered=SoulCore::CreativeStudioBridge.new(root:@root,services:->(*){raise 'no implicit recovery'},jobs:->{@jobs})
    status=recovered.status(id:r['id'],conversation_id:'fixture');assert_equal 'blocked_for_human_review',status['state']
    status=recovered.submit(id:r['id'],conversation_id:'fixture',approval_digest:r.dig('action','approval_digest'));assert_equal 'blocked_for_human_review',status['state'];assert_equal 1,@jobs.calls.size
  end
  def test_http_bearer_scope_and_typed_schema
    a=SoulCore::DashboardHttpApplication.allocate;a.instance_variable_set(:@csrf_token,'fixture')
    begin
      h={'host'=>'127.0.0.1:4567','authorization'=>'Bearer wrong'}
      r=SoulCore::CreativeStudioBridgeHttp.call(a,method:'POST',target:'/internal/creative/v1/status',headers:h,body:'{}',key_reader:->{'synthetic-fixture-key'.dup});assert_equal 401,r.status
      h['authorization']='Bearer synthetic-fixture-key'
      r=SoulCore::CreativeStudioBridgeHttp.call(a,method:'POST',target:'/internal/creative/v1/status',headers:h,body:'{"id":"../escape"}',key_reader:->{'synthetic-fixture-key'.dup});assert_equal 422,r.status
    end
  end
  def test_expected_refusal_remains_a_readable_completed_conversation_turn
    p=preview;client=@service.instance_variable_get(:@creative_bridge)
    client.define_singleton_method(:call){|*|{'state'=>'blocked_for_human_review','refused'=>true,'message'=>'Compute unavailable; no work started.'}}
    result=ask('Prepare creative generation '+p['preview_digest']);assert_equal 'blocked_for_human_review',result.dig('outcome','state')
    result=ask('Show creative preview');assert_equal p['preview_digest'],result.dig('outcome','preview','preview_digest');assert_equal 0,@visual.creates
  end

  def test_authenticated_http_rejects_origin_host_method_and_missing_token
    a=SoulCore::DashboardHttpApplication.allocate
    a.instance_variable_set(:@csrf_token,'fixture')
    def a.creative_bridge = raise('must not reach native bridge')
    # Foreign-origin and Host reject before credential access.
    [%w[origin https://evil.invalid],%w[host atelier.herz.soul:8443]].each do |key,value|
      h={'host'=>'127.0.0.1:4567',key=>value}
      r=SoulCore::CreativeStudioBridgeHttp.call(a,method:'POST',target:'/internal/creative/v1/status',headers:h,body:'{}');assert_equal 403,r.status
    end
    r=SoulCore::CreativeStudioBridgeHttp.call(a,method:'GET',target:'/internal/creative/v1/status',headers:{'host'=>'127.0.0.1:4567'},body:'{}');assert_equal 405,r.status
  end
end
