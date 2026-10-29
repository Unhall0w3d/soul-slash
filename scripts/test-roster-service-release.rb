# frozen_string_literal: true
require 'minitest/autorun'
require_relative 'support/roster_service_driver'

class RosterServiceReleaseTest < Minitest::Test
  def row(at:, pid:nil)
    {'monotonic'=>at,'total'=>16*1024**3,'used'=>15*1024**3,
      'clients'=>pid ? [{'holders'=>[{'pid'=>pid}]}] : []}
  end
  def probe(rows, nv_pid:nil, error:nil)
    value=RosterServiceDriver.allocate
    value.instance_variable_set(:@clock,9.0)
    value.instance_variable_set(:@saved,[])
    value.define_singleton_method(:now) { @clock+=1.0 }
    value.define_singleton_method(:sleep) { |_| nil }
    value.define_singleton_method(:stop_telemetry) { @collector_stopped=true }
    value.define_singleton_method(:creative_nvidia_sample) { {'name'=>'NVIDIA GeForce GTX 1070','compute_pids'=>[nv_pid].compact,'free_mib'=>1} }
    value.define_singleton_method(:validate_resources!) { |_| raise 'must not conflate release and admission' }
    value.define_singleton_method(:save) { |name,sample| @saved << [name,sample] }
    client=Object.new
    client.define_singleton_method(:sample) do
      raise SoulCore::GpuAccountingSnapshot::Unavailable,'incomplete accounting' if error
      rows.length>1 ? rows.shift : rows.first
    end
    original=SoulCore::GpuAccountingSnapshot.method(:new)
    SoulCore::GpuAccountingSnapshot.define_singleton_method(:new) { client }
    yield value
  ensure
    SoulCore::GpuAccountingSnapshot.define_singleton_method(:new,original) if original
  end
  def test_release_uses_two_fresh_samples_despite_foreign_memory_pressure
    probe([row(at:9,pid:123),row(at:11),row(at:12)]) do |value|
      value.wait_for_release(123)
      assert value.instance_variable_get(:@collector_stopped)
      evidence=value.instance_variable_get(:@saved).first.last
      assert_equal [11,12],evidence['observations'].map { |r| r['amd']['monotonic'] }
    end
  end
  def test_old_owned_client_or_stale_data_cannot_prove_release
    [row(at:9),row(at:50,pid:123)].each do |sample|
      probe([sample]) do |value|
        assert_raises(ChatReplacementTrial::Abort) { value.wait_for_release(123) }
        assert_empty value.instance_variable_get(:@saved)
      end
    end
  end
  def test_nvidia_holder_and_incomplete_amd_snapshot_fail_closed
    probe([row(at:11)],nv_pid:123) do |value|
      assert_raises(ChatReplacementTrial::Abort) { value.wait_for_release(123) }
      assert_empty value.instance_variable_get(:@saved)
    end
    probe([],error:true) do |value|
      assert_raises(SoulCore::GpuAccountingSnapshot::Unavailable) { value.wait_for_release(123) }
      assert_empty value.instance_variable_get(:@saved)
    end
  end
  def test_nonadvancing_release_samples_are_refused
    probe([row(at:11)]) do |value|
      assert_raises(ChatReplacementTrial::Abort) { value.wait_for_release(123) }
      assert_empty value.instance_variable_get(:@saved)
    end
  end
end
