# frozen_string_literal: true
require_relative 'cpu_member_creative_preview_gateway'
module SoulCore
  class CpuMemberCreativePreviewGatewayV2 < CpuMemberCreativePreviewGateway
    def self.manifest(owner)
      super.merge('service_version'=>'cpu_member_a9_v2','a9_confirmation_routing_sha256'=>Digest::SHA256.file(__FILE__).hexdigest)
    end
    def complete(**args)
      text=args.fetch(:messages).last.fetch('content').strip
      if /\A(?:yes(?:,? please)?|confirm|generate|start|START_CREATIVE_WORKFLOW)[.!]?\z/i.match?(text)
        creative=with_store do
          previous=@attempts.values.select{|a|a['input']['conversation_id']==args.fetch(:conversation_id)}.last
          previous&&previous['state']=='complete'&&previous.dig('result','kind')=='creative_preview'
        end
        # Preserve the established immediately-prior proposal rule. An older
        # active creative draft must not capture a newer GPU-task confirmation.
        return CpuMemberOperationsGatewayV2.instance_method(:complete).bind_call(self,**args) unless creative
      end
      super
    end
  end
end
