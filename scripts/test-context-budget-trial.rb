# frozen_string_literal: true
require "minitest/autorun"
require_relative "run-context-budget-trial"

class ContextBudgetTrialTest < Minitest::Test
  def test_startup_identity_requires_exact_trial_context_and_other_identity_fields
    [WorkdayCoexistenceTrial,ContextBudgetTrial].each do |klass|
      trial=klass.allocate
      trial.instance_variable_set(:@model,"/synthetic/model.gguf")
      trial.instance_variable_set(:@candidate,"gpt-oss-20b")
      props={"model_path"=>"/synthetic/model.gguf","model_alias"=>"gpt-oss-20b",
        "build_info"=>ChatReplacementTrial::BUILD,"total_slots"=>1,
        "default_generation_settings"=>{"n_ctx"=>trial.context_limit}}
      assert trial.send(:server_identity_matches?,props)
      refute trial.send(:server_identity_matches?,props.merge("default_generation_settings"=>{"n_ctx"=>trial.context_limit==8192 ? 4096 : 8192}))
      %w[model_path model_alias build_info total_slots].each do |key|
        refute trial.send(:server_identity_matches?,props.merge(key=>"wrong"))
      end
    end
  end

  def test_generation_uses_declared_context_and_timeout
    trial = ContextBudgetTrial.allocate
    trial.instance_variable_set(:@generation_count,0)
    trial.instance_variable_set(:@candidate,"gemma-4-26b-a4b")
    trial.instance_variable_set(:@condition,"deliberate")
    trial.instance_variable_set(:@asset,{})
    trial.define_singleton_method(:pace_resources) { |**| }
    trial.define_singleton_method(:save) { |*| }
    token_count = 4000
    trial.define_singleton_method(:json_http) { |path,*| path=="/apply-template" ? {"prompt"=>"synthetic"} : {"tokens"=>Array.new(token_count,1)} }
    timeout_seen = nil
    response = Struct.new(:code,:body).new("200","{}")
    trial.define_singleton_method(:http) { |path,payload,seconds:| timeout_seen=seconds; response }
    payload={"model"=>"gemma-4-26b-a4b","messages"=>[],"max_tokens"=>4096}
    assert_equal response,trial.generate(payload).first
    assert_equal 180,timeout_seen
    token_count=4065
    error=assert_raises(ChatReplacementTrial::Abort) { trial.generate(payload) }
    assert_match(/context headroom/,error.message)
  end

  def test_defaults_remain_unchanged
    old = WorkdayCoexistenceTrial.allocate
    assert_equal 4096, old.context_limit
    assert_equal 120, old.request_seconds
  end

  def test_declared_limits_match_launch
    trial = ContextBudgetTrial.allocate
    assert_equal 8192, trial.context_limit
    assert_equal 180, trial.request_seconds
    assert_equal 2640, ContextBudgetTrial::BUDGET_SECONDS
    assert_equal 1200, trial.candidate_seconds
    assert_equal DemandLoadedProbes, trial.method(:validate_resources!).owner
    ContextBudgetTrial::IDS.each do |id|
      a = ContextBudgetTrial.argv(id, "/synthetic/model.gguf")
      assert_equal "8192", a[a.index("--ctx-size")+1]
      assert_equal "4096", a[a.index("--predict")+1]
      assert_equal(id.start_with?("gemma"), a.include?("--no-mmap"))
    end
  end

  def test_frozen_design_without_inference
    trial = ContextBudgetTrial.allocate
    trial.instance_variable_set(:@candidate,"gemma-4-26b-a4b")
    rows=[]
    trial.define_singleton_method(:collect) { |name,input| rows << [name,input,generation_limit,native_kwargs,@paired_seed] }
    trial.probe
    assert_equal 12, rows.size
    assert_equal({2048=>4,4096=>4,1024=>4},rows.group_by { |r|r[2] }.transform_values(&:size))
    assert rows.first(8).all? { |r|r[3]=={"enable_thinking"=>true} }
    assert rows.last(4).all? { |r|r[3]=={"enable_thinking"=>false} }
    assert_equal rows[0][4], rows[2][4]
    short=ContextBudgetTrial.source_task(expanded:false)
    long=ContextBudgetTrial.source_task(expanded:true)
    assert_equal short["required"],long["required"]
    assert_operator long["text"].bytesize,:>,short["text"].bytesize
    assert_operator long["text"].bytesize,:<,30_000
  end
end
