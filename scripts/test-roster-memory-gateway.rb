# frozen_string_literal: true
require_relative 'test-roster-conversation-gateway'
require_relative '../lib/soul_core/roster_memory_gateway'
class RosterMemoryGatewayTest < Minitest::Test
  G=SoulCore::RosterMemoryGateway
  def setup
    @tmp=Dir.mktmpdir;@driver=RosterConversationGatewayTest::Driver.new
    @owner=SoulCore::RosterRuntimeOwner.new(leases:SoulCore::ModelRuntimeLeaseStore.new(root:@tmp),driver:@driver,clock:->{10.0})
    @source=File.join(@tmp,'v1');@target=File.join(@tmp,'v2')
    SoulCore::RosterConversationGateway.create(path:@source,owner:@owner)
    @old=SoulCore::RosterConversationGateway.new(path:@source,owner:@owner,clock:->{10.0})
    @args={conversation_id:'chat',request_id:'one',adapter:SoulCore::RosterChatAdapter.new(model:'gpt-oss-20b'),messages:[{'role'=>'user','content'=>'Cabinet?'}],deadline:100.0}
    @result=@old.complete(**@args);@old.close
    @store=SoulCore::ConversationMemoryStore.new(root:@tmp)
    r=@store.propose(layer:'preference',content:'Cabinet blue',source:{kind:'fixture',reference:'test'},confidence:1,metadata:{'roster_scope'=>{'kind'=>'shared'},'always_include'=>true})
    @record=@store.approve(r['id'])
    @memory=SoulCore::RosterMemoryContext.new(store:@store)
  end
  def teardown
    @gateway&.close;@old&.close;FileUtils.remove_entry(@tmp)
  end
  def snapshot = Dir.children(@source).sort.to_h{|n|[n,File.binread(File.join(@source,n))]}
  def transition
    digest=G.digest(JSON.parse(File.read(File.join(@source,'roster.json'))))
    G.transition(source:@source,destination:@target,owner:@owner,expected_manifest_sha256:digest)
    @gateway=G.new(path:@target,owner:@owner,memory:@memory,clock:->{10.0})
  end
  def test_implementation_upgrade_preserves_replay_and_source
    transition
    @gateway.complete(**next_args)
    @gateway.close
    before=Dir.children(@target).sort.to_h{|n|[n,File.binread(File.join(@target,n))]}
    files=G.manifest(@owner)['memory_implementation'].keys.to_h{|n|[n,File.expand_path('../lib/soul_core/'+n,__dir__)]}
    digest=G.digest(JSON.parse(File.read(File.join(@target,'roster.json'))))
    dest=File.join(@tmp,'upgrade')
    result=G.upgrade(source:@target,destination:dest,owner:@owner,expected_manifest_sha256:digest,implementation_files:files)
    assert_equal 'complete',result['state']
    @gateway=G.new(path:dest,owner:@owner,memory:@memory,clock:->{10.0})
    assert_equal @result.merge('replayed'=>true),@gateway.complete(**@args)
    assert_equal true,@gateway.complete(**next_args)['replayed']
    assert_equal before,Dir.children(@target).sort.to_h{|n|[n,File.binread(File.join(@target,n))]}
    assert_raises(G::Refused){G.upgrade(source:@target,destination:File.join(@tmp,'bad'),owner:@owner,expected_manifest_sha256:'0'*64,implementation_files:files)}
    assert_raises(G::Refused){@gateway.complete(**next_args.merge(messages:[{'role'=>'user','content'=>'changed'}]))}
  end
  def test_upgrade_refuses_unfinished_source_and_busy_source
    transition
    files=G.manifest(@owner)['memory_implementation'].keys.to_h{|n|[n,File.expand_path('../lib/soul_core/'+n,__dir__)]}
    digest=G.digest(JSON.parse(File.read(File.join(@target,'roster.json'))))
    dest=File.join(@tmp,'upgrade')
    lock=@gateway.instance_variable_get(:@lock)
    lock.flock(File::LOCK_EX)
    assert_raises(G::Refused){G.upgrade(source:@target,destination:dest,owner:@owner,expected_manifest_sha256:digest,implementation_files:files)}
    lock.flock(File::LOCK_UN)
    @gateway.send(:load!)
    input={'conversation_id'=>'pending','request_id'=>'pending','adapter'=>@args[:adapter].binding,'messages'=>[{'role'=>'user','content'=>'Cabinet?'}]}
    @gateway.send(:append!,'requested','pending',input)
    @gateway.close
    assert_raises(G::Refused){G.upgrade(source:@target,destination:dest,owner:@owner,expected_manifest_sha256:digest,implementation_files:files)}
    refute File.exist?(dest)
  end
  def test_more_than_sixteen_chats_share_record_budget_and_full_journal_replays
    transition
    completed=0
    loop do
      args=@args.merge(conversation_id:"capacity#{completed}",request_id:"capacity#{completed}")
      records_before=Dir.glob(File.join(@target,'r-*.json')).length
      if records_before+5 > G::LIMIT
        starts_before=@driver.starts.length
        error=assert_raises(G::Refused){@gateway.complete(**args)}
        assert_equal 'journal quota',error.message
        assert_equal starts_before,@driver.starts.length
        assert_equal records_before,Dir.glob(File.join(@target,'r-*.json')).length
        break
      end
      @gateway.complete(**args)
      completed+=1
    end
    assert_operator completed,:>,16
    assert_operator Dir.glob(File.join(@target,'r-*.json')).length,:<=,G::LIMIT
    assert_equal @result.merge('replayed'=>true),@gateway.complete(**@args)
    assert_raises(G::Refused){@gateway.complete(**@args.merge(messages:[{'role'=>'user','content'=>'edited'}]))}
  end
  def next_args
    @args.merge(request_id:'two',messages:@args[:messages]+[{'role'=>'assistant','content'=>'Hello'},{'role'=>'user','content'=>'Next cabinet?'}])
  end
  def test_preserves_source_replays_and_continuation_then_restart
    before=snapshot;transition
    assert_equal before,snapshot
    replay=@gateway.complete(**@args)
    assert_equal @result.merge('replayed'=>true),replay
    assert_equal 1,@driver.starts.length
    result=@gateway.complete(**next_args)
    assert_equal [@record['id']],result['memory']['revisions'].map{|r|r['id']}
    assert_includes @driver.calls.last[1]['messages'].last['content'],'Cabinet blue'
    @gateway.close;@store.delete(@record['id'],reason:'fixture')
    @gateway=G.new(path:@target,owner:@owner,memory:@memory,clock:->{10.0})
    assert_equal result.merge('replayed'=>true),@gateway.complete(**next_args)
    assert_equal 2,@driver.starts.length
    assert_equal before,snapshot
    assert_raises(G::Refused){@gateway.complete(**next_args.merge(messages:[{'role'=>'user','content'=>'Changed'}]))}
  end
  def test_explicit_old_and_new_runtime_bindings_preserve_replay
    old_owner=@owner
    driver=RosterConversationGatewayTest::Driver.new
    base=driver.binding
    driver.define_singleton_method(:binding){base.transform_values{|b|b.merge('launch_sha256'=>'d'*64)}}
    @owner=SoulCore::RosterRuntimeOwner.new(leases:SoulCore::ModelRuntimeLeaseStore.new(root:@tmp),driver:driver,clock:->{10.0})
    digest=G.digest(JSON.parse(File.read(File.join(@source,'roster.json'))))
    G.transition(source:@source,destination:@target,owner:@owner,source_owner:old_owner,expected_manifest_sha256:digest)
    @gateway=G.new(path:@target,owner:@owner,memory:@memory,clock:->{10.0})
    assert_equal @result.merge('replayed'=>true),@gateway.complete(**@args)
    assert_empty driver.starts
    assert_equal 'd'*64,@gateway.complete(**next_args)['runtime']['identity']['launch_sha256']
  end
  def test_missing_imported_record_refused
    transition;@gateway.close
    File.unlink(Dir.glob(File.join(@target,'r-*.json')).sort.last)
    @gateway=G.new(path:@target,owner:@owner,memory:@memory,clock:->{10.0})
    assert_raises(G::Refused){@gateway.complete(**@args)}
  end
  def test_unfinished_source_never_creates_destination
    File.unlink(Dir.glob(File.join(@source,'r-*.json')).sort.last)
    assert_raises(G::Refused){transition}
    refute File.exist?(@target)
  end
  def test_wrong_source_digest_and_existing_destination_refused
    assert_raises(G::Refused){G.transition(source:@source,destination:@target,owner:@owner,expected_manifest_sha256:'0'*64)}
    refute File.exist?(@target)
    transition
    assert_raises(G::Refused){transition}
  end
  def test_rehashed_memory_revision_mismatch_refused
    transition;@gateway.complete(**next_args);@gateway.close
    prior=G.digest(JSON.parse(File.read(File.join(@target,'roster.json'))))
    Dir.glob(File.join(@target,'r-*.json')).sort.each do |p|
      r=JSON.parse(File.read(p));r['previous']=prior
      if r['request_id']=='two' && r['state']=='final_received'
        r['data']['memory']['rendered_sha256']='0'*64
      end
      File.write(p,JSON.generate(r));prior=G.digest(r)
    end
    @gateway=G.new(path:@target,owner:@owner,memory:@memory,clock:->{10.0})
    assert_raises(G::Refused){@gateway.complete(**next_args)}
  end
end
