# frozen_string_literal: true
require "minitest/autorun"
require_relative "../lib/soul_core/roster_chat_application"
require_relative "../lib/soul_core/roster_chat_server"

class RosterChatApplicationTest < Minitest::Test
  TOKEN = "synthetic-roster-token-not-a-secret-12345"
  class Backend
    attr_reader :calls
    def initialize = @calls = []
    def complete(**args)
      @calls << args
      {"model"=>args[:adapter].model, "adapter"=>args[:adapter].binding,
       "request_id"=>args[:request_id], "conversation_id"=>args[:conversation_id],
       "content"=>"Birch.", "replayed"=>@calls.length>1, "lineage"=>"synthetic"}
    end
  end
  def setup
    @backend=Backend.new
    @app=SoulCore::RosterChatApplication.new(backend:@backend,bearer_token:TOKEN,clock:-> {10})
    @headers={"authorization"=>"Bearer #{TOKEN}","x-soul-conversation-id"=>"fresh-chat"}
  end
  def request(model: SoulCore::RosterChatAdapter::MODELS.first, extra: {}, headers: @headers, cancel: -> {false})
    @app.call(method:"POST",target:"/v1/chat/completions",headers:headers,cancel:cancel,
      body:JSON.generate({"model"=>model,"messages"=>[{"role"=>"user","content"=>"Shelf?"}]}.merge(extra)))
  end
  def test_both_models_and_replay_identity
    SoulCore::RosterChatAdapter::MODELS.each do |model|
      a=JSON.parse(request(model:model).body)
      b=JSON.parse(request(model:model).body)
      assert_equal model,a["model"]
      assert_equal a["id"],b["id"]
      assert_equal "Birch.",a.dig("choices",0,"message","content")
      assert_equal 189,@backend.calls.last[:deadline]
    end
    refute_equal @backend.calls[0][:request_id],@backend.calls[2][:request_id]
  end
  def test_cancellation_forwarded
    cancel=-> {true}
    request(cancel:cancel)
    assert_same cancel,@backend.calls.last[:cancel]
  end
  def test_candidate_requires_explicit_application_opt_in
    assert_equal 422,request(model:"qwen3.8-27b").status
    assert_empty @backend.calls
    ids=["qwen3.8-27b"]
    @app=SoulCore::RosterChatApplication.new(backend:@backend,bearer_token:TOKEN,isolated_models:ids)
    ids.clear
    assert_equal 200,request(model:"qwen3.8-27b").status
    assert_equal false,@backend.calls.last[:adapter].native_controls["enable_thinking"]
    assert_raises(ArgumentError) { SoulCore::RosterChatApplication.new(backend:@backend,bearer_token:TOKEN,isolated_models:["foreign"]) }
  end
  def test_javascript_temperature_serialization
    assert_equal 200,request(extra:{"temperature"=>1,"max_tokens"=>2048,"top_p"=>0.95}).status
    assert_equal 422,request(extra:{"temperature"=>"1"}).status
  end
  def test_stream_attribution
    response=request(model:"gemma-4-26b-a4b",extra:{"stream"=>true})
    assert_equal 200,response.status
    frames=response.body.lines.grep(/^data: /).reject{|s|s.include?("[DONE]")}.map{|s|JSON.parse(s.delete_prefix("data: "))}
    assert frames.all?{|f| f["model"]=="gemma-4-26b-a4b"}
    assert_equal "Birch.",frames[1].dig("choices",0,"delta","content")
  end
  def test_rejects_legacy_or_overrides_before_backend
    assert_equal 422,request(model:"soul-continuity-qwen").status
    [{"max_tokens"=>768},{"temperature"=>0.6},{"tools"=>[]},{"messages"=>[{"role"=>"system","content"=>"override"}]}].each do |extra|
      assert_equal 422,request(extra:extra).status
    end
    assert_empty @backend.calls
  end
  def test_auth_origin_and_conversation
    assert_equal 401,request(headers:{}).status
    assert_equal 403,request(headers:@headers.merge("origin"=>"http://example.invalid")).status
    assert_equal 422,request(headers:@headers.merge("x-soul-conversation-id"=>"new")).status
    assert_empty @backend.calls
  end
  def test_socket_disconnect_and_trailing_bytes
    server=SoulCore::RosterChatServer.new(host:"127.0.0.1",port:0,application:@app)
    local,peer=Socket.pair(:UNIX,:STREAM,0)
    refute server.send(:disconnected?,local)
    peer.write("x")
    assert server.send(:disconnected?,local)
    local.read(1)
    peer.close
    assert server.send(:disconnected?,local)
  ensure
    local&.close
    peer&.close unless peer&.closed?
  end

  def test_http_disconnect_reaches_active_request
    observed=Queue.new
    application=Object.new
    application.define_singleton_method(:call) do |cancel:, **_request|
      observed << :entered
      sleep 0.01 until cancel.call
      observed << :canceled
      SoulCore::ContinuityLab::ChatApplication::Response.new(status:200,headers:{},body:"not delivered")
    end
    server=SoulCore::RosterChatServer.new(host:"127.0.0.1",port:0,application:application)
    local,peer=Socket.pair(:UNIX,:STREAM,0)
    worker=Thread.new { server.send(:handle,local) }
    peer.write("POST /v1/chat/completions HTTP/1.1\r\nContent-Length: 2\r\n\r\n{}")
    assert_equal :entered,Timeout.timeout(2) { observed.pop }
    peer.close
    assert_equal :canceled,Timeout.timeout(2) { observed.pop }
    assert worker.join(2)
    assert local.closed?
  ensure
    peer&.close unless peer&.closed?
    worker&.kill
    worker&.join
    local&.close unless local&.closed?
  end
end
class RosterChatApplicationTest
  def test_only_typed_preadmission_busy_is_retryable
    [SoulCore::RosterAdmissionBusy,SoulCore::RosterRuntimeOwner::Unavailable,SoulCore::RosterConversationGateway::Refused].each do |klass|
      @backend.define_singleton_method(:complete){|**|raise klass,'busy-looking internal detail'}
      response=request;data=JSON.parse(response.body)
      assert_equal({SoulCore::RosterAdmissionBusy=>409,SoulCore::RosterRuntimeOwner::Unavailable=>503,SoulCore::RosterConversationGateway::Refused=>409}.fetch(klass),response.status)
      if klass==SoulCore::RosterAdmissionBusy
        assert_equal 'roster_busy',data.dig('error','code');assert_equal false,data.dig('error','request_admitted')
        assert_includes data.dig('error','message'),'then try again'
      else
        refute_equal 'roster_busy',data.dig('error','code')
      end
    end
  end
end
