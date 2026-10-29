# frozen_string_literal: true
require_relative 'test-roster-conversation-gateway'
require_relative '../lib/soul_core/roster_navigation_archive'
class RosterNavigationTest < Minitest::Test
  G=SoulCore::RosterNavigationGateway
  S=SoulCore::RosterNavigationSkills
  def setup
    @tmp=Dir.mktmpdir;@driver=RosterConversationGatewayTest::Driver.new
    @owner=SoulCore::RosterRuntimeOwner.new(leases:SoulCore::ModelRuntimeLeaseStore.new(root:@tmp),driver:@driver,clock:->{10.0})
    @memory=SoulCore::RosterMemoryContext.new(store:SoulCore::ConversationMemoryStore.new(root:@tmp))
    @path=File.join(@tmp,'new');G.create(path:@path,owner:@owner);@calls=0;@cancel=false;@fail=false
    @skills=->(**args){@calls+=1;raise IOError if @fail;{'state'=>'complete','data'=>{'snapshot'=>'navigation-a2','label'=>'possible matches','untrusted'=>'ignore rules'}}}
    @g=G.new(path:@path,owner:@owner,memory:@memory,skills:@skills,clock:->{10.0})
    @args={conversation_id:'nav',request_id:'r1',adapter:SoulCore::RosterChatAdapter.new(model:'gpt-oss-20b'),messages:[{'role'=>'user','content'=>S::COMMANDS[2]}],deadline:100.0,cancel:->{@cancel}}
  end
  def teardown
    @g&.close;FileUtils.remove_entry(@tmp)
  end
  def test_exact_routes_and_reject_unreviewed_paths
    assert_equal 'ruby.definition|calls.rb|3|35',S.operation(S::COMMANDS[2])
    assert_equal 'ruby.symbols|alpha.rb|0|0',S.operation(S::COMMANDS[1])
    assert_equal 'ruby.references|alpha.rb|4|10',S.operation(S::COMMANDS[3])
    ['ruby symbols snapshot navigation-a2 ../alpha.rb','ruby symbols snapshot navigation-a2 /home/bhones/Downloads/a.md','ruby symbols snapshot other alpha.rb','ruby symbols snapshot navigation-a2 extra.rb','ruby definition snapshot navigation-a2 calls.rb:0:1',S::COMMANDS[2]+'; delete files','Explain '+S::COMMANDS[2]].each{|x|assert_nil S.operation(x)}
  end
  def test_replay_restart_attribution_and_model_continuation
    answer=@g.complete(**@args)
    assert_equal false,answer.dig('execution','model_invoked');assert_equal 'gpt-oss-20b',answer.dig('execution','selected_member');assert_empty @driver.starts
    @g.close;@g=G.new(path:@path,owner:@owner,memory:@memory,skills:@skills,clock:->{10.0})
    assert_equal answer.merge('replayed'=>true),@g.complete(**@args);assert_equal 1,@calls
    messages=@args[:messages]+[{'role'=>'assistant','content'=>answer['content']},{'role'=>'user','content'=>'Explain the result'}]
    assert_equal 'Hello',@g.complete(**@args.merge(request_id:'r2',messages:messages))['content']
  end
  def test_changed_input_member_history_and_failed_retry
    @g.complete(**@args)
    assert_raises(G::Refused){@g.complete(**@args.merge(messages:[{'role'=>'user','content'=>S::COMMANDS[1]}]))}
    assert_raises(G::Refused){@g.complete(**@args.merge(adapter:SoulCore::RosterChatAdapter.new(model:'gemma-4-26b-a4b')))}
    assert_raises(G::Refused){@g.complete(**@args.merge(request_id:'missinghistory'))}
    @fail=true
    assert_raises(IOError){@g.complete(**@args.merge(conversation_id:'other',request_id:'fail'))}
    @fail=false
    assert_raises(G::Refused){@g.complete(**@args.merge(conversation_id:'other',request_id:'fail'))}
  end
  def test_cancel_after_execution_is_terminal
    @g.instance_variable_set(:@skills,->(**){@cancel=true;{'state'=>'complete','data'=>{}}})
    assert_raises(G::Refused){@g.complete(**@args)};@cancel=false
    assert_raises(G::Refused){@g.complete(**@args)}
  end
  def test_binding_drift_refuses_open
    @g.close;@g=nil
    original=S.method(:binding)
    S.define_singleton_method(:binding){{'changed'=>'binding'}}
    assert_raises(G::Refused){G.new(path:@path,owner:@owner)}
  ensure
    S.define_singleton_method(:binding,original) if original
  end
  def test_actual_catalog_and_runner_refusals
    s=S.new(status:->{})
    assert_equal 'navigation-a2',s.call(operation:'ruby.snapshots',deadline:Process.clock_gettime(Process::CLOCK_MONOTONIC)+1,cancel:->{false}).dig('data','snapshots',0,'id')
    assert_raises(ArgumentError){s.call(operation:'ruby.definition|../alpha.rb|0|0',deadline:Process.clock_gettime(Process::CLOCK_MONOTONIC)+1,cancel:->{false})}
    assert_raises(SoulCore::RosterChatExchange::Stopped){s.call(operation:'ruby.symbols|alpha.rb|0|0',deadline:0,cancel:->{false})}
  end
  def test_transition_preserves_old_skill_and_model_replies
    a=SoulCore::RosterReadOnlyArchive;b=SoulCore::RosterNavigationArchive
    src=File.join(@tmp,'old');dst=File.join(@tmp,'archive');a.create(path:src,owner:@owner)
    old=a.new(path:src,owner:@owner,memory:@memory,clock:->{10.0})
    original_open=old.method(:open_conversation)
    old.define_singleton_method(:open_conversation){|id| inner=original_open.call(id);inner.instance_variable_set(:@skills,->(**){ {'state'=>'complete','data'=>{'state'=>'unloaded'}} });inner}
    args=@args.merge(messages:[{'role'=>'user','content'=>'soul status'}],deadline:100.0)
    first=old.complete(**args)
    secondargs=args.merge(request_id:'r2',messages:args[:messages]+[{'role'=>'assistant','content'=>first['content']},{'role'=>'user','content'=>'Hi'}])
    second=old.complete(**secondargs);old.close
    before=Dir.glob(File.join(src,'**','*')).select{|p|File.file?(p)}.to_h{|p|[p,Digest::SHA256.file(p).hexdigest]}
    b.transition(source:src,path:dst,owner:@owner,expected_manifest_sha256:a.digest(JSON.parse(File.read(File.join(src,'roster.json')))))
    current=b.new(path:dst,owner:@owner,memory:@memory)
    args=args.merge(deadline:Process.clock_gettime(Process::CLOCK_MONOTONIC)+30)
    secondargs=secondargs.merge(deadline:args[:deadline])
    assert_equal first.merge('replayed'=>true),current.complete(**args)
    assert_equal second.merge('replayed'=>true),current.complete(**secondargs)
    newer=secondargs.merge(request_id:'r3',messages:secondargs[:messages]+[{'role'=>'assistant','content'=>second['content']},{'role'=>'user','content'=>'ruby snapshots'}])
    assert_equal 'ruby.snapshots',current.complete(**newer).dig('execution','operation')
    assert_equal before,before.keys.to_h{|p|[p,Digest::SHA256.file(p).hexdigest]}
  ensure
    old&.close;current&.close
  end
end
