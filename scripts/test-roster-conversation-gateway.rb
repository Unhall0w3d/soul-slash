# frozen_string_literal: true
require "minitest/autorun"
require "tmpdir"
require_relative "../lib/soul_core/roster_conversation_gateway"

class RosterConversationGatewayTest < Minitest::Test
  G = SoulCore::RosterConversationGateway
  A = SoulCore::RosterChatAdapter
  O = SoulCore::RosterRuntimeOwner
  class Driver
    attr_accessor :fail_at, :cancel_hook, :cleanup, :drift
    attr_reader :calls, :starts, :stops
    def initialize
      @calls, @starts, @stops, @cleanup = [], [], [], true
    end
    def binding
      A::MODELS.to_h { |m| [m, {"artifact_sha256"=>"a"*64,"server_sha256"=>"b"*64,"launch_sha256"=>"c"*64}] }
    end
    def start(adapter:, ownership_id:, deadline:, cancel:)
      @model, @id = adapter.model, ownership_id
      @starts << @model
      raise IOError if fail_at == :start
    end
    def observe(ownership_id:, deadline:)
      {"ownership_id"=>ownership_id,"model"=>@model,"identity"=>binding.fetch(@model),
       "admitted"=>true,"pid"=>123,"process_start"=>drift ? "changed" : "start",
       "captured_at"=>10.0}
    end
    def stop_and_verify(ownership_id:, deadline:)
      @stops << ownership_id
      cleanup
    end
    def request(method, path, payload, deadline:)
      @calls << [path, payload]
      @cancel_hook&.call(path)
      raise IOError, "fixture secret must not enter journal" if path == fail_at
      case path
      when "/apply-template" then {"prompt"=>"fixture native template"}
      when "/tokenize" then {"tokens"=>[1,2]}
      else
        count = @model == A::MODELS.first ? 2 : 3
        {"model"=>@model,"choices"=>[{"index"=>0,"finish_reason"=>"stop","message"=>{"role"=>"assistant","content"=>"Hello", "reasoning_content"=>"private trace"}}],
         "usage"=>{"prompt_tokens"=>count,"completion_tokens"=>1,"total_tokens"=>count+1}}
      end
    end
  end
  def setup
    @tmp = Dir.mktmpdir("roster-journal-test-")
    @driver = Driver.new
    @leases = SoulCore::ModelRuntimeLeaseStore.new(root: @tmp)
    @owner = O.new(leases: @leases, driver: @driver, clock: -> {10.0})
    @path = File.join(@tmp,"new-roster")
    G.create(path: @path, owner: @owner)
    @gateway = G.new(path: @path, owner: @owner, clock: -> {10.0})
    @adapter = A.new(model: A::MODELS.first)
    @messages = [{"role"=>"user","content"=>"Hi"}]
  end
  def teardown
    @gateway&.close
    FileUtils.remove_entry(@tmp)
  end
  def call(**opts)
    @gateway.complete(**{conversation_id:"chat1",request_id:"request1",adapter:@adapter,
      messages:@messages,deadline:100.0}.merge(opts))
  end
  def records = Dir.glob(File.join(@path,"r-*.json")).sort.map { |p| JSON.parse(File.read(p)) }
  def test_commit_replay_restart_and_model_attribution
    result = call
    assert_equal "Hello", result["content"]
    assert_equal @adapter.model, result["runtime"]["model"]
    assert_equal %w[requested owned generation_intent final_received complete], records.map { |r| r["state"] }
    assert_empty @leases.active_leases
    @gateway.close
    @gateway = G.new(path:@path,owner:@owner,clock:->{10.0})
    replay = call
    assert_equal true, replay["replayed"]
    assert_equal result.reject { |k| k=="replayed" }, replay.reject { |k| k=="replayed" }
    assert_equal 1, @driver.starts.size
    refute JSON.generate(records).include?("private trace")
  end
  def test_continuation_and_switch_between_distinct_conversations
    call
    history = @messages + [{"role"=>"assistant","content"=>"Hello"},{"role"=>"user","content"=>"Next"}]
    call(request_id:"request2",messages:history)
    gemma = A.new(model:A::MODELS.last)
    assert_raises(G::Refused) { call(request_id:"request3",messages:history,adapter:gemma) }
    call(conversation_id:"chat2",request_id:"request3",adapter:gemma)
    assert_equal [A::MODELS.first,A::MODELS.first,A::MODELS.last], @driver.starts
    assert_equal 3,@driver.stops.size
    assert_empty @leases.active_leases
  end
  def test_reused_ids_rewritten_history_and_regeneration_refuse_before_loading
    call
    assert_raises(G::Refused) { call(messages:[{"role"=>"user","content"=>"Different"}]) }
    assert_raises(G::Refused) { call(request_id:"new-request") }
    assert_raises(G::Refused) { call(conversation_id:"another") }
    history=@messages + [{"role"=>"assistant","content"=>"Invented"},{"role"=>"user","content"=>"Next"}]
    assert_raises(G::Refused) { call(request_id:"r2",messages:history) }
    assert_equal 1,@driver.starts.size
  end
  def test_uncertain_transport_never_regenerates_or_leaks_error
    @driver.fail_at="/v1/chat/completions"
    assert_raises(IOError) { call }
    assert_equal "failed",records.last["state"]
    @driver.fail_at=nil
    assert_raises(G::Refused) { call }
    assert_equal 1,@driver.starts.size
    refute JSON.generate(records).include?("fixture secret")
    assert_empty @leases.active_leases
  end
  def test_cancellation_before_generation_and_after_response
    canceled=false
    @driver.cancel_hook=->(path) { canceled=true if path=="/tokenize" }
    assert_raises(SoulCore::RosterChatExchange::Stopped) { call(cancel:->{canceled}) }
    refute @driver.calls.any? { |path,_| path=="/v1/chat/completions" }
    assert_equal "canceled",records.last["state"]
    assert_equal 1,@driver.stops.size
    assert_raises(G::Refused) { call }
  end
  def test_cleanup_failure_retains_lease_blocks_new_load_and_does_not_commit
    @driver.cleanup=false
    assert_raises(O::Unavailable) { call }
    assert_equal "failed", records.last["state"]
    assert_equal 1,@leases.with_control_lock { @leases.leases_for_quiescent_admission_unlocked }.size
    assert_raises(SoulCore::ModelRuntimeLeaseStore::ResourceBusy) { call(conversation_id:"c2",request_id:"r2") }
    assert_equal 1,@driver.starts.size
  end
  def test_partial_start_is_cleaned_and_consumed
    @driver.fail_at=:start
    assert_raises(IOError) { call }
    assert_equal 1,@driver.stops.size
    assert_empty @leases.active_leases
    assert_raises(G::Refused) { call }
  end
  def test_process_drift_refuses_and_cleans
    @driver.cancel_hook=->(_) { @driver.drift=true }
    assert_raises(O::Unavailable) { call }
    assert_equal 1,@driver.stops.size
    assert_equal "failed",records.last["state"]
  end
  def test_corruption_symlink_and_foreign_root_refused
    call
    File.write(File.join(@path,"r-000002.json"),"broken")
    assert_raises(JSON::ParserError) { call }
    assert_equal 1,@driver.starts.size
    assert_raises(G::Refused) { G.create(path:@path,owner:@owner) }
    foreign=File.join(@tmp,"old-qwen")
    Dir.mkdir(foreign,0700)
    File.write(File.join(foreign,"adapter.json"),"historical")
    assert_raises(StandardError) { G.new(path:foreign,owner:@owner) }
    assert_equal "historical",File.read(File.join(foreign,"adapter.json"))
    link=File.join(@tmp,"link")
    File.symlink(@path,link)
    assert_raises(StandardError) { G.new(path:link,owner:@owner) }
  end
  def test_interrupted_intent_is_not_replayed_after_restart
    # Simulate a crash at the journal callback, not a recoverable model failure.
    original=@gateway.method(:append!)
    @gateway.define_singleton_method(:append!) do |state,id,data|
      original.call(state,id,data)
      raise Interrupt if state=="generation_intent"
    end
    assert_raises(Interrupt) { call }
    assert_equal "generation_intent",records.last["state"]
    @gateway.close
    @gateway=G.new(path:@path,owner:@owner,clock:->{10.0})
    assert_raises(G::Refused) { call }
    assert_equal 1,@driver.starts.size
    assert_empty @leases.active_leases
  end
  def test_stale_lease_is_retained_not_pruned_by_roster_admission
    lease=@leases.acquire(provider_id:"fixture",model_id:"fixture",request_id:"stale",ttl_seconds:-1)
    assert_raises(SoulCore::ModelRuntimeLeaseStore::ResourceBusy) { call }
    assert_empty @driver.starts
    assert_equal lease["lease_id"], @leases.with_control_lock { @leases.leases_for_quiescent_admission_unlocked }.first["lease_id"]
  end

  def test_no_commit_when_canceled_after_generation
    canceled=false
    @driver.cancel_hook=->(path) { canceled=true if path=="/v1/chat/completions" }
    assert_raises(SoulCore::RosterChatExchange::Stopped) { call(cancel:->{canceled}) }
    assert_equal %w[requested owned generation_intent canceled],records.map { |r| r["state"] }
    assert_empty @leases.active_leases
  end

  def test_terminal_write_failure_is_not_a_delivered_answer
    original=@gateway.method(:append!)
    @gateway.define_singleton_method(:append!) do |state,id,data|
      raise IOError if state=="complete"
      original.call(state,id,data)
    end
    assert_raises(IOError) { call }
    assert_equal "failed",records.last["state"]
    assert_empty @leases.active_leases
    assert_raises(G::Refused) { call }
  end

  def test_foreign_controller_and_concurrent_gateway_refuse
    @leases.with_control_lock do
      assert_raises(SoulCore::ModelRuntimeLeaseStore::LockUnavailable) { call }
    end
    assert_empty @driver.starts
    another=G.new(path:@path,owner:@owner,clock:->{10.0})
    @driver.cancel_hook=->(_) {
      assert_raises(G::Refused) { another.complete(conversation_id:"x",request_id:"x",adapter:@adapter,messages:@messages,deadline:100) }
    }
    call(conversation_id:"second",request_id:"second")
  ensure
    another&.close
  end

  def test_bounded_recent_projection_preserves_full_transport_history
    history=[]
    5.times do |i|
      history << {"role"=>"user","content"=>"question #{i}"}
      result=call(request_id:"r#{i}",messages:history)
      history << {"role"=>"assistant","content"=>result["content"]}
    end
    prompts=@driver.calls.select { |path,_| path=="/v1/chat/completions" }.map { |_,payload| payload["messages"] }
    assert_equal [1,3,5,7,7],prompts.map(&:length)
    assert_equal "question 1",prompts.last.first["content"]
    assert_equal 9,records.select { |r| r["state"]=="requested" }.last["data"]["messages"].size
  end

  def test_crash_after_final_receipt_is_not_a_committed_reply
    original=@gateway.method(:append!)
    @gateway.define_singleton_method(:append!) do |state,id,data|
      original.call(state,id,data)
      raise Interrupt if state=="final_received"
    end
    assert_raises(Interrupt) { call }
    assert_equal "final_received",records.last["state"]
    @gateway.close
    @gateway=G.new(path:@path,owner:@owner,clock:->{10.0})
    assert_raises(G::Refused) { call }
    assert_equal 1,@driver.starts.size
    assert_empty @leases.active_leases
  end

  def test_cancel_and_deadline_before_admission_leave_no_intent
    assert_raises(G::Refused) { call(cancel:->{true}) }
    assert_raises(G::Refused) { call(deadline:Float::INFINITY) }
    assert_empty records
    assert_empty @driver.starts
  end

  def test_stale_attestation_never_reaches_transport
    original=@driver.method(:observe)
    @driver.define_singleton_method(:observe) { |**kw| original.call(**kw).merge("captured_at"=>0) }
    assert_raises(O::Unavailable) { call }
    assert_empty @driver.calls
    assert_equal 1,@driver.stops.size
    assert_empty @leases.active_leases
  end

  def test_root_identity_and_configuration_binding_are_immutable
    other=File.join(@tmp,"other")
    G.create(path:other,owner:@owner)
    a=JSON.parse(File.read(File.join(@path,"roster.json")))
    b=JSON.parse(File.read(File.join(other,"roster.json")))
    refute_equal a["lineage_id"],b["lineage_id"]
    call
    assert_raises(G::Refused) { call(request_id:"r2",adapter:A.new(model:@adapter.model,mode:"work",
      isolated:A::ISOLATED_MODELS.include?(@adapter.model))) }
    a["history_policy"]="changed"
    File.write(File.join(@path,"roster.json"),JSON.generate(a))
    assert_raises(G::Refused) { call }
    assert_equal 1,@driver.starts.size
  end
end
