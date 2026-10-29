require 'minitest/autorun'
require_relative 'run-video-editing-long-pilot'
class LongPilotTest < Minitest::Test
  def template
    REXML::Document.new(File.read(File.join(VideoEditingLongPilot::INPUT,'pilot.kdenlive')))
  end
  def test_original_bounds_remain_fixed
    assert_equal 600,VideoEditingPilot::OVERALL_SECONDS
    assert_equal 120,VideoEditingPilot::CHILD_SECONDS
    assert_equal 1200,VideoEditingLongPilot::OVERALL_SECONDS
    assert_equal 600,VideoEditingLongPilot::CHILD_SECONDS
  end
  def test_native_time_and_frames
    assert_equal 149,VideoEditingLongPilot.frame('00:00:04.967')
    assert_equal 149,VideoEditingLongPilot.frame('149')
    assert_raises(VideoEditingPilot::Refused){VideoEditingLongPilot.frame('bad')}
  end
  def test_template_and_rejected_mutations
    assert VideoEditingLongPilot.validate_template!(template)
    ['gap','caption','resource','mixer','profile'].each do |mutation|
      d=template
      case mutation
      when 'gap';d.root.elements["playlist[@id='playlist0']"].add_element('blank',{'length'=>'37'})
      when 'caption';d.root.elements["chain[@id='review_clip1']/property[@name='kdenlive:id']"].text='5'
      when 'resource';d.root.elements["chain[@id='review_source']/property[@name='resource']"].text='/tmp/other.mkv'
      when 'mixer';d.root.elements["playlist[@id='main_bin']/property[@name='kdenlive:docproperties.audioChannels']"].text='1'
      when 'profile';d.root.elements['profile'].attributes['width']='1920'
      end
      assert_raises(VideoEditingPilot::Refused,mutation){VideoEditingLongPilot.validate_template!(d)}
    end
  end
  def test_long_project_prepared_before_first_command
    Dir.mktmpdir('a2-test-') do |root|
      File.chmod(0700,root)
      p=VideoEditingLongPilot.new(root)
      p.define_singleton_method(:command){|*_|raise VideoEditingPilot::Refused,'test boundary: no renderer'}
      assert_raises(VideoEditingPilot::Refused){p.run}
      d=REXML::Document.new(File.read(File.join(root,'pilot.kdenlive')))
      %w[playlist0 playlist4].each do |id|
        list=d.root.elements["playlist[@id='#{id}']"]
        assert_equal 240,list.get_elements('entry').length
        assert_equal 28800,list.get_elements('entry').sum{|e|VideoEditingLongPilot.frame(e.attributes['out'])-VideoEditingLongPilot.frame(e.attributes['in'])+1}
        assert_empty list.get_elements('blank')
      end
      assert_equal 'failed',JSON.parse(File.read(File.join(root,'failure.json')))['state']
      assert_raises(VideoEditingPilot::Refused){p.run}
    end
  end
end
