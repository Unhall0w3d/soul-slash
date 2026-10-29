# frozen_string_literal: true
require_relative 'test-roster-source-navigation'
require_relative '../lib/soul_core/roster_symbol_page_archive'
class SymbolPagesTest < Minitest::Test
  S=SoulCore::RosterSymbolPageSkills
  G=SoulCore::RosterSymbolPageGateway
  def setup
    @s=S.new(status:->{})
    @file='workflow_handler_registry.rb';@snapshot='soul-workflows-a1'
    @items=12.times.map{|n|["SoulCore::Method#{format('%02d',n)}",6,n]}
    @result={'state'=>'complete','data'=>{'snapshot'=>@snapshot,'snapshot_sha256'=>'a'*64,'file'=>@file,'locations'=>@items,'evidence'=>'raw'}}
  end
  def page(n,result=@result)=@s.send(:paginate,result,snapshot:@snapshot,file:@file,page:n)
  def test_complete_disjoint_ordered_coverage_and_digest
    rows=(1..3).map{|n|page(n)['data']}
    assert_equal @items,rows.flat_map{|r|r['symbols']}
    assert_equal 12,rows.flat_map{|r|r['symbols']}.uniq.length
    assert_equal 1,rows.map{|r|r['symbol_set_sha256']}.uniq.length
    assert_nil rows.last['next_command'];assert rows.last['complete']
    rows.each{|r|assert_operator JSON.pretty_generate(r).bytesize,:<=,8192;assert_equal r['page']<3,!r['next_command'].nil?}
  end
  def test_empty_and_exact_page_boundary
    r=page(1,{'state'=>'complete','data'=>@result['data'].merge('locations'=>[])})
    assert_equal [],r['data']['symbols'];assert_equal 1,r['data']['page_count']
    assert_equal 'awaiting_input',page(2,{'state'=>'complete','data'=>@result['data'].merge('locations'=>@items.first(4))})['state']
  end
  def test_bad_page_is_bounded_deterministic_response
    assert_equal 'awaiting_input',page(4)['state']
    ['0','-1','65','01','1; run shell'].each{|n|assert_equal 'symbols.invalid',S.operation("ruby symbols snapshot soul-workflows-a1 #{@file} page #{n}")}
    r=@s.call(operation:'symbols.invalid',deadline:Process.clock_gettime(Process::CLOCK_MONOTONIC)+1,cancel:->{false})
    assert_equal 'awaiting_input',r['state']
  end
  def test_snapshot_file_and_content_bindings
    changed={'state'=>'complete','data'=>@result['data'].merge('snapshot_sha256'=>'b'*64)}
    refute_equal page(1)['data']['symbol_set_sha256'],page(1,changed)['data']['symbol_set_sha256']
    assert_raises(IOError){page(1,{'state'=>'complete','data'=>@result['data'].merge('file'=>'other.rb')})}
    assert_raises(IOError){page(1,{'state'=>'complete','data'=>@result['data'].merge('locations'=>[['x'*513,6,1]])})}
    assert_raises(IOError){page(1,{'state'=>'complete','data'=>@result['data'].merge('locations'=>257.times.map{|n|['x',6,n]})})}
  end
  def test_exact_dispatch_keeps_old_operation
    assert_equal 'corpus.symbols|workflow_handler_registry.rb|0|0',S.operation("ruby symbols snapshot soul-workflows-a1 #{@file}")
    assert_equal 'symbols.page|soul-workflows-a1|workflow_handler_registry.rb|2',S.operation("ruby symbols snapshot soul-workflows-a1 #{@file} page 2")
    assert_equal 'symbols.invalid',S.operation('ruby symbols snapshot soul-workflows-a1 ../other.rb page 1')
    assert_equal 'symbols.invalid',S.operation('ruby symbols snapshot soul-workflows-a1 unlisted.rb page 1')
  end
  def test_gateway_restart_replay_changed_page_and_correction
    Dir.mktmpdir do |tmp|
      driver=RosterConversationGatewayTest::Driver.new
      owner=SoulCore::RosterRuntimeOwner.new(leases:SoulCore::ModelRuntimeLeaseStore.new(root:tmp),driver:driver,clock:->{10.0})
      path=File.join(tmp,'journal');G.create(path:path,owner:owner);calls=0
      skill=->(**opts){calls+=1;opts[:operation]=='symbols.invalid' ? @s.send(:invalid,'Choose a valid page') : page(opts[:operation].split('|').last.to_i)}
      g=G.new(path:path,owner:owner,skills:skill,clock:->{10.0})
      msg="ruby symbols snapshot soul-workflows-a1 #{@file} page 1"
      args={conversation_id:'pages',request_id:'p1',adapter:SoulCore::RosterChatAdapter.new(model:'gpt-oss-20b'),messages:[{'role'=>'user','content'=>msg}],deadline:100.0}
      first=g.complete(**args);g.close;g=G.new(path:path,owner:owner,skills:skill,clock:->{10.0})
      assert_equal first.merge('replayed'=>true),g.complete(**args);assert_equal 1,calls
      assert_raises(G::Refused){g.complete(**args.merge(messages:[{'role'=>'user','content'=>msg.sub('page 1','page 2')}]))}
      assert_raises(G::Refused){g.complete(**args.merge(adapter:SoulCore::RosterChatAdapter.new(model:'gemma-4-26b-a4b')))}
      nextargs=args.merge(request_id:'p2',messages:args[:messages]+[{'role'=>'assistant','content'=>first['content']},{'role'=>'user','content'=>msg.sub('page 1','page 2')}])
      second=g.complete(**nextargs);assert_includes second['content'],'"page": 2';assert_equal 2,calls;assert_empty driver.starts
      badargs=args.merge(request_id:'bad',messages:nextargs[:messages]+[{'role'=>'assistant','content'=>second['content']},{'role'=>'user','content'=>msg.sub('page 1','page 0')}])
      bad=g.complete(**badargs);assert_equal 'awaiting_input',bad.dig('execution','state')
      fixedargs=args.merge(request_id:'fixed',messages:badargs[:messages]+[{'role'=>'assistant','content'=>bad['content']},{'role'=>'user','content'=>msg.sub('page 1','page 3')}])
      fixed=g.complete(**fixedargs);assert_includes fixed['content'],'"page": 3';assert_empty driver.starts
    ensure
      g&.close
    end
  end
end
class RosterSourceNavigationTest
  def test_page_archive_preserves_prior_unpaged_reply
    a=SoulCore::RosterSourceNavigationArchive;b=SoulCore::RosterSymbolPageArchive
    src=File.join(@tmp,'unpaged');dst=File.join(@tmp,'paged');a.create(path:src,owner:@owner)
    old=a.new(path:src,owner:@owner,memory:@memory,clock:->{10.0})
    original=old.method(:open_conversation)
    old.define_singleton_method(:open_conversation){|id|g=original.call(id);g.instance_variable_set(:@skills,->(**){{'state'=>'complete','data'=>{'legacy_unpaged'=>'kept exactly'}}});g}
    first=old.complete(**@args);old.close
    b.transition(source:src,path:dst,owner:@owner,expected_manifest_sha256:a.digest(JSON.parse(File.read(File.join(src,'roster.json')))))
    new=b.new(path:dst,owner:@owner,memory:@memory,clock:->{10.0})
    assert_equal first.merge('replayed'=>true),new.complete(**@args)
  ensure
    old&.close;new&.close
  end
end
