# frozen_string_literal: true
require "minitest/autorun"
require_relative "run-roster-adapter-trial"

class RosterAdapterTrialTest < Minitest::Test
  def test_both_models_use_real_exchange_with_existing_owner_and_bounds
    RosterAdapterTrial::IDS.each do |id|
      trial = RosterAdapterTrial.allocate
      trial.instance_variable_set(:@candidate, id)
      trial.instance_variable_set(:@generation_count, 0)
      records, calls = {}, []
      trial.define_singleton_method(:save) { |name, value| records[name] = value }
      trial.define_singleton_method(:cool_down) {}
      trial.define_singleton_method(:sample_resources) { {} }
      trial.define_singleton_method(:validate_resources!) { |*| true }
      trial.define_singleton_method(:adapter_http) do |path, payload, deadline:|
        calls << [path, payload, deadline]
        case path
        when "/apply-template" then {"prompt"=>"native fixture"}
        when "/tokenize" then {"tokens"=>[1, 2]}
        when "/v1/chat/completions"
          count = id == "gpt-oss-20b" ? 2 : 3
          {"model"=>id, "choices"=>[{"index"=>0,"finish_reason"=>"stop",
            "message"=>{"role"=>"assistant","content"=>"fixture final"}}],
            "usage"=>{"prompt_tokens"=>count,"completion_tokens"=>1,"total_tokens"=>count+1}}
        end
      end
      trial.probe
      assert_equal 6, calls.length
      assert_equal 2, records.keys.count { |k| k.start_with?("answer-") }
      assert_equal 4, records.keys.count { |k| k.start_with?("exchange-") }
      assert_equal 2, trial.instance_variable_get(:@generation_count)
      expected = id == "gpt-oss-20b" ? {"reasoning_effort"=>"low"} : {"enable_thinking"=>false}
      calls.select { |c| c[0] == "/v1/chat/completions" }.each do |_, payload, _|
        assert_equal expected, payload["chat_template_kwargs"]
        refute payload.key?("tools")
      end
      assert_equal DemandLoadedProbes, RosterAdapterTrial.instance_method(:run).owner
      assert_equal DemandLoadedProbes, RosterAdapterTrial.instance_method(:validate_resources!).owner
      assert_equal 600, RosterAdapterTrial::BUDGET_SECONDS
    end
  end
end
