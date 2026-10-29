# frozen_string_literal: true
require_relative "test-roster-conversation-gateway"

class Qwen38JournalBoundaryTest < RosterConversationGatewayTest
  def setup
    super
    @gateway.close
    original_binding=@driver.method(:binding)
    @driver.define_singleton_method(:binding) do
      original_binding.call.merge("qwen3.8-27b"=>{"artifact_sha256"=>"d"*64,"server_sha256"=>"b"*64,"launch_sha256"=>"e"*64})
    end
    original_request=@driver.method(:request)
    @driver.define_singleton_method(:request) do |*args,**kw|
      result=original_request.call(*args,**kw)
      if result["model"]=="qwen3.8-27b"
        result["usage"]={"prompt_tokens"=>2,"completion_tokens"=>1,"total_tokens"=>3}
      end
      result
    end
    @owner=O.new(leases:@leases,driver:@driver,clock:-> {10.0},isolated_models:["qwen3.8-27b"])
    @path=File.join(@tmp,"isolated-qwen")
    G.create(path:@path,owner:@owner)
    @gateway=G.new(path:@path,owner:@owner,clock:-> {10.0})
    @adapter=A.new(model:"qwen3.8-27b",isolated:true)
  end

  def test_continuation_and_switch_between_distinct_conversations
    call
    history=@messages+[{"role"=>"assistant","content"=>"Hello"},{"role"=>"user","content"=>"Next"}]
    call(request_id:"request2",messages:history)
    gpt=A.new(model:"gpt-oss-20b")
    assert_raises(G::Refused) { call(request_id:"request3",messages:history,adapter:gpt) }
    call(conversation_id:"chat2",request_id:"request3",adapter:gpt)
    assert_equal ["qwen3.8-27b","qwen3.8-27b","gpt-oss-20b"],@driver.starts
    assert_empty @leases.active_leases
  end

  def test_candidate_requires_explicit_owner_opt_in
    assert_raises(ArgumentError) { O.new(leases:@leases,driver:@driver) }
    assert_raises(ArgumentError) { O.new(leases:@leases,driver:@driver,isolated_models:["unknown"]) }
    default_driver=Driver.new
    default_owner=O.new(leases:@leases,driver:default_driver,clock:-> {10.0})
    assert_raises(O::Unavailable) do
      default_owner.with_runtime(adapter:@adapter,request_id:"isolated",conversation_id:"isolated",
        deadline:100,cancel:-> {false}) { flunk "unbound model must not run" }
    end
    assert_empty default_driver.starts
    assert_empty @leases.active_leases
  end
end
