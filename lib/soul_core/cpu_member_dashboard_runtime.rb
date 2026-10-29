# frozen_string_literal: true
require_relative 'cpu_member_adapter'
require_relative 'cpu_member_calculation'
require_relative 'cpu_member_assistance_gateway'
# Loaded after the shared authenticated client definition, without changing its
# GPU endpoint or interpretation of GPU execution receipts.
module SoulCore
  class CpuMemberDashboardRuntime < RosterDashboardRuntime
    MEMBERS=[CpuMemberAdapter::MODEL].freeze
    def status
      token=@key_reader.call
      http=Net::HTTP.new('127.0.0.1',8097,nil);http.open_timeout=2;http.read_timeout=3;http.max_retries=0
      req=Net::HTTP::Get.new('/health',{'Authorization'=>'Bearer '+token});bytes=+'';code=nil
      http.request(req){|r|code=r.code;r.read_body{|b|bytes<<b;raise 'status bound' if bytes.bytesize>8192}}
      data=JSON.parse(bytes)
      raise 'CPU status unavailable' unless code=='200'&&data['member']==CpuMemberAdapter::MODEL&&data['cpu_only']==true&&%w[loaded unloaded].include?(data['state'])&&data['idle_seconds'].nil?
      {'ok'=>true,'lifecycle_state'=>'complete','data'=>data.slice('member','state','cpu_only','residency','context_tokens','output_tokens'),'mutation'=>'none'}
    rescue StandardError
      {'ok'=>false,'lifecycle_state'=>'blocked_for_human_review','reason'=>'CPU coordinator status unavailable. No model was started.','data'=>{},'mutation'=>'none'}
    ensure
      token&.clear
    end
    private
    def coordinator_port = 8097
    def member_adapter(member) = CpuMemberAdapter.new
    def validate_execution!(execution,identity,adapter,messages,content,member)
      provider,operation,state=execution.values_at('provider','operation','state')
      valid=if provider=='deterministic.cpu_assistance'
        input={'conversation_id'=>identity['conversation_id'],'request_id'=>identity['request_id'],'messages'=>messages,'scope'=>CpuMemberAdapter::OPERATIONS.keys,'adapter'=>adapter.binding}
        action=CpuMemberAssistanceGateway.resolve(messages.last['content'])
        exact=execution.keys.sort==%w[input_sha256 model_invoked operation provider result_sha256 state]&&execution['model_invoked']==false&&%w[complete awaiting_input].include?(state)&&action&&operation==action.first&&execution['input_sha256']==RosterConversationGateway.digest(input)&&execution['result_sha256']==Digest::SHA256.hexdigest(content)
        if exact && action.first=='calculation'
          renderer=CpuMemberAssistanceGateway.allocate;renderer.instance_variable_set(:@adapter,adapter)
          expected=renderer.send(:assistance_result,input,'calculation',action.last)['content']
          exact=content==expected
        end
        exact
      elsif provider=='deterministic.calculation'
        input={'conversation_id'=>identity['conversation_id'],'request_id'=>identity['request_id'],'messages'=>messages,'scope'=>CpuMemberAdapter::OPERATIONS.keys,'adapter'=>adapter.binding}
        data=CpuMemberCalculation.parse(messages.last['content'])
        expected=data && "Soul validated calculation — executed by the deterministic harness; CPU model not invoked.\n"+JSON.pretty_generate(CpuMemberCalculation.evaluate(data))
        execution.keys.sort==%w[input_sha256 model_invoked operation provider result_sha256 state]&&execution['model_invoked']==false&&state=='complete'&&data&&operation=='calculate.'+data['operation']&&content==expected&&execution['input_sha256']==RosterConversationGateway.digest(input)&&execution['result_sha256']==Digest::SHA256.hexdigest(content)
      elsif provider=='deterministic.task_handoff'
        input={'conversation_id'=>identity['conversation_id'],'request_id'=>identity['request_id'],'messages'=>messages,'scope'=>CpuMemberAdapter::OPERATIONS.keys,'adapter'=>adapter.binding}
        execution.keys.sort==%w[cpu_model_invoked input_sha256 operation provider result_sha256 selected_member state]&&execution['cpu_model_invoked']==false&&%w[tasks.preview tasks.run tasks.help].include?(operation)&&%w[complete failed canceled blocked_for_human_review].include?(state)&&(execution['selected_member'].nil?||(RosterChatAdapter::MODELS+RosterChatAdapter::ISOLATED_MODELS).include?(execution['selected_member']))&&execution['input_sha256']==RosterConversationGateway.digest(input)&&execution['result_sha256']==Digest::SHA256.hexdigest(content)&&messages.last['content'].start_with?('/task ')
      elsif provider=='deterministic.task_control'
        execution.keys.sort==%w[model_invoked operation provider state]&&execution['model_invoked']==false&&
          %w[tasks.add tasks.cancel tasks.list tasks.help].include?(operation)&&state=='complete'&&messages.last['content'].start_with?('/task')
      else
        execution.keys.sort==%w[operation provider state]&&%w[complete failed awaiting_input blocked_for_human_review].include?(state)&&
          ((provider=='deterministic.task_list'&&operation=='tasks.list')||(provider=='deterministic.read_only'&&(CpuMemberAdapter::OPERATIONS.values-['tasks.list']).include?(operation)))
      end
      raise RuntimeError,'invalid CPU tool attribution' unless valid
    end
  end
end
