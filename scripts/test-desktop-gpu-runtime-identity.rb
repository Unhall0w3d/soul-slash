# frozen_string_literal: true
require 'minitest/autorun'
require_relative 'support/roster_service_driver'
class DesktopGpuRuntimeIdentityTest < Minitest::Test
  def test_exact_runtime_replacement_preserves_other_identity_and_capacity_refusals
    allowed=SoulCore::DesktopGpuAllowances.holders
    target='/home/bhones/.config/Codex/artifact-sessions/runtime-generations/generation-0HlJhs/runtime/bin/node'
    assert_includes allowed,[Process.uid,target]
    refute_includes allowed,[Process.uid,target.sub('0HlJhs','unknown')]
    refute_includes allowed,[Process.uid+1,target]
    sample={'clients'=>[{'bytes'=>12288,'holders'=>[{'pid'=>123,'uid'=>Process.uid,'exe'=>target}]}]}
    assert DesktopCoexistenceTrial.validate_desktop_amd!(sample,owned_pid:nil,allowed:allowed)
    sample['clients'][0]['bytes']=7*1024**3
    assert_raises(ChatReplacementTrial::Abort){DesktopCoexistenceTrial.validate_desktop_amd!(sample,owned_pid:nil,allowed:allowed)}
    sample['clients'][0]['bytes']=12288;sample['clients'][0]['holders'][0]['exe']=target.sub('0HlJhs','unknown')
    assert_raises(ChatReplacementTrial::Abort){DesktopCoexistenceTrial.validate_desktop_amd!(sample,owned_pid:nil,allowed:allowed)}
  end
end
