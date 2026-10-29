# frozen_string_literal: true
require "minitest/autorun"
require "stringio"
require_relative "../lib/soul_core/gpu_accounting_snapshot"

class GpuAccountingSnapshotTest < Minitest::Test
  def setup
    @clock=10.0
    @client=SoulCore::GpuAccountingSnapshot.new(clock:-> {@clock})
    @row={"state"=>"sample","pci"=>"0000:0a:00.0","monotonic"=>9.0,
      "total"=>16*1024**3,"used"=>0,"clients"=>[]}
  end
  def decode(row=@row) = @client.send(:decode,JSON.generate(row))
  def test_sequence_and_replay
    assert_equal 1,decode["sequence"]
    assert_raises(SoulCore::GpuAccountingSnapshot::Unavailable){decode}
    @row["monotonic"]=9.5
    assert_equal 2,decode["sequence"]
  end
  def test_rejects_stale_future_wrong_gpu_and_incomplete_accounting
    [{"monotonic"=>6},{"monotonic"=>11},{"pci"=>"other"},{"state"=>"complete"},
     {"used"=>1024**3},{"total"=>1},{"clients"=>[{}]}].each do |change|
      assert_raises(SoulCore::GpuAccountingSnapshot::Unavailable){decode(@row.merge(change))}
    end
    assert_equal 1,decode["sequence"]
  end
  def test_fixed_command_no_shell_arguments
    assert_equal ["/usr/bin/timeout","--foreground","--kill-after=1s","6s",
      "/usr/bin/sudo","-n","--","/usr/local/libexec/soul-gpu-accounting/snapshot"],SoulCore::GpuAccountingSnapshot::COMMAND
  end
  def test_empty_helper_output_is_explicitly_unavailable
    original=Open3.method(:popen3)
    Open3.define_singleton_method(:popen3) do |*args, &block|
      block.call(StringIO.new, StringIO.new, StringIO.new, Object.new)
    end
    error=assert_raises(SoulCore::GpuAccountingSnapshot::Unavailable) { @client.sample }
    assert_includes error.message,"returned no data"
  ensure
    Open3.define_singleton_method(:popen3,original) if original
  end
  def test_failed_helper_codes_remain_failures_and_unknown_text_is_not_exposed
    original=Open3.method(:popen3)
    (SoulCore::GpuAccountingSnapshot::FAILURE_CODES + ["private secret", nil]).each do |code|
      body=JSON.generate(state:"failed", error_code:code)
      Open3.define_singleton_method(:popen3) do |*args, &block|
        status=Struct.new(:success?).new(false)
        block.call(StringIO.new, StringIO.new(body), StringIO.new, Struct.new(:value).new(status))
      end
      error=assert_raises(SoulCore::GpuAccountingSnapshot::Unavailable) { @client.sample }
      expected=SoulCore::GpuAccountingSnapshot::FAILURE_CODES.include?(code) ? "accounting helper failed: #{code}" : "accounting helper failed"
      assert_equal expected,error.message
    end
  ensure
    Open3.define_singleton_method(:popen3,original) if original
  end
end
