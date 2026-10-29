# frozen_string_literal: true
require "minitest/autorun"
require_relative "run-workday-coexistence-trial"

class WorkdayCoexistenceTrialTest < Minitest::Test
  def test_loading_intervention_changes_only_gemma_flag
    WorkdayCoexistenceTrial::IDS.each do |id|
      baseline = WorkdayCoexistenceTrial.argv(id, "/synthetic/model.gguf")
      changed = WorkdayNoMmapTrial.argv(id, "/synthetic/model.gguf")
      assert_equal(id == "gemma-4-26b-a4b" ? baseline + ["--no-mmap"] : baseline, changed)
    end
    trial = WorkdayNoMmapTrial.allocate
    assert_equal 600, WorkdayNoMmapTrial::BUDGET_SECONDS
    assert_equal 240, trial.candidate_seconds
    assert_equal DemandLoadedProbes, trial.method(:validate_resources!).owner
    assert_equal 2048, trial.generation_limit
  end

  def test_bounded_settings_and_existing_guards
    trial = WorkdayCoexistenceTrial.allocate
    assert_equal 600, WorkdayCoexistenceTrial::BUDGET_SECONDS
    assert_equal 240, trial.candidate_seconds
    assert_equal 2, trial.max_generations
    assert_equal 2048, trial.generation_limit
    assert_equal DemandLoadedProbes, trial.method(:validate_resources!).owner
    assert_equal RosterInterfaceTrial::IDS, WorkdayCoexistenceTrial::IDS
  end

  def test_two_requests_and_native_economy_settings_without_inference
    WorkdayCoexistenceTrial::IDS.each do |id|
      trial = WorkdayCoexistenceTrial.allocate
      trial.instance_variable_set(:@candidate, id)
      captured = []
      trial.define_singleton_method(:collect) { |name, input| captured << [name, input, native_kwargs] }
      trial.probe
      assert_equal %w[dispatch cache], captured.map(&:first)
      expected = id == "gpt-oss-20b" ? {"reasoning_effort"=>"low"} : {"enable_thinking"=>false}
      assert captured.all? { |_, _, kwargs| kwargs == expected }
    end
  end
end
