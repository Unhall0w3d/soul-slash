# frozen_string_literal: true
require_relative "roster_warm_session"
require_relative "roster_conversation_gateway"

module SoulCore
  # Only alive inside run's foreground block. HTTP workers never own the model.
  # One pending/active request maximum; contention is refused, not silently queued.
  class RosterWarmBackend
    def initialize(owner:, path:, tick_seconds: 0.5, max_requests: 6, journal_mode: :create, gateway_class: RosterConversationGateway, memory: nil)
      raise ArgumentError,"tick interval" unless tick_seconds.between?(0.01,1.0)
      raise ArgumentError,"request bound" unless max_requests.is_a?(Integer) && max_requests.between?(1,32)
      raise ArgumentError,"explicit journal mode required" unless %i[create resume].include?(journal_mode)
      @gateway_class, @memory = gateway_class, memory
      @journal_mode=journal_mode
      @remaining=max_requests
      @owner,@path,@tick_seconds=owner,path,tick_seconds
      @mutex=Mutex.new
      @changed=ConditionVariable.new
      @closing=@finished=@ready=false
    end

    def run(seconds:600)
      raise ArgumentError,"backend already used" if @thread
      @thread=Thread.new do
        gateway=nil
        begin
          @owner.session(seconds:seconds) do
            # Resume never creates a missing root or rewrites its binding. The
            # gateway still validates the manifest and each request's history.
            @gateway_class.create(path:@path,owner:@owner) if @journal_mode==:create
            options={path:@path,owner:@owner}
            options[:memory]=@memory if @memory
            gateway=@gateway_class.new(**options)
            @mutex.synchronize { @ready=true; @changed.broadcast }
            loop do
              job=@mutex.synchronize do
                @changed.wait(@mutex,@tick_seconds) unless @job || @closing
                @job
              end
              break if closing?
              if job
                begin
                  original_cancel=job[:args].fetch(:cancel,-> {false})
                  value=job[:control] ? job[:control].call : gateway.complete(**job[:args].merge(cancel:-> {closing? || original_cancel.call}))
                rescue Exception => error
                  failure=error
                  begin
                    @owner.release_idle! unless job[:control]
                  rescue Exception => release_error
                    failure=release_error
                  end
                ensure
                  @mutex.synchronize do
                    job[:value],job[:error],job[:done]=value,failure,true
                    @job=nil
                    @changed.broadcast
                  end
                end
                raise failure if failure && !failure.is_a?(StandardError)
                value=failure=nil
              else
                @owner.tick
              end
            end
          end
        rescue Exception => error
          @mutex.synchronize { @failure=error }
        ensure
          begin
            gateway&.close
          ensure
            @mutex.synchronize { @finished=true; @changed.broadcast }
          end
        end
      end
      @mutex.synchronize { @changed.wait(@mutex) until @ready || @finished }
      raise RosterRuntimeOwner::Unavailable,"warm backend startup failed" unless @ready
      yield self
    ensure
      if @thread
        @mutex.synchronize { @closing=true; @changed.broadcast }
        # Driver cancellation interrupts owned work; request and cleanup also have
        # independent bounds. Never kill this thread and skip verified release.
        raise RosterRuntimeOwner::Unavailable,"warm backend shutdown unverified" unless @thread.join(215)
        raise RosterRuntimeOwner::Unavailable,"warm backend ended with failure" if @failure
      end
    end

    def complete(**args)
      job={args:args}
      @mutex.synchronize do
        raise RosterRuntimeOwner::Unavailable,"warm backend unavailable" unless @ready && !@closing && !@finished
        raise RosterRuntimeOwner::Unavailable,"warm backend busy" if @job
        consume_request!
        @job=job
        @changed.broadcast
        @changed.wait(@mutex) until job[:done] || @finished
        raise RosterRuntimeOwner::Unavailable,"warm backend stopped" unless job[:done]
        raise job[:error] if job[:error]
        job[:value]
      end
    end

    def finished? = @mutex.synchronize { @finished }
    private
    def consume_request!
      raise RosterRuntimeOwner::Unavailable,"session request bound" if @remaining<=0
      @remaining-=1
    end
    def closing? = @mutex.synchronize { @closing }
  end
end
