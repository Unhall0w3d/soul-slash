# frozen_string_literal: true
require_relative 'cpu_reference_gateway_v2'
require_relative 'cpu_reference_requests_v2'
module SoulCore
  class CpuReferenceGatewayV3 < CpuReferenceGatewayV2
    def self.manifest(owner)
      super.merge('service_version'=>'cpu_member_a11_v3',
        'a11_runtime_implementation'=>%w[cpu_reference_gateway_v3.rb cpu_reference_requests_v2.rb].to_h{|f|[f,Digest::SHA256.file(File.join(__dir__,f)).hexdigest]})
    end
    def initialize(reference_reader:nil,**args)
      super(reference_reader:reference_reader||CpuReferenceRequestsV2.new,**args)
    end
  end
end
