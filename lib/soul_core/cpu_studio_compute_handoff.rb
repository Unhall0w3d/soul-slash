# frozen_string_literal: true
require_relative 'creative_compute_handoff'
require_relative 'cpu_member_adapter'
module SoulCore
  # The native Studio executes; the originating CPU member/conversation and
  # exact approval stay in the bridge's immutable import/action/result receipts.
  # Do not add a CPU model to the GPU owner's runtime binding for attribution.
  class CpuStudioComputeHandoff < CreativeComputeHandoff
    def with_origin(member:,conversation_id:)
      raise ArgumentError,'exact CPU Studio origin required' unless member==CpuMemberAdapter::MODEL
      super(member:'studio',conversation_id:conversation_id){yield}
    end
  end
end
