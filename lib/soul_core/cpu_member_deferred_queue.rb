# frozen_string_literal: true
require_relative 'cpu_member_handoff_store'
require_relative 'cpu_member_roster_handoff'
module SoulCore
  # A confirmed job has one durable dispatch intent. Status polls never retry a
  # dispatched job. This queue shares the existing service's shutdown lifecycle.
  class CpuMemberDeferredQueue
    G=CpuMemberGateway
    def initialize(base:,path:,client:,status_reader:,clock:->{Time.now.to_f})
      @base,@client,@status_reader,@clock=base,client,status_reader,clock
      @root=G::Directory.new(path);@mutex=Mutex.new;@worker=nil;@active=nil;@run_mutex=Mutex.new;@fault=nil;@cancel={};@stopping=false;@next_poll=0
      @root.write('queue.lock',{}) unless @root.children.include?('queue.lock')
      @lock=@root.open_file('queue.lock',File::RDWR)
      locked do
        policy={'version'=>'cpu_confirmed_queue_a6_v1','implementation'=>Digest::SHA256.file(__FILE__).hexdigest,'attempts'=>1,'expires_seconds'=>86400}
        @root.children.include?('policy.json') ? (raise G::Refused,'queue binding changed' unless @root.read('policy.json')==policy) : @root.write('policy.json',policy)
      end
    end
    def availability
      d=@status_reader.call
      raise G::Refused,'invalid compute status' unless d.is_a?(Hash)&&%w[available reserved].include?(d['policy'])&&%w[unloaded resident working blocked].include?(d['state'])&&[true,false].include?(d['available'])
      d.slice('policy','state','model','available','handoff')
    rescue StandardError
      {'policy'=>'unknown','state'=>'unknown','available'=>false,'handoff'=>nil}
    end
    def ready?(s)=s['policy']=='available'&&s['available']==true&&%w[unloaded resident].include?(s['state'])&&s['handoff'].nil?
    def enqueue(proposal:)
      raise ArgumentError,'proposal fields' unless proposal.is_a?(Hash)&&proposal.keys.sort==%w[detail member proposal_id title]&&/\A[a-f0-9]{64}\z/.match?(proposal['proposal_id'].to_s)&&CpuMemberHandoffStore::MEMBERS.include?(proposal['member'])&&proposal['title'].is_a?(String)&&proposal['title'].bytesize.between?(1,160)&&proposal['detail'].is_a?(String)&&proposal['detail'].bytesize.between?(1,2048)
      request='queue-'+proposal['proposal_id'];id='t-'+G.digest(request)[0,24]
      locked do
        if exists?(id,'manifest')
          m=read(id,'manifest');raise G::Refused,'changed queue confirmation' unless m['proposal']==proposal
          return project(id)
        end
        raise G::Refused,'queue capacity' if ids.length>=128
        now=@clock.call
        m={'proposal'=>proposal,'task_id'=>id,'request_id'=>request,'confirmed_at'=>now,'expires_at'=>now+86400}
        write(id,'manifest',m)
        # Manifest reserves this task against manual dispatch even if interrupted.
        result=@base.call('add',{request_id:request,title:proposal['title'],detail:proposal['detail'],member:proposal['member']})
        raise G::Refused,'queue task identity' unless result.dig('task','task_id')==id
        write(id,'queued',{'task'=>result['task']});project(id)
      end
    end
    def cancel_task(id)
      locked do
        raise G::Refused,'unknown queued task' unless ids.include?(id)
        row=project(id)
        return row if %w[complete failed canceled expired blocked_for_human_review].include?(row['state'])
        if @active==id
          @cancel[id]=true;return row.merge('state'=>'cancel_requested')
        end
        write(id,'terminal',{'state'=>'canceled','model_invoked'=>false});project(id)
      end
    end
    def status(id=nil)
      locked do
        return project(id) if id && ids.include?(id)
        raise G::Refused,'unknown queued task' if id
        names=ids;{'tasks'=>names.last(16).map{|i|project(i).reject{|k,_|k=='result'}},'total'=>names.length,'display_truncated'=>names.length>16,'blocked_for_human_review'=>!!held?}
      end
    end
    def call(action,args)
      if %w[preview run cancel].include?(action) && locked{ids.include?(args[:task_id])}
        return {'task'=>cancel_task(args[:task_id])} if action=='cancel'
        raise G::Refused,'confirmed queue owns this task; inspect queue status or cancel it'
      end
      if action=='run'
        raise G::Refused,'GPU task already active' unless @run_mutex.try_lock
        begin
          raise G::Refused,'queue cleanup requires review' if locked{held?}
          return @base.call(action,args)
        ensure
          @run_mutex.unlock
        end
      end
      result=@base.call(action,args)
      if action=='list'
        result=result.merge('tasks'=>result['tasks'].map{|t|locked{ids.include?(t['task_id']) ? t.merge('state'=>project(t['task_id'])['state'],'queue'=>project(t['task_id']).reject{|k,_|k=='result'}) : t}})
      end
      result
    end
    def tick
      return if @stopping||@fault||(@worker&&@worker.alive?)||@clock.call<@next_poll
      @next_poll=@clock.call+10
      @worker=Thread.new do
        begin
          next unless locked{!held?&&ids.any?{|id|project(id)['state']=='queued'}}
          s=availability;next unless ready?(s)
          selected=locked do
            ids.find do |id|
              next false unless project(id)['state']=='queued'
              if read(id,'manifest')['expires_at']<=@clock.call
                write(id,'terminal',{'state'=>'expired','model_invoked'=>false});next false
              end
              true
            end
          end
          dispatch(selected) if selected
        rescue StandardError=>e
          @fault=e.class.name # Stop this service lifetime; never retry an uncertain write.
        end
      end
    end
    def dispatch(id)
      owned=@run_mutex.try_lock
      return unless owned
      task=locked do
        return if @stopping||@fault||project(id)['state']!='queued'
        return unless read(id,'manifest')['expires_at']>@clock.call
        write(id,'started',{'started_at'=>@clock.call,'attempt'=>1});@active=id
        read(id,'queued')['task']
      end
      result=nil;failure=nil
      begin
        result=@client.call(task:task,deadline:Process.clock_gettime(Process::CLOCK_MONOTONIC)+110,cancel:->{@stopping||@cancel[id]==true})
        raise G::Refused,'queue member attribution' unless result.is_a?(Hash)&&result['member']==task['member']&&result['content'].is_a?(String)&&result['content'].bytesize.between?(1,32768)
      rescue StandardError=>e
        failure={'state'=>(@stopping||@cancel[id])&&@client.cleanup_confirmed? ? 'canceled' : 'blocked_for_human_review','error_class'=>e.class.name,'cleanup_confirmed'=>@client.cleanup_confirmed?,'requires_review'=>true}
      end
      locked do
        write(id,'terminal',failure||{'state'=>'complete','result'=>result,'model_invoked'=>true})
        @active=nil
      end
    ensure
      @active=nil if @active==id
      @run_mutex.unlock if owned
    end
    def close
      @stopping=true
      raise G::Refused,'queue shutdown cleanup unconfirmed' if @worker&&!@worker.join(12)
      @lock.close;@root.close;@base.close
    end
    private
    def held?
      @fault || ids.any? do |id|
        next true unless exists?(id,'queued')
        next false unless exists?(id,'started')
        !exists?(id,'terminal') || (read(id,'terminal')['state']=='blocked_for_human_review' && read(id,'terminal')['cleanup_confirmed']!=true)
      end
    end
    def locked
      @mutex.synchronize do
        raise G::Refused,'queue busy' unless @lock.flock(File::LOCK_EX|File::LOCK_NB)
        begin;@root.verify!;yield;ensure;@lock.flock(File::LOCK_UN);end
      end
    end
    def ids = @root.children.grep(/\At-[a-f0-9]{24}-manifest.json\z/).map{|n|n.delete_suffix('-manifest.json')}.sort_by{|id|[read(id,'manifest')['confirmed_at'],id]}
    def name(id,part)
      raise ArgumentError,'task identity' unless /\At-[a-f0-9]{24}\z/.match?(id.to_s)
      "#{id}-#{part}.json"
    end
    def exists?(id,part)=@root.children.include?(name(id,part))
    def read(id,part)
      d=@root.read(name(id,part))
      raise G::Refused,'queue record binding' unless d.is_a?(Hash) && (part=='manifest' || d['manifest_sha256']==G.digest(read(id,'manifest')))
      if part=='manifest'
        p=d['proposal'];request=p.is_a?(Hash) ? 'queue-'+p['proposal_id'].to_s : ''
        raise G::Refused,'queue manifest identity' unless d.keys.sort==%w[confirmed_at expires_at proposal request_id task_id] && d['task_id']==id && d['request_id']==request && id=='t-'+G.digest(request)[0,24] && d['confirmed_at'].is_a?(Numeric) && d['expires_at']==d['confirmed_at']+86400
      elsif part=='queued'
        m=read(id,'manifest');t=d['task'];p=m['proposal']
        raise G::Refused,'queue task changed' unless t.is_a?(Hash)&&t['task_id']==id&&%w[member title detail].all?{|k|t[k]==p[k]}
      end
      d
    end
    def write(id,part,data)
      value=part=='manifest' ? data : data.merge('manifest_sha256'=>G.digest(read(id,'manifest')))
      @root.write(name(id,part),value)
    end
    def project(id)
      m=read(id,'manifest');terminal=exists?(id,'terminal') ? read(id,'terminal') : nil
      state=terminal ? terminal['state'] : exists?(id,'started') ? (@active==id ? 'running' : 'blocked_for_human_review') : exists?(id,'queued') ? 'queued' : 'blocked_for_human_review'
      state='expired' if state=='queued'&&m['expires_at']<=@clock.call
      raise G::Refused,'invalid queue state' unless %w[queued running complete failed canceled expired blocked_for_human_review].include?(state)
      {'task_id'=>id,'member'=>m['proposal']['member'],'title'=>m['proposal']['title'],'detail'=>m['proposal']['detail'],'state'=>state,'expires_at'=>m['expires_at'],'result'=>terminal&&terminal['result'],'requires_review'=>state=='blocked_for_human_review'}
    end
  end
end
