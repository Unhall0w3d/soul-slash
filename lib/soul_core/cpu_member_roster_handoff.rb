# frozen_string_literal: true
require_relative 'roster_dashboard_runtime'
module SoulCore
  class CpuMemberRosterHandoff < RosterDashboardRuntime
    def cleanup_confirmed? = @clean==true
    def call(task:,deadline:,cancel:)
      @clean=false;token=@key_reader.call;member=task.fetch('member');adapter=member_adapter(member)
      raise ArgumentError,'GPU roster member required' unless (RosterChatAdapter::MODELS+RosterChatAdapter::ISOLATED_MODELS).include?(member)
      conversation='cpu_task_'+RosterConversationGateway.digest(task)
      messages=[{'role'=>'user','content'=>"Work on this explicitly reviewed task within your existing read-only capabilities. Do not claim execution beyond tool receipts. Return a concise result for review.\nTitle: #{task.fetch('title')}\nTask: #{task.fetch('detail')}"}]
      identity={'conversation_id'=>conversation,'request_id'=>RosterConversationGateway.digest({'conversation'=>conversation,'adapter'=>adapter.binding,'messages'=>messages})}
      status=@transport.call('/v1/soul/compute/status',{},token,3,{})
      raise RuntimeError,'GPU compute unavailable or reserved' unless status['available']==true&&status['policy']=='available'&&status['handoff'].nil?&&%w[unloaded resident].include?(status['state'])
      raise RuntimeError,'handoff canceled' if cancel.call
      cutoff=[deadline,Process.clock_gettime(Process::CLOCK_MONOTONIC)+110].min
      mutex=Mutex.new;done=false;changed=ConditionVariable.new
      watcher=Thread.new do
        loop do
          break if mutex.synchronize{changed.wait(mutex,0.1) unless done;done}
          next unless cancel.call||Process.clock_gettime(Process::CLOCK_MONOTONIC)>=cutoff
          begin;@transport.call('/v1/soul/requests/cancel',identity,token,3,{});rescue StandardError;end
        end
      end
      sent=true
      response=@transport.call('/v1/chat/completions',{'model'=>member,'messages'=>messages,'stream'=>false},token,[cutoff-Process.clock_gettime(Process::CLOCK_MONOTONIC),0.1].max,{'X-Soul-Conversation-Id'=>conversation})
      raise RuntimeError,'handoff canceled' if cancel.call||Process.clock_gettime(Process::CLOCK_MONOTONIC)>=cutoff
      soul=response.fetch('soul');choice=response.fetch('choices').first;content=choice&.dig('message','content')
      raise RuntimeError,'handoff attribution mismatch' unless response['model']==member&&soul.values_at('conversation_id','request_id','model','adapter')==[conversation,identity['request_id'],member,adapter.binding]
      raise RuntimeError,'invalid handoff answer' unless choice&.dig('message','role')=='assistant'&&choice['finish_reason']=='stop'&&content.is_a?(String)&&content.valid_encoding?&&content.bytesize.between?(1,32_768)
      validate_execution!(soul['execution'],identity,adapter,messages,content,member) if soul['execution']
      {'member'=>member,'adapter'=>adapter.binding,'conversation_id'=>conversation,'request_id'=>identity['request_id'],'content'=>content,'execution'=>soul['execution'],'replayed'=>soul['replayed']}
    rescue StandardError
      if sent&&token&&identity
        # A lost response is not proof of completion or release. Stop/status are
        # the only retryable calls; generation is never retried here.
        until Process.clock_gettime(Process::CLOCK_MONOTONIC)>=(finish_by||=Process.clock_gettime(Process::CLOCK_MONOTONIC)+8)
          begin
            @transport.call('/v1/soul/requests/cancel',identity,token,2,{})
            s=@transport.call('/v1/soul/requests/status',identity,token,2,{})
            if s.values_at('conversation_id','request_id','state','cleanup_confirmed')==[identity['conversation_id'],identity['request_id'],'canceled_released',true]
              @clean=true;break
            end
          rescue StandardError
          end
          sleep 0.1
        end
      end
      raise
    ensure
      mutex&.synchronize{done=true;changed.broadcast}
      raise RuntimeError,'handoff watcher did not stop' if watcher&&!watcher.join(4)
      token&.clear
    end
  end
end
