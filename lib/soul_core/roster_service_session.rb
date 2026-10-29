# frozen_string_literal: true
require_relative "roster_warm_session"

module SoulCore
  # Explicit long-lived coordinator contract. Each residency is still bounded;
  # retained leases never expire into permission to ignore an uncertain process.
  class RosterServiceSession < RosterWarmSession
    RESIDENCY_SECONDS = 600
    REQUEST_SECONDS = 180

    def prepare_handoff(provider_id:,request_id:,conversation_id:,member:,input_digest:,origin_conversation_id: conversation_id)
      session_check!
      raise Unavailable,"request active" if @busy
      raise ArgumentError,"unsupported creative provider" unless %w[amd-visual amd-music].include?(provider_id)
      raise ArgumentError,"unknown originating member" unless member == "studio" || binding.key?(member)
      h={"handoff_id"=>SecureRandom.hex(16),"provider_id"=>provider_id,"request_id"=>request_id,
        "conversation_id"=>conversation_id,"origin_conversation_id"=>origin_conversation_id,"member"=>member,"input_digest"=>input_digest,"state"=>"prepared"}
      @leases.with_control_lock do
        store=@leases.compute_policy_unlocked; prior=store.read
        raise Unavailable,"compute reserved or handoff pending" unless prior["policy"]=="available" && prior["handoff"].nil?
        raise Unavailable,"foreign workload present" unless @leases.leases_for_quiescent_admission_unlocked.all? { |r| @lease && r["lease_id"]==@lease["lease_id"] }
        store.write(prior.merge("handoff"=>h,"revision"=>prior["revision"]+1))
      end
      release_idle!
      @leases.with_control_lock do
        raise Unavailable,"handoff release unverified" unless @leases.leases_for_quiescent_admission_unlocked.empty?
        store=@leases.compute_policy_unlocked; prior=store.read
        raise Unavailable,"handoff changed" unless prior["handoff"]==h
        raise Unavailable,"creative admission release unverified" unless @driver.respond_to?(:creative_release_verified?) && @driver.creative_release_verified?(provider_id: provider_id) == true
        store.write(prior.merge("handoff"=>h.merge("state"=>"released"),"revision"=>prior["revision"]+1))
      end
      compute_status
    end

    def finish_handoff(handoff_id:,outcome:,result_digest:)
      session_check!
      raise ArgumentError,"bounded handoff result required" unless %w[complete failed canceled].include?(outcome) && result_digest.is_a?(String) && result_digest.match?(/\A[a-f0-9]{64}\z/)
      @leases.with_control_lock do
        store=@leases.compute_policy_unlocked; prior=store.read; h=prior["handoff"]
        raise Unavailable,"exact released handoff required" unless h && h["handoff_id"]==handoff_id && %w[released running].include?(h["state"])
        raise Unavailable,"creative lease remains" unless @leases.leases_for_quiescent_admission_unlocked.empty?
        # Close admission before observing release; a stale writer cannot start
        # another creative process between the evidence check and policy update.
        store.write(prior.merge("handoff"=>h.merge("state"=>"prepared"),"revision"=>prior["revision"]+1))
        raise Unavailable,"creative release check unavailable" unless @driver.respond_to?(:creative_release_verified?) && @driver.creative_release_verified?(provider_id: h.fetch('provider_id')) == true
        store.record_handoff(h.merge("outcome"=>outcome,"result_digest"=>result_digest,"follow_up"=>"pending"))
        prior=store.read
        store.write(prior.merge("handoff"=>nil,"revision"=>prior["revision"]+1))
      end
      compute_status
    end

    # Explicit recovery never infers release from an absent lease or process.
    # Prepared also covers an interrupted finish; record failure, never success.
    def recover_prepared_handoff(handoff_id:, expected_digest:, confirmation:, result_digest:)
      session_check!
      raise Unavailable, "request or resident model active" if @busy || @lease
      raise ArgumentError, "exact recovery confirmation required" unless confirmation == "RECOVER_PREPARED_HANDOFF" &&
        handoff_id.is_a?(String) && handoff_id.match?(/\A[a-f0-9]{32}\z/) &&
        result_digest.is_a?(String) && result_digest.match?(/\A[a-f0-9]{64}\z/)
      @leases.with_control_lock do
        store = @leases.compute_policy_unlocked
        prior = store.read
        h = prior["handoff"]
        raise Unavailable, "exact prepared handoff required" unless h && h["state"] == "prepared" && h["handoff_id"] == handoff_id
        raise Unavailable, "recovery state changed" unless expected_digest == Digest::SHA256.hexdigest(JSON.generate(prior))
        raise Unavailable, "lease remains" unless @leases.leases_for_quiescent_admission_unlocked.empty?
        raise Unavailable, "recovery release unverified" unless @driver.respond_to?(:creative_release_verified?) && @driver.creative_release_verified?(provider_id: h.fetch('provider_id')) == true
        store.record_handoff(h.merge("outcome"=>"failed", "result_digest"=>result_digest,
          "recovery"=>"explicit_prepared_handoff", "follow_up"=>"pending"))
        store.write(prior.merge("handoff"=>nil, "revision"=>prior["revision"]+1))
      end
      compute_status
    end

    # Mutations remain on the owner's thread; the backend serializes controls
    # with requests. Policy is persisted before teardown, so failure stays closed.
    def compute_status
      @leases.with_control_lock { @leases.compute_policy_unlocked.read }.merge(status)
    end

    def creative_telemetry(handoff_id:)
      session_check!
      raise ArgumentError, "invalid handoff identity" unless handoff_id.is_a?(String) && handoff_id.match?(/\A[a-f0-9]{32}\z/)
      @leases.with_control_lock do
        h = @leases.compute_policy_unlocked.read["handoff"]
        raise Unavailable, "exact active creative handoff required" unless h && h["handoff_id"] == handoff_id && %w[amd-visual amd-music].include?(h["provider_id"]) && h["state"] == "running"
      end
      # Serialized on the owner thread: no queued poller or privilege grant to
      # the dashboard. The driver bounds the single helper collection.
      @driver.creative_telemetry
    end

    def compute_control(policy:,expected_digest:,confirmation:)
      session_check!
      raise Unavailable,"request active" if @busy
      raise ArgumentError,"invalid compute policy" unless %w[available reserved].include?(policy) && confirmation=="SET_COMPUTE_POLICY"
      @leases.with_control_lock do
        store=@leases.compute_policy_unlocked
        prior=store.read
        raise Unavailable,"compute policy changed; preview again" unless Digest::SHA256.hexdigest(JSON.generate([prior,policy]))==expected_digest
        raise Unavailable,"workload handoff needs completion" if prior["handoff"]
        others=@leases.leases_for_quiescent_admission_unlocked.reject { |r| @lease && r["lease_id"]==@lease["lease_id"] }
        raise Unavailable,"other workload active; finish it first" unless others.empty?
        store.write(prior.merge("policy"=>"reserved","revision"=>prior["revision"]+1))
      end
      release_idle!
      if policy=="available"
        @leases.with_control_lock do
          raise Unavailable,"release unverified" unless @leases.leases_for_quiescent_admission_unlocked.empty?
          store=@leases.compute_policy_unlocked
          prior=store.read
          store.write(prior.merge("policy"=>"available","revision"=>prior["revision"]+1))
        end
      end
      compute_status
    end

    def session(seconds: nil)
      raise ArgumentError, "service lifetime is explicit" unless seconds.nil?
      raise Unavailable, "session already used" if @session_thread
      @session_thread = Thread.current
      entered = true
      @session_deadline = Float::INFINITY
      yield self
    ensure
      if entered && !@closed
        begin
          unload!
        ensure
          @closed = true
        end
      end
    end

    def with_runtime(**args, &block)
      session_check!
      raise Unavailable, "request already active" if @busy
      # Do not begin a request that could outlast this residency's lease budget.
      if @lease && @residency_start && @clock.call + REQUEST_SECONDS >= @residency_start + RESIDENCY_SECONDS
        unload!
      end
      prior = @lease
      started = @clock.call
      super(**args, &block)
    ensure
      if started
        @residency_start = started if @lease && @lease != prior
        @residency_start = nil unless @lease
      end
    end

    def tick
      session_check!
      if @lease && @residency_start && @clock.call >= @residency_start + RESIDENCY_SECONDS
        release_idle!
      end
      super
    end

    def status
      {"state" => @blocked ? "blocked" : (@lease ? (@busy ? "working" : "resident") : "unloaded"),
       "model" => @adapter&.model, "idle_seconds" => @idle_seconds,
       "residency_limit_seconds" => RESIDENCY_SECONDS}
    end
  end
end
