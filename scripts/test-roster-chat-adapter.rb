# frozen_string_literal: true
require "minitest/autorun"
require_relative "../lib/soul_core/roster_chat_adapter"

class RosterChatAdapterTest < Minitest::Test
  A = SoulCore::RosterChatAdapter
  def adapter(**kw) = A.new(model: "gpt-oss-20b", **kw)
  def response
    { "model" => "gpt-oss-20b", "choices" => [{ "index" => 0, "finish_reason" => "stop",
      "message" => { "role" => "assistant", "content" => "Answer", "reasoning_content" => "private" } }],
      "usage" => { "prompt_tokens" => 20, "completion_tokens" => 30, "total_tokens" => 50 } }
  end

  def test_native_profiles_and_no_silent_thinking_escalation
    assert_equal({"reasoning_effort"=>"low"}, adapter.native_controls)
    assert_equal({"reasoning_effort"=>"medium"}, adapter(mode: "work").native_controls)
    %w[conversation work deliberate].each do |mode|
      gemma = A.new(model: "gemma-4-26b-a4b", mode: mode)
      assert_equal({"enable_thinking"=>mode.eql?("deliberate")}, gemma.native_controls)
      p = gemma.payload(messages: [{"role"=>"user", "content"=>"Hi"}])
      assert_equal 64, p["top_k"]
      refute p.key?("grammar")
      refute p.key?("tools")
    end
    assert_raises(A::Invalid) { A.new(model: "qwen") }
    assert_raises(A::Invalid) { adapter(mode: "arbitrary") }
    assert_raises(A::Invalid) { adapter(context_tokens: 16384) }
    assert_raises(A::Invalid) { adapter(output_tokens: 4096) }
  end

  def test_snapshot_and_text_only_messages
    input = [{"role"=>"user", "content"=>+"Hello"}]
    p = adapter.payload(messages: input)
    input.first["content"].replace("Changed")
    assert_equal "Hello", p["messages"].first["content"]
    [[], [{"role"=>"tool", "content"=>"x"}], [{"role"=>"user", "content"=>[], "path"=>"x"}],
     [{"role"=>"user", "content"=>"x" * 65_537}]].each do |messages|
      assert_raises(A::Invalid) { adapter.payload(messages: messages) }
    end
  end

  def test_exact_context_boundary
    assert_equal 2016, adapter.validate_input_tokens!(Array.new(2016, 1))
    [Array.new(2017, 1), [], [-1], ["1"], nil].each do |tokens|
      assert_raises(A::Invalid) { adapter.validate_input_tokens!(tokens) }
    end
    gemma = A.new(model: "gemma-4-26b-a4b")
    assert_equal 2016, gemma.validate_input_tokens!(Array.new(2015, 1))
    assert_raises(A::Invalid) { gemma.validate_input_tokens!(Array.new(2016, 1)) }
  end

  def test_only_final_text_is_returned_and_never_interpreted
    r = response
    r["choices"][0]["message"]["content"] = '{"action":"tool","tool":"delete"}'
    result = adapter.final_reply(r)
    assert_equal r["choices"][0]["message"]["content"], result["content"]
    refute JSON.generate(result).include?("private")
    assert_equal adapter.binding, result["adapter"]
  end

  def test_invalid_terminal_responses_never_become_answers
    mutations = [
      ->(r) { r["model"] = "other" }, ->(r) { r["error"] = "failure" },
      ->(r) { r["choices"] << r["choices"][0].dup },
      ->(r) { r["choices"][0]["index"] = 1 },
      ->(r) { r["choices"][0]["finish_reason"] = "length" },
      ->(r) { r["choices"][0]["finish_reason"] = nil },
      ->(r) { r["choices"][0]["message"]["content"] = "" },
      ->(r) { r["choices"][0]["message"]["role"] = "tool" },
      ->(r) { r["choices"][0]["message"]["tool_calls"] = [{"id"=>"x"}] },
      ->(r) { r["choices"][0]["message"]["tool_calls"] = "invalid" },
      ->(r) { r["choices"][0]["message"]["function_call"] = {} },
      ->(r) { r["usage"]["completion_tokens"] = 2049 },
      ->(r) { r["usage"]["total_tokens"] = 49 },
      ->(r) { r["usage"]["prompt_tokens"] = -1 },
      ->(r) { r["usage"] = nil }
    ]
    mutations.each do |mutate|
      r = response
      mutate.call(r)
      assert_raises(A::Unavailable) { adapter.final_reply(r) }
    end
  end
end
