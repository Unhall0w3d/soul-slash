# frozen_string_literal: true
require "minitest/autorun"
require_relative "../lib/soul_core/roster_chat_exchange"

class RosterChatExchangeTest < Minitest::Test
  A = SoulCore::RosterChatAdapter
  E = SoulCore::RosterChatExchange
  def setup
    @calls, @records, @cancelled, @time, @admit = [], [], false, 10.0, true
    @tokens, @reported_tokens = [1, 2], 3
    @transport_failure, @receipt_failure = false, false
    @client = Object.new
    owner = self
    @client.define_singleton_method(:request) { |*args, **kw| owner.request(*args, **kw) }
    @exchange = E.new(adapter: A.new(model: "gemma-4-26b-a4b"), client: @client,
      admission: -> { @admit }, cancel: -> { @cancelled }, clock: -> { @time },
      receipt: ->(r) { raise IOError if @receipt_failure; @records << r })
  end

  def request(method, path, payload, deadline:)
    @calls << [method, path, payload, deadline]
    @cancelled = true if path == @cancel_after
    case path
    when "/apply-template" then {"prompt"=>"native prompt"}
    when "/tokenize" then {"tokens"=>@tokens}
    when "/v1/chat/completions"
      raise IOError, "uncertain transport" if @transport_failure
      {"model"=>"gemma-4-26b-a4b", "choices"=>[{"index"=>0, "finish_reason"=>"stop",
        "message"=>{"role"=>"assistant", "content"=>"Final", "reasoning_content"=>"not disclosed"}}],
        "usage"=>{"prompt_tokens"=>@reported_tokens, "completion_tokens"=>5, "total_tokens"=>@reported_tokens+5}}
    else raise "unexpected route"
    end
  end

  def run_exchange = @exchange.call(messages: [{"role"=>"user", "content"=>"Hello"}], deadline: 100)

  def test_native_round_trip_and_receipts
    result = run_exchange
    assert_equal "Final", result["content"]
    assert_equal %w[/apply-template /tokenize /v1/chat/completions], @calls.map { |x| x[1] }
    assert_equal({"enable_thinking"=>false}, @calls.first[2]["chat_template_kwargs"])
    assert_equal @calls.first[2]["chat_template_kwargs"], @calls.last[2]["chat_template_kwargs"]
    assert_equal %w[generation_intent final_received], @records.map { |r| r["state"] }
    refute JSON.generate(@records).include?("not disclosed")
    assert_raises(E::Stopped) { run_exchange }
    assert_equal 3, @calls.length
  end

  def test_cancellation_before_and_during_exchange
    @cancelled = true
    assert_raises(E::Stopped) { run_exchange }
    assert_empty @calls
    setup
    @cancel_after = "/tokenize"
    assert_raises(E::Stopped) { run_exchange }
    assert_equal 2, @calls.length
    assert_empty @records
    setup
    @cancel_after = "/v1/chat/completions"
    assert_raises(E::Stopped) { run_exchange }
    assert_equal ["generation_intent"], @records.map { |r| r["state"] }
  end

  def test_failed_admission_and_oversized_context_never_generate
    @admit = false
    assert_raises(E::Stopped) { run_exchange }
    assert_empty @calls
    setup
    @tokens = Array.new(2017, 1)
    assert_raises(A::Invalid) { run_exchange }
    assert_equal 2, @calls.length
    assert_empty @records
  end

  def test_uncertain_transport_is_not_retried
    @transport_failure = true
    assert_raises(IOError) { run_exchange }
    assert_raises(E::Stopped) { run_exchange }
    assert_equal 3, @calls.length
    assert_equal ["generation_intent"], @records.map { |r| r["state"] }
  end

  def test_receipt_failure_prevents_generation
    @receipt_failure = true
    assert_raises(IOError) { run_exchange }
    assert_equal 2, @calls.length
  end

  def test_token_count_drift_refuses_final
    @reported_tokens = 4
    assert_raises(A::Unavailable) { run_exchange }
    assert_equal ["generation_intent"], @records.map { |r| r["state"] }
  end

  def test_deadline_after_response_and_final_receipt_failure_do_not_return_answer
    original = method(:request)
    define_singleton_method(:request) do |*args, **kw|
      value = original.call(*args, **kw)
      @time = 100 if args[1] == "/v1/chat/completions"
      value
    end
    assert_raises(E::Stopped) { run_exchange }
    assert_equal ["generation_intent"], @records.map { |r| r["state"] }
    singleton_class.remove_method(:request)
    setup
    original = method(:request)
    define_singleton_method(:request) do |*args, **kw|
      value = original.call(*args, **kw)
      @receipt_failure = true if args[1] == "/v1/chat/completions"
      value
    end
    assert_raises(IOError) { run_exchange }
    assert_raises(E::Stopped) { run_exchange }
  end

  def test_invalid_deadlines_never_touch_transport
    [nil, Float::INFINITY, Float::NAN, 10, 191].each do |deadline|
      setup
      assert_raises(E::Stopped) { @exchange.call(messages: [], deadline: deadline) }
      assert_empty @calls
    end
  end
end
