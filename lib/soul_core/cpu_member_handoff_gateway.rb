# frozen_string_literal: true
require_relative 'cpu_member_service_store'
module SoulCore
  class CpuMemberHandoffGateway < CpuMemberServiceGateway
    def self.manifest(owner)
      super.merge('service_version'=>'cpu_member_a4_v1','handoff_implementation'=>%w[cpu_member_handoff_gateway.rb cpu_member_handoff_store.rb cpu_member_roster_handoff.rb].to_h{|f|[f,Digest::SHA256.file(File.join(__dir__,f)).hexdigest]})
    end
    def self.command(text)
      return ['help',{}] if text=='/task help'
      if (m=/\A\/task (preview|run) (\{.*\})\z/m.match(text))
        raise ArgumentError,'command bound' if text.bytesize>4096
        d=JSON.parse(m[2],allow_duplicate_key:false)
        keys=m[1]=='run' ? %w[expected_digest task_id] : %w[task_id]
        raise ArgumentError,'exact handoff fields required' unless d.is_a?(Hash)&&d.keys.sort==keys&&d['task_id'].is_a?(String)&&/\At-[a-f0-9]{24}\z/.match?(d['task_id'])
        raise ArgumentError,'preview digest required' if m[1]=='run'&&!(d['expected_digest'].is_a?(String)&&/\A[a-f0-9]{64}\z/.match?(d['expected_digest']))
        return [m[1],d.transform_keys(&:to_sym)]
      end
      super
    end
    def complete(**args)
      cmd=self.class.command(args.fetch(:messages).last.fetch('content'))
      return super unless cmd&&%w[preview run help].include?(cmd[0])
      conversation_id,request_id,messages,scope,deadline,cancel=args.values_at(:conversation_id,:request_id,:messages,:scope,:deadline,:cancel)
      cancel||=->{false};scope||=[]
      ContinuityLab::ChatGateway.validate_input!(conversation_id,messages);valid_id!(request_id)
      input=JSON.parse(JSON.generate({'conversation_id'=>conversation_id,'request_id'=>request_id,'messages'=>messages,'scope'=>scope,'adapter'=>@adapter.binding}))
      with_store do
        check!(deadline,cancel)
        if (prior=@attempts[request_id])
          raise Refused,'changed or unfinished command' unless prior['input']==input&&prior['state']=='complete'
          return Marshal.load(Marshal.dump(prior['result'])).merge('replayed'=>true)
        end
        turns=@attempts.values.select{|a|a['input']['conversation_id']==conversation_id}
        expected=turns.flat_map{|a|[a['input']['messages'].last,{'role'=>'assistant','content'=>a.dig('result','content')}]}
        raise Refused,'command history changed' unless turns.all?{|a|a['state']=='complete'}&&messages[0...-1]==expected
        raise Refused,'journal capacity' if @records.length+2>LIMIT
        append!('cpu_requested',request_id,input)
        begin
          action,fields=cmd
          outcome=if action=='help'
            {'commands'=>['/task list','/task add {"title":"...","detail":"...","member":"gpt-oss-20b"}','/task preview {"task_id":"t-..."}','/task run {"task_id":"t-...","expected_digest":"..."}','/task cancel {"task_id":"t-..."}'],
             'note'=>'Review preview contents and target before Run. One explicit foreground attempt; no automatic dispatch or retry. Stop cancels active work. Canceled chats require a new conversation. CPU context is 4096 tokens including up to 1024 output tokens.'}
          else
            @task_store.call(action,fields.merge(action=='run' ? {request_id:request_id,deadline:deadline,cancel:cancel} : {}))
          end
          check!(deadline,cancel)
          content="Soul explicit task #{action} — CPU model not invoked; results are reference material.\n"+JSON.pretty_generate(outcome)
          raise Refused,'handoff output bound' if content.bytesize>65_536
          member=outcome.dig('task','member')
          execution={'provider'=>'deterministic.task_handoff','operation'=>'tasks.'+action,'state'=>outcome.dig('task','run','state')||'complete','selected_member'=>member,'cpu_model_invoked'=>false,'result_sha256'=>Digest::SHA256.hexdigest(content),'input_sha256'=>self.class.digest(input)}
          result={'kind'=>'handoff','content'=>content,'model'=>CpuMemberAdapter::MODEL,'adapter'=>@adapter.binding,'request_id'=>request_id,'conversation_id'=>conversation_id,'replayed'=>false,'execution'=>execution}
          append!('cpu_handoff_complete',request_id,result);result
        rescue StandardError=>e
          if @attempts[request_id]['state']=='cpu_requested'
            append!(cancel.call ? 'cpu_canceled' : 'cpu_failed',request_id,{'requires_review'=>true,'error_class'=>e.class.name})
          end
          raise
        end
      end
    end
    private
    def apply!(record)
      return super unless record['state']=='cpu_handoff_complete'
      prior=@attempts[record['request_id']];d=record['data'];e=d['execution']
      raise Refused,'invalid handoff receipt' unless prior&&prior['state']=='cpu_requested'&&d.keys.sort==%w[adapter content conversation_id execution kind model replayed request_id]&&d.values_at('kind','model','adapter','request_id','conversation_id','replayed')==['handoff',CpuMemberAdapter::MODEL,@adapter.binding,record['request_id'],prior['input']['conversation_id'],false]&&text?(d['content'],65_536)&&e.is_a?(Hash)&&e.keys.sort==%w[cpu_model_invoked input_sha256 operation provider result_sha256 selected_member state]&&e['provider']=='deterministic.task_handoff'&&e['cpu_model_invoked']==false&&e['operation']=='tasks.'+self.class.command(prior['input']['messages'].last['content'])[0]&&%w[complete failed canceled blocked_for_human_review].include?(e['state'])&&(e['selected_member'].nil?||MEMBERS.include?(e['selected_member']))&&e['input_sha256']==self.class.digest(prior['input'])&&e['result_sha256']==Digest::SHA256.hexdigest(d['content'])
      prior['state']='complete';prior['result']=d
    end
  end
end
