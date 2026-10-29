# frozen_string_literal: true
require_relative 'test-creative-compute-handoff'
require_relative '../lib/soul_core/cpu_studio_compute_handoff'
class CreativeComputeHandoffTest
  def test_cpu_bridge_uses_studio_execution_actor_without_loading_a_cpu_gpu_member
    bridge
    handoff=SoulCore::CpuStudioComputeHandoff.new(control:Control.new(@backend))
    @backend.run do
      result=handoff.with_origin(member:SoulCore::CpuMemberAdapter::MODEL,conversation_id:'cpu_conversation') do
        handoff.run(provider_id:'amd-visual',project_id:'project',request_id:'candidate',input_digest:'a'*64) do
          assert_equal 'studio',@backend.compute_status.dig('handoff','member')
          assert_equal 'cpu_conversation',@backend.compute_status.dig('handoff','origin_conversation_id')
          {'ok'=>false,'lifecycle_state'=>'canceled'}
        end
      end
      refute result['ok'];assert_nil @backend.compute_status['handoff'];assert_empty @driver.starts
      assert_raises(ArgumentError){handoff.with_origin(member:'unknown',conversation_id:'x'){flunk}}
    end
  end
end
