# frozen_string_literal: true
require "minitest/autorun"
require_relative "run-qwen38-journal-trial"
class Qwen38JournalTrialTest < Minitest::Test
  def test_isolated_bindings_and_placements
    trial=Qwen38JournalTrial.allocate
    assert_equal %w[gpt-oss-20b gemma-4-26b-a4b qwen3.8-27b],trial.roster_ids
    assert_equal trial.roster_ids.sort,trial.roster_binding.keys.sort
    trial.roster_ids.each do |id|
      args=Qwen38JournalTrial.argv(id,trial.roster_assets.fetch(id).fetch("path"))
      assert_equal "127.0.0.1",args[args.index("--host")+1]
      assert_equal "4096",args[args.index("--ctx-size")+1]
      assert_equal id=="gemma-4-26b-a4b" ? "1,1" : "2,1",args[args.index("--tensor-split")+1]
      assert_equal id,trial.roster_adapter(id).model
    end
    assert_equal 600,Qwen38JournalTrial::BUDGET_SECONDS
    assert_equal RosterJournalTrial,Qwen38JournalTrial.instance_method(:run).owner
    assert_equal ChatReplacementTrial,Qwen38JournalTrial.instance_method(:cleanup_owned_runtime).owner
    refute_includes SoulCore::RosterChatAdapter::MODELS,"qwen3.8-27b"
  end
end
