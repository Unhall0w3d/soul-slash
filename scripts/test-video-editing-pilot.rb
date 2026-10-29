# frozen_string_literal: true
require 'minitest/autorun'
require_relative 'run-video-editing-pilot'
class VideoEditingPilotTest < Minitest::Test
  P=VideoEditingPilot
  def setup
    @dir=Dir.mktmpdir('video-pilot-test-');@calls=0
    fake=Object.new;fake.define_singleton_method(:run){|*args,**kw|raise 'execution forbidden in boundary test'}
    @pilot=P.new(@dir,runner:fake)
    %w[original.mkv original-backup.mkv].each{|f|File.write(File.join(@dir,f),'synthetic source')}
    @plan={'version'=>1,'fps'=>30,'source'=>'original.mkv','source_sha256'=>P.digest(File.join(@dir,'original.mkv')),'cuts'=>[{'in'=>30,'out'=>150,'title'=>'CUT 1'},{'in'=>210,'out'=>330,'title'=>'CUT 2'}]}
    File.write(File.join(@dir,'plan.json'),JSON.generate(@plan));manifest
  end
  def manifest
    File.write(File.join(@dir,'manifest.json'),JSON.generate('source_sha256'=>@plan['source_sha256'],'plan_sha256'=>P.digest(File.join(@dir,'plan.json'))))
  end
  def teardown = FileUtils.remove_entry(@dir)
  def test_exact_plan_and_xml_escaping
    assert_equal @plan,@pilot.checked_plan;@pilot.project(@plan)
    xml=REXML::Document.new(File.read(File.join(@dir,'pilot.kdenlive')))
    assert_equal ['original.mkv']*3,REXML::XPath.match(xml,"//chain/property[@name='resource']").map(&:text)
    assert_equal '1',REXML::XPath.first(xml,"//playlist[@id='main_bin']/property[@name='xml_retain']").text
    assert_equal 'main_bin',xml.root.attributes['producer'];assert_equal 2,REXML::XPath.match(xml,"//playlist[@id='v0']/entry").size
    assert_equal %w[30 210],REXML::XPath.match(xml,"//playlist[@id='v0']/entry").map{|e|e.attributes['in']}
    assert_equal %w[149 329],REXML::XPath.match(xml,"//playlist[@id='v0']/entry").map{|e|e.attributes['out']}
  end
  def test_invalid_range_type_and_fields
    [->(p){p['source']='../../Downloads/file.md'},->(p){p['source']='https://example.com/x'},->(p){p['cuts'][0]['in']='30'},->(p){p['cuts'][0]['in']=-1},->(p){p['cuts'][0]['out']=361},->(p){p['cuts'][0]['title']='<script>'},->(p){p['command']='touch x'},->(p){p['cuts'][0]['out']=151}].each do |mutate|
      candidate=Marshal.load(Marshal.dump(@plan));mutate.call(candidate);assert_raises(P::Refused){P.validate_plan!(candidate)}
    end
  end
  def test_source_drift
    File.write(File.join(@dir,'original.mkv'),'changed');assert_raises(P::Refused){@pilot.render}
  end
  def test_plan_drift
    File.write(File.join(@dir,'plan.json'),JSON.pretty_generate(@plan));assert_raises(P::Refused){@pilot.render}
  end
  def test_existing_output_refused
    File.write(File.join(@dir,'preview.mp4'),'existing');assert_raises(P::Refused){@pilot.render};assert_equal 'existing',File.read(File.join(@dir,'preview.mp4'))
  end
  def test_failed_attempt_cannot_retry
    File.write(File.join(@dir,'intent.json'),'{}');assert_raises(P::Refused){@pilot.render};assert_raises(P::Refused){@pilot.render}
  end
  def test_symlink_refused
    File.symlink('/etc/hosts',File.join(@dir,'preview.mp4'));assert_raises(P::Refused){@pilot.render}
  end
  def test_replay_binds_plan_and_artifacts
    hashes=P::OUTPUTS.to_h{|n|File.write(File.join(@dir,n),'retained');[n,P.digest(File.join(@dir,n))]}
    File.write(File.join(@dir,'receipt.json'),JSON.generate('state'=>'complete','plan_sha256'=>P.digest(File.join(@dir,'plan.json')),'outputs'=>hashes))
    assert @pilot.render['replayed'];File.write(File.join(@dir,'preview.mp4'),'changed');assert_raises(P::Refused){@pilot.render}
  end
  def test_actual_timeout_reaps_child
    r=SoulCore::BoundedCommandRunner.new.run(RbConfig.ruby,'-e','$stdout.sync=true;puts Process.pid;sleep 30',timeout_seconds:0.25)
    assert_equal 'timeout',r.status;refute File.exist?("/proc/#{Integer(r.stdout.strip)}")
  end
  def test_actual_monitor_cancellation_reaps_child
    pid=nil;r=SoulCore::BoundedCommandRunner.new.run(RbConfig.ruby,'-e','sleep 30',timeout_seconds:2,monitor:->(p){pid=p;raise P::Refused,'synthetic cancellation'})
    assert_equal 'guard_refused',r.status;refute File.exist?("/proc/#{pid}")
  end
  def test_path_traversal_refused
    ['.','..','../file','x/y'].each{|name|assert_raises(P::Refused){@pilot.path(name)}}
  end
  def test_setup_failure_has_terminal_receipt
    @pilot.define_singleton_method(:setup){raise P::Refused,'synthetic setup failure'}
    assert_raises(P::Refused){@pilot.run}
    assert_equal 'failed',JSON.parse(File.read(File.join(@dir,'failure.json')))['state']
  end
  def test_interrupt_reaps_child
    pid=nil
    assert_raises(Interrupt){SoulCore::BoundedCommandRunner.new.run(RbConfig.ruby,'-e','sleep 30',timeout_seconds:2,monitor:->(p){pid=p;raise Interrupt})}
    refute File.exist?("/proc/#{pid}")
  end
  def test_replay_rejects_rebound_plan
    hashes=P::OUTPUTS.to_h{|n|File.write(File.join(@dir,n),'retained');[n,P.digest(File.join(@dir,n))]}
    File.write(File.join(@dir,'receipt.json'),JSON.generate('state'=>'complete','plan_sha256'=>P.digest(File.join(@dir,'plan.json')),'outputs'=>hashes))
    @plan['cuts'][0]['title']='Changed';File.write(File.join(@dir,'plan.json'),JSON.generate(@plan));manifest
    assert_raises(P::Refused){@pilot.render}
  end

  def test_editor_background_and_source_identity
    @pilot.project(@plan,filename:'editor-review.kdenlive')
    xml=REXML::Document.new(File.read(File.join(@dir,'editor-review.kdenlive')))
    black=REXML::XPath.first(xml,"//producer[@id='black_track']")
    assert_equal 'black_track',REXML::XPath.first(black,"property[@name='kdenlive:playlistid']").text
    assert_equal 'black_track',REXML::XPath.first(xml,"//tractor[@id='sequence']/track").attributes['producer']
    ids=REXML::XPath.match(xml,"//chain/property[@name='kdenlive:control_uuid']").map(&:text)
    assert_equal 3,ids.size
    assert_equal 1,ids.uniq.size
    assert_match(/\A\{[0-9a-f-]{36}\}\z/,ids.first)
    refute File.exist?(File.join(@dir,'pilot.kdenlive'))
  end

end
