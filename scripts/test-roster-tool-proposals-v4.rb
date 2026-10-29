# frozen_string_literal: true
require_relative 'test-roster-tool-proposals-v3'
require_relative '../lib/soul_core/roster_tool_proposal_v4_archive'
require_relative 'run-chat-replacement-trial'
class RosterToolProposalV4Test < Minitest::Test
  G=SoulCore::RosterToolProposalV4Gateway
  A=SoulCore::RosterToolProposalV4Archive
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
  def test_native_payload_binding_and_proposal_replay
    r=@g.complete(**@args);assert_equal 'roster.status',r.dig('execution','operation')
    template=@driver.calls.find{|p,_|p=='/apply-template'}[1];payload=@driver.calls.find{|p,_|p=='/v1/chat/completions'}[1]
    assert_equal SoulCore::RosterGptFinalFormat.response_format,payload['response_format'];assert_equal payload['response_format'],template['response_format']
    intent=rows.find{|r|r['state']=='generation_intent'}['data'];assert_equal Digest::SHA256.hexdigest(JSON.generate(payload)),intent['request_sha256']
    assert_equal SoulCore::RosterGptFinalFormat::BINDING,intent['output_format'];assert_equal @args[:adapter].native_controls,payload['chat_template_kwargs']
    assert_equal r.merge('replayed'=>true),@g.complete(**@args)
  end
  def test_ordinary_answer_is_unwrapped_without_dispatch
    @driver.instance_variable_set(:@reply,JSON.generate('answer'=>'A short ordinary answer.'))
    r=@g.complete(**@args);assert_equal 'A short ordinary answer.',r['content'];assert_nil r['execution'];assert_empty @calls
    final=rows.find{|r|r['state']=='final_received'}['data'];assert_equal Digest::SHA256.hexdigest(r['content']),final['final_sha256'];refute_equal final['native_final_sha256'],final['final_sha256']
    assert_equal r.merge('replayed'=>true),@g.complete(**@args)
  end
  def test_malformed_envelopes_and_proposal_in_answer_are_rejected
    values=['', '{}', '{"answer":""}', '{"answer":"x","extra":1}', '{"answer":"a","answer":"b"}',JSON.generate('answer'=>JSON.generate('soul_tool_proposal'=>{'tool'=>'roster_status','arguments'=>{}}))]
    values.each{|v|assert_raises(SoulCore::RosterChatAdapter::Unavailable){SoulCore::RosterGptFinalFormat.normalize(v)}}
  end
  def test_native_calls_stay_rejected_even_with_valid_final
    alter{|r|r['choices'][0]['message']['tool_calls']=[{'type'=>'function'}]}
    assert_raises(SoulCore::RosterChatAdapter::Unavailable){@g.complete(**@args)};assert_empty @calls;assert_equal 'failed',rows.last['state']
  end
  def test_driver_abort_is_terminal_and_normalized_not_reexecuted
    original=@driver.method(:request);@driver.define_singleton_method(:request){|m,p,b,deadline:|raise ChatReplacementTrial::Abort,'private transport text' if p=='/v1/chat/completions';original.call(m,p,b,deadline:deadline)}
    assert_raises(SoulCore::RosterRuntimeOwner::Unavailable){@g.complete(**@args)};assert_equal 'failed',rows.last['state'];refute_includes JSON.generate(rows),'private transport text'
    assert_raises(G::Refused){@g.complete(**@args)};assert_empty @calls
  end
  def test_other_members_keep_existing_payload_contract
    @args[:adapter]=SoulCore::RosterChatAdapter.new(model:'gemma-4-26b-a4b');@g.complete(**@args)
    payload=@driver.calls.find{|p,_|p=='/v1/chat/completions'}[1];refute payload.key?('response_format');assert_equal SoulCore::RosterProposalInstructions::SYSTEM,payload['messages'].first['content']
  end
  def test_rehashed_format_receipt_mismatch_is_rejected
    @g.complete(**@args);records=rows;records.find{|r|r['state']=='generation_intent'}['data']['output_format']={'version'=>'wrong'};previous=records.first['previous']
    records.each_with_index{|r,i|r['previous']=previous;File.write(File.join(@path,format('r-%06d.json',i+1)),JSON.generate(r));previous=G.digest(r)}
    assert_raises(G::Refused){@g.complete(**@args)}
  end
  def test_v11_transition_preserves_proposal_and_diagnostic_failure
    src=File.join(@tmp,'v10');dst=File.join(@tmp,'v11');oldclass=SoulCore::RosterToolProposalV3Archive;oldclass.create(path:src,owner:@owner)
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
    opener=store.method(:open_conversation);store.define_singleton_method(:open_conversation){|id|x=opener.call(id);x.instance_variable_set(:@skills,skills);x}
    alter{|r|r['choices'][0]['message']['content']=JSON.generate('soul_tool_proposal'=>{'tool'=>'roster_status','arguments'=>{}})}
    followup=@args.merge(request_id:'followup',messages:@args[:messages]+[{'role'=>'assistant','content'=>first['content']},{'role'=>'user','content'=>'Check the roster again.'}])
    next_reply=store.complete(**followup);assert_equal 'roster.status',next_reply.dig('execution','operation');assert_equal next_reply.merge('replayed'=>true),store.complete(**followup)
    assert before.all?{|p,h|Digest::SHA256.file(p).hexdigest==h}
  ensure
    old&.close;store&.close
  end
  def test_cancellation_discards_even_valid_native_final
    canceled=false;alter{|r|canceled=true}
    assert_raises(SoulCore::RosterChatExchange::Stopped){@g.complete(**@args.merge(cancel:->{canceled}))}
    assert_equal 'canceled',rows.last['state'];assert_empty @calls;refute rows.any?{|r|r['state']=='final_received'}
    assert_raises(G::Refused){@g.complete(**@args)}
  end

end
