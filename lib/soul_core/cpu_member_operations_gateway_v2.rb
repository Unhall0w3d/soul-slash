# frozen_string_literal: true
require_relative 'cpu_member_operations_gateway'
require_relative 'cpu_member_operations_v2'
module SoulCore
  # V1 replies remain bound to their original collector/cache behavior.
  class CpuMemberOperationsGatewayV2 < CpuMemberOperationsGateway
    def self.manifest(owner)
      super.merge('service_version'=>'cpu_member_a8_v2',
        'a8_v2_implementation'=>%w[cpu_member_operations_gateway_v2.rb cpu_member_operations_v2.rb].to_h{|f|[f,Digest::SHA256.file(File.join(__dir__,f)).hexdigest]},
        'a8_v2_helper'=>Digest::SHA256.file(File.expand_path('../../scripts/cpu-member-read-only-operation-v2.rb',__dir__)).hexdigest)
    end
    def initialize(operations:nil,**args);super(operations:operations||CpuMemberOperationsV2.new,**args);end
    private
    def operation_result(input,operation,outcome)
      result=super
      checked=outcome['report']['checked_at']||outcome['report']['collected_at']
      if checked
        raise Refused,'invalid collection time' unless checked.is_a?(String)&&/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\z/.match?(checked)
        result['content']+="\nSource checked at: #{checked}"
        result['execution']['result_sha256']=Digest::SHA256.hexdigest(result['content'])
      end
      result
    end
  end
end
