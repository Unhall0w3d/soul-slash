require 'minitest/autorun'
require_relative '../lib/soul_core/creative_workload_admission'

class CreativeWorkloadAdmissionTest < Minitest::Test
  def amd(used: 1, bytes: 1, pid: 555, uid: Process.uid, exe: '/new/lightweight/app')
    {'total'=>16*1024**3,'used'=>used,'clients'=>[{'bytes'=>bytes,'holders'=>[{'pid'=>pid,'uid'=>uid,'exe'=>exe}]}]}
  end
  def visual(row, **args)
    SoulCore::CreativeWorkloadAdmission.amd_visual!(row, **args)
  end
  def test_visual_headroom_boundaries_and_new_apps
    gib=1024**3
    assert visual(amd(used:6*gib), admission:true)
    assert_raises(ArgumentError) { visual(amd(used:6*gib+1), admission:true) }
    assert visual(amd(used:14*gib), admission:false)
    assert_raises(ArgumentError) { visual(amd(used:14*gib+1), admission:false) }
    assert visual(amd(bytes:7*gib-1))
    assert_raises(ArgumentError) { visual(amd(bytes:7*gib)) }
    [-1,16*gib+1,Float::NAN].each { |used| assert_raises(ArgumentError) { visual(amd(used:used)) } }
  end
  def test_visual_ownership_does_not_depend_on_familiar_paths
    assert visual(amd)
    assert visual(amd(exe:'/another/new/editor'))
    assert visual(amd(exe:'/runtime/sd-cli',pid:123), owned_pid:123)
    %w[/runtime/sd-cli /runtime/llama-server].each do |path|
      assert_raises(ArgumentError) { visual(amd(exe:path)) }
      assert_raises(ArgumentError) { visual(amd(exe:path+' (deleted)')) }
      assert_raises(ArgumentError) { visual(amd(exe:path,pid:123,uid:Process.uid+1),owned_pid:123) }
    end
    row=amd(exe:'/runtime/sd-cli',pid:123)
    row['clients'][0]['holders'] << {'pid'=>456,'uid'=>Process.uid,'exe'=>'/desktop/editor'}
    assert_raises(ArgumentError) { visual(row,owned_pid:123) }
    row['clients'][0]['holders']=[]
    assert_raises(ArgumentError) { visual(row) }
  end
  def sample
    {'name'=>'NVIDIA GeForce GTX 1070','temperature_c'=>45,'ram_available_kib'=>16*1024**2,
      'compute_pids'=>[100,101], 'processes'=>[{'pid'=>100,'used_mib'=>84},{'pid'=>101,'used_mib'=>10}]}
  end
  def test_foreign_clients_on_unused_device_do_not_claim_soul_ownership
    assert check(sample)
  end
  def check(row, path: '/usr/lib/libreoffice/program/soffice.bin')
    SoulCore::CreativeWorkloadAdmission.nvidia_environment!(row, runtime_paths:['/qualified/llama-server'], executable:->(pid) { path })
  end
  def test_remaining_owned_runtime_and_unreadable_process_still_block
    assert_raises(ArgumentError) { check(sample, path:'/qualified/llama-server') }
    assert_raises(ArgumentError) { check(sample, path:'/qualified/llama-server (deleted)') }
    assert_raises(Errno::ENOENT) do
      SoulCore::CreativeWorkloadAdmission.nvidia_environment!(sample, runtime_paths:['/qualified/llama-server'], executable:->(pid) { raise Errno::ENOENT })
    end
  end
  def test_thermal_memory_identity_and_missing_data_still_refuse
    [{'temperature_c'=>88},{'temperature_c'=>Float::NAN},{'temperature_c'=>-1},
      {'ram_available_kib'=>4*1024**2-1},{'name'=>'different'}].each do |change|
      assert_raises(ArgumentError) { check(sample.merge(change)) }
    end
    assert_raises(KeyError) { check({}) }
  end
  def test_only_prequalified_compositor_can_use_permission_fallback
    row=sample.merge('compute_pids'=>[100])
    args={runtime_paths:['/qualified/llama-server'], executable:->(_) { raise Errno::EACCES }}
    assert_raises(Errno::EACCES) { SoulCore::CreativeWorkloadAdmission.nvidia_environment!(row, **args) }
    assert SoulCore::CreativeWorkloadAdmission.nvidia_environment!(row, **args, desktop_pids:[100])
    assert_raises(Errno::EACCES) { SoulCore::CreativeWorkloadAdmission.nvidia_environment!(row, **args, desktop_pids:[101]) }
  end
end
