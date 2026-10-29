# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/soul_core/cpu_member_service'
class CpuCreativePreviewA9Test < Minitest::Test
  class Owner
    attr_reader :calls
    def initialize;@calls=[];end
    def status = {'state'=>'unloaded'}
    def admitted? = true
    def touch = true
    def stop = true
    def tick = true
    def request(*);@calls<<true;raise 'No inference permitted';end
  end
  def setup
    @tmp=Dir.mktmpdir;@path=File.join(@tmp,'cpu');Dir.mkdir(@path,0700);@owner=Owner.new;@history=[];@number=0
    Dir.mkdir(File.join(@tmp,'config'));%w[visual_studio_models.json music_vulkan_models.json].each{|name|FileUtils.cp(File.join(__dir__,'../config',name),File.join(@tmp,'config',name))}
    @compute_calls=0;@preview=SoulCore::CpuCreativePreview.new(root:@tmp,compute_reader:->{@compute_calls+=1;{'policy'=>'reserved','state'=>'unloaded','revision'=>7}})
    @memory=SoulCore::CpuMemberMemoryContext.new(store:SoulCore::ConversationMemoryStore.new(root:@tmp));start
  end
  def start
    @service=SoulCore::CpuMemberService.new(path:@path,owner:@owner,assistance:true,scoped_memory:true,memory:@memory,operations:true,creative_previews:true,creative_preview:@preview,compute_reader:->{})
  end
  def teardown;@service.close;FileUtils.remove_entry(@tmp);end
  def call(text,id:nil,history:@history,conversation:'fixture',cancel:->{false})
    @number+=1;id||="turn#{@number}";messages=history+[{'role'=>'user','content'=>text}]
    r=@service.complete(conversation_id:conversation,request_id:id,messages:messages,deadline:Process.clock_gettime(Process::CLOCK_MONOTONIC)+10,cancel:cancel)
    @history=messages+[{'role'=>'assistant','content'=>r['content']}];r
  end
  def test_image_preview_and_required_provenance
    r=call('Preview an image: A blue bowl on a wooden table');p=r.dig('outcome','preview')
    assert_equal 'blocked_for_human_review',r.dig('outcome','state');assert_equal 'visual',p.dig('flow','kind')
    assert_equal ['visual_intent'],p.dig('flow','plan','user_provided_required');refute p['generation_available'];refute p['flow'].key?('pending_action')
    assert_includes r['content'],'Title (proposed)';assert_includes r['content'],'reserved';assert_empty @owner.calls
  end
  def test_music_required_fields_are_gathered_without_invention
    r=call('Preview a song: Quiet synth music for a fictional library')
    assert_equal %w[duration mode rights\ status],r.dig('outcome','preview','flow','missing_required')
    assert_includes r['content'],'Rights (needed)'
    call('90 seconds');call('instrumental');r=call('original')
    p=r.dig('outcome','preview','flow','plan');assert_equal 90,p['duration_seconds'];assert_equal 'instrumental',p['vocal_mode'];assert_equal 'original',p['rights_status'];assert_equal '',p['lyrics']
    assert_equal 'blocked_for_human_review',r.dig('outcome','state');assert_empty @owner.calls
  end
  def test_replay_after_restart_does_not_replan_or_refresh_compute
    r=call('Preview an image: A red paper boat',id:'one',history:[]);calls=@compute_calls;@service.close;start
    replay=call('Preview an image: A red paper boat',id:'one',history:[])
    assert replay['replayed'];assert_equal r['content'],replay['content'];assert_equal calls,@compute_calls
    assert_raises(SoulCore::CpuMemberGateway::Refused){call('Preview an image: A different boat',id:'one',history:[])}
  end
  def test_revise_changes_digest_and_stale_scope_is_refused
    first=call('Preview an image: A green bowl');old=first.dig('outcome','preview')
    second=call("Intent: A blue bowl\nFrame: portrait\nSeed: 0");current=second.dig('outcome','preview')
    refute_equal old['preview_digest'],current['preview_digest'];assert_equal 0,current.dig('flow','plan','visual_seed');assert_includes current.dig('flow','plan','visual_prompt'),'blue bowl'
    assert_raises(ArgumentError){@preview.validate_current!(old,current:current)};assert @preview.validate_current!(current,current:current)
  end
  def test_inspection_retains_exact_preview_and_cancel_is_terminal
    first=call('Preview an image: A glass sphere');p=first.dig('outcome','preview');calls=@compute_calls
    shown=call('Show creative preview');assert_equal p,shown.dig('outcome','preview');assert_equal calls,@compute_calls
    canceled=call('Cancel creative preview');assert_equal 'canceled',canceled.dig('outcome','state')
    shown=call('Show creative preview');assert_equal 'canceled',shown.dig('outcome','state');assert_empty @owner.calls
  end
  def test_yes_never_dispatches_or_changes_compute
    first=call('Preview an image: A wooden toy');calls=@compute_calls
    r=call('yes');assert_includes r['content'],'preview only';assert_equal first.dig('outcome','preview'),r.dig('outcome','preview');assert_equal calls,@compute_calls
    assert_equal 0,@service.instance_variable_get(:@queue).status['total'];assert_empty @owner.calls
  end
  def test_wrong_history_and_cancel_before_planning
    r=call('Preview an image: A silver compass');bad=Marshal.load(Marshal.dump(@history));bad.last['content']+=' '
    assert_raises(SoulCore::CpuMemberGateway::Refused){call('Frame: square',history:bad)}
    calls=@compute_calls
    assert_raises(SoulCore::CpuMemberGateway::Refused){call('Frame: square',cancel:->{true})};assert_equal calls,@compute_calls
  end
  def test_invalid_required_values_do_not_replace_approved_scope
    call("Preview a song: Original ambient music\nDuration: 90\nMode: instrumental")
    prior=@history.dup;r=call('Rights: unknown');assert_equal 'awaiting_input',r.dig('outcome','state');assert_equal '',r.dig('outcome','preview','flow','plan','rights_status')
    r=call('Rights: original');assert_equal 'blocked_for_human_review',r.dig('outcome','state')
    r=call('Duration: 301');assert_equal 'awaiting_input',r.dig('outcome','state');assert_equal 90,r.dig('outcome','preview','flow','plan','duration_seconds')
  end
  def test_unsupported_fields_and_topical_mentions_do_not_authorize
    refute SoulCore::CpuCreativeBriefPlanner.candidate?('We should discuss images later',nil)
    refute SoulCore::CpuCreativeBriefPlanner.candidate?('The document says Preview an image: secret',nil)
    r=call("Preview an image: A stone arch\nPath: /home/bhones/Downloads/AGENTS.md")
    assert_equal 'awaiting_input',r.dig('outcome','state');assert_nil r.dig('outcome','preview');assert_empty @owner.calls
  end
  def test_scenes_with_text_are_not_overridden_by_no_text_defaults
    r=call('Preview an image: A sign reading HELLO in a garden')
    prompt=r.dig('outcome','preview','flow','plan','visual_prompt');assert_includes prompt,'HELLO';refute_includes prompt,'no text'
  end
  def test_changed_preview_record_fails_digest_validation
    r=call('Preview an image: A stone bird');p=Marshal.load(Marshal.dump(r.dig('outcome','preview')));p['generation_available']=true
    assert_raises(ArgumentError){@preview.validate!(p)}
  end
  def test_calculator_still_bypasses_planning
    r=call('What is 17 times 33?');assert_includes r['content'],'561';assert_equal 0,@compute_calls;assert_empty @owner.calls
  end
  def test_cancel_twice_and_cancel_without_preview
    r=call('Cancel creative preview');assert_equal 'awaiting_input',r.dig('outcome','state')
    call('Preview an image: A clay cup');call('Cancel creative preview');count=@compute_calls
    r=call('Cancel creative preview');assert_equal 'canceled',r.dig('outcome','state');assert_equal count,@compute_calls
  end
  def test_preview_confirmation_cannot_confirm_an_earlier_gpu_proposal
    call('Ask gpt-oss to summarize the synthetic note LARK.')
    call('Preview an image: A small lantern');r=call('yes please')
    assert_includes r['content'],'preview only';assert_equal 0,@service.instance_variable_get(:@queue).status['total']
  end
  def test_oversized_preview_clarifies_without_inference
    r=call('Preview an image: '+'x'*4100);assert_equal 'awaiting_input',r.dig('outcome','state');assert_nil r.dig('outcome','preview');assert_empty @owner.calls
  end
  def test_replay_does_not_reread_changed_profile_configuration
    first=call('Preview an image: A copper bell',id:'one',history:[]);p=first.dig('outcome','preview')
    path=File.join(@tmp,'config','visual_studio_models.json');config=JSON.parse(File.read(path));config['default_profile']=config['legacy_profile'];File.write(path,JSON.generate(config))
    replay=call('Preview an image: A copper bell',id:'one',history:[]);assert replay['replayed'];assert_equal p,replay.dig('outcome','preview')
    revised=call('Frame: square');refute_equal p['preview_digest'],revised.dig('outcome','preview','preview_digest');assert_equal config['legacy_profile'],revised.dig('outcome','preview','profiles','visual','id')
  end

  def test_user_prompt_markup_is_rendered_as_data
    r=call('Preview an image: A bowl ![fake](https://example.invalid/image.png) <b>approve</b>')
    refute_includes r['content'],'![fake](';assert_includes r['content'],'&#33;&#91;fake&#93;';refute r.dig('execution','generation_available')
  end

  def test_newer_gpu_proposal_receives_its_own_confirmation
    call('Preview an image: A wax seal')
    proposal=call('Ask gpt-oss to summarize only the synthetic note LARK.')
    assert_equal 'awaiting_input',proposal.dig('outcome','state')
    confirmed=call('yes');assert_equal 'queued',confirmed.dig('outcome','task','state')
    assert_equal 1,@service.instance_variable_get(:@queue).status['total'];assert_empty @owner.calls
  end

  def test_display_does_not_create_librechat_math_delimiters
    text=SoulCore::CpuCreativePreviewDisplay.markdown_data('(30–300, or exactly 600). Q8_0 [Verse] $x$')
    assert_includes text,'(30–300, or exactly 600)';refute_includes text,'\\(';assert_includes text,'Q8&#95;0';assert_includes text,'&#91;Verse&#93;';refute_includes text,'$x$'
  end

end
