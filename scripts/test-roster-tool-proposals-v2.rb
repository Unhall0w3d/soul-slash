# frozen_string_literal: true
require_relative 'test-roster-tool-proposals'
require_relative '../lib/soul_core/roster_tool_proposal_v2_archive'
class RosterToolProposalV2Test < Minitest::Test
  G=SoulCore::RosterToolProposalV2Gateway
  A=SoulCore::RosterToolProposalV2Archive
  D=SoulCore::RosterProposalResponseDiagnostics
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
  def test_metadata_contains_no_raw_model_or_error_text
    raw={'model'=>'secret model','error'=>'secret error','choices'=>[{'index'=>0,'finish_reason'=>'secret finish','message'=>{'role'=>'secret role','content'=>'secret content','reasoning_content'=>'secret reasoning','tool_calls'=>[{'arguments'=>'secret arguments'}],'function_call'=>{'name'=>'secret function'}}}],'usage'=>{'prompt_tokens'=>-1,'completion_tokens'=>'secret usage','total_tokens'=>10**30}}
    d=D.capture(raw,model:'gpt-oss-20b').merge('reason'=>'unclassified')
    assert D.valid?(d);refute_includes JSON.generate(d),'secret'
    assert_equal 'other',d['finish_reason'];assert_equal 1,d['tool_call_count'];assert d['usage'].values.all?(&:nil?)
    refute D.valid?(d.merge('text'=>'secret'));refute D.valid?(d.merge('reason'=>'arbitrary'))
    [nil,[],false,'private'].each{|v|assert D.valid?(D.capture(v,model:'x').merge('reason'=>'identity_or_choices'))}
  end
  def test_rejection_records_reason_and_remains_terminal
    alter{|r|r['choices'][0]['finish_reason']='tool_calls';r['choices'][0]['message']['reasoning_content']='PRIVATE';r['choices'][0]['message']['tool_calls']=[{'arguments'=>'PRIVATE'}]}
    assert_raises(SoulCore::RosterChatAdapter::Unavailable){@g.complete(**@args)}
    assert_equal %w[requested owned generation_intent response_rejected failed],rows.map{|r|r['state']}
    d=rows[-2].dig('data','diagnostic');assert_equal 'finish_reason',d['reason'];assert_equal 1,d['tool_call_count'];refute_includes JSON.generate(rows),'PRIVATE';assert_empty @calls
    @g.close;@g=G.new(path:@path,owner:@owner,memory:@memory,skills:@skills,clock:->{10.0})
    assert_raises(G::Refused){@g.complete(**@args)};assert_empty @calls
  end
  def test_final_null_is_not_accepted_or_coerced
    alter{|r|r['choices'][0]['message']['content']=nil}
    assert_raises(SoulCore::RosterChatAdapter::Unavailable){@g.complete(**@args)}
    d=rows[-2].dig('data','diagnostic');assert_equal 'final_text_or_tool_request',d['reason'];assert_equal 'null',d['content_type'];assert_empty @calls
  end
  def test_valid_proposal_and_prompt_keep_native_controls_and_replay
    result=@g.complete(**@args);assert_equal 'roster.status',result.dig('execution','operation')
    assert_equal result.merge('replayed'=>true),@g.complete(**@args);assert_equal ['roster.status'],@calls
    payload=@driver.calls.find{|p,_|p=='/v1/chat/completions'}[1]
    assert_equal @args[:adapter].native_controls,payload['chat_template_kwargs'];assert_includes payload['messages'][0]['content'],'currently loaded member';assert_includes payload['messages'][0]['content'],'Absence from memory'
    refute rows.any?{|r|r['state']=='response_rejected'}
  end
  def test_cancellation_takes_precedence_over_response_diagnostics
    canceled=false;alter{|r|r['choices'][0]['message']['content']=nil;canceled=true}
    assert_raises(SoulCore::RosterChatExchange::Stopped){@g.complete(**@args,cancel:->{canceled})}
    assert_equal 'canceled',rows.last['state'];refute rows.any?{|r|r['state']=='response_rejected'};assert_empty @calls
  end
  def test_diagnostic_write_failure_does_not_allow_reexecution
    alter{|r|r['choices'][0]['message']['content']=nil};append=@g.method(:append!)
    @g.define_singleton_method(:append!){|state,*args|raise IOError,'fixture' if state=='response_rejected';append.call(state,*args)}
    assert_raises(IOError){@g.complete(**@args)};assert_equal 'failed',rows.last['state'];assert_raises(G::Refused){@g.complete(**@args)};assert_empty @calls
  end
  def test_rehashed_diagnostic_with_extra_content_is_rejected
    alter{|r|r['choices'][0]['message']['content']=nil};assert_raises(SoulCore::RosterChatAdapter::Unavailable){@g.complete(**@args)}
    records=rows;records[-2]['data']['diagnostic']['raw_reasoning']='forbidden';previous=records.first['previous']
    records.each_with_index{|r,i|r['previous']=previous;File.write(File.join(@path,format('r-%06d.json',i+1)),JSON.generate(r));previous=G.digest(r)}
    assert_raises(G::Refused){@g.complete(**@args)}
  end
  def test_v9_transition_preserves_proposal_plain_chat_and_failure
    src=File.join(@tmp,'v9');dst=File.join(@tmp,'v10');oldclass=SoulCore::RosterToolProposalArchive;oldclass.create(path:src,owner:@owner)
    old=oldclass.new(path:src,owner:@owner,memory:@memory,clock:->{10.0});original=old.method(:open_conversation);skills=@skills
    old.define_singleton_method(:open_conversation){|id|v=original.call(id);v.instance_variable_set(:@skills,skills);v}
    first=old.complete(**@args);@driver.reply='ordinary response';plain=@args.merge(conversation_id:'plain',request_id:'plain');second=old.complete(**plain)
    @driver.fail_at='/v1/chat/completions';failed=@args.merge(conversation_id:'failed',request_id:'failed');assert_raises(IOError){old.complete(**failed)};@driver.fail_at=nil;old.close
    before=Dir.glob(src+'/**/*').select{|p|File.file?(p)}.to_h{|p|[p,Digest::SHA256.file(p).hexdigest]}
    A.transition(source:src,path:dst,owner:@owner,expected_manifest_sha256:A.digest(JSON.parse(File.read(src+'/roster.json'))))
    assert before.all?{|p,h|Digest::SHA256.file(p).hexdigest==h};store=A.new(path:dst,owner:@owner,memory:@memory,clock:->{10.0})
    calls=@driver.calls.length;assert_equal first.merge('replayed'=>true),store.complete(**@args);assert_equal second.merge('replayed'=>true),store.complete(**plain);assert_raises(G::Refused){store.complete(**failed)};assert_equal calls,@driver.calls.length
    assert_raises(G::Refused){store.complete(**@args.merge(conversation_id:'different'))}
    store.close
  ensure
    old&.close;store&.close
  end
end
class RosterToolProposalV2Test
  def test_template_usage_mismatch_has_specific_diagnostic
    alter{|r|r['usage']={'prompt_tokens'=>3,'completion_tokens'=>1,'total_tokens'=>4}}
    assert_raises(SoulCore::RosterChatAdapter::Unavailable){@g.complete(**@args)}
    assert_equal 'template_token_count',rows[-2].dig('data','diagnostic','reason');assert_empty @calls
  end
  def test_memory_present_and_absent_keep_scoping_and_guidance
    [false,true].each do |present|
      captured=[];validations=[];memory=Object.new
      memory.define_singleton_method(:select){|**kw|captured<<kw;{'records'=>present ? [{}] : [],'rendered'=>present ? 'Synthetic reference data.' : '', 'version'=>'fixture','member'=>'gemma-4-26b-a4b','selection_sha256'=>'a'*64,'revisions'=>[]}}
      memory.define_singleton_method(:validate_current!){|selection|validations<<selection;true}
      @driver.instance_variable_set(:@model,'gemma-4-26b-a4b');@driver.calls.clear;receipt=[]
      messages=[{'role'=>'system','content'=>SoulCore::RosterProposalInstructions::SYSTEM},{'role'=>'user','content'=>'Which member is loaded?'}];before=Marshal.load(Marshal.dump(messages))
      exchange=SoulCore::RosterProposalMemoryExchange.new(adapter:SoulCore::RosterChatAdapter.new(model:'gemma-4-26b-a4b'),memory:memory,client:@driver,admission:->{true},receipt:->(r){receipt<<r},clock:->{10.0})
      exchange.call(messages:messages,deadline:100.0,chat_id:'fixture-chat')
      assert_equal before,messages;assert_equal({member:'gemma-4-26b-a4b',query:'Which member is loaded?',chat_id:'fixture-chat'},captured.first)
      body=@driver.calls.find{|p,_|p=='/v1/chat/completions'}[1];assert_equal 1,body['messages'].count{|m|m['role']=='system'}
      if present
        assert_includes body['messages'].last['content'],'Eligibility and evidence';assert_includes body['messages'].last['content'],'follow';assert_includes body['messages'].last['content'],'absence from memory'
      else
        assert_equal messages.last,body['messages'].last
      end
      assert_operator validations.length,:>=,5;assert_equal %w[generation_intent final_received],receipt.map{|r|r['state']}
    end
  end
  def test_explicit_command_does_not_generate_and_keeps_replay
    result=@g.complete(**@args.merge(messages:[{'role'=>'user','content'=>'soul status'}]))
    assert_equal false,result.dig('execution','model_invoked');assert_empty @driver.starts
  end
end
