# frozen_string_literal: true
require_relative 'test-cpu-creative-execution-a10'
class CpuCreativeExecutionA10V2Test < Minitest::Test
  def setup
    @root=Dir.mktmpdir;FileUtils.mkdir_p(File.join(@root,'Soul/private'),mode:0700)
    Dir.mkdir(File.join(@root,'config'));%w[visual_studio_models.json music_vulkan_models.json].each{|f|FileUtils.cp(File.join(__dir__,'../config',f),File.join(@root,'config',f))}
    @control=CpuCreativeExecutionA10Test::Control.new;@visual=CpuCreativeExecutionA10Test::Studio.new('visual');@music=CpuCreativeExecutionA10Test::Studio.new('music');@handoff=CpuCreativeExecutionA10Test::Handoff.new
    @jobs=CpuCreativeExecutionA10Test::Jobs.new
    @bridge=SoulCore::CreativeStudioBridgeV2.new(root:@root,services:->(*){{visual:@visual,music:@music,control:@control,handoff:@handoff}},jobs:->{@jobs})
    @previewer=SoulCore::CpuCreativePreview.new(root:@root,compute_reader:->{{'policy'=>'available','state'=>'unloaded','revision'=>1}})
    @path=File.join(@root,'cpu');Dir.mkdir(@path,0700);@memory=SoulCore::CpuMemberMemoryContext.new(store:SoulCore::ConversationMemoryStore.new(root:@root));@history=[];@n=0;start
  end
  def start
    bridge=@bridge;client=Object.new
    client.define_singleton_method(:call){|action,body|bridge.public_send(action,**body.transform_keys(&:to_sym))}
    @service=SoulCore::CpuMemberService.new(path:@path,owner:CpuCreativeExecutionA10Test::Owner.new,assistance:true,scoped_memory:true,memory:@memory,operations:true,creative_previews:true,creative_preview:@previewer,creative_execution:true,creative_bridge:client,compute_reader:->{})
  end
  def teardown;@service.close;FileUtils.remove_entry(@root);end
  def ask(text)
    @n+=1;messages=@history+[{'role'=>'user','content'=>text}]
    r=@service.complete(conversation_id:'fixture',request_id:"turn#{@n}",messages:messages,deadline:Process.clock_gettime(Process::CLOCK_MONOTONIC)+10)
    @history=messages+[{'role'=>'assistant','content'=>r['content']}];r
  end
  def prepare(music:false)
    text=music ? "Preview a song: Gentle original bells for a fictional garden\nDuration: 30 seconds\nMode: instrumental\nRights: original" : 'Preview an image: A small brass bowl under soft studio light'
    p=ask(text).dig('outcome','preview');ask('Prepare creative generation '+p['preview_digest'])['outcome']
  end
  def ready(music:false)
    r=prepare(music:music);@bridge.execute_prepare_job(id:r['id'],progress:->(*){})
    ask('Creative status '+r['id'])['outcome']
  end
  def test_async_preparation_has_no_native_writes_until_owned_job
    r=prepare;assert_equal 'preparing',r['state'];assert_equal 0,@visual.creates;assert_nil r['action'];assert_equal 'creative.bridge.v2.prepare',@jobs.calls.last['operation']
    @bridge.execute_prepare_job(id:r['id'],progress:->(*){});s=ask('Creative status '+r['id'])['outcome']
    assert_equal 'prepared',s['state'];assert_equal 1,@visual.creates;assert_equal 0,@visual.executions;assert s.dig('action','approval_digest')
  end
  def test_exact_approval_results_and_replay_after_restart
    r=ready;@service.close;start
    ask('Generate creative '+r.dig('action','approval_digest'));@bridge.execute_job(id:r['id'],approval_digest:r.dig('action','approval_digest'),progress:->(*){})
    result=ask('Creative status '+r['id']);assert result.dig('outcome','terminal','ok');assert_equal 1,@visual.executions;assert_equal 1,result.dig('outcome','artifacts').size
    @bridge.submit(id:r['id'],conversation_id:'fixture',approval_digest:r.dig('action','approval_digest'));assert_equal 2,@jobs.calls.size
  end
  def test_music_gets_separate_preparation_and_generation_approvals
    r=ready(music:true);assert_equal 30,r.dig('action','brief','duration_seconds');assert_equal 0,@music.executions
    ask('Generate creative '+r.dig('action','approval_digest'));@bridge.execute_job(id:r['id'],approval_digest:r.dig('action','approval_digest'),progress:->(*){})
    result=ask('Creative status '+r['id']);assert_equal 2,result.dig('outcome','artifacts').size;assert_equal 1,@music.executions
  end
  def test_cancel_before_async_creation_has_no_project_and_no_retry
    r=prepare;ask('Cancel creative generation '+r['id']);@bridge.execute_prepare_job(id:r['id'],progress:->(*){})
    assert_equal 0,@visual.creates;s=ask('Creative status '+r['id'])['outcome'];assert_equal 'canceled',s['state'];assert_nil s['action']
  end
  def test_interrupted_prepare_remains_held_and_cannot_import_again
    r=prepare;@visual.raise_create=true;@bridge.execute_prepare_job(id:r['id'],progress:->(*){})
    s=ask('Creative status '+r['id'])['outcome'];assert_equal 'blocked_for_human_review',s['state'];assert_equal 1,@visual.creates
    @bridge.execute_prepare_job(id:r['id'],progress:->(*){});assert_equal 1,@visual.creates
  end
  def test_stale_approval_after_revision_is_nonexecuting
    r=ready;ask('Frame: portrait');outcome=ask('Generate creative '+r.dig('action','approval_digest'))['outcome']
    assert_equal 'awaiting_input',outcome['state'];assert_equal 1,@jobs.calls.size;assert_equal 0,@visual.executions
  end
  def test_real_existing_job_manager_handles_both_phases
    @jobs=SoulCore::DashboardMusicJobManager.new(root:@root,facade:nil,creative_bridge_v2:->{@bridge})
    r=prepare;Thread.pass until @jobs.active.empty?
    s=ask('Creative status '+r['id'])['outcome'];assert_equal 'prepared',s['state']
    ask('Generate creative '+s.dig('action','approval_digest'));Thread.pass until @jobs.active.empty?
    assert ask('Creative status '+r['id']).dig('outcome','terminal','ok');assert_equal 1,@visual.executions
  end
  def test_lost_preparation_response_is_idempotent
    r=prepare;p=@history # get original preview without re-planning
    root=@service.instance_variable_get(:@conversations).path
    journal=Dir.glob(File.join(root,'*','r-000002.json')).first
    preview=JSON.parse(File.read(journal)).dig('data','outcome','preview')
    repeated=@bridge.prepare(conversation_id:'fixture',preview:preview)
    assert_equal r['id'],repeated['id'];assert_equal 1,@jobs.calls.size;assert_equal 0,@visual.creates
  end
end
