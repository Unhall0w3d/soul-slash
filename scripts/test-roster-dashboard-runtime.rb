# frozen_string_literal: true
require "minitest/autorun"
require "tmpdir"
require_relative "../lib/soul_core/roster_dashboard_runtime"
require_relative "../lib/soul_core/chat_store"
require_relative "../lib/soul_core/application_chat_service"
require_relative "../lib/soul_core/application_facade"

class RosterDashboardRuntimeTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir
    @store = SoulCore::ChatStore.new(root: @root)
    @chat = @store.create_chat(member: "gpt-oss-20b")
    @calls = []
  end
  def teardown = FileUtils.remove_entry(@root)
  def runtime(&handler)
    SoulCore::RosterDashboardRuntime.new(store: @store, key_reader: -> { "a" * 64 }, transport: lambda do |path, body, token, seconds, headers|
      @calls << path
      handler.call(path, body, headers)
    end)
  end
  def reply(body, headers)
    adapter = SoulCore::RosterChatAdapter.new(model: body.fetch("model"))
    conversation = headers.fetch("X-Soul-Conversation-Id")
    id = SoulCore::RosterConversationGateway.digest({"conversation" => conversation, "adapter" => adapter.binding, "messages" => body.fetch("messages")})
    {"model" => adapter.model, "soul" => {"model" => adapter.model, "adapter" => adapter.binding, "conversation_id" => conversation, "request_id" => id},
      "choices" => [{"finish_reason" => "stop", "message" => {"role" => "assistant", "content" => "hello"}}]}
  end
  def service(member_runtime)
    legacy = Object.new
    legacy.define_singleton_method(:respond) { |**| raise "must not use legacy" }
    SoulCore::ApplicationChatService.new(root: @root, store: @store, runtime: legacy, member_runtime: member_runtime)
  end
  def send_with(s, id = "request_0001")
    s.send(chat_id: @chat.fetch("id"), message: "hello", request_id: id)
  end

  def test_member_attribution_followup_and_replay
    s = service(runtime { |path, body, headers| reply(body, headers) })
    assert_equal "complete", send_with(s)["lifecycle_state"]
    assert send_with(s)["idempotent_replay"]
    assert_equal "complete", send_with(s, "request_0002")["lifecycle_state"]
    assert_equal 2, @calls.count("/v1/chat/completions")
    assert_equal "gpt-oss-20b", @store.messages(@chat["id"]).last.dig("metadata", "runtime", "model")
  end

  def test_no_member_fallback_and_unknown_member_refused
    assert_raises(ArgumentError) { @store.create_chat(member: "invented") }
    assert_equal "blocked_for_human_review", send_with(service(nil))["lifecycle_state"]
    assert_empty @store.messages(@chat["id"])
    refute @store.create_chat.dig("metadata", "roster_member")
  end

  def test_wrong_attribution_not_saved
    s = service(runtime { |_, body, headers| reply(body, headers).merge("model" => "other") })
    assert_equal "blocked_for_human_review", send_with(s)["lifecycle_state"]
    assert_equal ["user"], @store.messages(@chat["id"]).map { |r| r["role"] }
  end

  def test_facade_member_creation_projection_and_cancel_contract
    facade = SoulCore::ApplicationFacade.new(root: @root, chat_store: @store)
    request = {"schema_version" => "soul.application.v1", "request_id" => "create_0001", "operation" => "chats.create",
      "parameters" => {"member" => "gemma-4-26b-a4b"}, "context" => {"interface" => "dashboard"}}
    response = facade.call(request)
    assert_equal "complete", response["lifecycle_state"]
    assert_equal "gemma-4-26b-a4b", response.dig("data", "record", "roster_member")
    id = response.dig("data", "record", "id")
    response = facade.call(request.merge("request_id" => "cancel_9999", "operation" => "chats.cancel",
      "parameters" => {"chat_id" => id, "target_request_id" => "missing_9999"}))
    assert_equal "awaiting_input", response["lifecycle_state"]
    refute response.dig("data", "cancellation_requested")
  end

  def test_stop_requires_exact_positive_cleanup_ack
    [true, false].each_with_index do |confirmed, i|
      @chat = @store.create_chat(member: "gpt-oss-20b")
      entered, release = Queue.new, Queue.new
      client = runtime do |path, body, _|
        if path == "/v1/chat/completions"
          entered << true
          Timeout.timeout(2) { release.pop }
          raise IOError
        elsif path.end_with?("/cancel")
          release << true
          body.merge("state" => "cancel_requested")
        else
          body.merge("state" => confirmed ? "canceled_released" : "unknown", "cleanup_confirmed" => confirmed)
        end
      end
      s = service(client)
      thread = Thread.new { send_with(s, "cancel_000#{i}") }
      Timeout.timeout(2) { entered.pop }
      assert s.cancel(chat_id: @chat["id"], target_request_id: "cancel_000#{i}").dig("data", "cancellation_requested")
      result = Timeout.timeout(3) { thread.value }
      assert_equal confirmed ? "canceled" : "blocked_for_human_review", result["lifecycle_state"]
      assert_equal ["user"], @store.messages(@chat["id"]).map { |r| r["role"] }
    end
  end

  def test_deterministic_maintenance_is_not_model_output_or_model_history
    workflow = Object.new
    workflow.define_singleton_method(:candidate_message?) { |chat_id:, message:| message == "Maintain Crucible" }
    workflow.define_singleton_method(:plan) do |**|
      {"content" => "Review this exact plan first.", "mode" => "maintenance_confirmation_required",
       "metadata" => {"capability_id" => "maintenance.device", "lifecycle_state" => "awaiting_input", "model_authorization" => false}}
    end
    bodies = []
    client = SoulCore::RosterDashboardRuntime.new(store: @store, maintenance_workflow: workflow,
      key_reader: -> { "a" * 64 }, transport: lambda { |_, body, _, _, headers| bodies << body; reply(body, headers) })
    s = service(client)
    assert_equal "complete", send_with(s)["lifecycle_state"]
    request = {chat_id: @chat["id"], message: "Maintain Crucible", request_id: "maintenance_0001"}
    assert_equal "complete", s.send(**request)["lifecycle_state"]
    assert s.send(**request)["idempotent_replay"]
    assistant = @store.messages(@chat["id"]).last
    assert_equal "soul_maintenance_workflow", assistant.dig("metadata", "responder")
    assert_nil assistant.dig("metadata", "runtime", "model")
    assert_equal 1, bodies.length
    assert_equal "complete", send_with(s, "request_0002")["lifecycle_state"]
    assert_equal %w[user assistant user], bodies.last["messages"].map { |r| r["role"] }
    refute bodies.last["messages"].any? { |r| r["content"].include?("Crucible") }
  end
end
class RosterDashboardRuntimeTest
  def test_deterministic_tool_attribution_and_foreign_receipt_refusal
    [false,true].each do |foreign|
      @chat=@store.create_chat(member:'gpt-oss-20b')
      s=service(runtime do |_,body,headers|
        response=reply(body,headers)
        response['soul']['execution']={'provider'=>'deterministic.read_only','selected_member'=>foreign ? 'other' : 'gpt-oss-20b','model_invoked'=>false,'result_sha256'=>Digest::SHA256.hexdigest('hello')}
        response
      end)
      result=send_with(s)
      assert_equal foreign ? 'blocked_for_human_review' : 'complete',result['lifecycle_state']
      unless foreign
        assert_equal 'deterministic.read_only',@store.messages(@chat['id']).last.dig('metadata','provider_id')
        assert send_with(s)['idempotent_replay']
      end
    end
  end
end
class RosterDashboardRuntimeTest
  def test_busy_audit_is_preserved_and_manual_retry_projects_only_admitted_history
    busy=true;bodies=[]
    client=runtime do |_,body,headers|
      bodies<<body
      raise SoulCore::RosterAdmissionBusy if busy
      reply(body,headers)
    end
    s=service(client);first=send_with(s)
    assert_equal 'awaiting_input',first['lifecycle_state'];assert_equal 'roster_busy',first['code']
    assert_equal ['user'],@store.messages(@chat['id']).map{|r|r['role']}
    assert_equal 'blocked_for_human_review',send_with(s)['lifecycle_state']
    assert_equal 1,bodies.length
    busy=false
    assert_equal 'complete',send_with(s,'request_retry')['lifecycle_state']
    assert_equal [{'role'=>'user','content'=>'hello'}],bodies.last['messages']
    assert_equal %w[user user assistant],@store.messages(@chat['id']).map{|r|r['role']}
    assert send_with(s,'request_retry')['idempotent_replay'];assert_equal 2,bodies.length
    assert_equal 'complete',send_with(s,'request_followup')['lifecycle_state']
    assert_equal %w[user assistant user],bodies.last['messages'].map{|r|r['role']}
  end
  def test_busy_history_filter_requires_exact_audit_identity
    client=runtime{|*|raise SoulCore::RosterAdmissionBusy};send_with(service(client))
    rows=@store.messages(@chat['id'])
    assert_equal [],client.send(:without_unadmitted_busy_messages,rows,@chat['id'])
    assert_raises(RuntimeError){client.send(:without_unadmitted_busy_messages,[rows.first.merge('content'=>'changed')],@chat['id'])}
    assert_raises(RuntimeError){client.send(:without_unadmitted_busy_messages,rows+rows,@chat['id'])}
    assert_raises(RuntimeError){client.send(:without_unadmitted_busy_messages,rows,'different')}
  end
end
class RosterDashboardRuntimeTest
  def test_only_exact_busy_transport_proof_allows_manual_retry
    client=runtime{};body=JSON.generate({'error'=>{'code'=>'roster_busy','request_admitted'=>false}})
    assert_raises(SoulCore::RosterAdmissionBusy){client.send(:refuse_response!,'/v1/chat/completions','409',body)}
    [['429',body],['503',body],['409','{}'],['409','null'],['409','invalid'],['409',body.sub('false','true')],['409',body.sub('roster_busy','quota_exceeded')]].each do |code,bytes|
      assert_raises(RuntimeError){client.send(:refuse_response!,'/v1/chat/completions',code,bytes)}
    end
    assert_raises(RuntimeError){client.send(:refuse_response!,'/v1/soul/requests/status','409',body)}
  end
end
class RosterDashboardRuntimeTest
  def test_busy_receipt_write_failure_never_claims_retry_permission
    client=runtime{|*|raise SoulCore::RosterAdmissionBusy};s=service(client)
    s.instance_variable_get(:@receipt_store).define_singleton_method(:fail){|**|raise IOError,'unavailable'}
    result=send_with(s)
    assert_equal 'blocked_for_human_review',result['lifecycle_state']
    refute result.key?('request_admitted')
    rows=@store.messages(@chat['id'])
    assert_equal ['user'],rows.map{|r|r['role']}
    assert_equal rows,client.send(:without_unadmitted_busy_messages,rows,@chat['id'])
  end
end
class RosterDashboardRuntimeTest
  def test_model_proposal_receipts_require_scope_and_input_binding
    [nil,'scope','input','unknown','member','result','marker'].each do |corrupt|
      @chat=@store.create_chat(member:'gpt-oss-20b')
      s=service(runtime do |_,body,headers|
        response=reply(body,headers);soul=response['soul']
        execution={'provider'=>'deterministic.read_only','selected_member'=>'gpt-oss-20b','model_invoked'=>true,
          'tool_executed'=>true,'operation'=>'skills.list','state'=>'complete',
          'proposal'=>{'tool'=>'list_skills','arguments'=>{}},'proposal_sha256'=>'a'*64,
          'result_sha256'=>Digest::SHA256.hexdigest('hello'),
          'input_sha256'=>SoulCore::RosterConversationGateway.digest(soul.slice('conversation_id','request_id','adapter').merge('messages'=>body['messages']))}
        case corrupt
        when 'scope' then execution['proposal']['arguments']={'path'=>'/home/bhones/Downloads/AGENTS.md'}
        when 'input' then execution['input_sha256']='b'*64
        when 'unknown' then execution['operation']='shell'
        when 'member' then execution['selected_member']='other'
        when 'result' then execution['result_sha256']='c'*64
        when 'marker' then execution.delete('proposal_sha256')
        end
        soul['execution']=execution;response
      end)
      assert_equal(corrupt ? 'blocked_for_human_review' : 'complete',send_with(s,"proposal_#{corrupt || 'valid'}")["lifecycle_state"])
      assert_equal(corrupt ? ['user'] : %w[user assistant],@store.messages(@chat['id']).map{|r|r['role']})
    end
  end
end
