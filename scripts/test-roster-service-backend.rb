# frozen_string_literal: true
require_relative "test-roster-warm-backend"
require_relative "../lib/soul_core/roster_service_backend"
require_relative "soul-roster-coordinator"

class RosterServiceBackendTest < Minitest::Test
  def setup
    @tmp=Dir.mktmpdir
    @driver=RosterWarmBackendTest::Driver.new
    @leases=SoulCore::ModelRuntimeLeaseStore.new(root:@tmp)
    @owner=SoulCore::RosterServiceSession.new(leases:@leases,driver:@driver)
    @backend=SoulCore::RosterServiceBackend.new(owner:@owner,path:File.join(@tmp,"journal"))
  end
  def teardown = FileUtils.remove_entry(@tmp)
  def test_idle_start_repeated_replay_and_shutdown
    @backend.run do
      assert_equal "unloaded",@backend.status["state"]
      assert @backend.status["available"]
      assert_empty @driver.starts
      args={conversation_id:"one",request_id:"one",adapter:SoulCore::RosterChatAdapter.new(model:"gpt-oss-20b"),
        messages:[{"role"=>"user","content"=>"Hi"}],deadline:Process.clock_gettime(Process::CLOCK_MONOTONIC)+30}
      @backend.complete(**args)
      33.times { assert @backend.complete(**args)["replayed"] }
      assert_equal "resident",@backend.status["state"]
      assert_equal "gpt-oss-20b",@backend.status["model"]
      assert_equal 1,@driver.starts.length
    end
    assert_empty @leases.active_leases
    refute @backend.status["available"]
  end
  def test_health_requires_auth_and_does_not_start_model
    app=SoulRosterCoordinator::Application.new(backend:@backend,bearer_token:"a"*64)
    @backend.run do
      assert_equal 401,app.call(method:"GET",target:"/health",headers:{}).status
      response=app.call(method:"GET",target:"/health",headers:{"Authorization"=>"Bearer #{"a"*64}"})
      assert_equal 200,response.status
      assert_equal "unloaded",JSON.parse(response.body)["state"]
      assert_equal 16,JSON.parse(response.body)["journal_conversation_limit"]
      assert_empty @driver.starts
    end
  end

  def test_scoped_memory_health_is_explicit_without_loading
    memory=SoulCore::RosterMemoryContext.new(store:SoulCore::ConversationMemoryStore.new(root:@tmp))
    @backend=SoulCore::RosterServiceBackend.new(owner:@owner,path:File.join(@tmp,'memory-journal'),gateway_class:SoulCore::RosterMemoryGateway,memory:memory)
    app=SoulRosterCoordinator::Application.new(backend:@backend,bearer_token:'a'*64)
    @backend.run do
      response=app.call(method:'GET',target:'/health',headers:{'Authorization'=>"Bearer #{'a'*64}"})
      body=JSON.parse(response.body)
      assert_equal 'approved_shared_and_member_scoped_v1',body['memory_policy']
      assert_nil body['journal_conversation_limit']
      assert_equal 'shared_record_budget',body['journal_capacity_policy']
      assert_equal 512,body['journal_record_limit']
      assert_equal 'text-only roster; approved scoped memory; no tools',body['scope']
      assert_empty @driver.starts
      args={conversation_id:'memory',request_id:'memory',adapter:SoulCore::RosterChatAdapter.new(model:'gpt-oss-20b'),messages:[{'role'=>'user','content'=>'Hello'}],deadline:Process.clock_gettime(Process::CLOCK_MONOTONIC)+30}
      result=@backend.complete(**args)
      assert_equal 'final_received',result['memory']['stage']
      assert_empty result['memory']['revisions']
      assert_equal result.merge('replayed'=>true),@backend.complete(**args)
      assert_equal 1,@driver.starts.length
    end
  end

  def test_archived_journal_health_and_replay
    memory=SoulCore::RosterMemoryContext.new(store:SoulCore::ConversationMemoryStore.new(root:@tmp))
    @backend=SoulCore::RosterServiceBackend.new(owner:@owner,path:File.join(@tmp,'archive'),gateway_class:SoulCore::RosterArchiveGateway,memory:memory)
    @backend.run do
      assert_equal 'per_conversation_with_global_replay_registry',@backend.status['journal_capacity_policy']
      assert_equal 'conversation',@backend.status['journal_record_limit_scope']
      args={conversation_id:'archive',request_id:'archive',adapter:SoulCore::RosterChatAdapter.new(model:'gpt-oss-20b'),messages:[{'role'=>'user','content'=>'Hello'}],deadline:Process.clock_gettime(Process::CLOCK_MONOTONIC)+30}
      answer=@backend.complete(**args)
      assert_equal answer.merge('replayed'=>true),@backend.complete(**args)
      assert_equal 1,@driver.starts.length
    end
    assert_empty @leases.active_leases
  end

  def test_request_control_acknowledges_only_after_owner_release
    entered = Queue.new
    @driver.cancel_hook = ->(path) do
      if path == "/apply-template"
        entered << true
        Timeout.timeout(2) { sleep 0.001 until @driver.cancel.call }
        raise SoulCore::RosterChatExchange::Stopped, "synthetic cancellation"
      end
    end
    identity = {conversation_id: "controlled", request_id: "controlled"}
    @backend.run do
      request = Thread.new do
        assert_raises(SoulCore::RosterChatExchange::Stopped) do
          @backend.complete(**identity, adapter: SoulCore::RosterChatAdapter.new(model: "gpt-oss-20b"),
            messages: [{"role" => "user", "content" => "Hi"}], deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10)
        end
      end
      Timeout.timeout(2) { entered.pop }
      refute @backend.cancel_request(**identity)["cleanup_confirmed"]
      Timeout.timeout(2) { request.value }
      assert @backend.request_status(**identity)["cleanup_confirmed"]
      assert_empty @leases.active_leases
      assert_equal 1, @driver.stops.length
    end
  end
end
class RosterServiceBackendTest
  def test_read_only_http_attribution_replay_and_no_model_launch
    require_relative '../lib/soul_core/roster_read_only_archive'
    memory=SoulCore::RosterMemoryContext.new(store:SoulCore::ConversationMemoryStore.new(root:@tmp))
    @backend=SoulCore::RosterServiceBackend.new(owner:@owner,path:File.join(@tmp,'skills'),gateway_class:SoulCore::RosterReadOnlyArchive,memory:memory)
    app=SoulRosterCoordinator::Application.new(backend:@backend,bearer_token:'a'*64)
    @backend.run do
      headers={'Authorization'=>"Bearer #{'a'*64}",'X-Soul-Conversation-Id'=>'skill-http'}
      payload=JSON.generate('model'=>'gpt-oss-20b','messages'=>[{'role'=>'user','content'=>'soul status'}])
      first=app.call(method:'POST',target:'/v1/chat/completions',headers:headers,body:payload)
      assert_equal 200,first.status
      data=JSON.parse(first.body)
      assert_equal 'deterministic.read_only',data.dig('soul','execution','provider')
      assert_equal 'gpt-oss-20b',data.dig('soul','execution','selected_member')
      second=JSON.parse(app.call(method:'POST',target:'/v1/chat/completions',headers:headers,body:payload).body)
      assert second.dig('soul','replayed')
      assert_equal data['choices'],second['choices']
      assert @backend.status['read_only_skills']
      assert_empty @driver.starts
    end
  end
end
class RosterServiceBackendTest
  def test_overlapping_http_request_is_busy_before_admission_and_first_completes
    entered,release=Queue.new,Queue.new
    @driver.cancel_hook=->(path){if path=='/apply-template';entered<<true;Timeout.timeout(3){release.pop};end}
    app=SoulRosterCoordinator::Application.new(backend:@backend,bearer_token:'a'*64)
    call=->(id){app.call(method:'POST',target:'/v1/chat/completions',headers:{'Authorization'=>"Bearer #{'a'*64}",'X-Soul-Conversation-Id'=>id},body:JSON.generate({'model'=>'gpt-oss-20b','messages'=>[{'role'=>'user','content'=>'hello'}]}))}
    @backend.run do
      thread=Thread.new{call.call('first_request')}
      begin
        Timeout.timeout(3){entered.pop}
        rejected=call.call('second_request')
        assert_equal 409,rejected.status
        assert_equal false,JSON.parse(rejected.body).dig('error','request_admitted')
        assert_equal 'roster_busy',JSON.parse(rejected.body).dig('error','code')
        assert_equal 1,@driver.starts.length
      ensure
        release<<true
      end
      assert_equal 200,Timeout.timeout(3){thread.value}.status
      assert_equal 1,@driver.starts.length
    end
    assert_empty @leases.active_leases
  end
end
