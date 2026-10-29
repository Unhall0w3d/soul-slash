# frozen_string_literal: true
require_relative 'cpu_member_memory_gateway'
require_relative 'cpu_member_operations'
module SoulCore
  class CpuMemberOperationsGateway < CpuMemberMemoryGateway
    def self.manifest(owner)
      files=%w[cpu_member_operations_gateway.rb cpu_member_operations.rb invocation_catalog_service.rb dotenv_reader.rb conversation_security_status_service.rb conversation_fleet_observability_service.rb wazuh_security_status_service.rb wazuh_alert_evidence_service.rb wazuh_compliance_posture_service.rb fleet_observability_summary_service.rb]
      super.merge('service_version'=>'cpu_member_a8_v1','a8_implementation'=>files.to_h{|f|[f,Digest::SHA256.file(File.join(__dir__,f)).hexdigest]},'a8_helper'=>Digest::SHA256.file(File.expand_path('../../scripts/cpu-member-read-only-operation.rb',__dir__)).hexdigest)
    end
    def initialize(operations:nil,**args);@operations=operations||CpuMemberOperations.new;super(**args);end
    def complete(**args)
      messages=args.fetch(:messages);operation=CpuMemberOperations.resolve(messages.last.fetch('content'))
      return super unless operation
      conversation_id,request_id,scope,deadline,cancel=args.values_at(:conversation_id,:request_id,:scope,:deadline,:cancel);cancel||=->{false};scope||=[]
      ContinuityLab::ChatGateway.validate_input!(conversation_id,messages);valid_id!(request_id)
      @adapter.payload(messages:messages.last(7),scope:scope)
      input=JSON.parse(JSON.generate({'conversation_id'=>conversation_id,'request_id'=>request_id,'messages'=>messages,'scope'=>scope,'adapter'=>@adapter.binding}))
      with_store do
        check!(deadline,cancel)
        raise Refused,'task request identity reused' if @task_requests.key?(request_id)
        if (prior=@attempts[request_id])
          raise Refused,'changed or unfinished operation' unless prior['input']==input&&prior['state']=='complete'
          return Marshal.load(Marshal.dump(prior['result'])).merge('replayed'=>true)
        end
        turns=@attempts.values.select{|a|a['input']['conversation_id']==conversation_id}
        expected=turns.flat_map{|a|[a['input']['messages'].last,{'role'=>'assistant','content'=>a.dig('result','content')}]}
        raise Refused,'operational history changed' unless turns.all?{|a|a['state']=='complete'}&&messages[0...-1]==expected
        raise Refused,'journal capacity' if @records.length+3>LIMIT
        append!('cpu_requested',request_id,input)
        begin
          append!('cpu_operation_intent',request_id,{'operation'=>operation})
          outcome=@operations.call(operation:operation,query:messages.last['content'],deadline:deadline,cancel:cancel)
          check!(deadline,cancel);result=operation_result(input,operation,outcome)
          append!('cpu_operation_complete',request_id,result);result
        rescue StandardError=>e
          append!(cancel.call ? 'cpu_canceled' : 'cpu_failed',request_id,{'requires_review'=>true,'error_class'=>e.class.name}) if @attempts[request_id]['state']=='cpu_requested'
          raise
        end
      end
    end
    private
    def operation_result(input,operation,outcome)
      CpuMemberOperations.validate!(outcome)
      content="Soul read-only result — deterministic harness; CPU model not invoked.\nOperation: #{operation}\n"+outcome['content'].strip
      raise Refused,'operational presentation bound' if content.bytesize>48*1024
      {'kind'=>'operational','content'=>content,'model'=>CpuMemberAdapter::MODEL,'adapter'=>@adapter.binding,'request_id'=>input['request_id'],'conversation_id'=>input['conversation_id'],'replayed'=>false,'outcome'=>outcome,
       'execution'=>{'provider'=>'deterministic.cpu_operations','operation'=>operation,'state'=>outcome['state'],'model_invoked'=>false,'input_sha256'=>self.class.digest(input),'result_sha256'=>Digest::SHA256.hexdigest(content)}}
    end
    def apply!(record)
      state=record['state'];return super unless %w[cpu_operation_intent cpu_operation_complete].include?(state)
      prior=@attempts[record['request_id']];data=record['data']
      raise Refused,'operational state' unless prior&&prior['state']=='cpu_requested'
      operation=CpuMemberOperations.resolve(prior['input']['messages'].last['content']);raise Refused,'not an explicit operation' unless operation
      if state=='cpu_operation_intent'
        raise Refused,'operational intent' unless data=={'operation'=>operation}&&!prior['operation_intent']
        prior['operation_intent']=operation
      else
        raise Refused,'operational attribution' unless prior['operation_intent']==operation&&data==operation_result(prior['input'],operation,data['outcome'])
        prior['state']='complete';prior['result']=data
      end
    end
  end
end
