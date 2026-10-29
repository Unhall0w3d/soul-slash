# frozen_string_literal: true
require_relative 'cpu_member_creative_preview_gateway_v3'
require_relative 'creative_studio_bridge_http'
module SoulCore
  class CpuMemberCreativeExecutionGateway < CpuMemberCreativePreviewGatewayV3
    COMMAND=/\A(Prepare creative generation|Generate creative|Creative status|Cancel creative generation) ([a-f0-9]{64})\z/i
    def self.command(text)
      m=COMMAND.match(text.strip)
      return unless m
      [{'prepare creative generation'=>'prepare','generate creative'=>'submit','creative status'=>'status','cancel creative generation'=>'cancel'}.fetch(m[1].downcase),m[2]]
    end
    def self.candidate?(text)=/\A(?:Prepare creative generation|Generate creative|Creative status|Cancel creative generation)\b/i.match?(text.strip)
    def self.manifest(owner)
      super.merge('service_version'=>'cpu_member_a10_v1','a10_implementation'=>%w[cpu_member_creative_execution_gateway.rb creative_studio_bridge.rb creative_studio_bridge_http.rb creative_bridge_runners.rb].to_h{|f|[f,Digest::SHA256.file(File.join(__dir__,f)).hexdigest]})
    end
    def initialize(creative_bridge:nil,**args)
      @creative_bridge=creative_bridge||CreativeStudioBridgeClient.new
      super(**args)
    end
    def complete(**args)
      text=args.fetch(:messages).last.fetch('content');return super unless self.class.candidate?(text)
      conversation,request,messages,scope,deadline,cancel=args.values_at(:conversation_id,:request_id,:messages,:scope,:deadline,:cancel);cancel||=->{false};scope||=[]
      ContinuityLab::ChatGateway.validate_input!(conversation,messages);valid_id!(request);@adapter.payload(messages:messages.last(7),scope:scope)
      input=JSON.parse(JSON.generate({'conversation_id'=>conversation,'request_id'=>request,'messages'=>messages,'scope'=>scope,'adapter'=>@adapter.binding}))
      with_store do
        check!(deadline,cancel);raise Refused,'task request identity reused' if @task_requests.key?(request)
        if (old=@attempts[request])
          raise Refused,'changed or unfinished Studio request' unless old['input']==input&&old['state']=='complete'
          return Marshal.load(Marshal.dump(old['result'])).merge('replayed'=>true)
        end
        turns=@attempts.values.select{|a|a['input']['conversation_id']==conversation}
        expected=turns.flat_map{|a|[a['input']['messages'].last,{'role'=>'assistant','content'=>a.dig('result','content')}]}
        raise Refused,'Studio history changed' unless turns.all?{|a|a['state']=='complete'}&&messages[0...-1]==expected
        raise Refused,'journal capacity' if @records.length+3>LIMIT
        command=self.class.command(text);preview=latest_preview(conversation)
        binding=command&&command_binding(command,preview,conversation)
        append!('cpu_requested',request,input)
        begin
          append!('cpu_studio_intent',request,{'command'=>command,'binding'=>binding})
          outcome=if binding
            action,token=command
            body=action=='prepare' ? {'conversation_id'=>conversation,'preview'=>preview} : {'conversation_id'=>conversation,'id'=>binding['id']}
            body['approval_digest']=token if action=='submit'
            @creative_bridge.call(action,body)
          else
            {'state'=>'awaiting_input','message'=>'Use the exact command and digest from the current reviewed brief/native action in this conversation. Nothing was started.'}
          end
          check!(deadline,cancel);result=studio_result(input,command,binding,outcome)
          append!('cpu_studio_complete',request,result);result
        rescue StandardError=>error
          append!(cancel.call ? 'cpu_canceled' : 'cpu_failed',request,{'requires_review'=>true,'error_class'=>error.class.name})
          raise
        end
      end
    end
    private
    def command_binding(command,preview,conversation)
      action,token=command
      if action=='prepare'
        return unless preview&&preview['preview_digest']==token&&preview.dig('flow','stage')=='ready'&&preview.dig('flow','lifecycle_state')=='blocked_for_human_review'
        return {'id'=>CreativeStudioBridge.digest({'conversation_id'=>conversation,'preview_digest'=>token}),'preview_digest'=>token}
      end
      prior=@attempts.values.reverse.find do |a|
        r=a['result'];o=r&&r['outcome']
        a['state']=='complete'&&a['input']['conversation_id']==conversation&&r['kind']=='creative_studio'&&o['id']&&
          (action=='submit' ? o.dig('action','approval_digest')==token : o['id']==token)
      end
      return unless prior
      outcome=prior['result']['outcome']
      return if action=='submit'&&(!preview||preview['preview_digest']!=outcome['preview_digest']||preview.dig('flow','stage')!='ready')
      {'id'=>outcome['id'],'preview_digest'=>outcome['preview_digest']}
    end
    def preview_result(input,outcome)
      result=super
      result['content']=result['content'].sub('Generation needs a separately connected exact approval and compute-handoff action; nothing was queued or started.','Use the exact preparation and generation commands below; nothing was queued or started.')
      if (p=outcome['preview'])&&p.dig('flow','stage')=='ready'&&p.dig('flow','lifecycle_state')=='blocked_for_human_review'
        result['content']+="\n\nTo create this native Studio project and review its exact generation action (no rendering yet), send:\nPrepare creative generation #{p['preview_digest']}"
        result['execution']['result_sha256']=Digest::SHA256.hexdigest(result['content'])
      end
      result['execution']['result_sha256']=Digest::SHA256.hexdigest(result['content'])
      result
    end
    def studio_result(input,command,binding,outcome)
      if binding && outcome.is_a?(Hash) && outcome.keys.sort==%w[message refused state]
        raise Refused,'Studio refusal schema' unless outcome['state']=='blocked_for_human_review'&&outcome['refused']==true&&outcome['message'].is_a?(String)&&outcome['message'].bytesize.between?(1,1024)
        content="Creative Studio could not proceed: "+CpuCreativePreviewDisplay.markdown_data(outcome['message'])+"\nNo automatic retry. Any partial native state is retained for review."
      elsif binding
        CreativeStudioBridge.validate_public!(outcome)
        raise Refused,'Studio receipt attribution' unless outcome.values_at('id','conversation_id','preview_digest')==[binding['id'],input['conversation_id'],binding['preview_digest']]
        if command.first=='submit'
          raise Refused,'Studio approval attribution' unless outcome.dig('action','approval_digest')==command.last
        end
        content=CreativeStudioBridge.presentation(outcome)
      else
        raise Refused,'Studio invalid command result' unless outcome=={'state'=>'awaiting_input','message'=>'Use the exact command and digest from the current reviewed brief/native action in this conversation. Nothing was started.'}
        content=outcome['message']
      end
      raise Refused,'Studio response bound' if content.bytesize>24*1024
      {'kind'=>'creative_studio','content'=>content,'model'=>CpuMemberAdapter::MODEL,'adapter'=>@adapter.binding,'request_id'=>input['request_id'],'conversation_id'=>input['conversation_id'],'replayed'=>false,'outcome'=>outcome,
       'execution'=>{'provider'=>'deterministic.creative_studio','operation'=>command ? 'creative.'+command.first : 'creative.help','state'=>outcome['state'],'model_invoked'=>false,'input_sha256'=>self.class.digest(input),'result_sha256'=>Digest::SHA256.hexdigest(content)}}
    end
    def apply!(record)
      return super unless %w[cpu_studio_intent cpu_studio_complete].include?(record['state'])
      prior=@attempts[record['request_id']];raise Refused,'Studio receipt state' unless prior&&prior['state']=='cpu_requested'
      command=self.class.command(prior['input']['messages'].last['content'])
      binding=command&&command_binding(command,latest_preview(prior['input']['conversation_id']),prior['input']['conversation_id'])
      if record['state']=='cpu_studio_intent'
        raise Refused,'Studio intent source binding' unless !prior.key?('studio_intent')&&record['data']=={'command'=>command,'binding'=>binding}
        prior['studio_intent']=record['data']
      else
        raise Refused,'Studio result binding' unless prior['studio_intent']=={'command'=>command,'binding'=>binding}&&record['data']==studio_result(prior['input'],command,binding,record['data']['outcome'])
        prior['state']='complete';prior['result']=record['data']
      end
    end
  end
end
