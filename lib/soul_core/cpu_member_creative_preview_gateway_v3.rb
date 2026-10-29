# frozen_string_literal: true
require_relative 'cpu_member_creative_preview_gateway_v2'
require_relative 'cpu_creative_preview_display'
module SoulCore
  class CpuMemberCreativePreviewGatewayV3 < CpuMemberCreativePreviewGatewayV2
    def self.manifest(owner)
      super.merge('service_version'=>'cpu_member_a9_v3','a9_display_implementation'=>%w[cpu_member_creative_preview_gateway_v3.rb cpu_creative_preview_display.rb].to_h{|f|[f,Digest::SHA256.file(File.join(__dir__,f)).hexdigest]})
    end
    private
    def preview_result(input,outcome)
      result=super;result['content']=CpuCreativePreviewDisplay.render(outcome)
      raise Refused,'preview presentation bound' if result['content'].bytesize>24*1024
      result['execution']['result_sha256']=Digest::SHA256.hexdigest(result['content']);result
    end
  end
end
