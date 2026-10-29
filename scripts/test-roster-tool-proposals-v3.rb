# frozen_string_literal: true
require_relative 'test-roster-tool-proposals-v2'
require_relative '../lib/soul_core/roster_tool_proposal_v3_archive'
class RosterToolProposalV3Test < Minitest::Test
  G=SoulCore::RosterToolProposalV3Gateway
  A=SoulCore::RosterToolProposalV3Archive
  def setup
    @tmp=Dir.mktmpdir;@driver=RosterToolProposalTest::Driver.new
    @owner=SoulCore::RosterRuntimeOwner.new(leases:SoulCore::ModelRuntimeLeaseStore.new(root:@tmp),driver:@driver,clock:->{10.0})
    @memory=SoulCore::RosterMemoryContext.new(store:SoulCore::ConversationMemoryStore.new(root:@tmp));@calls=[]
    @skills=->(operation:,**){@calls<<operation;{'state'=>'complete','data'=>{'idle_seconds'=>240}}}
    @path=File.join(@tmp,'journal');G.create(path:@path,owner:@owner)
    @g=G.new(path:@path,owner:@owner,memory:@memory,skills:@skills,clock:->{10.0})
    @args={conversation_id:'chat',request_id:'r1',adapter:SoulCore::RosterChatAdapter.new(model:'gpt-oss-20b'),messages:[{'role'=>'user','content'=>'Which member is resident, and for how long?'}],deadline:100.0}
    @driver.reply=JSON.generate('soul_tool_proposal'=>{'tool'=>'roster_status','arguments'=>{}})
  end
  def teardown
    @g&.close;FileUtils.remove_entry(@tmp)
  end
  def rows = Dir.glob(@path+'/r-*.json').sort.map{|p|JSON.parse(File.read(p))}
  def alter(&block)
    original=@driver.method(:request)
    @driver.define_singleton_method(:request){|*args,**kw|r=original.call(*args,**kw);block.call(r) if args[1]=='/v1/chat/completions';r}
  end
  def test_channel_guidance_only_changes_gpt_oss
    i=SoulCore::RosterProposalFinalInstructions
    %w[gemma-4-26b-a4b qwen3.8-27b].each{|model|assert_equal SoulCore::RosterProposalInstructions::SYSTEM,i.for_model(model)}
    refute_equal SoulCore::RosterProposalInstructions::SYSTEM,i.for_model('gpt-oss-20b')
    assert_includes i.for_model('gpt-oss-20b'),'Use the final channel'
    refute_match(/<\|(?:start|channel|message|end)\|>/,i.for_model('gpt-oss-20b'))
    result=@g.complete(**@args);assert_equal 'roster.status',result.dig('execution','operation')
    payload=@driver.calls.find{|p,_|p=='/v1/chat/completions'}[1]
    assert_equal i::GPT_OSS,payload['messages'].first['content'];assert_equal @args[:adapter].native_controls,payload['chat_template_kwargs']
    assert_equal result.merge('replayed'=>true),@g.complete(**@args)
  end
  def test_empty_final_is_still_rejected_with_diagnostic_and_no_execution
    alter{|r|r['choices'][0]['message']['content']='';r['choices'][0]['message']['reasoning_content']='PRIVATE'}
    assert_raises(SoulCore::RosterChatAdapter::Unavailable){@g.complete(**@args)}
    assert_equal 'final_text_or_tool_request',rows[-2].dig('data','diagnostic','reason');assert_equal 0,rows[-2].dig('data','diagnostic','content_bytes')
    assert_empty @calls;refute_includes JSON.generate(rows),'PRIVATE';assert_raises(G::Refused){@g.complete(**@args)}
  end
  def test_v10_transition_preserves_proposal_and_diagnostic_failure
    src=File.join(@tmp,'v10');dst=File.join(@tmp,'v11');oldclass=SoulCore::RosterToolProposalV2Archive;oldclass.create(path:src,owner:@owner)
    old=oldclass.new(path:src,owner:@owner,memory:@memory,clock:->{10.0});original=old.method(:open_conversation);skills=@skills
    old.define_singleton_method(:open_conversation){|id|g=original.call(id);g.instance_variable_set(:@skills,skills);g}
    first=old.complete(**@args);alter{|r|r['choices'][0]['message']['content']=''}
    failed=@args.merge(conversation_id:'failed',request_id:'failed');assert_raises(SoulCore::RosterChatAdapter::Unavailable){old.complete(**failed)};old.close
    before=Dir.glob(src+'/**/*').select{|p|File.file?(p)}.to_h{|p|[p,Digest::SHA256.file(p).hexdigest]}
    A.transition(source:src,path:dst,owner:@owner,expected_manifest_sha256:A.digest(JSON.parse(File.read(src+'/roster.json'))))
    assert before.all?{|p,h|Digest::SHA256.file(p).hexdigest==h};store=A.new(path:dst,owner:@owner,memory:@memory,clock:->{10.0})
    calls=@driver.calls.length;assert_equal first.merge('replayed'=>true),store.complete(**@args);assert_raises(G::Refused){store.complete(**failed)};assert_equal calls,@driver.calls.length
    g=store.send(:open_conversation,'failed');g.send(:load!);assert_equal 'final_text_or_tool_request',g.instance_variable_get(:@attempts)['failed'].dig('response_rejected','diagnostic','reason');g.close
    assert_raises(G::Refused){store.complete(**@args.merge(conversation_id:'different'))}
  ensure
    old&.close;store&.close
  end
end
