# frozen_string_literal: true
require_relative 'cpu_member_creative_execution_gateway_v2'
require_relative 'cpu_reference_requests'
module SoulCore
  class CpuReferenceGateway < CpuMemberCreativeExecutionGatewayV2
    def self.manifest(owner)
      files=%w[cpu_reference_gateway.rb cpu_reference_requests.rb cpu_reference_reader.rb file_inspection_service.rb local_search_service.rb conversation_weather_service.rb web_research_service.rb skill_runner.rb]
      super.merge('service_version'=>'cpu_member_a11_v1',
        'a11_implementation'=>files.to_h{|f|[f,Digest::SHA256.file(File.join(__dir__,f)).hexdigest]},
        'a11_helper'=>Digest::SHA256.file(File.expand_path('../../scripts/cpu-reference-operation.rb',__dir__)).hexdigest,
        'a11_weather'=>Digest::SHA256.file(File.expand_path('../../Soul/skills/weather/report.rb',__dir__)).hexdigest)
    end
    def initialize(reference_reader:nil,**args)
      @reference_reader=reference_reader||CpuReferenceRequests.new
      super(**args)
    end
    def complete(**args)
      messages=args.fetch(:messages);parsed=CpuReferenceRequests.parse(messages.last.fetch('content'))
      return super unless parsed
      conversation_id,request_id,scope,deadline,cancel=args.values_at(:conversation_id,:request_id,:scope,:deadline,:cancel)
      cancel||=->{false};scope||=[]
      ContinuityLab::ChatGateway.validate_input!(conversation_id,messages);valid_id!(request_id)
      @adapter.payload(messages:messages.last(7),scope:scope)
      input=JSON.parse(JSON.generate({'conversation_id'=>conversation_id,'request_id'=>request_id,'messages'=>messages,'scope'=>scope,'adapter'=>@adapter.binding}))
      with_store do
        check!(deadline,cancel)
        raise Refused,'task request identity reused' if @task_requests.key?(request_id)
        if (prior=@attempts[request_id])
          raise Refused,'changed or unfinished reference request' unless prior['input']==input&&prior['state']=='complete'
          return Marshal.load(Marshal.dump(prior['result'])).merge('replayed'=>true)
        end
        turns=@attempts.values.select{|a|a['input']['conversation_id']==conversation_id}
        expected=turns.flat_map{|a|[a['input']['messages'].last,{'role'=>'assistant','content'=>a.dig('result','content')}]}
        raise Refused,'reference history changed' unless turns.all?{|a|a['state']=='complete'}&&messages[0...-1]==expected
        raise Refused,'journal capacity' if @records.length+3>LIMIT
        append!('cpu_requested',request_id,input)
        begin
          append!('cpu_reference_intent',request_id,parsed)
          outcome=@reference_reader.call(query:messages.last['content'],deadline:deadline,cancel:cancel)
          check!(deadline,cancel);result=reference_result(input,parsed,outcome)
          append!('cpu_reference_complete',request_id,result);result
        rescue StandardError=>error
          append!(cancel.call ? 'cpu_canceled' : 'cpu_failed',request_id,{'requires_review'=>true,'error_class'=>error.class.name}) if @attempts[request_id]['state']=='cpu_requested'
          raise
        end
      end
    end
    private
    def reference_result(input,parsed,outcome)
      CpuMemberOperations.validate!(outcome)
      content="Soul reference result — deterministic harness; CPU model not invoked.\nOperation: #{parsed.fetch('operation')}\n"+outcome['content'].strip
      raise Refused,'reference presentation bound' if content.bytesize>12*1024
      {'kind'=>'reference','content'=>content,'model'=>CpuMemberAdapter::MODEL,'adapter'=>@adapter.binding,
       'request_id'=>input['request_id'],'conversation_id'=>input['conversation_id'],'replayed'=>false,'outcome'=>outcome,
       'execution'=>{'provider'=>'deterministic.cpu_reference','operation'=>parsed['operation'],'state'=>outcome['state'],
         'model_invoked'=>false,'input_sha256'=>self.class.digest(input),'result_sha256'=>Digest::SHA256.hexdigest(content)}}
    end
    def apply!(record)
      return super unless %w[cpu_reference_intent cpu_reference_complete].include?(record['state'])
      prior=@attempts[record['request_id']];data=record['data']
      raise Refused,'reference state' unless prior&&prior['state']=='cpu_requested'
      parsed=CpuReferenceRequests.parse(prior['input']['messages'].last['content']);raise Refused,'not an explicit reference request' unless parsed
      if record['state']=='cpu_reference_intent'
        raise Refused,'reference intent' unless data==parsed&&!prior['reference_intent']
        prior['reference_intent']=parsed
      else
        raise Refused,'reference attribution' unless prior['reference_intent']==parsed&&data==reference_result(prior['input'],parsed,data['outcome'])
        prior['state']='complete';prior['result']=data
      end
    end
  end
end
