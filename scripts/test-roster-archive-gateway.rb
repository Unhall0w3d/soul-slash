# frozen_string_literal: true
require_relative 'test-roster-conversation-gateway'
require_relative '../lib/soul_core/roster_archive_gateway'
class RosterArchiveGatewayTest < Minitest::Test
  A=SoulCore::RosterArchiveGateway
  G=SoulCore::RosterMemoryGateway
  def setup
    @tmp=Dir.mktmpdir;@driver=RosterConversationGatewayTest::Driver.new
    @owner=SoulCore::RosterRuntimeOwner.new(leases:SoulCore::ModelRuntimeLeaseStore.new(root:@tmp),driver:@driver,clock:->{10.0})
    @memory=SoulCore::RosterMemoryContext.new(store:SoulCore::ConversationMemoryStore.new(root:@tmp))
    @path=File.join(@tmp,'archive');A.create(path:@path,owner:@owner)
    @a=A.new(path:@path,owner:@owner,memory:@memory,clock:->{10.0})
    @args={conversation_id:'chat',request_id:'one',adapter:SoulCore::RosterChatAdapter.new(model:'gpt-oss-20b'),messages:[{'role'=>'user','content'=>'Hi'}],deadline:100.0}
  end
  def teardown
    @a&.close;FileUtils.remove_entry(@tmp)
  end
  def test_more_than_512_aggregate_records_and_replay_after_restart
    first=@a.complete(**@args)
    104.times { |i| @a.complete(**@args.merge(conversation_id:"c#{i}",request_id:"r#{i}")) }
    @a.close;@a=A.new(path:@path,owner:@owner,memory:@memory,clock:->{10.0})
    starts=@driver.starts.length
    assert_equal first.merge('replayed'=>true),@a.complete(**@args)
    assert_equal starts,@driver.starts.length
    next_args=@args.merge(request_id:'two',messages:@args[:messages]+[{'role'=>'assistant','content'=>first['content']},{'role'=>'user','content'=>'Next'}])
    assert_equal 'Hello',@a.complete(**next_args)['content']
    assert_raises(A::Refused){@a.complete(**@args.merge(conversation_id:'another'))}
    assert_raises(A::Refused){@a.complete(**@args.merge(messages:[{'role'=>'user','content'=>'Edited'}]))}
    assert_operator Dir.glob(File.join(@path,'conversations','*','journal','r-*.json')).length,:>,512
  end
  def test_interrupted_reservation_refuses_retry_without_model
    @a.send(:create_conversation!,'chat')
    input={'conversation_id'=>'chat','request_id'=>'one','adapter'=>@args[:adapter].binding,'messages'=>@args[:messages]}
    @a.send(:reserve!,input)
    assert_raises(A::Refused){@a.complete(**@args)}
    assert_empty @driver.starts
  end
  def test_missing_conversation_and_registry_and_symlinks_fail_closed
    @a.complete(**@args)
    conv=File.join(@path,'conversations',A.digest('chat'))
    File.rename(conv,conv+'-retained')
    assert_raises(A::Refused){@a.complete(**@args)}
    File.symlink(conv+'-retained',conv)
    assert_raises(SoulCore::ContinuityLab::IntegrityError){@a.complete(**@args)}
    File.unlink(conv);File.rename(conv+'-retained',conv)
    bucket=File.join(@path,'requests','b-'+A.digest('one')[0,2]);File.rename(File.join(bucket,'r-000001.json'),File.join(@tmp,'saved-index.json'))
    assert_raises(A::Refused){@a.complete(**@args)}
    assert_equal 1,@driver.starts.length
  end
  def test_import_preserves_source_replay_and_continuation
    source=File.join(@tmp,'source');G.create(path:source,owner:@owner)
    g=G.new(path:source,owner:@owner,memory:@memory,clock:->{10.0});answer=g.complete(**@args);g.close
    before=Dir.children(source).to_h{|n|[n,File.binread(File.join(source,n))]}
    manifest=JSON.parse(File.read(File.join(source,'roster.json')));dest=File.join(@tmp,'imported')
    r=A.import(source:source,path:dest,owner:@owner,expected_manifest_sha256:G.digest(manifest))
    assert r['source_preserved']
    assert_equal before,Dir.children(source).to_h{|n|[n,File.binread(File.join(source,n))]}
    @a.close;@a=A.new(path:dest,owner:@owner,memory:@memory,clock:->{10.0})
    assert_equal answer.merge('replayed'=>true),@a.complete(**@args)
    assert_equal 1,@driver.starts.length
    next_args=@args.merge(request_id:'two',messages:@args[:messages]+[{'role'=>'assistant','content'=>answer['content']},{'role'=>'user','content'=>'Next'}])
    assert_equal 'Hello',@a.complete(**next_args)['content']
    @a.close
    file=File.join(dest,'legacy','r-000001.json');File.write(file,File.read(file)+' ')
    assert_raises(A::Refused){A.new(path:dest,owner:@owner,memory:@memory)}
  end
  def test_missing_registry_tail_cannot_reuse_identity_in_another_conversation
    @a.complete(**@args)
    bucket=File.join(@path,'requests','b-'+A.digest('one')[0,2])
    File.rename(File.join(bucket,'r-000001.json'),File.join(@tmp,'retained-record'))
    assert_raises(A::Refused){@a.complete(**@args.merge(conversation_id:'other'))}
    assert_equal 1,@driver.starts.length
  end
  def test_missing_identity_key_refuses_existing_and_cross_conversation_replays
    @a.complete(**@args)
    File.rename(File.join(@path,'request-keys',A.digest('one')+'.json'),File.join(@tmp,'retained-key'))
    assert_raises(A::Refused){@a.complete(**@args)}
    assert_raises(A::Refused){@a.complete(**@args.merge(conversation_id:'other'))}
    assert_equal 1,@driver.starts.length
  end
  def test_import_refuses_unfinished_source_without_publication
    source=File.join(@tmp,'unfinished');G.create(path:source,owner:@owner)
    g=G.new(path:source,owner:@owner);g.send(:load!)
    input={'conversation_id'=>'chat','request_id'=>'one','adapter'=>@args[:adapter].binding,'messages'=>@args[:messages]}
    g.send(:append!,'requested','one',input);g.close
    manifest=JSON.parse(File.read(File.join(source,'roster.json')))
    dest=File.join(@tmp,'not-published')
    assert_raises(A::Refused){A.import(source:source,path:dest,owner:@owner,expected_manifest_sha256:G.digest(manifest))}
    refute File.exist?(dest)
  end
  def test_failed_request_stays_failed_across_import
    source=File.join(@tmp,'failed');G.create(path:source,owner:@owner)
    g=G.new(path:source,owner:@owner,memory:@memory,clock:->{10.0});@driver.fail_at='/v1/chat/completions'
    assert_raises(IOError){g.complete(**@args)};g.close
    manifest=JSON.parse(File.read(File.join(source,'roster.json')));dest=File.join(@tmp,'import-failure')
    A.import(source:source,path:dest,owner:@owner,expected_manifest_sha256:G.digest(manifest))
    @a.close;@a=A.new(path:dest,owner:@owner,memory:@memory,clock:->{10.0});starts=@driver.starts.length
    assert_raises(A::Refused){@a.complete(**@args)}
    assert_equal starts,@driver.starts.length
  end

  def test_changed_conversation_descriptor_refuses_replay
    @a.complete(**@args)
    descriptor=File.join(@path,'conversations',A.digest('chat'),'descriptor.json')
    value=JSON.parse(File.read(descriptor));value['conversation_id']='other';File.write(descriptor,JSON.generate(value))
    assert_raises(A::Refused){@a.complete(**@args)}
    assert_equal 1,@driver.starts.length
  end
  def test_missing_lock_or_partial_key_never_admits_generation
    input={'conversation_id'=>'chat','request_id'=>'one','adapter'=>@args[:adapter].binding,'messages'=>@args[:messages]}
    @a.instance_variable_get(:@keys).write(A.digest('one')+'.json',@a.send(:reservation,input))
    assert_raises(A::Refused){@a.complete(**@args)}
    File.rename(File.join(@path,'lock'),File.join(@tmp,'old-lock'))
    File.write(File.join(@path,'lock'),'{}',perm:0600)
    assert_raises(A::Refused){@a.complete(**@args.merge(request_id:'fresh'))}
    assert_empty @driver.starts
  end

  def test_scoped_memory_is_supplied_and_retained_across_archive_restart
    store=SoulCore::ConversationMemoryStore.new(root:@tmp)
    add=->(scope,text) do
      item=store.propose(layer:'preference',content:text,source:{kind:'fixture',reference:'archive-test'},confidence:1,metadata:{'always_include'=>true,'roster_scope'=>scope})
      store.approve(item.fetch('id'));item.fetch('id')
    end
    shared=add.call({'kind'=>'shared'},'Shared cabinet is blue.')
    own=add.call({'kind'=>'member','member_id'=>'gpt-oss-20b'},'Personal cabinet is green.')
    foreign=add.call({'kind'=>'member','member_id'=>'gemma-4-26b-a4b'},'Other member cabinet is red.')
    expected=@memory.select(member:'gpt-oss-20b',query:'Hi',chat_id:'chat')
    assert_equal [own,shared].sort,expected['records'].map{|r|r['id']}.sort
    refute_includes expected['records'].map{|r|r['id']},foreign
    first=@a.complete(**@args)
    assert_equal expected['revisions'],first.fetch('memory').fetch('revisions')
    assert_equal 'final_received',first.dig('memory','stage')
    @a.close;@a=A.new(path:@path,owner:@owner,memory:@memory,clock:->{10.0})
    assert_equal first.merge('replayed'=>true),@a.complete(**@args)
    assert_equal 1,@driver.starts.length
  end

end
