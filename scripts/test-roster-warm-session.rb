# frozen_string_literal: true
require "minitest/autorun"
require "tmpdir"
require_relative "../lib/soul_core/roster_warm_session"

class RosterWarmSessionTest < Minitest::Test
  S=SoulCore::RosterWarmSession
  A=SoulCore::RosterChatAdapter
  L=SoulCore::ModelRuntimeLeaseStore
  class Driver
    attr_reader :events
    attr_accessor :cleanup,:drift,:admitted,:parked,:fail_start
    def initialize(clock)
      @clock=clock
      @events=[]
      @cleanup=@admitted=@parked=true
    end
    def binding = A::MODELS.to_h { |m| [m,{"artifact_sha256"=>"a"*64,"launch_sha256"=>"b"*64,"server_sha256"=>"c"*64}] }
    def start(adapter:,ownership_id:,**)
      @model,@id=adapter.model,ownership_id
      @events << [:start,@model]
      raise IOError if fail_start
    end
    def activate_request(**) = (@events << [:activate,@model]; true)
    def park(**) = (@events << [:park,@model]; @parked)
    def observe(**)
      {"ownership_id"=>@id,"model"=>@model,"identity"=>binding.fetch(@model),"admitted"=>@admitted,
        "pid"=>42,"process_start"=>drift ? "changed" : "original","captured_at"=>@clock.call}
    end
    def stop_and_verify(**) = (@events << [:stop,@model]; @cleanup)
  end

  def setup
    @root=Dir.mktmpdir
    @time=10.0
    @wall=Time.utc(2026,10,23)
    @leases=L.new(root:@root,clock:-> {@wall})
    @driver=Driver.new(-> {@time})
    @owner=S.new(leases:@leases,driver:@driver,clock:-> {@time})
  end
  def teardown = FileUtils.remove_entry(@root)
  def request(model=A::MODELS.first,cancel:-> {false},&block)
    @owner.with_runtime(adapter:A.new(model:model),request_id:"r",conversation_id:"c",deadline:@time+100,cancel:cancel) do |client,admission,identity|
      assert admission.call
      block ? block.call(client,admission,identity) : "answer"
    end
  end
  def retained = @leases.with_control_lock { @leases.leases_for_quiescent_admission_unlocked }

  def test_warm_reuse_and_control_lock_available_while_idle
    @owner.session do
      assert_equal "answer",request
      assert_equal 1,retained.length
      assert_equal :idle,@owner.tick
      request
      assert_equal 1,@driver.events.count { |e|e.first==:start }
      assert_equal 0,@driver.events.count { |e|e.first==:stop }
    end
    assert_empty retained
    assert_equal 1,@driver.events.count { |e|e.first==:stop }
  end

  def test_switch_releases_before_starting_other_model
    @owner.session { request; request(A::MODELS.last) }
    assert_equal [[:start,A::MODELS.first],[:stop,A::MODELS.first],[:start,A::MODELS.last],[:stop,A::MODELS.last]],@driver.events.select { |e|%i[start stop].include?(e.first) }
  end

  def test_expiry_and_session_exit_unload
    @owner.session do
      request
      @time+=240
      assert_equal :unloaded,@owner.tick
      assert_empty retained
      request
    end
    assert_equal 2,@driver.events.count { |e|e.first==:stop }
  end

  def test_request_after_idle_expiry_cold_loads
    @owner.session { request; @time+=240; request }
    assert_equal 2,@driver.events.count { |e|e.first==:start }
  end

  def test_failed_release_blocks_reload_without_cleanup_retry
    assert_raises(S::Unavailable) do
      @owner.session do
        request
        @driver.cleanup=false
        assert_raises(S::Unavailable) { request(A::MODELS.last) }
        assert_raises(S::Unavailable) { request }
      end
    end
    assert_equal 1,@driver.events.count { |e|e.first==:start }
    assert_equal 1,@driver.events.count { |e|e.first==:stop }
    assert_equal 1,retained.length
  end

  def test_cancellation_and_attestation_drift_release
    @owner.session do
      request
      assert_raises(S::Unavailable) { request(cancel:-> {true}) }
      assert_empty retained
      request
      @driver.drift=true
      assert_raises(S::Unavailable) { request }
      assert_empty retained
    end
  end

  def test_start_and_park_failure_cleanup
    [true,false].each do |start_failure|
      setup_owner=S.new(leases:@leases,driver:@driver,clock:-> {@time})
      @owner=setup_owner
      @driver.fail_start=start_failure
      @driver.parked=false
      assert_raises(start_failure ? IOError : S::Unavailable) { @owner.session { request } }
      assert_empty retained
    end
  end

  def test_no_request_outside_session_or_from_foreign_thread
    assert_raises(S::Unavailable) { request }
    @owner.session do
      thread=Thread.new { assert_raises(S::Unavailable) { request } }
      thread.join
      request
      assert_raises(S::Unavailable) { @owner.session {} }
      assert_equal :idle,@owner.tick
    end
    assert_raises(S::Unavailable) { request }
  end

  def test_stale_retained_lease_survives_status_and_blocks_legacy_admission
    lease=@leases.acquire_retained(provider_id:"fixture",model_id:"m",request_id:"r",conversation_id:"c",resource_group:"amd-vulkan-generation",ttl_seconds:1)
    @wall+=1000
    assert_equal "verified",@leases.active_leases.first["release_policy"]
    assert_equal [lease],retained
    assert_raises(L::ResourceBusy) { @leases.acquire(provider_id:"other",model_id:"m",request_id:"r") }
    assert_raises(L::ResourceBusy) { @leases.acquire_exclusive(provider_id:"other",model_id:"m",request_id:"r",resource_group:"different") }
    assert_raises(L::ResourceBusy) { @owner.session { request } }
    assert_empty @driver.events
  end

  def test_ordinary_expired_lease_behavior_unchanged
    @leases.acquire(provider_id:"ordinary",model_id:"m",request_id:"r",ttl_seconds:1)
    @wall+=2
    assert_empty @leases.active_leases
  end

  def test_idle_resource_failure_and_request_exception_unload
    @owner.session do
      request
      @driver.admitted=false
      assert_raises(S::Unavailable) { @owner.tick }
      assert_empty retained
      @driver.admitted=true
      assert_raises(IOError) { request { raise IOError,"synthetic generation failure" } }
      assert_empty retained
    end
  end

  def test_session_deadline_cleanup_and_no_reentry_while_busy
    @owner.session do
      request do
        assert_raises(S::Unavailable) { request }
        assert_raises(S::Unavailable) { @owner.tick }
      end
      @time+=601
      assert_raises(S::Unavailable) { request }
    end
    assert_empty retained
    assert_equal 1,@driver.events.count { |e|e.first==:stop }
  end
end
