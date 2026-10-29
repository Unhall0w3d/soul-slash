# frozen_string_literal: true
require_relative "test-roster-conversation-gateway"
require_relative "../lib/soul_core/roster_warm_backend"
require_relative "roster-warm-librechat-trial"

class RosterWarmBackendTest < Minitest::Test
  A=SoulCore::RosterChatAdapter
  class Driver < RosterConversationGatewayTest::Driver
    attr_accessor :on_park
    attr_reader :cancel
    def activate_request(cancel:,**)
      @cancel=cancel
      true
    end
    def park(**)
      on_park&.call
      true
    end
    def observe(**args) = super.merge("captured_at"=>Process.clock_gettime(Process::CLOCK_MONOTONIC))
  end
  def setup
    @tmp=Dir.mktmpdir
    @driver=Driver.new
    @leases=SoulCore::ModelRuntimeLeaseStore.new(root:@tmp)
    @owner=SoulCore::RosterWarmSession.new(leases:@leases,driver:@driver)
    @backend=SoulCore::RosterWarmBackend.new(owner:@owner,path:File.join(@tmp,"journal"),tick_seconds:0.01)
  end
  def teardown = FileUtils.remove_entry(@tmp)
  def args(id,model=A::MODELS.first)
    {conversation_id:id,request_id:id,adapter:A.new(model:model),messages:[{"role"=>"user","content"=>"Hi"}],
      deadline:Process.clock_gettime(Process::CLOCK_MONOTONIC)+30,cancel:-> {false}}
  end
  def test_reuse_switch_and_exit_through_real_journal
    @backend.run(seconds:30) do
      assert_equal "Hello",@backend.complete(**args("one"))["content"]
      @backend.complete(**args("two"))
      assert_equal 1,@driver.starts.length
      @backend.complete(**args("three",A::MODELS.last))
      assert_equal A::MODELS,@driver.starts
      assert_equal 1,@driver.stops.length
    end
    assert_equal 2,@driver.stops.length
    assert_empty @leases.active_leases
    assert @backend.finished?
  end
  def test_busy_refusal_does_not_start_second_model
    entered,release=Queue.new,Queue.new
    @driver.cancel_hook=->(path) { if path=="/apply-template"; entered << true; release.pop; end }
    @backend.run(seconds:30) do
      request=Thread.new { @backend.complete(**args("one")) }
      entered.pop
      assert_raises(SoulCore::RosterRuntimeOwner::Unavailable){@backend.complete(**args("two",A::MODELS.last))}
      release << true
      request.value
      assert_equal 1,@driver.starts.length
    end
    assert_empty @leases.active_leases
  end
  def test_canceled_request_and_replay
    @backend.run(seconds:30) do
      input=args("one")
      @backend.complete(**input)
      assert @backend.complete(**input)["replayed"]
      assert_equal 1,@driver.starts.length
      assert_raises(SoulCore::RosterConversationGateway::Refused){@backend.complete(**args("two").merge(cancel:-> {true}))}
    end
    assert_empty @leases.active_leases
  end
  def test_trial_placement_and_binding_are_distinct
    %w[gpt-oss-20b gemma-4-26b-a4b].each do |model|
      args=RosterWarmLibreChatTrial.argv(model,"/fixture")
      assert_equal(model=="gpt-oss-20b" ? "2,1" : "1,1",args[args.index("--tensor-split")+1])
    end
    refute_equal RosterLibreChatTrial.new.roster_binding,RosterWarmLibreChatTrial.new.roster_binding
    assert_equal 240,RosterWarmLibreChatTrial::IDLE_SECONDS
  end
  def test_foreground_loop_ticks_idle_expiry
    observed=Queue.new
    @owner.define_singleton_method(:tick) do
      value=super()
      observed << value
      value
    end
    @backend.run(seconds:30) do
      @backend.complete(**args("one"))
      @owner.instance_variable_set(:@idle_until,Process.clock_gettime(Process::CLOCK_MONOTONIC)-1)
      assert_equal :unloaded,Timeout.timeout(2){ loop { value=observed.pop; break value if value==:unloaded } }
      assert_empty @leases.active_leases
    end
  end
  def test_shutdown_cancels_active_work_and_joins_release
    entered=Queue.new
    @driver.cancel_hook=->(path) {
      if path=="/apply-template"
        entered << true
        sleep 0.01 until @driver.cancel.call
        raise SoulCore::RosterChatExchange::Stopped,"canceled"
      end
    }
    request=nil
    @backend.run(seconds:30) do
      request=Thread.new { assert_raises(SoulCore::RosterChatExchange::Stopped){@backend.complete(**args("one"))} }
      entered.pop
    end
    request.value
    assert_empty @leases.active_leases
    assert_equal 1,@driver.stops.length
  end
  def test_uncertain_release_retains_lease_without_retry
    @driver.cleanup=false
    assert_raises(SoulCore::RosterRuntimeOwner::Unavailable) do
      @backend.run(seconds:30) { @backend.complete(**args("one")) }
    end
    assert_equal 1,@driver.stops.length
    assert_equal 1,@leases.active_leases.length
  end
  def test_request_quota_refuses_before_new_work
    @backend=SoulCore::RosterWarmBackend.new(owner:@owner,path:File.join(@tmp,"journal"),max_requests:1)
    @backend.run(seconds:30) do
      @backend.complete(**args("one"))
      assert_raises(SoulCore::RosterRuntimeOwner::Unavailable){@backend.complete(**args("two"))}
      assert_equal 1,@driver.starts.length
    end
    assert_empty @leases.active_leases
  end

  def resumed_backend
    @driver=Driver.new
    @owner=SoulCore::RosterWarmSession.new(leases:@leases,driver:@driver)
    SoulCore::RosterWarmBackend.new(owner:@owner,path:File.join(@tmp,"journal"),journal_mode: :resume)
  end

  def test_explicit_resume_replays_without_generation_and_accepts_exact_followup
    @backend.run(seconds:30) { @backend.complete(**args("one")) }
    original=File.binread(File.join(@tmp,"journal","roster.json"))
    resumed_backend.run(seconds:30) do |backend|
      assert backend.complete(**args("one"))["replayed"]
      assert_empty @driver.starts
      followup=args("two").merge(conversation_id:"one",messages:[
        {"role"=>"user","content"=>"Hi"},
        {"role"=>"assistant","content"=>"Hello"},
        {"role"=>"user","content"=>"Continue"}])
      assert_equal "Hello",backend.complete(**followup)["content"]
      assert_equal 1,@driver.starts.length
    end
    assert_equal original,File.binread(File.join(@tmp,"journal","roster.json"))
    assert_empty @leases.active_leases
  end

  def test_resume_missing_root_refuses_without_creating_it
    assert_raises(SoulCore::RosterRuntimeOwner::Unavailable) { resumed_backend.run(seconds:30) { flunk "must not start" } }
    refute File.exist?(File.join(@tmp,"journal"))
    assert_empty @driver.starts
  end

  def test_default_create_still_refuses_existing_root
    @backend.run(seconds:30) { }
    backend=resumed_backend
    backend.instance_variable_set(:@journal_mode,:create)
    assert_raises(SoulCore::RosterRuntimeOwner::Unavailable) { backend.run(seconds:30) { flunk "must not rebind" } }
    assert_empty @driver.starts
  end

  def test_resume_rejects_changed_manifest_without_generation
    @backend.run(seconds:30) { }
    path=File.join(@tmp,"journal","roster.json")
    manifest=JSON.parse(File.read(path))
    manifest["version"]="foreign"
    File.write(path,JSON.generate(manifest))
    assert_raises(SoulCore::RosterRuntimeOwner::Unavailable) { resumed_backend.run(seconds:30) { flunk "must not rebind" } }
    assert_empty @driver.starts
    assert_equal "foreign",JSON.parse(File.read(path))["version"]
  end
end
