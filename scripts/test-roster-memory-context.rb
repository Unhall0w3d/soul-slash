# frozen_string_literal: true
require "minitest/autorun"
require "tmpdir"
require_relative "../lib/soul_core/roster_memory_context"

class RosterMemoryContextTest < Minitest::Test
  def setup
    @tmp=Dir.mktmpdir
    @store=SoulCore::ConversationMemoryStore.new(root:@tmp)
    @context=SoulCore::RosterMemoryContext.new(store:@store)
  end
  def teardown = FileUtils.remove_entry(@tmp)
  def add(scope:nil, approved:true, content:"Cabinet preference", extra:{})
    metadata={"always_include"=>true}.merge(extra)
    metadata["roster_scope"]=scope if scope
    r=@store.propose(layer:"preference",content:content,source:{kind:"fixture",reference:"test"},
      confidence:1,metadata:metadata)
    approved ? @store.approve(r.fetch("id")) : r
  end
  def select(member:"gpt-oss-20b",limit:8)
    @context.select(member:member,query:"cabinet",limit:limit)
  end
  def test_relevance_and_unrelated_abstention
    relevant=add(scope:{"kind"=>"shared"},content:"downloads.restore_last_cleanup refuses to overwrite an existing path.",extra:{"always_include"=>false})
    add(scope:{"kind"=>"shared"},content:"Weather report is read only and must use API evidence.",extra:{"always_include"=>false})
    query="During recovery can it replace something already at the destination?"
    selected=@context.select(member:"gpt-oss-20b",query:query)
    assert_equal [relevant['id']],selected['records'].map{|r|r['id']}
    add(scope:{"kind"=>"member","member_id"=>"gemma-4-26b-a4b"},content:query,extra:{"always_include"=>false})
    assert_equal selected,@context.select(member:"gpt-oss-20b",query:query)
    assert_empty @context.select(member:"gpt-oss-20b",query:"Favorite jazz album?")['records']
  end
  def test_scopes_filter_before_ranking_and_limit
    add
    add(scope:{"kind"=>"member","member_id"=>"gemma-4-26b-a4b"})
    add(scope:{"kind"=>"shared"},approved:false)
    shared=add(scope:{"kind"=>"shared"})
    selected=select(limit:1)
    assert_equal [shared["id"]],selected["records"].map { |r| r["id"] }
    assert_equal "selected_not_supplied",selected["stage"]
    assert @context.validate_current!(selected)
  end
  def test_member_specific_and_malformed_scope
    own=add(scope:{"kind"=>"member","member_id"=>"gpt-oss-20b"})
    add(scope:{"kind"=>"shared","unknown"=>true})
    assert_equal [own["id"]],select["records"].map { |r| r["id"] }
    assert_empty select(member:"gemma-4-26b-a4b")["records"]
  end
  def test_canonical_change_revokes_selection
    r=add(scope:{"kind"=>"shared"})
    selected=select
    @store.delete(r["id"],reason:"fixture")
    assert_raises(SoulCore::RosterMemoryContext::Changed) { @context.validate_current!(selected) }
    assert_empty select["records"]
  end
  def test_selection_is_read_only_and_tampering_refused
    add(scope:{"kind"=>"shared"})
    before=File.binread(@store.path)
    selected=select
    selected["rendered"]="different"
    assert_raises(SoulCore::RosterMemoryContext::Changed) { @context.validate_current!(selected) }
    assert_equal before,File.binread(@store.path)
  end
  def test_bounded_render_and_no_unknown_member
    add(scope:{"kind"=>"shared"},content:"x"*9000)
    assert_empty select["records"]
    assert_raises(ArgumentError) { select(member:"unknown") }
    assert_raises(ArgumentError) { select(limit:9) }
  end
end
