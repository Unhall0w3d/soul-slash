# frozen_string_literal: true
require "timeout"
require_relative "roster_runtime_owner"

module SoulCore
  # Candidate foreground session owner; deliberately not connected to any HTTP
  # server. Single-thread-affine dispatch, explicit tick, bounded session block.
  # A future driver must monitor idle resources and support activate/park without
  # leaving request cancellation watchers attached to completed requests.
  class RosterWarmSession < RosterRuntimeOwner
    def initialize(leases:, driver:, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, idle_seconds: 240, isolated_models: [])
      super(leases:leases,driver:driver,clock:clock,isolated_models:isolated_models)
      raise ArgumentError,"idle range" unless idle_seconds.is_a?(Integer) && idle_seconds.between?(180,300)
      raise ArgumentError,"warm driver contract required" unless %i[activate_request park].all? { |method| driver.respond_to?(method) }
      @idle_seconds=idle_seconds
      @blocked=false
    end

    def session(seconds:600)
      raise Unavailable,"session already used" if @session_thread
      raise ArgumentError,"bounded session required" unless seconds.is_a?(Integer) && seconds.between?(30,600)
      @session_thread=Thread.current
      entered=true
      @session_deadline=@clock.call+seconds
      Timeout.timeout(seconds,Unavailable,"session deadline") { yield self }
    ensure
      if entered && !@closed
        begin
          unload!
        ensure
          @closed=true
        end
      end
    end

    def with_runtime(adapter:, request_id:, conversation_id:, deadline:, cancel:)
      session_check!
      raise ArgumentError,"explicit roster adapter required" unless adapter.instance_of?(RosterChatAdapter)
      raise Unavailable,"model absent from owned roster" unless binding.key?(adapter.model)
      raise Unavailable,"request already active" if @busy
      @busy=true
      begin
        check!(deadline,cancel)
        raise Unavailable,"runtime binding drift" unless @driver.binding==binding
        if @lease && (@adapter.binding!=adapter.binding || @clock.call>=@idle_until)
          unload!
        end
        unless @lease
          @lease=@leases.acquire_retained(provider_id:"local.roster.warm",model_id:adapter.model,
            request_id:request_id,conversation_id:conversation_id,resource_group:"amd-vulkan-generation",
            ttl_seconds:660)
          @adapter=adapter
          @identity=nil
          @started=false
        end
        @leases.with_control_lock do
          verify_lease!
          unless @started
            @started=true # start may raise after partially spawning
            bounded(deadline) { @driver.start(adapter:adapter,ownership_id:@lease.fetch("lease_id"),deadline:deadline,cancel:cancel) }
          end
          raise Unavailable,"request monitor activation failed" unless bounded(deadline) { @driver.activate_request(deadline:deadline,cancel:cancel) }==true
          admission=-> { observe!(deadline,cancel); true }
          admission.call
          value=bounded(deadline) { yield(@driver,admission,JSON.parse(JSON.generate(@identity))) }
          admission.call
          raise Unavailable,"idle monitoring unverified" unless bounded(deadline) { @driver.park(deadline:deadline) }==true
          @idle_until=[@clock.call+@idle_seconds,@session_deadline].min
          value
        end
      rescue Exception
        unload!
        raise
      ensure
        @busy=false
      end
    end

    # Caller supplies the bounded foreground event loop. No hidden timer/thread.
    def tick
      session_check!
      raise Unavailable,"request active" if @busy
      return :unloaded unless @lease
      if @clock.call>=@idle_until
        unload!
        return :unloaded
      end
      @leases.with_control_lock do
        verify_lease!
        observe!([@clock.call+2,@session_deadline].min,-> {false})
      end
      :idle
    rescue Exception
      unload! if @session_thread==Thread.current && !@busy
      raise
    end

    # Gateway rejection after a parked response (including a late disconnect)
    # must not leave residency behind a failed conversation operation.
    def release_idle!
      session_check!
      raise Unavailable,"request active" if @busy
      unload!
    end

    private

    def session_check!
      raise Unavailable,"inactive, foreign-thread or blocked session" unless @session_thread==Thread.current && !@closed && !@blocked
      raise Unavailable,"session expired" if @clock.call>=@session_deadline
    end

    def bounded(deadline)
      remaining=[deadline,@session_deadline].min-@clock.call
      raise Unavailable,"deadline exhausted" unless remaining.positive?
      Timeout.timeout(remaining,Unavailable,"operation deadline") { yield }
    end

    def verify_lease!
      raise Unavailable,"lease ownership changed" unless @leases.leases_for_quiescent_admission_unlocked==[@lease]
    end

    def observe!(deadline,cancel)
      session_check!
      check!(deadline,cancel)
      raise Unavailable,"runtime binding drift" unless @driver.binding==binding
      evidence=bounded(deadline) { @driver.observe(ownership_id:@lease.fetch("lease_id"),deadline:deadline) }
      age=evidence.is_a?(Hash) && evidence["captured_at"].is_a?(Numeric) ? @clock.call-evidence["captured_at"] : -1
      unless evidence.is_a?(Hash) && evidence["ownership_id"]==@lease["lease_id"] && evidence["model"]==@adapter.model &&
        evidence["identity"]==binding.fetch(@adapter.model) && evidence["admitted"]==true &&
        evidence["pid"].is_a?(Integer) && evidence["pid"].positive? &&
        evidence["process_start"].is_a?(String) && !evidence["process_start"].empty? && age.between?(0,2)
        raise Unavailable,"runtime attestation failed"
      end
      identity=evidence.slice("pid","process_start","ownership_id","model","identity")
      raise Unavailable,"runtime process changed" if @identity && @identity!=identity
      @identity=identity
    end

    def unload!
      return unless @lease
      # Never retry an uncertain cleanup implicitly, including the session ensure.
      raise Unavailable,"release unverified; review retained lease" if @blocked
      @leases.with_control_lock do
        verify_lease!
        if @started
          clean=Timeout.timeout(30,Unavailable,"cleanup deadline") do
            @driver.stop_and_verify(ownership_id:@lease.fetch("lease_id"),deadline:@clock.call+30)
          end
          raise Unavailable,"cleanup unverified" unless clean==true
        end
        @leases.release(@lease.fetch("lease_id"))
        @lease=@adapter=@identity=nil
        @started=false
      end
    rescue Exception
      @blocked=true
      raise
    end
  end
end
