#!/usr/bin/env ruby
require "minitest/autorun"
require "rbconfig"
require "tmpdir"
require_relative "../lib/soul_core/creative_render_guard"
class CreativeRenderGuardTest < Minitest::Test
  def setup
    @guard = SoulCore::CreativeRenderGuard.new(root: File.expand_path("..", __dir__))
    @row = {"amd"=>{"total"=>16*1024**3,"used"=>1024**3,"clients"=>[]},
      "temperatures"=>{"edge"=>50,"junction"=>60,"mem"=>50},"ram_available_kib"=>16*1024**2,"swap_pages"=>10}
  end
  def check(row=@row, admission: false)
    @guard.validate!(row, allowed: [], pid: 123, initial_swap: 10, admission: admission)
  end
  def test_limits
    assert check(admission: true)
    %w[edge junction mem].zip([90,100,90]).each do |key, value|
      original=@row["temperatures"][key]; @row["temperatures"][key]=value
      assert_raises(RuntimeError) { check }; @row["temperatures"][key]=original
    end
    @row["amd"]["used"]=15*1024**3; assert_raises(ArgumentError) { check }
    @row["amd"]["used"]=7*1024**3; assert_raises(ArgumentError) { check(admission: true) }
    @row["amd"]["used"]=1024**3
    @row["swap_pages"]=1_310_830; assert check
    @row["swap_pages"]=9; assert_raises(RuntimeError) { check }
    @row["swap_pages"]=10; @row["ram_available_kib"]=1; assert_raises(RuntimeError) { check }
  end
  def test_remote_failure_stale_and_replay_refused
    row={"amd"=>{"state"=>"sample","pci"=>"0000:0a:00.0","monotonic"=>9.0,"total"=>16*1024**3,"used"=>0,"clients"=>[]}}
    response={"ok"=>true,"data"=>row}
    control=Object.new
    control.define_singleton_method(:telemetry) { |handoff_id:| raise "wrong binding" unless handoff_id=="a"*32; response }
    guard=SoulCore::CreativeRenderGuard.new(root:"/unused",control:control)
    client=SoulCore::GpuAccountingSnapshot.new(clock:-> { 10.0 })
    assert_equal row,guard.remote_capture(client,"a"*32)
    assert_raises(SoulCore::GpuAccountingSnapshot::Unavailable) { guard.remote_capture(client,"a"*32) }
    row["amd"]["monotonic"]=5
    assert_raises(SoulCore::GpuAccountingSnapshot::Unavailable) { guard.remote_capture(client,"a"*32) }
    response["ok"]=false
    assert_raises(RuntimeError) { guard.remote_capture(client,"a"*32) }
  end
  def test_new_desktop_holder_is_allowed_but_missing_sensor_still_refuses
    @row["amd"]["clients"]=[{"bytes"=>1,"holders"=>[{"pid"=>555,"uid"=>Process.uid,"exe"=>"unknown"}]}]
    assert check
    @row["amd"]["clients"][0]["holders"][0]["pid"]=123
    assert check
    @row["temperatures"].delete("junction"); assert_raises(KeyError) { check }
  end
  def test_monitor_failure_reaps_owned_process
    pid=nil
    result=SoulCore::BoundedCommandRunner.new.run(RbConfig.ruby,"-e","sleep 30",timeout_seconds:3, monitor: ->(p) { pid=p; raise "telemetry unavailable" })
    assert_equal "guard_refused", result.status
    assert_includes result.stderr,"telemetry unavailable"
    assert_raises(Errno::ESRCH) { Process.kill(0,pid) }
  end
  def test_timeout_and_success_unchanged
    runner=SoulCore::BoundedCommandRunner.new
    assert_equal "timeout",runner.run(RbConfig.ruby,"-e","sleep 30",timeout_seconds:0.1,monitor:->(_p) {}).status
    assert runner.run(RbConfig.ruby,"-e","puts 'ok'",timeout_seconds:2,monitor:->(_p) {}).success?
  end
  def test_admission_failure_never_launches_and_retains_receipt
    Dir.mktmpdir do |root|
      source=File.join(File.expand_path("..",__dir__),SoulCore::CreativeRenderGuard::BASELINE)
      target=File.join(root,SoulCore::CreativeRenderGuard::BASELINE)
      FileUtils.mkdir_p(File.dirname(target)); FileUtils.cp(source,target)
      runner=Object.new
      runner.define_singleton_method(:run) { |*| raise "must not launch" }
      @row["temperatures"]["junction"]=100
      guard=SoulCore::CreativeRenderGuard.new(root:root,runner:runner,sampler:-> { @row })
      result=guard.run("/fixture/sd-cli",timeout_seconds:2)
      assert_equal "guard_refused",result.status
      assert_includes result.stderr,"junction thermal bound"
      receipts=Dir.glob(File.join(root,"Soul/runtime/qualification/creative-monitor/*.json"))
      assert_equal 1,receipts.size
      assert_equal "guard_refused",JSON.parse(File.read(receipts.first))["status"]
    end
  end
end
