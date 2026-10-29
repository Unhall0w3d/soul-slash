# frozen_string_literal: true
require_relative 'cpu_member_service_store'
require_relative 'roster_chat_adapter'
module SoulCore
  # Original task ledgers remain immutable. A separate one-attempt run receipt
  # overlays their state; a crash after intent never turns into an automatic retry.
  class CpuMemberHandoffStore
    G=CpuMemberGateway
    MEMBERS=(RosterChatAdapter::MODELS+RosterChatAdapter::ISOLATED_MODELS).freeze
    def initialize(tasks:,path:,client:)
      @tasks,@client=tasks,client;@task_index=G::Directory.new(File.join(File.dirname(path),'tasks'));@root=G::Directory.new(path);@mutex=Mutex.new
      @root.write('runs.lock',{}) unless @root.children.include?('runs.lock')
      @lock=@root.open_file('runs.lock',File::RDWR)
      locked do
        policy={'version'=>'cpu_task_run_v1','implementation'=>%w[cpu_member_handoff_store.rb cpu_member_roster_handoff.rb].to_h{|f|[f,Digest::SHA256.file(File.join(__dir__,f)).hexdigest]}}
        if @root.children.include?('policy.json')
          raise G::Refused,'changed run implementation; review required' unless @root.read('policy.json')==policy
        else
          @root.write('policy.json',policy)
        end
      end
    end
    def close;@lock.close;@root.close;@task_index.close;@tasks.close;end
    def call(action,args)
      locked do
        if action=='list'
          page=@tasks.call(action,args)
          page.merge('tasks'=>page['tasks'].map{|t|
            row=project(t)
            if row['run']&&row['run']['result']
              row=row.merge('run'=>row['run'].merge('result'=>row['run']['result'].reject{|k,_|k=='content'}.merge('content_sha256'=>Digest::SHA256.hexdigest(row['run']['result']['content']))))
            end
            row
          })
        elsif action=='preview'
          preview(args.fetch(:task_id))
        elsif action=='run'
          run(**args)
        else
          id=args.fetch(:request_id)
          raise G::Refused,'run request identity reused' if @root.children.include?(index(id))
          if action=='cancel'
            t=task(args.fetch(:task_id));raise G::Refused,'run already attempted; use Stop for active work' if attempted?(t['task_id'])
          end
          @tasks.call(action,args)
        end
      end
    end
    private
    def locked
      @mutex.synchronize do
        raise G::Refused,'run store busy' unless @lock.flock(File::LOCK_EX|File::LOCK_NB)
        begin;@root.verify!;yield;ensure;@lock.flock(File::LOCK_UN);end
      end
    end
    def valid_task(id)
      raise ArgumentError,'task identity' unless id.is_a?(String)&&/\At-[a-f0-9]{24}\z/.match?(id)
      id
    end
    def task(id)
      valid_task(id);cursor=nil
      loop do
        page=@tasks.call('list',cursor:cursor);found=page['tasks'].find{|t|t['task_id']==id};return found if found
        cursor=page['next_cursor'];break unless cursor
      end
      raise G::Refused,'unknown task'
    end
    def index(id)
      raise ArgumentError,'request identity' unless id.is_a?(String)&&G::ID.match?(id)
      'request-'+G.digest(id)+'.json'
    end
    def attempted?(id)=@root.children.include?(valid_task(id)+'-intent.json')
    def adapter(t)=RosterChatAdapter.new(model:t['member'],isolated:RosterChatAdapter::ISOLATED_MODELS.include?(t['member'])).binding
    def preview(id)
      t=task(id)
      raise G::Refused,'only pending GPU-member tasks can run' unless t['state']=='pending'&&MEMBERS.include?(t['member'])&&!attempted?(id)
      {'task'=>t,'expected_digest'=>G.digest({'version'=>'cpu_task_run_v1','task'=>t,'adapter'=>adapter(t)}),
       'note'=>'Explicit Run invokes this member once through the existing coordinator. Results are reference material. No automatic retry or dispatch.'}
    end
    def project(t)
      return t unless attempted?(t['task_id'])
      intent=@root.read(t['task_id']+'-intent.json')
      raise G::Refused,'run task binding changed' unless intent['task']==t
      name=t['task_id']+'-result.json'
      return t.merge('state'=>'blocked_for_human_review','run_reason'=>'Retained intent without terminal receipt; never retry automatically.') unless @root.children.include?(name)
      receipt=@root.read(name)
      raise G::Refused,'run receipt binding changed' unless receipt['intent_sha256']==G.digest(intent)&&%w[complete failed canceled blocked_for_human_review].include?(receipt['state'])
      t.merge('state'=>receipt['state'],'run'=>receipt)
    end
    def run(task_id:,expected_digest:,request_id:,deadline:,cancel:)
      id=valid_task(task_id);name=index(request_id)
      raise G::Refused,'task command identity reused' if @task_index.children.include?(name)
      command={'task_id'=>id,'expected_digest'=>expected_digest,'request_id'=>request_id}
      if @root.children.include?(name)
        raise G::Refused,'changed run request' unless @root.read(name)==command
        raise G::Refused,'unfinished run index requires review' unless attempted?(id)
        t=project(task(id));raise G::Refused,'unfinished run requires review' if t['state']=='blocked_for_human_review'
        return {'task'=>t,'replayed'=>true}
      end
      p=preview(id);raise G::Refused,'stale or altered preview' unless expected_digest==p['expected_digest']
      raise G::Refused,'run canceled before intent' if cancel.call||Process.clock_gettime(Process::CLOCK_MONOTONIC)>=deadline
      # The request index is committed first. Either interrupted write order is
      # closed to replay; no unrecorded outbound request can follow an error.
      @root.write(name,command)
      intent=command.merge('task'=>p['task'],'adapter'=>adapter(p['task']))
      @root.write(id+'-intent.json',intent)
      begin
        result=@client.call(task:p['task'],deadline:deadline,cancel:cancel)
        receipt={'intent_sha256'=>G.digest(intent),'state'=>'complete','result'=>result}
      rescue StandardError=>e
        clean=@client.respond_to?(:cleanup_confirmed?)&&@client.cleanup_confirmed?
        receipt={'intent_sha256'=>G.digest(intent),'state'=>cancel.call&&clean ? 'canceled' : 'blocked_for_human_review','error_class'=>e.class.name,'requires_review'=>true,'cleanup_confirmed'=>clean}
      end
      @root.write(id+'-result.json',receipt)
      {'task'=>project(p['task']),'replayed'=>false}
    end
  end
end
