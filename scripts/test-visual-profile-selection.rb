require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/soul_core/visual_studio_service'
class VisualProfileSelectionTest < Minitest::Test
  def setup
    @service=SoulCore::VisualStudioService.allocate
    @profile={'files'=>%w[diffusion_model vae text_encoder].map{|r|{'role'=>r,'filename'=>r}},'cfg_scale'=>1.0,'steps'=>4,'vulkan_device_selector'=>'1002:73bf!','vulkan_device_index'=>0}
    @manifest={'profiles'=>{'old'=>@profile.merge('steps'=>2),'new'=>@profile.merge('mmap'=>true)},'default_profile'=>'new'}
    @service.define_singleton_method(:read_manifest){@fixture}
    @service.instance_variable_set(:@fixture,@manifest)
    @service.define_singleton_method(:runtime_binary){'/fixture/sd-cli'}
    @service.define_singleton_method(:model_path){|f|'/fixture/'+f.fetch('filename')}
  end
  def test_explicit_default_drives_command_without_launch
    assert_equal 'new',@service.send(:selected_visual_profile).first
    args=@service.send(:command,{'negative_prompt'=>'','aspect_ratio'=>'landscape'},'/tmp/not-created.png',prompt:'test',seed:83)
    assert_includes args,'--mmap'
    assert_equal '4',args[args.index('--steps')+1]
    assert_equal '1002:73bf!',@service.send(:visual_vulkan_environment)['MESA_VK_DEVICE_SELECT']
  end
  def test_legacy_default_and_fail_closed_selection
    @manifest.delete('default_profile')
    assert_equal 'old',@service.send(:selected_visual_profile).first
    @manifest['default_profile']='missing'
    assert_raises(KeyError){@service.send(:selected_visual_profile)}
    @manifest['default_profile']='new'
    @manifest['profiles']['new']['enabled']=false
    assert_raises(KeyError){@service.send(:selected_visual_profile)}
    @manifest['profiles']['new'].delete('enabled')
    @manifest['profiles']['new']['requires_paced_runtime']=true
    assert_raises(KeyError){@service.send(:selected_visual_profile)}
    @manifest['profiles']['new'].delete('requires_paced_runtime')
    @manifest['profiles']['new']['mmap']='false'
    assert_raises(KeyError){@service.send(:selected_visual_profile)}
  end

  def test_project_command_and_device_environment_ignore_changed_default
    @manifest['profiles']['old']['vulkan_device_index'] = 1
    project = {'profile_id'=>'old','negative_prompt'=>'','aspect_ratio'=>'landscape'}
    args = @service.send(:command,project,'/tmp/not-created.png',prompt:'test',seed:83)
    assert_equal '2', args[args.index('--steps')+1]
    refute_includes args, '--mmap'
    assert_equal '1', @service.send(:visual_vulkan_environment,profile_id:'old')['GGML_VK_VISIBLE_DEVICES']
    assert_equal '0', @service.send(:visual_vulkan_environment)['GGML_VK_VISIBLE_DEVICES']
    refute @service.send(:visual_vulkan_environment,profile_id:'old').key?('SOUL_RENDER_PACING')
  end

  def test_paced_binding_and_tamper_rejection_without_launch
    Dir.mktmpdir do |root|
      @service.instance_variable_set(:@runtime_root,root)
      bytes='fixture renderer, never executed'
      sha=Digest::SHA256.hexdigest(bytes)
      path=File.join(root,'paced',sha,'sd-cli')
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path,bytes); File.chmod(0700,path)
      profile=@manifest['profiles']['new']
      profile.merge!('requires_paced_runtime'=>true,'renderer'=>{'kind'=>'paced-v1','sha256'=>sha},'steps'=>20,'cfg_scale'=>4)
      args=@service.send(:command,{'negative_prompt'=>'','aspect_ratio'=>'landscape'},'/tmp/not-created.png',prompt:'test',seed:83)
      assert_equal path,args.first
      assert_equal '20',args[args.index('--steps')+1]
      assert_includes args,'--mmap'
      assert_equal '1',@service.send(:visual_vulkan_environment)['SOUL_RENDER_PACING']
      profile['renderer']['kind']='standard'
      assert_raises(KeyError){@service.send(:selected_visual_profile)}
      profile['renderer']['kind']='paced-v1'
      File.write(path,'tampered')
      assert_raises(KeyError){@service.send(:command,{'negative_prompt'=>'','aspect_ratio'=>'landscape'},'/tmp/not-created.png',prompt:'test',seed:83)}
      profile['renderer']['sha256']='../../escape'
      assert_raises(KeyError){@service.send(:selected_visual_profile)}
      profile['renderer']['sha256']=sha
      profile['enabled']=false
      assert_raises(KeyError){@service.send(:selected_visual_profile)}
    end
  end
end
