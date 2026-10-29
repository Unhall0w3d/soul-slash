require 'minitest/autorun'
require 'yaml'
require_relative '../lib/soul_core/roster_librechat_presentation'
class RosterLibreChatPresentationTest < Minitest::Test
  P=SoulCore::RosterLibreChatPresentation
  def test_only_presentation_changes_and_idempotence
    config=YAML.safe_load(File.read(File.expand_path('../docs/examples/roster-librechat-service.yaml',__dir__)))
    trial={'name'=>'soul-roster-gpt-oss-trial','label'=>'Old GPT','preset'=>{'endpoint'=>'OldEndpoint','model'=>'gpt-oss-20b'}}
    config['modelSpecs']['list'].unshift(trial);before=Marshal.load(Marshal.dump(config));updated=P.update(config)
    assert_equal before,config
    assert_equal config['endpoints'],updated['endpoints']
    assert_equal 'soul-member-gpt-oss',updated['modelSpecs']['list'][0]['name']
    config['modelSpecs']['list'].each do |old|
      new=updated['modelSpecs']['list'].find{|r|r['name']==old['name']}
      assert_equal old.reject{|k,_|%w[label description].include?(k)},new.reject{|k,_|%w[label description].include?(k)}
    end
    assert_equal updated,P.update(updated)
    assert updated['modelSpecs']['list'].last['label'].start_with?('Manual trial — ')
  end
  def test_missing_or_rebound_member_refuses
    config={'modelSpecs'=>{'list'=>[]}}
    assert_raises(ArgumentError){P.update(config)}
  end
  def test_retire_only_exact_trial_presets_without_rebinding
    config=YAML.safe_load(File.read(File.expand_path('../docs/examples/roster-librechat-service.yaml',__dir__)))
    custom={'name'=>'other-trial','label'=>'Keep me','preset'=>{'endpoint'=>'Other','model'=>'custom'}}
    config['modelSpecs']['list'] << custom
    retained=Marshal.load(Marshal.dump(config))
    P::TRIALS.each{|name|config['modelSpecs']['list'] << {'name'=>name,'label'=>name,'preset'=>{'endpoint'=>'OldEndpoint'}}}
    original=Marshal.load(Marshal.dump(config))
    result=P.without_trial_presets(config)
    assert_equal retained,result
    assert_equal original,config
    assert_equal result,P.without_trial_presets(result)
    duplicate=Marshal.load(Marshal.dump(config));duplicate['modelSpecs']['list'] << custom
    assert_raises(ArgumentError){P.without_trial_presets(duplicate)}
    config['modelSpecs']['list'].first['preset']['endpoint']='Foreign'
    assert_raises(ArgumentError){P.without_trial_presets(config)}
  end
end
