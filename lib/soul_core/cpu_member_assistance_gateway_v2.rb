# frozen_string_literal: true
require_relative 'cpu_member_assistance_gateway'
module SoulCore
  # Preserve A6 v1's exact saved replies; only new journals use this wording.
  class CpuMemberAssistanceGatewayV2 < CpuMemberAssistanceGateway
    def self.manifest(owner)
      super.merge('service_version'=>'cpu_member_a6_v2','a6_presentation_sha256'=>Digest::SHA256.file(__FILE__).hexdigest)
    end
    def assistance_result(input,kind,outcome)
      result=super
      if outcome.dig('queue','blocked_for_human_review') && outcome.dig('queue','tasks')&.any?{|t|t['state']=='running'}
        result['content']=result['content'].sub("Queue is held for cleanup review; no further tasks will start.","A task is running; additional tasks wait for it to finish and cleanup to be verified.")
        result['execution']['result_sha256']=Digest::SHA256.hexdigest(result['content'])
      end
      result
    end
  end
end
