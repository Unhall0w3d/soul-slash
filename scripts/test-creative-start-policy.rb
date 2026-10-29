require 'minitest/autorun'
require_relative 'support/creative_start_policy'
class CreativeStartPolicyTest < Minitest::Test
  def test_workday_is_separate_from_cold
    t={'edge'=>42,'junction'=>55,'mem'=>44}
    assert CreativeStartPolicy.validate!(t,mode:'workday-warm')
    assert_raises(RuntimeError){CreativeStartPolicy.validate!(t,mode:'cold')}
    assert CreativeStartPolicy.validate!(t.merge('junction'=>54),mode:'cold')
  end
  def test_warm_boundaries_and_invalid_readings_fail_closed
    t={'edge'=>42,'junction'=>55,'mem'=>44}
    {'edge'=>65,'junction'=>75,'mem'=>70}.each do |k,v|
      [v,100,Float::NAN,-1,'42'].each do |bad|
        assert_raises(RuntimeError){CreativeStartPolicy.validate!(t.merge(k=>bad),mode:'workday-warm')}
      end
    end
    assert_raises(KeyError){CreativeStartPolicy.validate!({},mode:'workday-warm')}
    assert_raises(ArgumentError){CreativeStartPolicy.validate!(t,mode:'unknown')}
  end
end
