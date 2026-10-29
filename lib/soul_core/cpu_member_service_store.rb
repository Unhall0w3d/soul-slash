# frozen_string_literal: true
require_relative 'cpu_member_gateway'

module SoulCore
  # One A2 ledger per task: its two terminal transitions cannot consume chat capacity.
  # An immutable command index prevents a request identity moving between tasks.
  class CpuMemberTaskStore
    Directory = CpuMemberGateway::Directory
    def initialize(path:)
      @path=path; @root=Directory.new(path); @mutex=Mutex.new
      @root.write("tasks.lock",{}) unless @root.children.include?("tasks.lock")
      @lock=@root.open_file("tasks.lock",File::RDWR)
    end
    def close
      @lock.close; @root.close
    end
    def call(action, args)
      @mutex.synchronize do
        raise CpuMemberGateway::Refused,"task store busy" unless @lock.flock(File::LOCK_EX|File::LOCK_NB)
        begin
          @root.verify!
          return list(**args) if action=='list'
          id=args.fetch(:request_id)
          raise ArgumentError,'request identity' unless id.is_a?(String)&&CpuMemberGateway::ID.match?(id)
          command={'action'=>action,'args'=>args.transform_keys(&:to_s)}
          name='request-'+CpuMemberGateway.digest(id)+'.json'
          if @root.children.include?(name)
            raise CpuMemberGateway::Refused,'changed task command' unless @root.read(name)==command
          else
            @root.write(name,command)
          end
          task_id=action=='add' ? 't-'+CpuMemberGateway.digest(id)[0,24] : args.fetch(:task_id)
          raise ArgumentError,'task identity' unless /\At-[a-f0-9]{24}\z/.match?(task_id.to_s)
          path=File.join(@path,task_id)
          if action=='add' && !@root.children.include?(task_id)
            CpuMemberGateway.create(path:path,owner:CpuMemberAdapter.new)
          end
          ledger=CpuMemberGateway.new(path:path)
          action=='add' ? ledger.add_task(**args) : ledger.cancel_task(**args)
        ensure
          ledger&.close
          # Directory's initialization lock is a flock on this open descriptor.
          @lock.flock(File::LOCK_UN)
        end
      end
    end
    def list(cursor:nil)
      raise ArgumentError,'cursor' unless cursor.nil? || /\At-[a-f0-9]{24}\z/.match?(cursor)
      names=@root.children.grep(/\At-[a-f0-9]{24}\z/).sort
      selected=names.select{|n|cursor.nil? || n>cursor}.first(17)
      more=selected.length>16; selected=selected.first(16)
      tasks=selected.map do |name|
        ledger=CpuMemberGateway.new(path:File.join(@path,name))
        begin
          rows=ledger.tasks
          raise CpuMemberGateway::Refused,'incomplete task; inspect retained intent' unless rows.length==1&&rows[0]['task_id']==name
          rows.first
        ensure
          ledger.close
        end
      end
      {'tasks'=>tasks,'total'=>names.length,'next_cursor'=>more ? selected.last : nil,
        'scope'=>'explicit user tasks; pending is not scheduled'}
    end
  end

  class CpuMemberServiceGateway < CpuMemberGateway
    def self.manifest(owner)
      super.merge('service_version'=>'cpu_member_a3_v1','service_implementation'=>Digest::SHA256.file(__FILE__).hexdigest)
    end
    def initialize(tasks:,**args)
      @task_store=tasks
      super(**args)
    end
    # Only a literal user message reaches this parser. Generated text never does.
    def self.command(text)
      return nil unless text.start_with?('/task')
      return ['help',{}] if text=='/task help'
      return ['list',{}] if text=='/task list'
      match=/\A\/task (add|cancel|list) (\{.*\})\z/m.match(text)
      raise ArgumentError,'Use /task help for the exact task commands.' unless match&&text.bytesize<=4096
      data=JSON.parse(match[2],allow_duplicate_key:false)
      keys={'add'=>%w[detail member title],'cancel'=>%w[task_id],'list'=>%w[cursor]}.fetch(match[1])
      raise ArgumentError,'exact task fields required' unless data.is_a?(Hash)&&data.keys.sort==keys
      [match[1],data.transform_keys(&:to_sym)]
    end
    def complete(**args)
      cmd=self.class.command(args.fetch(:messages).last.fetch('content'))
      return super unless cmd
      conversation_id,request_id,messages,scope,deadline,cancel=args.values_at(:conversation_id,:request_id,:messages,:scope,:deadline,:cancel)
      cancel ||= ->{false}; scope ||= []
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
        action,fields=cmd
        outcome=if action=='help'
          {'commands'=>['/task list','/task add {"title":"...","detail":"...","member":"gemma-4-e4b-cpu"}','/task cancel {"task_id":"t-..."}','/task list {"cursor":"t-..."}'], 'members'=>MEMBERS,'note'=>'Explicit user actions only. Pending tasks are recorded, not scheduled. No model or GPU dispatch.'}
        else
          @task_store.call(action,fields.merge(%w[add cancel].include?(action) ? {request_id:request_id} : {}))
        end
        result={'kind'=>'user_command','content'=>"Soul explicit task action (no model invoked)\n"+JSON.pretty_generate(outcome),
          'model'=>CpuMemberAdapter::MODEL,'adapter'=>@adapter.binding,'request_id'=>request_id,'conversation_id'=>conversation_id,
          'replayed'=>false,'execution'=>{'provider'=>'deterministic.task_control','operation'=>'tasks.'+action,'state'=>'complete','model_invoked'=>false}}
        # Once a durable task mutation has committed, retain its receipt even if
        # the socket disconnected. A retry can only replay this exact outcome.
        append!('cpu_user_complete',request_id,result);result
      end
    end
    private
    def load!
      super
      page=@task_store.call('list',{})
      @tasks=Struct.new(:values,:length).new(page['tasks'],page['total'])
    end
    def apply!(record)
      return super unless record['state']=='cpu_user_complete'
      prior=@attempts[record['request_id']];data=record['data']
      raise Refused,'invalid explicit command receipt' unless prior&&prior['state']=='cpu_requested'&&self.class.command(prior['input']['messages'].last['content'])&&
        data.keys.sort==%w[adapter content conversation_id execution kind model replayed request_id]&&data['kind']=='user_command'&&data['model']==CpuMemberAdapter::MODEL&&data['adapter']==@adapter.binding&&data['request_id']==record['request_id']&&data['conversation_id']==prior['input']['conversation_id']&&data['replayed']==false&&text?(data['content'],65_536)&&
        data['execution']=={'provider'=>'deterministic.task_control','operation'=>'tasks.'+self.class.command(prior['input']['messages'].last['content'])[0],'state'=>'complete','model_invoked'=>false}
      prior['state']='complete';prior['result']=data
    end
  end
end
