# frozen_string_literal: true
require_relative 'cpu_member_assistance_gateway_v2'
module SoulCore
  # Emit canonical text before journaling; never normalize incoming history.
  class CpuMemberAssistanceGatewayV3 < CpuMemberAssistanceGatewayV2
    def self.manifest(owner)
      super.merge('service_version'=>'cpu_member_a6_v3','a6_canonical_text_sha256'=>Digest::SHA256.file(__FILE__).hexdigest)
    end
    def assistance_result(input,kind,outcome)
      result=super
      result['content']=result['content'].strip
      result['execution']['result_sha256']=Digest::SHA256.hexdigest(result['content'])
      result
    end
  end
end
