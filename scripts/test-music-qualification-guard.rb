require 'minitest/autorun'
require_relative 'support/music_qualification_guard'
class MusicQualificationGuardTest < Minitest::Test
  def row(temp=60, used=1024**3)
    {'amd'=>{'total'=>16*1024**3,'used'=>used,'clients'=>[]},'temperatures'=>{'edge'=>50,'junction'=>temp,'mem'=>50},'ram_available_kib'=>16*1024**2,'swap_pages'=>10}
  end
  def test_admission_failure_never_starts
    called=false
    runner=Object.new
    runner.define_singleton_method(:run) { |*a,**k| called=true }
    guard=MusicQualificationGuard.new(root:'/unused',runner:runner,sampler:-> { row(100) })
    assert_raises(RuntimeError) { guard.run(['unused']) }
    refute called
  end
  def test_runtime_thermal_and_memory_failure_reap_child
    [row(100),row(60,15*1024**3)].each do |bad|
      samples=[row,bad]; pid=nil
      guard=MusicQualificationGuard.new(root:'/unused',sampler:-> { samples.shift || bad },attach:->(p) {pid=p})
      result=guard.run([RbConfig.ruby,'-e','sleep 30'],timeout_seconds:3)
      assert_equal 'guard_refused',result.status
      assert_raises(Errno::ESRCH) { Process.kill(0,pid) }
    end
  end
  def test_missing_telemetry_and_cancellation_reap_child
    [false,true].each do |cancel|
      count=0; pid=nil
      sample=-> { count+=1; raise 'missing telemetry' if count>1; row }
      guard=MusicQualificationGuard.new(root:'/unused',sampler:sample,canceled:-> {cancel},attach:->(p) {pid=p})
      result=guard.run([RbConfig.ruby,'-e','sleep 30'],timeout_seconds:3)
      assert_equal 'guard_refused',result.status
      assert_raises(Errno::ESRCH) { Process.kill(0,pid) }
    end
  end
  def test_paging_diagnostic_only_and_success
    sample=row; sample['swap_pages']=999999
    guard=MusicQualificationGuard.new(root:'/unused',sampler:-> {sample})
    assert guard.run([RbConfig.ruby,'-e','sleep 0.1; puts "ok"'],timeout_seconds:2).success?
    assert_equal 1,guard.pids.size
  end
end
