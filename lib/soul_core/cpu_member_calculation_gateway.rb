# frozen_string_literal: true
require_relative 'cpu_member_handoff_gateway'
require_relative 'cpu_member_calculation'
require_relative 'cpu_member_conversation_cache'
module SoulCore
  class CpuMemberCalculationGateway < CpuMemberHandoffGateway
    def self.manifest(owner)
      super.merge('service_version'=>'cpu_member_a5_v1','a5_implementation'=>%w[cpu_member_calculation_gateway.rb cpu_member_calculation.rb cpu_member_conversation_cache.rb].to_h{|f|[f,Digest::SHA256.file(File.join(__dir__,f)).hexdigest]},'cache_policy'=>'single_cpu_slot_exact_conversation_ephemeral_v1')
    end
    def self.command(text)
      d=CpuMemberCalculation.parse(text)
      d ? ['calculate',d] : super
    end
    def complete(**args)
      d=CpuMemberCalculation.parse(args.fetch(:messages).last.fetch('content'))
      return super unless d
      conversation_id,request_id,messages,scope,deadline,cancel=args.values_at(:conversation_id,:request_id,:messages,:scope,:deadline,:cancel)
      cancel||=->{false};scope||=[]
      ContinuityLab::ChatGateway.validate_input!(conversation_id,messages);valid_id!(request_id)
      input=JSON.parse(JSON.generate({'conversation_id'=>conversation_id,'request_id'=>request_id,'messages'=>messages,'scope'=>scope,'adapter'=>@adapter.binding}))
      with_store do
        check!(deadline,cancel)
        raise Refused,'task request identity reused' if @task_requests.key?(request_id)
        if (prior=@attempts[request_id])
          raise Refused,'changed or unfinished calculation' unless prior['input']==input&&prior['state']=='complete'
          return Marshal.load(Marshal.dump(prior['result'])).merge('replayed'=>true)
        end
        turns=@attempts.values.select{|a|a['input']['conversation_id']==conversation_id}
        expected=turns.flat_map{|a|[a['input']['messages'].last,{'role'=>'assistant','content'=>a.dig('result','content')}]}
        raise Refused,'calculation history changed' unless turns.all?{|a|a['state']=='complete'}&&messages[0...-1]==expected
        raise Refused,'journal capacity' if @records.length+2>LIMIT
        append!('cpu_requested',request_id,input)
        begin
          result=calculation_result(input);check!(deadline,cancel)
          append!('cpu_calculation_complete',request_id,result);result
        rescue StandardError=>e
          append!(cancel.call ? 'cpu_canceled' : 'cpu_failed',request_id,{'requires_review'=>true,'error_class'=>e.class.name}) if @attempts[request_id]['state']=='cpu_requested'
          raise
        end
      end
    end
    private
    def calculation_result(input)
      data=CpuMemberCalculation.parse(input['messages'].last['content']);raise Refused,'not a calculation' unless data
      outcome=CpuMemberCalculation.evaluate(data)
      content="Soul validated calculation — executed by the deterministic harness; CPU model not invoked.\n"+JSON.pretty_generate(outcome)
      {'kind'=>'calculation','content'=>content,'model'=>CpuMemberAdapter::MODEL,'adapter'=>@adapter.binding,'request_id'=>input['request_id'],'conversation_id'=>input['conversation_id'],'replayed'=>false,
       'execution'=>{'provider'=>'deterministic.calculation','operation'=>'calculate.'+data['operation'],'state'=>'complete','model_invoked'=>false,'input_sha256'=>self.class.digest(input),'result_sha256'=>Digest::SHA256.hexdigest(content)}}
    end
    def apply!(record)
      return super unless record['state']=='cpu_calculation_complete'
      prior=@attempts[record['request_id']]
      raise Refused,'invalid calculation receipt' unless prior&&prior['state']=='cpu_requested'&&record['data']==calculation_result(prior['input'])
      prior['state']='complete';prior['result']=record['data']
    end
  end
end
