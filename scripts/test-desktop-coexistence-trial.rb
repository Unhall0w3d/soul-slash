# frozen_string_literal: true
require "minitest/autorun"
require_relative "run-desktop-coexistence-trial"
require_relative "run-gemma-placement-trial"

class DesktopCoexistenceTest < Minitest::Test
  def test_equal_placement_changes_only_split_and_packet
    old=GemmaPlacementTrial.argv("gemma-4-26b-a4b","/fixture/model")
    expected=old.dup
    expected[expected.index("--tensor-split")+1]="1,1"
    assert_equal expected,GemmaEqualPlacementTrial.argv("gemma-4-26b-a4b","/fixture/model")
    assert_raises(ArgumentError) { GemmaEqualPlacementTrial.argv("gpt-oss-20b","/fixture/model") }
    t=GemmaEqualPlacementTrial.allocate
    records={}
    t.define_singleton_method(:save) { |k,v| records[k]=v }
    t.extra_preflight
    p=records.fetch("frozen-placement-packet.json")
    assert_equal "gemma-desktop-placement-1-1-v1",p["protocol"]
    assert_equal 2,p["max_replies"]
    assert_equal 900,p["seconds"]
    assert_equal 300,p["candidate_seconds"]
    assert_equal DesktopCoexistenceTrial,t.method(:validate_resources!).owner
  end
  def test_gemma_placement_only_changes_split
    id="gemma-4-26b-a4b"
    old=DesktopCoexistenceTrial.argv(id,"/fixture/model")
    expected=old.dup
    expected[expected.index("--tensor-split")+1]="3,2"
    assert_equal expected,GemmaPlacementTrial.argv(id,"/fixture/model")
    assert_raises(ArgumentError) { GemmaPlacementTrial.argv("gpt-oss-20b","/fixture/model") }
    assert_equal [id],GemmaPlacementTrial::IDS
    t=GemmaPlacementTrial.allocate
    records={}
    t.define_singleton_method(:save) { |k,v| records[k]=v }
    t.extra_preflight
    packet=records.fetch("frozen-placement-packet.json")
    assert_equal 2,packet["max_replies"]
    assert_equal 900,packet["seconds"]
    assert_equal 300,packet["candidate_seconds"]
    assert_equal RosterAdapterTrial::TASK_MESSAGES,packet["messages"]
    assert_equal DesktopCoexistenceTrial,t.method(:validate_resources!).owner
  end
  def client(bytes: 3*1024**3, pid: 12, uid: Process.uid, exe: "/fixture/game", compute: 100_000_000)
    {"bytes"=>bytes,"compute"=>compute,"holders"=>[{"pid"=>pid,"uid"=>uid,"exe"=>exe}]}
  end
  def check(clients,owned: nil)
    DesktopCoexistenceTrial.validate_desktop_amd!({"clients"=>clients},owned_pid:owned,allowed:[[Process.uid,"/fixture/game"]])
  end
  def test_expected_activity_and_aggregate_limit
    assert check([client])
    assert check([client(bytes:7*1024**3-1)])
    assert_raises(ChatReplacementTrial::Abort) { check([client(bytes:7*1024**3)]) }
    assert_raises(ChatReplacementTrial::Abort) { check([client(bytes:4*1024**3),client(bytes:3*1024**3)]) }
  end
  def test_identity_and_shared_ownership
    assert_raises(ChatReplacementTrial::Abort) { check([client(exe:"/unknown")]) }
    assert_raises(ChatReplacementTrial::Abort) { check([client(uid:Process.uid+1)]) }
    assert_raises(ChatReplacementTrial::Abort) { check([{"bytes"=>0,"holders"=>[]}]) }
    assert check([client(exe:"/owned",bytes:12*1024**3)],owned:12)
    mixed=client(exe:"/owned")
    mixed["holders"] << {"pid"=>13,"uid"=>Process.uid,"exe"=>"/unknown"}
    assert_raises(ChatReplacementTrial::Abort) { check([mixed],owned:12) }
  end
  def test_bounds_and_launch_unchanged
    t=DesktopCoexistenceTrial.allocate
    assert_equal 900,DesktopCoexistenceTrial::BUDGET_SECONDS
    assert_equal 300,t.candidate_seconds
    assert_equal 2,t.max_generations
    DesktopCoexistenceTrial::IDS.each do |id|
      assert_equal RosterAdapterTrial.argv(id,"/fixture/model"),DesktopCoexistenceTrial.argv(id,"/fixture/model")
    end
    assert_equal MixedGpuPilot.singleton_class,MixedGpuPilot.method(:validate_amd!).owner
  end
  def test_inherited_safety_limits_and_nvidia_reserve
    t=DesktopCoexistenceTrial.allocate
    t.define_singleton_method(:save) { |*| }
    sample={"name"=>"NVIDIA GeForce GTX 1070","temperature_c"=>30,"free_mib"=>8094,
      "compute_pids"=>[],"processes"=>[],"ram_available_kib"=>32*1024**2,
      "swap_delta_pages"=>0,"amd"=>{"total"=>16*1024**3,"used"=>5*1024**3},
      "amd_temperatures"=>{"edge"=>40,"junction"=>50,"mem"=>45}}
    t.validate_resources!(sample,admission:true)
    t.validate_resources!(sample.merge("free_mib"=>1024))
    assert_raises(ChatReplacementTrial::Abort) { t.validate_resources!(sample.merge("free_mib"=>1023)) }
    assert_raises(ChatReplacementTrial::Abort) { t.validate_resources!(sample.merge("free_mib"=>6655),admission:true) }
    assert_raises(ChatReplacementTrial::Abort) { t.validate_resources!(sample.merge("amd"=>{"total"=>16*1024**3,"used"=>14*1024**3+1})) }
    assert_raises(ChatReplacementTrial::Abort) { t.validate_resources!(sample.merge("amd"=>{"total"=>16*1024**3,"used"=>7*1024**3}),admission:true) }
    assert_raises(ChatReplacementTrial::Abort) { t.validate_resources!(sample.merge("ram_available_kib"=>8*1024**2-1)) }
    assert_raises(ChatReplacementTrial::Abort) { t.validate_resources!(sample.merge("swap_delta_pages"=>131073)) }
    assert_raises(ChatReplacementTrial::Abort) { t.validate_resources!(sample.merge("temperature_c"=>88)) }
    assert_raises(ChatReplacementTrial::Abort) { t.validate_resources!(sample.merge("amd_temperatures"=>sample["amd_temperatures"].merge("junction"=>100))) }
    assert_raises(ChatReplacementTrial::Abort) { t.validate_resources!(sample.merge("compute_pids"=>[123])) }
  end
end
