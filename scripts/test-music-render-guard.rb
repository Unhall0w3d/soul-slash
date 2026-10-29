require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/soul_core/music_render_guard'
class MusicRenderGuardTest < Minitest::Test
  def setup
    @root=Dir.mktmpdir; @pid=nil
    @command=File.join(@root,'ace-synth');File.symlink(RbConfig.ruby,@command)
    @control=Object.new;@control.define_singleton_method(:status) { {'data'=>{'handoff'=>{'handoff_id'=>'a'*32}}} }
  end
  def teardown = FileUtils.remove_entry(@root)
  def row
    {'amd'=>{'total'=>16*1024**3,'used'=>1024**3,'clients'=>[]},'temperatures'=>{'edge'=>40,'junction'=>50,'mem'=>40},'ram_available_kib'=>16*1024**2,'swap_pages'=>1}
  end
  def options
    {env:{},chdir:@root,timeout_seconds:2,max_output_bytes:1024,on_spawn:->(pid,_) {@pid=pid},canceled:-> {false}}
  end
  def test_music_backend_restricts_driver_before_any_model_process
    manifest=JSON.parse(File.read(File.expand_path('../config/music_vulkan_models.json',__dir__)))
    backend=SoulCore::MusicVulkanGenerationBackend.new(music_root:@root,manifest:manifest,runner:nil)
    seen=nil
    execute=->(_command,_timeout,env,_chdir) {seen=env;SoulCore::MusicGenerationService::ProcessResult.new(status:'failed',stdout:'',stderr:'fixture')}
    backend.run(input:{'language'=>'en','lyrics'=>'[Instrumental]','duration'=>30,'seed'=>1},staging:@root,execute:execute)
    assert_equal '/usr/share/vulkan/icd.d/radeon_icd.json',seen.fetch('VK_DRIVER_FILES')
    assert_equal '0',seen.fetch('GGML_VK_VISIBLE_DEVICES')
    request=JSON.parse(File.read(File.join(@root,'lm-attempt-1','request.json')))
    assert_equal 'acestep-v15-xl-turbo-Q8_0.gguf',request.fetch('synth_model')
    assert_equal '666ac70204440867d8c01ba4b119cc79c95b370a',backend.model_profile.fetch('model_revision')
    assert_equal 'acestep-v15-xl-turbo-Q8_0.gguf',backend.model_profile.fetch('synth_model')
  end
  def test_default_vulkan_service_is_guarded
    service=SoulCore::MusicGenerationService.new(root:@root)
    assert_instance_of SoulCore::MusicRenderGuard,service.instance_variable_get(:@process_runner)
  end
  def test_baseline_remains_selectable_for_rollback
    manifest=JSON.parse(File.read(File.expand_path('../config/music_vulkan_models.json',__dir__)))
    manifest.fetch('profile')['synth_model']='acestep-v15-turbo-Q8_0.gguf'
    backend=SoulCore::MusicVulkanGenerationBackend.new(music_root:@root,manifest:manifest,runner:nil)
    execute=->(_command,_timeout,_env,_chdir) {SoulCore::MusicGenerationService::ProcessResult.new(status:'failed',stdout:'',stderr:'fixture')}
    backend.run(input:{'language'=>'en','lyrics'=>'[Instrumental]','duration'=>30,'seed'=>1},staging:@root,execute:execute)
    request=JSON.parse(File.read(File.join(@root,'lm-attempt-1','request.json')))
    assert_equal 'acestep-v15-turbo-Q8_0.gguf',request.fetch('synth_model')
    assert_equal manifest.dig('models','revision'),backend.model_profile.fetch('model_revision')
  end
  def test_initial_refusal_does_not_start
    bad=row;bad['temperatures']['junction']=100
    guard=SoulCore::MusicRenderGuard.new(root:@root,control:@control,sampler:-> {bad})
    refute guard.run([@command,'-e','sleep 30'],**options).success?
    assert_nil @pid
    assert_equal 1,Dir.glob(File.join(@root,'Soul/runtime/qualification/music-monitor/*.json')).size
  end
  def test_lost_telemetry_reaps_child_and_retains_failure
    calls=0
    guard=SoulCore::MusicRenderGuard.new(root:@root,control:@control,sampler:-> {calls+=1;raise 'telemetry lost' if calls>1;row})
    result=guard.run([@command,'-e','sleep 30'],**options)
    refute result.success?
    assert_includes result.stderr,'telemetry lost'
    assert_raises(Errno::ESRCH) {Process.kill(0,@pid)}
  end
  def test_cancellation_and_timeout_reap_child
    [true,false].each do |cancel|
      guard=SoulCore::MusicRenderGuard.new(root:@root,control:@control,sampler:-> {row})
      opts=options.merge(timeout_seconds:0.2,canceled:-> {cancel && !@pid.nil?})
      @pid=nil
      assert_equal 'canceled',guard.run([@command,'-e','sleep 30'],**opts).status
      assert_raises(Errno::ESRCH) {Process.kill(0,@pid)}
    end
  end
  def test_success_preserves_progress_and_attach
    events=[]
    guard=SoulCore::MusicRenderGuard.new(root:@root,control:@control,sampler:-> {row})
    result=guard.run([@command,'-e','puts "stage"; sleep 0.3'],**options,progress:->(e) {events<<e})
    assert result.success?
    assert @pid
    refute_empty events
  end
  def test_non_model_process_does_not_query_telemetry
    guard=SoulCore::MusicRenderGuard.new(root:@root,control:@control,sampler:-> {raise 'must not sample'})
    assert guard.run([RbConfig.ruby,'-e','puts "ok"'],**options).success?
    assert_empty Dir.glob(File.join(@root,'Soul/runtime/qualification/music-monitor/*.json'))
  end
end
