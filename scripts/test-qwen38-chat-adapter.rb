# frozen_string_literal: true
require_relative "test-roster-chat-adapter"
require_relative "test-roster-chat-exchange"

# Reuse the complete response-boundary suite with Qwen identity and controls.
class Qwen38ChatAdapterTest < RosterChatAdapterTest
  def adapter(**kw) = A.new(model: "qwen3.8-27b", isolated: true, **kw)
  def response = super.merge("model" => "qwen3.8-27b")

  def test_isolation_and_native_profile
    assert_raises(A::Invalid) { A.new(model: "qwen3.8-27b") }
    assert_raises(A::Invalid) { A.new(model: "qwen3.8-27b", isolated: "true") }
    refute_includes A::MODELS, "qwen3.8-27b"
    %w[conversation work deliberate].each do |mode|
      a = adapter(mode: mode)
      p = a.payload(messages: [{"role"=>"user", "content"=>"Hello"}])
      thinking = mode == "deliberate"
      assert_equal({"enable_thinking"=>thinking, "preserve_thinking"=>false, "reasoning_effort"=>"low"}, a.native_controls)
      assert_equal thinking ? 1.0 : 0.7, p["temperature"]
      assert_equal thinking ? 0.95 : 0.8, p["top_p"]
      assert_equal thinking ? 0.0 : 1.5, p["presence_penalty"]
      assert_equal 20, p["top_k"]
      refute p.key?("tools")
    end
    assert_raises(A::Invalid) { adapter.payload(messages: [
      {"role"=>"user", "content"=>"Hi"}, {"role"=>"system", "content"=>"late"},
      {"role"=>"user", "content"=>"Next"}]) }
  end

  def test_native_profiles_and_no_silent_thinking_escalation
    test_isolation_and_native_profile
  end
end

class Qwen38ChatExchangeTest < RosterChatExchangeTest
  def setup
    super
    @reported_tokens = 2
    @exchange = E.new(adapter: A.new(model: "qwen3.8-27b", isolated: true), client: @client,
      admission: -> { @admit }, cancel: -> { @cancelled }, clock: -> { @time },
      receipt: ->(r) { raise IOError if @receipt_failure; @records << r })
  end

  def request(*args, **kw)
    result = super
    result["model"] = "qwen3.8-27b" if result.key?("model")
    result
  end

  def test_native_round_trip_and_receipts
    result = run_exchange
    assert_equal "Final", result["content"]
    assert_equal "qwen3.8-27b", result["model"]
    assert_equal({"enable_thinking"=>false, "preserve_thinking"=>false, "reasoning_effort"=>"low"}, @calls.first[2]["chat_template_kwargs"])
    assert_equal @calls.first[2]["chat_template_kwargs"], @calls.last[2]["chat_template_kwargs"]
    assert_equal %w[generation_intent final_received], @records.map { |r| r["state"] }
    refute JSON.generate(result).include?("not disclosed")
    assert_raises(E::Stopped) { run_exchange }
  end
end
