# frozen_string_literal: true
require_relative 'cpu_member_operations_gateway_v2'
require_relative 'cpu_creative_preview'
module SoulCore
  class CpuMemberCreativePreviewGateway < CpuMemberOperationsGatewayV2
    def self.manifest(owner)
      super.merge('service_version'=>'cpu_member_a9_v1','a9_implementation'=>%w[cpu_member_creative_preview_gateway.rb cpu_creative_preview.rb cpu_creative_brief_planner.rb conversation_creative_workflow_service.rb conversation_creative_planner.rb conversation_creative_flow_store.rb].to_h{|f|[f,Digest::SHA256.file(File.join(__dir__,f)).hexdigest]})
    end
    def initialize(creative_preview:nil,**args)
      super(**args)
      @creative_preview=creative_preview||CpuCreativePreview.new(compute_reader:->{@queue.availability})
    end
    def complete(**args)
      text=args.fetch(:messages).last.fetch('content');conversation_id=args.fetch(:conversation_id)
      prior=with_store{latest_preview(conversation_id)}
      return super unless CpuCreativeBriefPlanner.candidate?(text,prior)
      request_id,messages,scope,deadline,cancel=args.values_at(:request_id,:messages,:scope,:deadline,:cancel);cancel||=->{false};scope||=[]
      ContinuityLab::ChatGateway.validate_input!(conversation_id,messages);valid_id!(request_id);@adapter.payload(messages:messages.last(7),scope:scope)
      input=JSON.parse(JSON.generate({'conversation_id'=>conversation_id,'request_id'=>request_id,'messages'=>messages,'scope'=>scope,'adapter'=>@adapter.binding}))
      with_store do
        check!(deadline,cancel);raise Refused,'task request identity reused' if @task_requests.key?(request_id)
        if (old=@attempts[request_id])
          raise Refused,'changed or unfinished preview' unless old['input']==input&&old['state']=='complete'
          return Marshal.load(Marshal.dump(old['result'])).merge('replayed'=>true)
        end
        turns=@attempts.values.select{|a|a['input']['conversation_id']==conversation_id}
        expected=turns.flat_map{|a|[a['input']['messages'].last,{'role'=>'assistant','content'=>a.dig('result','content')}]}
        raise Refused,'preview history changed' unless turns.all?{|a|a['state']=='complete'}&&messages[0...-1]==expected
        raise Refused,'journal capacity' if @records.length+2>LIMIT
        append!('cpu_requested',request_id,input)
        begin
          prior=latest_preview(conversation_id)
          outcome=@creative_preview.call(text:text,conversation_id:conversation_id,input_digest:self.class.digest(input),prior:prior)
          check!(deadline,cancel);result=preview_result(input,outcome)
          append!('cpu_creative_preview_complete',request_id,result);result
        rescue StandardError=>e
          append!(cancel.call ? 'cpu_canceled' : 'cpu_failed',request_id,{'requires_review'=>true,'error_class'=>e.class.name}) if @attempts[request_id]['state']=='cpu_requested'
          raise
        end
      end
    end
    private
    def latest_preview(conversation_id)
      @attempts.values.reverse_each do |a|
        next unless a['state']=='complete'&&a['input']['conversation_id']==conversation_id&&a.dig('result','kind')=='creative_preview'
        return a.dig('result','outcome','preview')
      end
      nil
    end
    def preview_result(input,outcome)
      raise Refused,'preview result schema' unless outcome.is_a?(Hash)&&outcome.keys.sort==%w[message preview state]&&%w[awaiting_input blocked_for_human_review canceled].include?(outcome['state'])&&outcome['message'].is_a?(String)&&outcome['message'].bytesize<=2048
      if (r=outcome['preview'])
        @creative_preview.validate!(r)
        raise Refused,'foreign preview conversation' unless r['flow']['chat_id']=='chat_cpu_'+Digest::SHA256.hexdigest(input['conversation_id'])
      end
      content=CpuCreativePreview.render(outcome)
      raise Refused,'preview output bound' if content.bytesize>24*1024
      {'kind'=>'creative_preview','content'=>content,'model'=>CpuMemberAdapter::MODEL,'adapter'=>@adapter.binding,'request_id'=>input['request_id'],'conversation_id'=>input['conversation_id'],'replayed'=>false,'outcome'=>outcome,
       'execution'=>{'provider'=>'deterministic.creative_preview','operation'=>'creative.preview','state'=>outcome['state'],'model_invoked'=>false,'input_sha256'=>self.class.digest(input),'result_sha256'=>Digest::SHA256.hexdigest(content),'preview_digest'=>r&&r['preview_digest'],'generation_available'=>false}}
    end
    def apply!(record)
      return super unless record['state']=='cpu_creative_preview_complete'
      prior=@attempts[record['request_id']];data=record['data']
      raise Refused,'preview receipt state' unless prior&&prior['state']=='cpu_requested'
      previous=latest_preview(prior['input']['conversation_id'])
      raise Refused,'preview without user request' unless CpuCreativeBriefPlanner.candidate?(prior['input']['messages'].last['content'],previous)
      outcome=data['outcome'];projection=outcome&&outcome['preview'];text=prior['input']['messages'].last['content']
      if projection&&projection!=previous
        raise Refused,'preview source input changed' unless projection['origin_input_sha256']==self.class.digest(prior['input'])
        if text.strip.match?(/\Acancel creative preview[.!]?\z/i)
          raise Refused,'cancel changed brief' unless previous&&projection['flow']['plan']==previous['flow']['plan']&&projection['flow']['lifecycle_state']=='canceled'
        else
          planner=CpuCreativeBriefPlanner.new(input_digest:self.class.digest(prior['input']),user_fields:previous ? previous['user_fields'] : [])
          draft=planner.draft(provider:nil,chat_id:projection['flow']['chat_id'],messages:[{'role'=>'user','content'=>text}],prior:previous&&previous['flow'])
          raise Refused,'creative choices are not source-bound' unless draft['ok']&&draft['plan']==projection['flow']['plan']&&planner.user_fields==projection['user_fields']
        end
      end
      raise Refused,'preview attribution changed' unless data==preview_result(prior['input'],data['outcome'])
      prior['state']='complete';prior['result']=data
    end
  end
end
