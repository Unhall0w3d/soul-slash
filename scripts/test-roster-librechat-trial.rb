# frozen_string_literal: true
require "minitest/autorun"
require_relative "roster-librechat-trial"
require_relative "roster-desktop-librechat-trial"

class RosterLibreChatTrialTest < Minitest::Test
  def test_gemma_desktop_placement_and_model_boundary
    base=RosterDesktopLibreChatTrial.argv("gemma-4-26b-a4b","/fixture/model")
    expected=base.dup
    expected[expected.index("--tensor-split")+1]="1,1"
    assert_equal expected,GemmaDesktopLibreChatTrial.argv("gemma-4-26b-a4b","/fixture/model")
    assert_equal RosterDesktopLibreChatTrial.argv("gpt-oss-20b","/fixture/model"),GemmaDesktopLibreChatTrial.argv("gpt-oss-20b","/fixture/model")
    assert_equal 900,GemmaDesktopLibreChatTrial::BUDGET_SECONDS
    trial=GemmaDesktopLibreChatTrial.new
    assert_equal SoulCore::RosterChatAdapter::MODELS.sort,trial.roster_binding.keys.sort
    refute_equal RosterDesktopLibreChatTrial.new.roster_binding,trial.roster_binding
    assert_raises(RosterDesktopLibreChatTrial::GuardStopped) do
      trial.roster_start(adapter:SoulCore::RosterChatAdapter.new(model:"gpt-oss-20b"),ownership_id:"refused",deadline:999,cancel:-> {false})
    end
    assert_equal "refused",trial.instance_variable_get(:@ownership)
  end
  def test_desktop_trial_binding_and_guard_translation
    trial=RosterDesktopLibreChatTrial.new
    assert_equal SoulCore::RosterChatAdapter::MODELS.sort,trial.roster_binding.keys.sort
    assert_equal 900,RosterDesktopLibreChatTrial::BUDGET_SECONDS
    assert_equal 600,RosterLibreChatTrial::BUDGET_SECONDS
    assert_equal RosterLibreChatTrial.argv("gpt-oss-20b","/fixture/model"),RosterDesktopLibreChatTrial.argv("gpt-oss-20b","/fixture/model")
    Dir.mktmpdir do |root|
      trial.instance_variable_set(:@root_output,root)
      trial.define_singleton_method(:roster_bounded) { |_| raise ChatReplacementTrial::Abort,"fixture resource refusal" }
      begin
        assert_raises(RosterDesktopLibreChatTrial::GuardStopped) do
          trial.roster_start(adapter:SoulCore::RosterChatAdapter.new(model:"gpt-oss-20b"),ownership_id:"fixture",deadline:999,cancel:-> {false})
        end
        record=JSON.parse(File.read(File.join(root,"fixture/startup-guard-refusal.json")))
        assert_equal "fixture resource refusal",record["reason"]
      ensure
        trial.stop_cancel_watcher
      end
    end
  end
  class Fixture < RosterLibreChatTrial
    attr_reader :events
    def initialize(path)
      super()
      @path=path
      @events=[]
    end
    def create_output = @path
    def protected_state = {"unit"=>"ActiveState=inactive", "amd_units"=>"ActiveState=inactive\nActiveState=inactive\n"}
    def port_closed? = true
    def start_telemetry = raise(Abort,"fixture telemetry failure")
    def stop_telemetry = @events << :telemetry_stopped
    def cleanup_owned_runtime = @events << :runtime_cleaned
  end

  def test_early_failure_receipt_and_cleanup
    Dir.mktmpdir do |root|
      File.chmod(0700,root)
      key=File.join(root,"key")
      File.write(key,"f"*64,perm:0600)
      trial=Fixture.new(root)
      refute trial.serve(key_file:key)
      assert_equal [:runtime_cleaned,:telemetry_stopped],trial.events
      receipt=JSON.parse(File.read(File.join(root,"receipt.json")))
      assert_equal "failed",receipt["state"]
      assert_includes receipt["error"],"fixture telemetry failure"
      refute File.exist?(File.join(root,"journal"))
    end
  end

  def test_disconnect_interrupts_wait_and_watcher_joins
    trial=RosterLibreChatTrial.new
    assert_raises(SoulCore::RosterChatExchange::Stopped) do
      begin
        trial.start_cancel_watcher(-> {true})
        sleep 2
      ensure
        trial.stop_cancel_watcher
      end
    end
    assert_nil trial.instance_variable_get(:@cancel_watcher)
  end

  def test_no_late_cancellation_after_teardown_begins
    trial=RosterLibreChatTrial.new
    canceled=false
    trial.start_cancel_watcher(-> {canceled})
    trial.stop_cancel_watcher
    canceled=true
    sleep 0.15
    assert_nil trial.instance_variable_get(:@cancel_watcher)
  end
end
