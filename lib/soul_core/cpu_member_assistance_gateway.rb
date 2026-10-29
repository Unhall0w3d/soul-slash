# frozen_string_literal: true
require_relative 'cpu_member_calculation_gateway'
require_relative 'cpu_member_natural_calculation'
require_relative 'cpu_member_deferred_queue'
module SoulCore
  class CpuMemberAssistanceGateway < CpuMemberCalculationGateway
    ALIASES={'gpt-oss'=>'gpt-oss-20b','gpt-oss 20b'=>'gpt-oss-20b','gemma'=>'gemma-4-26b-a4b','gemma 26b'=>'gemma-4-26b-a4b','qwen'=>'qwen3.8-27b'}.freeze
    def self.manifest(owner)
      super.merge('service_version'=>'cpu_member_a6_v1','a6_implementation'=>%w[cpu_member_assistance_gateway.rb cpu_member_natural_calculation.rb cpu_member_deferred_queue.rb].to_h{|f|[f,Digest::SHA256.file(File.join(__dir__,f)).hexdigest]})
    end
    def initialize(queue:,**args);@queue=queue;super(**args);end
    def self.resolve(text)
      return ['compute',{}] if /\A(?:please )?(?:check (?:gpu )?compute(?: availability)?|is (?:gpu )?compute available\??|are (?:the )?gpu models available\??)\z/i.match?(text.strip)
      return ['queue_status',{}] if /\A(?:show|list|check)(?: my| the)? (?:queued tasks|queue)\.?\z/i.match?(text.strip)
      if (m=/\A(?:show|read) (?:the )?(?:result (?:for|of) )?(t-[a-f0-9]{24})[.!]?\z/i.match(text.strip));return ['queue_result',{'task_id'=>m[1]}];end
      if (m=/\A(?:please )?cancel (?:queued )?task (t-[a-f0-9]{24})\.?\z/i.match(text.strip));return ['queue_cancel',{'task_id'=>m[1]}];end
      if (m=/\A(?:please )?(?:(?:can|could|would) you (?:please )?)?(?:ask|have|use) (gpt-oss(?: 20b)?|gemma(?: 26b)?|qwen)(?: to)?\s+(.+)\z/im.match(text.strip))
        detail=m[2].strip;raise ArgumentError,'task bound' unless detail.bytesize.between?(1,1800)
        return ['propose',{'title'=>'Requested GPU assistance','detail'=>detail,'member'=>ALIASES.fetch(m[1].downcase)}]
      end
      calc=CpuMemberNaturalCalculation.resolve(text);return ['calculation',calc] if calc
      return ['routing_help',{}] if /\b(?:use|ask|need|have)\b.*\b(?:gpu|larger model)\b/i.match?(text)
      return ['confirm',{}] if /\A(?:yes(?:,? please)?|confirm|queue it|yes,? queue (?:it|that)|add it to (?:the )?queue)[.!]?\z/i.match?(text.strip)
      nil
    end
    def complete(**args)
      action=self.class.resolve(args.fetch(:messages).last.fetch('content'))
      return super unless action
      conversation_id,request_id,messages,scope,deadline,cancel=args.values_at(:conversation_id,:request_id,:messages,:scope,:deadline,:cancel);scope||=[];cancel||=->{false}
      ContinuityLab::ChatGateway.validate_input!(conversation_id,messages);valid_id!(request_id)
      input=JSON.parse(JSON.generate({'conversation_id'=>conversation_id,'request_id'=>request_id,'messages'=>messages,'scope'=>scope,'adapter'=>@adapter.binding}))
      with_store do
        check!(deadline,cancel)
        raise Refused,'task request identity reused' if @task_requests.key?(request_id)
        if (prior=@attempts[request_id])
          raise Refused,'changed or unfinished assistance request' unless prior['input']==input&&prior['state']=='complete'
          return Marshal.load(Marshal.dump(prior['result'])).merge('replayed'=>true)
        end
        turns=@attempts.values.select{|a|a['input']['conversation_id']==conversation_id}
        expected=turns.flat_map{|a|[a['input']['messages'].last,{'role'=>'assistant','content'=>a.dig('result','content')}]}
        raise Refused,'assistance history changed' unless turns.all?{|a|a['state']=='complete'}&&messages[0...-1]==expected
        raise Refused,'journal capacity' if @records.length+2>LIMIT
        append!('cpu_requested',request_id,input)
        begin
          kind,data=action
          outcome=case kind
          when 'calculation';data
          when 'compute';{'state'=>'complete','compute'=>@queue.availability}
          when 'routing_help';{'state'=>'awaiting_input','compute'=>@queue.availability,'message'=>'Which GPU member should take this task? Say, for example, Ask GPT-OSS to review this code, followed by the exact request. I will show the scope before you confirm queueing.'}
          when 'queue_status';{'state'=>'complete','queue'=>@queue.status}
          when 'queue_result';{'state'=>'complete','task'=>@queue.status(data['task_id'])}
          when 'queue_cancel';{'state'=>'complete','task'=>@queue.cancel_task(data['task_id'])}
          when 'propose'
            proposal=data.merge('proposal_id'=>self.class.digest({'input'=>input,'task'=>data}))
            {'state'=>'awaiting_input','proposal'=>proposal,'compute'=>@queue.availability,'message'=>'Review the exact member and request below. Reply yes to queue this task for one attempt when compute permits. No task has been saved yet. Scope: existing read-only analysis and drafting; no new execution permissions.'}
          when 'confirm'
            previous=turns.last&.dig('result','outcome')
            if previous && previous['state']=='awaiting_input' && previous['proposal']
              check!(deadline,cancel)
              {'state'=>'complete','task'=>@queue.enqueue(proposal:previous['proposal']),'message'=>'Saved to the confirmed queue. One attempt when compute permits; no automatic retry. Results are retained: ask "show my queue". This does not change Compute Availability.'}
            else
              {'state'=>'awaiting_input','message'=>'There is no immediately preceding scoped task proposal to confirm. Tell me which GPU member to ask and the exact task.'}
            end
          end
          # Once enqueue/cancel commits, retain its receipt even if transport ends.
          check!(deadline,cancel) unless %w[confirm queue_cancel].include?(kind)
          result=assistance_result(input,kind,outcome)
          append!('cpu_assistance_complete',request_id,result);result
        rescue StandardError=>e
          append!(cancel.call ? 'cpu_canceled' : 'cpu_failed',request_id,{'requires_review'=>true,'error_class'=>e.class.name}) if @attempts[request_id]['state']=='cpu_requested'
          raise
        end
      end
    end
    private
    def assistance_result(input,kind,outcome)
      status=outcome['compute'];lead='Soul validated assistance — deterministic harness; CPU model not invoked.'
      if status && !@queue.ready?(status)
        lead+="\nGPU compute is #{status['policy']=='reserved' ? 'unavailable at this time' : status['policy']=='unknown' ? 'not currently verifiable' : 'busy or not ready'}. Refer to Compute Availability in the dashboard."
      end
      content=lead+"\n"
      if kind=='calculation'
        if outcome['state']=='complete'
          values=outcome['outcome']['operands'];symbol={'add'=>'+','subtract'=>'−','multiply'=>'×'}.fetch(outcome['outcome']['operation'])
          content+="#{values[0]} #{symbol} #{values[1]} = #{outcome['outcome']['result']}\nCalculated from the numbers in your message."
        else
          content+=outcome.fetch('message')
        end
      elsif outcome['proposal']
        p=outcome['proposal'];content+="Member: #{p['member']}\nRequest: #{p['detail']}\n#{outcome['message']}"
      elsif outcome['queue']
        content+="Queue is held for cleanup review; no further tasks will start.\n" if outcome['queue']['blocked_for_human_review']
        content+="Confirmed tasks (#{outcome['queue']['total']} total):\n"+outcome['queue']['tasks'].map{|t|"#{t['task_id']} — #{t['member']} — #{t['state']}\n#{t['detail']}"+(t['result'] ? "\nResult: #{t['result']['content']}" : '')}.join("\n\n")
      elsif outcome['task']
        t=outcome['task'];content+="Task #{t['task_id']}: #{t['state']} (#{t['member']}).\n#{outcome['message']}"+(t['result'] ? "\nResult: #{t['result']['content']}" : '')
      else
        content+=outcome['message']||"Compute Availability: #{status['policy']}; runtime: #{status['state']}. Availability does not bypass resource admission."
      end
      raise Refused,'assistance output bound' if content.bytesize>48*1024
      {'kind'=>'assistance','content'=>content,'model'=>CpuMemberAdapter::MODEL,'adapter'=>@adapter.binding,'request_id'=>input['request_id'],'conversation_id'=>input['conversation_id'],'replayed'=>false,'outcome'=>outcome,
       'execution'=>{'provider'=>'deterministic.cpu_assistance','operation'=>kind,'state'=>outcome['state'],'model_invoked'=>false,'input_sha256'=>self.class.digest(input),'result_sha256'=>Digest::SHA256.hexdigest(content)}}
    end
    def apply!(record)
      return super unless record['state']=='cpu_assistance_complete'
      prior=@attempts[record['request_id']];data=record['data']
      raise Refused,'invalid assistance state' unless prior&&prior['state']=='cpu_requested'&&data['outcome'].is_a?(Hash)
      action=self.class.resolve(prior['input']['messages'].last['content']);raise Refused,'invalid assistance operation' unless action
      outcome=data['outcome']
      raise Refused,'invalid calculation evidence' if action[0]=='calculation'&&outcome!=action[1]
      if action[0]=='propose'
        expected=action[1].merge('proposal_id'=>self.class.digest({'input'=>prior['input'],'task'=>action[1]}))
        raise Refused,'invalid scoped proposal' unless outcome['proposal']==expected&&outcome['state']=='awaiting_input'
      end
      if action[0]=='confirm' && outcome['task']
        previous=@attempts.values.select{|a|a['state']=='complete'&&a['input']['conversation_id']==prior['input']['conversation_id']}.last&.dig('result','outcome','proposal');task=outcome['task']
        raise Refused,'confirmation without exact proposal' unless previous&&%w[member title detail].all?{|k|task[k]==previous[k]}&&task['task_id']=='t-'+self.class.digest('queue-'+previous['proposal_id'])[0,24]
      end
      raise Refused,'invalid assistance receipt' unless %w[complete awaiting_input].include?(outcome['state'])&&data==assistance_result(prior['input'],action[0],outcome)
      prior['state']='complete';prior['result']=data
    end
  end
end
