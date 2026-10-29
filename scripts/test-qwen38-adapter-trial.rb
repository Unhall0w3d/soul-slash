# frozen_string_literal: true
require "minitest/autorun"
require_relative "run-qwen38-adapter-trial"

class Qwen38AdapterTrialTest < Minitest::Test
  def test_three_bounded_exchanges_and_late_cancellation
    trial=Qwen38AdapterTrial.allocate
    trial.instance_variable_set(:@candidate,"qwen3.8-27b")
    trial.instance_variable_set(:@generation_count,0)
    records={}
    calls=[]
    trial.define_singleton_method(:sample_resources) { {} }
    trial.define_singleton_method(:validate_resources!) { |_| true }
    trial.define_singleton_method(:save) { |name,value| records[name]=value }
    trial.define_singleton_method(:adapter_http) do |path,payload,deadline:|
      calls << path
      case path
      when "/apply-template" then {"prompt"=>"native"}
      when "/tokenize" then {"tokens"=>[1,2]}
      else
        {"model"=>"qwen3.8-27b","choices"=>[{"index"=>0,"finish_reason"=>"stop",
          "message"=>{"role"=>"assistant","content"=>"Answer"}}],
          "usage"=>{"prompt_tokens"=>2,"completion_tokens"=>1,"total_tokens"=>3}}
      end
    end
    trial.probe
    assert_equal 3,calls.count("/v1/chat/completions")
    assert_equal "passed",records.fetch("late-cancellation.json")["state"]
    refute records.key?("exchange-2-final_received.json")
    assert records.key?("exchange-2-generation_intent.json")
    assert_equal 600,Qwen38AdapterTrial::BUDGET_SECONDS
    assert_equal Qwen38NativeProbe,Qwen38AdapterTrial.instance_method(:validate_resources!).owner
  end
end
