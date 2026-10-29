# frozen_string_literal: true
require_relative 'cpu_member_service_store'
require_relative 'cpu_member_handoff_store'
require_relative 'cpu_member_handoff_gateway'
require_relative 'cpu_member_calculation_gateway'
require_relative 'cpu_member_creative_execution_gateway'
require_relative 'cpu_member_creative_execution_gateway_v2'
require_relative 'cpu_reference_gateway'
require_relative 'cpu_reference_gateway_v2'
require_relative 'cpu_reference_gateway_v3'
require_relative 'cpu_member_roster_handoff'
require_relative 'cpu_member_resident_owner'
require_relative 'roster_request_control'
require_relative 'roster_chat_application'
module SoulCore
  class CpuMemberService
    SCOPE=CpuMemberAdapter::OPERATIONS.keys.freeze
    def initialize(path:,owner:nil,handoff_client:nil,queue_client:nil,compute_reader:nil,assistance:false,scoped_memory:false,memory:nil,operations:false,operation_reader:nil,creative_previews:false,creative_preview:nil,creative_execution:false,creative_bridge:nil,references:false,reference_reader:nil)
      raise ArgumentError,'creative execution requires previews' if creative_execution&&!creative_previews
      raise ArgumentError,'references require complete creative gateway' if references&&!creative_execution
      @references,@reference_reader=references,reference_reader
      @creative_execution,@creative_bridge=creative_execution,creative_bridge
      raise ArgumentError,'creative previews require operations' if creative_previews&&!operations
      @creative_previews=creative_previews;@creative_preview=creative_preview
      raise ArgumentError,'operations require scoped memory' if operations&&!scoped_memory
      @operations_enabled=operations;@operation_reader=operation_reader
      raise ArgumentError,'memory requires assistance gateway' if scoped_memory&&!assistance
      @memory_context=scoped_memory ? (memory||CpuMemberMemoryContext.new(store:ConversationMemoryStore.new(root:File.expand_path('../..',__dir__),create:false))) : nil
      @path=path;@root=CpuMemberGateway::Directory.new(path);@mutex=Mutex.new;@control=RosterRequestControl.new
      @root.write('service.lock',{}) unless @root.children.include?('service.lock')
      @lock=@root.open_file('service.lock',File::RDWR)
      raise CpuMemberGateway::Refused,'CPU service already owned' unless @lock.flock(File::LOCK_EX|File::LOCK_NB)
      %w[tasks conversations runtime runs queue].each do |name|
        Dir.mkdir(@root.anchor(name),0700) unless @root.children.include?(name)
      end
      @root.sync
      @handoff_client=handoff_client||CpuMemberRosterHandoff.new(store:nil)
      @tasks=CpuMemberHandoffStore.new(tasks:CpuMemberTaskStore.new(path:File.join(path,'tasks')),path:File.join(path,'runs'),client:@handoff_client)
      if assistance
      reader=compute_reader||-> {
        bridge=RosterDashboardRuntime.new(store:nil);key=bridge.send(:read_key)
        begin;bridge.instance_variable_get(:@transport).call('/v1/soul/compute/status',{},key,3,{})
        ensure;key&.clear;end
      }
      @queue=CpuMemberDeferredQueue.new(base:@tasks,path:File.join(path,'queue'),client:queue_client||CpuMemberRosterHandoff.new(store:nil),status_reader:reader)
      @tasks=@queue
      end
      @conversations=CpuMemberGateway::Directory.new(File.join(path,'conversations'))
      @owner=owner||CpuMemberResidentOwner.new(path:File.join(path,'runtime'))
      @cache=(@memory_context ? CpuMemberMemoryCache : CpuMemberConversationCache).new(@owner)
      @closing=false
    end
    def complete(conversation_id:,request_id:,messages:,deadline:,cancel:->{false})
      @control.run(conversation_id:conversation_id,request_id:request_id,cancel:cancel,released:->{@owner.status['state']=='unloaded'&&(!@handoff_run||@handoff_client.cleanup_confirmed?)}) do |signal|
        locked=@mutex.try_lock;raise RosterAdmissionBusy unless locked
        begin
          raise CpuMemberGateway::Refused,'CPU service stopping' if @closing
          @handoff_run=CpuMemberHandoffGateway.command(messages.last['content'])&.first=='run'
          name=CpuMemberGateway.digest(conversation_id);path=File.join(@conversations.path,name)
          klass=@references ? CpuReferenceGatewayV3 : @creative_execution ? CpuMemberCreativeExecutionGatewayV2 : @creative_previews ? CpuMemberCreativePreviewGatewayV3 : (@operations_enabled ? CpuMemberOperationsGatewayV2 : (@memory_context ? CpuMemberMemoryGateway : (@queue ? CpuMemberAssistanceGatewayV3 : CpuMemberCalculationGateway)))
          if @conversations.children.include?(name)
            directory=CpuMemberGateway::Directory.new(path)
            begin;version=directory.read('roster.json')['service_version'];ensure;directory.close;end
            klass={'cpu_member_a3_v1'=>CpuMemberServiceGateway,'cpu_member_a4_v1'=>CpuMemberHandoffGateway,'cpu_member_a5_v1'=>CpuMemberCalculationGateway,'cpu_member_a6_v1'=>CpuMemberAssistanceGateway,'cpu_member_a6_v2'=>CpuMemberAssistanceGatewayV2,'cpu_member_a6_v3'=>CpuMemberAssistanceGatewayV3,'cpu_member_a7_v1'=>CpuMemberMemoryGateway,'cpu_member_a8_v1'=>CpuMemberOperationsGateway,'cpu_member_a8_v2'=>CpuMemberOperationsGatewayV2,'cpu_member_a9_v1'=>CpuMemberCreativePreviewGateway,'cpu_member_a9_v2'=>CpuMemberCreativePreviewGatewayV2,'cpu_member_a9_v3'=>CpuMemberCreativePreviewGatewayV3,'cpu_member_a10_v1'=>CpuMemberCreativeExecutionGateway,'cpu_member_a10_v2'=>CpuMemberCreativeExecutionGatewayV2,'cpu_member_a11_v1'=>CpuReferenceGateway,'cpu_member_a11_v2'=>CpuReferenceGatewayV2,'cpu_member_a11_v3'=>CpuReferenceGatewayV3}.fetch(version){raise CpuMemberGateway::Refused,'unknown CPU journal version'}
          else
            klass.create(path:path,owner:CpuMemberAdapter.new)
          end
          raise CpuMemberGateway::Refused,'A11 activation is required' if klass<=CpuReferenceGateway&&!@references
          raise ArgumentError,'Start a new conversation to use validated calculation.' if ![CpuMemberCalculationGateway,CpuMemberAssistanceGateway,CpuMemberAssistanceGatewayV2,CpuMemberAssistanceGatewayV3,CpuMemberMemoryGateway,CpuMemberOperationsGateway,CpuMemberOperationsGatewayV2,CpuMemberCreativePreviewGateway,CpuMemberCreativePreviewGatewayV2,CpuMemberCreativePreviewGatewayV3,CpuMemberCreativeExecutionGateway,CpuMemberCreativeExecutionGatewayV2].any?{|base|klass<=base} && messages.last['content'].start_with?('/calculate')
          raise CpuMemberGateway::Refused,'A10 activation is required' if [CpuMemberCreativeExecutionGateway,CpuMemberCreativeExecutionGatewayV2].any?{|base|klass<=base}&&!@creative_execution
          raise CpuMemberGateway::Refused,'A9 activation is required' if [CpuMemberCreativePreviewGateway,CpuMemberCreativePreviewGatewayV2,CpuMemberCreativePreviewGatewayV3,CpuMemberCreativeExecutionGateway,CpuMemberCreativeExecutionGatewayV2].any?{|base|klass<=base}&&!@creative_previews
          raise CpuMemberGateway::Refused,'A8 activation is required' if [CpuMemberOperationsGateway,CpuMemberOperationsGatewayV2,CpuMemberCreativePreviewGateway,CpuMemberCreativePreviewGatewayV2,CpuMemberCreativePreviewGatewayV3,CpuMemberCreativeExecutionGateway,CpuMemberCreativeExecutionGatewayV2].any?{|base|klass<=base}&&!@operations_enabled
          raise CpuMemberGateway::Refused,'A7 activation is required' if [CpuMemberMemoryGateway,CpuMemberOperationsGateway,CpuMemberOperationsGatewayV2,CpuMemberCreativePreviewGateway,CpuMemberCreativePreviewGatewayV2,CpuMemberCreativePreviewGatewayV3,CpuMemberCreativeExecutionGateway,CpuMemberCreativeExecutionGatewayV2].any?{|base|klass<=base}&&!@memory_context
          raise CpuMemberGateway::Refused,'A6 activation is required' if [CpuMemberAssistanceGateway,CpuMemberAssistanceGatewayV2,CpuMemberAssistanceGatewayV3,CpuMemberMemoryGateway,CpuMemberOperationsGateway,CpuMemberOperationsGatewayV2,CpuMemberCreativePreviewGateway,CpuMemberCreativePreviewGatewayV2,CpuMemberCreativePreviewGatewayV3,CpuMemberCreativeExecutionGateway,CpuMemberCreativeExecutionGatewayV2].any?{|base|klass<=base} && !@queue
          client=if [CpuMemberCalculationGateway,CpuMemberAssistanceGateway,CpuMemberAssistanceGatewayV2,CpuMemberAssistanceGatewayV3,CpuMemberMemoryGateway,CpuMemberOperationsGateway,CpuMemberOperationsGatewayV2,CpuMemberCreativePreviewGateway,CpuMemberCreativePreviewGatewayV2,CpuMemberCreativePreviewGatewayV3,CpuMemberCreativeExecutionGateway,CpuMemberCreativeExecutionGatewayV2].any?{|base|klass<=base}
            binding_directory=CpuMemberGateway::Directory.new(path)
            begin;binding=binding_directory.read('roster.json');ensure;binding_directory.close;end
            @cache.client([name,binding])
          else
            @cache.invalidate;@owner
          end
          gateway=klass.new(**(klass<=CpuReferenceGateway ? {reference_reader:@reference_reader} : {}),**([CpuMemberCreativeExecutionGateway,CpuMemberCreativeExecutionGatewayV2].any?{|base|klass<=base} ? {creative_bridge:@creative_bridge} : {}),path:path,tasks:@tasks,client:client,admission:->{@owner.admitted?},**([CpuMemberCreativePreviewGateway,CpuMemberCreativePreviewGatewayV2,CpuMemberCreativePreviewGatewayV3,CpuMemberCreativeExecutionGateway,CpuMemberCreativeExecutionGatewayV2].any?{|base|klass<=base} ? {creative_preview:@creative_preview} : {}),**([CpuMemberMemoryGateway,CpuMemberOperationsGateway,CpuMemberOperationsGatewayV2,CpuMemberCreativePreviewGateway,CpuMemberCreativePreviewGatewayV2,CpuMemberCreativePreviewGatewayV3,CpuMemberCreativeExecutionGateway,CpuMemberCreativeExecutionGatewayV2].any?{|base|klass<=base} ? {memory:@memory_context} : {}),**([CpuMemberOperationsGateway,CpuMemberOperationsGatewayV2,CpuMemberCreativePreviewGateway,CpuMemberCreativePreviewGatewayV2,CpuMemberCreativePreviewGatewayV3,CpuMemberCreativeExecutionGateway,CpuMemberCreativeExecutionGatewayV2].any?{|base|klass<=base} ? {operations:@operation_reader} : {}),**([CpuMemberAssistanceGateway,CpuMemberAssistanceGatewayV2,CpuMemberAssistanceGatewayV3,CpuMemberMemoryGateway,CpuMemberOperationsGateway,CpuMemberOperationsGatewayV2,CpuMemberCreativePreviewGateway,CpuMemberCreativePreviewGatewayV2,CpuMemberCreativePreviewGatewayV3,CpuMemberCreativeExecutionGateway,CpuMemberCreativeExecutionGatewayV2].any?{|base|klass<=base} ? {queue:@queue} : {}))
          value=gateway.complete(conversation_id:conversation_id,request_id:request_id,messages:messages,scope:SCOPE,deadline:deadline,cancel:signal)
          @owner.touch;value
        rescue StandardError
          @cache.invalidate;@owner.stop;raise
        ensure
          gateway&.close;@mutex.unlock if locked
        end
      end
    end
    def cancel_request(**args)=@control.cancel(**args)
    def request_status(**args)=@control.status(**args)
    def status
      {'member'=>CpuMemberAdapter::MODEL,'available'=>!@closing,'task_dispatch'=>false,'explicit_task_handoff'=>true,'context_tokens'=>4096,'output_tokens'=>1024,'memory_policy'=>(@memory_context ? 'approved_shared_and_exact_cpu_member_reference_only_v1' : 'none'),'read_only_skills'=>true,'confirmed_queue'=>!@queue.nil?,'explicit_operational_requests'=>@operations_enabled,'creative_previews'=>@creative_previews,'creative_execution'=>@creative_execution,'reference_requests'=>@references}.merge(@owner.status)
    end
    def tick
      return unless @mutex.try_lock
      begin;@queue&.tick;@owner.tick;@cache.invalidate if @owner.status['state']=='unloaded';ensure;@mutex.unlock;end
    end
    def close
      @closing=true
      @mutex.synchronize{begin;@tasks.close;ensure;@cache.invalidate;@owner.stop;end}
      @conversations.close;@lock.close;@root.close
    end
  end

  class CpuMemberApplication < RosterChatApplication
    CONTROL={'/v1/soul/requests/cancel'=>:cancel_request,'/v1/soul/requests/status'=>:request_status}.freeze
    def call(method:,target:,headers:,body:nil,cancel:->{false})
      return super unless CONTROL.key?(target)
      h=normalize_headers(headers)
      return error_response(403,'origin_forbidden','Cross-origin requests are not supported.') if h.key?('origin')
      return error_response(401,'unauthorized','Valid bearer token required.') unless authenticated?(h['authorization'])
      return error_response(405,'method_not_allowed','POST required.') unless method=='POST'
      raise ArgumentError unless body.is_a?(String)&&body.bytesize.between?(1,1024)
      data=ContinuityLab.parse(body)
      raise ArgumentError unless data.is_a?(Hash)&&data.keys.sort==%w[conversation_id request_id]
      json_response(200,@backend.public_send(CONTROL.fetch(target),**data.transform_keys(&:to_sym)))
    rescue StandardError
      error_response(422,'invalid_request','Exact request identity required.')
    end
    private
    def error_response(status,code,message)
      message='CPU context is full (4096 tokens including up to 1024 for the reply). Start a new conversation; saved history is preserved.' if code=='quota_exceeded'
      message='This CPU conversation has changed, was canceled, or contains unfinished work. Start a new conversation; saved history and task receipts are preserved. No retry was started.' if code=='history_conflict'
      super(status,code,message)
    end
    def supported_models = [CpuMemberAdapter::MODEL]
    def generation_parameters = {'max_tokens'=>1024,'temperature'=>1.0,'top_p'=>0.95}
    def health_response = json_response(200,@backend.status)
    def backend_complete(conversation_id,request,messages,cancel)
      adapter=CpuMemberAdapter.new
      CpuMemberCalculationGateway.command(messages.last['content']) # Reject malformed command before durable intent.
      request_id=CpuMemberGateway.digest({'conversation'=>conversation_id,'adapter'=>adapter.binding,'messages'=>messages})
      result=@backend.complete(conversation_id:conversation_id,request_id:request_id,messages:messages,deadline:@clock.call+119,cancel:cancel)
      raise ContinuityLab::Error unless result.values_at('model','adapter','conversation_id','request_id')==[CpuMemberAdapter::MODEL,adapter.binding,conversation_id,request_id]
      {'id'=>'chatcmpl-'+request_id,'created'=>Time.now.to_i,'model'=>CpuMemberAdapter::MODEL,'content'=>result['content'],
        'soul'=>result.slice('conversation_id','request_id','model','adapter','replayed','usage','execution','memory')}
    rescue RosterAdmissionBusy
      raise ContinuityLab::Busy
    rescue CpuMemberGateway::Refused=>e
      raise ContinuityLab::QuotaExceeded if e.message=='context exceeded'
      raise ContinuityLab::Conflict
    rescue ArgumentError,JSON::ParserError
      raise ContinuityLab::ValidationError
    rescue StandardError
      raise ContinuityLab::Error
    end
  end
end
