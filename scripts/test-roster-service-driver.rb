# frozen_string_literal: true
require "minitest/autorun"
require_relative "support/roster_service_driver"

class RosterServiceDriverTest < Minitest::Test
  def release_probe(nvidia: "", amd_valid: true, units: "ActiveState=inactive\n"*3, provider_id: nil, temperature: 45, owned: false)
    driver=RosterServiceDriver.allocate
    driver.define_singleton_method(:port_closed?) { true }
    driver.define_singleton_method(:creative_nvidia_released?) { nvidia.empty? }
    driver.instance_variable_set(:@pid, 999) if owned
    driver.define_singleton_method(:creative_nvidia_sample) do
      {'name'=>'NVIDIA GeForce GTX 1070','temperature_c'=>temperature,'ram_available_kib'=>8*1024**2,'compute_pids'=>[], 'processes'=>[]}
    end
    client=Object.new
    client.define_singleton_method(:sample) { {"total"=>16*1024**3,"used"=>amd_valid ? 0 : -1,"clients"=>[]} }
    runner=Object.new
    runner.define_singleton_method(:run) do |*args,**options|
      SoulCore::BoundedCommandRunner::Result.new(stdout:args.first=="nvidia-smi" ? nvidia : units,status:"ok",truncated:false)
    end
    old_snapshot=SoulCore::GpuAccountingSnapshot.method(:new)
    old_runner=SoulCore::BoundedCommandRunner.method(:new)
    old_validate=RosterServiceDriver.method(:validate_music_amd!)
    SoulCore::GpuAccountingSnapshot.define_singleton_method(:new) { client }
    SoulCore::BoundedCommandRunner.define_singleton_method(:new) { runner }
    RosterServiceDriver.define_singleton_method(:validate_music_amd!) { |*args,**opts| raise ChatReplacementTrial::Abort,"unrecognized holder" unless amd_valid; true }
    driver.creative_release_verified?(provider_id:provider_id)
  ensure
    SoulCore::GpuAccountingSnapshot.define_singleton_method(:new,old_snapshot)
    SoulCore::BoundedCommandRunner.define_singleton_method(:new,old_runner)
    RosterServiceDriver.define_singleton_method(:validate_music_amd!,old_validate)
  end

  def test_only_amd_visual_skips_foreign_nvidia_exclusivity_not_release_or_thermal_checks
    assert release_probe(nvidia:'desktop',provider_id:'amd-visual')
    refute release_probe(nvidia:'desktop',provider_id:'amd-music')
    refute release_probe(nvidia:'desktop',provider_id:'unknown')
    refute release_probe(provider_id:'amd-visual',temperature:88)
    refute release_probe(provider_id:'amd-visual',owned:true)
    refute release_probe(provider_id:'amd-visual',amd_valid:false)
    refute release_probe(provider_id:'amd-visual',units:'ActiveState=active')
  end

  def test_creative_release_requires_all_three_independent_observations
    assert release_probe
    refute release_probe(nvidia:"123\n")
    refute release_probe(amd_valid:false)
    refute release_probe(units:"ActiveState=active\n"+"ActiveState=inactive\n"*2)
    refute release_probe(units:"")
  end
  def collect_transition(foreign_after: false)
    driver=RosterServiceDriver.allocate
    driver.instance_variable_set(:@pid,123)
    driver.instance_variable_set(:@telemetry_mutex,Mutex.new)
    driver.define_singleton_method(:wait_for_telemetry!) do |deadline:|
      raise "collector timeout" unless @telemetry_thread.join(4)
    end
    count=0
    owned=sample(exe:"/synthetic/model",bytes:8*1024**3)
    client=Object.new
    client.define_singleton_method(:sample) do
      count+=1
      driver.instance_variable_set(:@pid,nil) if count==2
      driver.instance_variable_set(:@telemetry_stopping,true) if count==4
      count<=2 || foreign_after ? owned : {"total"=>16*1024**3,"used"=>0,"clients"=>[]}
    end
    original=SoulCore::GpuAccountingSnapshot.method(:new)
    SoulCore::GpuAccountingSnapshot.define_singleton_method(:new) { client }
    driver.start_telemetry
    [driver.instance_variable_get(:@telemetry),driver.instance_variable_get(:@telemetry_error),count]
  ensure
    SoulCore::GpuAccountingSnapshot.define_singleton_method(:new,original) if original
    driver&.stop_telemetry
  end

  def test_teardown_during_collection_discards_mixed_epoch_and_collects_fresh_release
    telemetry,error,count=collect_transition
    assert_nil error
    assert_equal 4,count
    assert_equal [],telemetry.fetch("clients")
  end

  def test_fresh_foreign_allocation_after_transition_still_fails_closed
    telemetry,error,count=collect_transition(foreign_after:true)
    assert_nil telemetry
    assert_equal 3,count
    assert_includes error,"desktop aggregate AMD allocation bound"
  end

  def sample(exe: "/usr/lib/kscreenlocker_greet", uid: Process.uid, bytes: 160 * 1024**2)
    {"total"=>16*1024**3,"used"=>bytes,"clients"=>[{"bytes"=>bytes,"holders"=>[{"pid"=>123,"uid"=>uid,"exe"=>exe}]}]}
  end

  def check(value)
    original=DesktopCoexistenceTrial.method(:baseline_holders)
    DesktopCoexistenceTrial.define_singleton_method(:baseline_holders) { [] }
    RosterServiceDriver.validate_music_amd!(value, previous:nil, owned_pid:nil)
  ensure
    DesktopCoexistenceTrial.define_singleton_method(:baseline_holders, original)
  end

  def test_exact_lock_greeter_retains_allocation_and_identity_guards
    assert check(sample)
    assert_raises(ChatReplacementTrial::Abort) { check(sample(exe:"/tmp/kscreenlocker_greet")) }
    assert_raises(ChatReplacementTrial::Abort) { check(sample(uid:Process.uid+1)) }
    assert_raises(ChatReplacementTrial::Abort) { check(sample(bytes:7*1024**3)) }
  end

  def test_workday_paths_are_exact_owner_scoped_and_keep_aggregate_limit
    (SoulCore::DesktopGpuAllowances::WORKDAY_PATHS + SoulCore::DesktopGpuAllowances::REBOOT_PATHS).each do |path|
      assert check(sample(exe:path))
      assert_raises(ChatReplacementTrial::Abort) { check(sample(exe:path,uid:Process.uid+1)) }
      assert_raises(ChatReplacementTrial::Abort) { check(sample(exe:path+".other")) }
      assert_raises(ChatReplacementTrial::Abort) { check(sample(exe:path,bytes:7*1024**3)) }
    end
  end

  def test_prelaunch_abort_is_reported_as_unavailable_without_retry
    driver=RosterServiceDriver.allocate
    driver.instance_variable_set(:@root_output,"/fixture")
    driver.define_singleton_method(:protected_state) { raise ChatReplacementTrial::Abort,"fixture refusal" }
    receipts=[]
    driver.define_singleton_method(:save) { |name,value| receipts << [name,value] }
    assert_raises(SoulCore::RosterRuntimeOwner::Unavailable) { driver.roster_start(ownership_id:"fixture") }
    assert_equal "startup-guard-refusal.json",receipts.fetch(0).first
    assert_equal "fixture refusal",receipts.fetch(0).last.fetch("reason")
  end

  def test_superseded_artifact_runtime_is_not_retained_as_an_allowance
    assert_raises(ChatReplacementTrial::Abort) do
      check(sample(exe:"/home/bhones/.config/Codex/artifact-sessions/runtime-generations/generation-VdPRHr/runtime/bin/node"))
    end
  end

  def test_chat_allows_new_desktop_clients_but_preserves_memory_and_runtime_ownership
    assert RosterServiceDriver.validate_amd!(sample(exe:'/tmp/new-desktop-app'),previous:nil,owned_pid:nil)
    assert_raises(ChatReplacementTrial::Abort) { RosterServiceDriver.validate_amd!(sample(bytes:7*1024**3),previous:nil,owned_pid:nil) }
    assert_raises(ChatReplacementTrial::Abort) { RosterServiceDriver.validate_amd!(sample(exe:'/tmp/llama-server'),previous:nil,owned_pid:nil) }
    assert RosterServiceDriver.validate_amd!(sample(exe:'/tmp/llama-server',bytes:8*1024**3),previous:nil,owned_pid:123)
    assert_raises(ChatReplacementTrial::Abort) { RosterServiceDriver.validate_amd!(sample(exe:'/tmp/llama-server',uid:Process.uid+1),previous:nil,owned_pid:123) }
  end

  def test_full_chat_driver_observes_paging_and_preserves_thermal_memory_bounds
    driver=RosterServiceDriver.allocate
    driver.define_singleton_method(:save) { |*args| nil }
    driver.instance_variable_set(:@protocol,{'cutoff_c'=>88})
    base={'name'=>'NVIDIA GeForce GTX 1070','temperature_c'=>60,'used_mib'=>1024,'free_mib'=>7168,
      'compute_pids'=>[],'processes'=>[],'ram_available_kib'=>9*1024**2,'swap_delta_pages'=>0,
      'amd'=>{'total'=>16*1024**3,'used'=>2*1024**3},'amd_temperatures'=>{'edge'=>60,'junction'=>70,'mem'=>60}}
    driver.send(:validate_resources!,base,admission:true)
    driver.send(:validate_resources!,base.merge('swap_delta_pages'=>1_310_730))
    assert_raises(ChatReplacementTrial::Abort) { MixedGpuPilot.allocate.send(:validate_swap_out!,base.merge('swap_delta_pages'=>131073)) }
    changes=[{'swap_delta_pages'=>-1},{'ram_available_kib'=>8*1024**2-1},
      {'temperature_c'=>88},{'amd'=>{'total'=>16*1024**3,'used'=>15*1024**3}}]
    {'edge'=>90,'junction'=>100,'mem'=>90}.each { |k,v| changes << {'amd_temperatures'=>base['amd_temperatures'].merge(k=>v)} }
    changes.each { |change| assert_raises(ChatReplacementTrial::Abort) { driver.send(:validate_resources!,base.merge(change)) } }
  end
end
