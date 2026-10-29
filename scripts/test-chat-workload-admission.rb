# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../lib/soul_core/chat_workload_admission'

class ChatWorkloadAdmissionTest < Minitest::Test
  def sample
    {'name'=>'NVIDIA GeForce GTX 1070','temperature_c'=>60,'used_mib'=>1024,'free_mib'=>7168,
      'ram_available_kib'=>9*1024**2,'compute_pids'=>[12],
      'processes'=>[{'pid'=>12,'uid'=>Process.uid,'start_ticks'=>123,'used_mib'=>100,
        'comm'=>'new-app','argv0'=>'/opt/new-app'}]}
  end
  def check(value=sample, admission:true, pid:nil)
    SoulCore::ChatWorkloadAdmission.nvidia!(value,expected_pid:pid,admission:admission,cutoff_c:88)
  end
  def test_new_clients_are_not_refused_by_name_or_arrival
    assert check
    value=sample
    value['processes'] << value['processes'].first.merge('pid'=>13,'argv0'=>'/opt/second-app')
    value['compute_pids'] << 13
    assert check(value)
  end
  def test_launch_and_runtime_reserves_stay_distinct
    [6656,6655,1024,1023].each do |free|
      value=sample.merge('free_mib'=>free,'used_mib'=>8192-free)
      if free>=6656 then assert check(value) else assert_raises(ArgumentError) { check(value) } end
      if free>=1024 then assert check(value,admission:false) else assert_raises(ArgumentError) { check(value,admission:false) } end
    end
  end
  def test_thermal_ram_and_bad_accounting_refuse
    [{'temperature_c'=>88},{'temperature_c'=>Float::NAN},{'ram_available_kib'=>8*1024**2-1},
      {'free_mib'=>-1},{'used_mib'=>8193},{'free_mib'=>8192}].each do |change|
      assert_raises(ArgumentError) { check(sample.merge(change)) }
    end
  end
  def test_foreign_models_and_pid_uid_mismatch_refuse
    value=sample
    value['processes'][0].merge!('comm'=>'llama-server','argv0'=>'/runtime/llama-server')
    assert_raises(ArgumentError) { check(value) }
    assert check(value,pid:12)
    value['processes'][0]['uid']+=1
    assert_raises(ArgumentError) { check(value,pid:12) }
  end
  def test_incomplete_process_accounting_refuses
    assert_raises(ArgumentError) { check(sample.merge('processes'=>[])) }
    assert_raises(ArgumentError) { check(sample.merge('compute_pids'=>[12,12])) }
    value=sample
    value['processes'][0]['start_ticks']=0
    assert_raises(ArgumentError) { check(value) }
  end
end
