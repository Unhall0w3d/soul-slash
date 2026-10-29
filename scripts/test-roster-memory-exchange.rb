# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/soul_core/roster_memory_exchange'
class RosterMemoryExchangeTest < Minitest::Test
  def setup
    @tmp=Dir.mktmpdir
    @store=SoulCore::ConversationMemoryStore.new(root:@tmp)
    @context=SoulCore::RosterMemoryContext.new(store:@store)
    @calls=[];@receipts=[];@model='gpt-oss-20b';@tokens=[1,2];@cancel=false
    @messages=[{'role'=>'user','content'=>'Cabinet preference?'}]
  end
  def teardown = FileUtils.remove_entry(@tmp)
  def add(scope, content='Cabinet blue')
    r=@store.propose(layer:'preference',content:content,source:{kind:'fixture',reference:'test'},confidence:1,
      metadata:{'always_include'=>true,'roster_scope'=>scope})
    @store.approve(r['id'])
  end
  def exchange
    client=Object.new;owner=self
    client.define_singleton_method(:request) { |*args,**kw| owner.request(*args,**kw) }
    SoulCore::RosterMemoryExchange.new(adapter:SoulCore::RosterChatAdapter.new(model:@model,isolated:@model=='qwen3.8-27b'),
      memory:@context,client:client,receipt:->(r){raise IOError if @receipt_failure;@receipts<<r},
      admission:->{true},cancel:->{@cancel},clock:->{10.0})
  end
  def request(method,path,payload,deadline:)
    @calls<<[path,payload]
    @store.delete(@revoke,reason:'fixture') if path==@revoke_after
    case path
    when '/apply-template' then {'prompt'=>'native fixture'}
    when '/tokenize' then {'tokens'=>@tokens}
    else
      raise IOError if @transport_failure
      n=@tokens.length+(@model=='gemma-4-26b-a4b' ? 1 : 0)
      {'model'=>@model,'choices'=>[{'index'=>0,'finish_reason'=>'stop','message'=>{'role'=>'assistant','content'=>'Blue'}}],
        'usage'=>{'prompt_tokens'=>n,'completion_tokens'=>1,'total_tokens'=>n+1}}
    end
  end
  def run_exchange(e=exchange) = e.call(messages:@messages,deadline:100)
  def test_all_members_receive_only_shared_and_own_revisions_without_mutating_history
    shared=add({'kind'=>'shared'})
    own=add({'kind'=>'member','member_id'=>'gpt-oss-20b'},'GPT private')
    foreign=add({'kind'=>'member','member_id'=>'gemma-4-26b-a4b'},'Gemma private')
    original=Marshal.dump(@messages);ledger=File.binread(@store.path)
    %w[gpt-oss-20b gemma-4-26b-a4b qwen3.8-27b].each do |model|
      @model=model;result=run_exchange
      ids=[shared['id']]+(model=='gpt-oss-20b' ? [own['id']] : model=='gemma-4-26b-a4b' ? [foreign['id']] : [])
      assert_equal ids.sort,result['memory']['revisions'].map{|r|r['id']}.sort
      assert_equal 'user',@calls.last[1]['messages'].last['role']
      assert_equal @calls[-3][1]['messages'],@calls.last[1]['messages']
      assert_equal 'final_received',result['memory']['stage']
    end
    assert_equal original,Marshal.dump(@messages)
    assert_equal ledger,File.binread(@store.path)
    refute JSON.generate(@receipts).include?('Cabinet blue')
  end
  def test_gemma_only_coverage_guidance_is_projected_before_reference_and_tokenized
    shared=add({'kind'=>'shared'})
    original=Marshal.dump(@messages)
    expected=@context.select(member:'gemma-4-26b-a4b',query:@messages.last['content'])
    @model='gemma-4-26b-a4b';result=run_exchange
    content=@calls.last[1]['messages'].last['content']
    guidance=SoulCore::RosterMemoryExchange::GEMMA_COVERAGE_GUIDANCE
    assert_includes content,guidance
    assert_operator content.index(guidance),:<,content.index(expected['rendered'])
    assert_equal expected['selection_sha256'],result['memory']['selection_sha256']
    assert_equal @calls[-3][1]['messages'],@calls.last[1]['messages']
    assert_equal original,Marshal.dump(@messages)
    @model='gpt-oss-20b';run_exchange
    refute_includes @calls.last[1]['messages'].last['content'],guidance
    @model='qwen3.8-27b';run_exchange
    refute_includes @calls.last[1]['messages'].last['content'],guidance
    @store.delete(shared['id'],reason:'fixture');@model='gemma-4-26b-a4b';run_exchange
    assert_equal @messages,@calls.last[1]['messages']
  end
  def test_empty_selection_does_not_change_prompt
    run_exchange
    assert_equal @messages,@calls.last[1]['messages']
    assert_empty @receipts.last['memory']['revisions']
  end
  def test_revocation_after_tokenization_prevents_generation
    @revoke=add({'kind'=>'shared'})['id'];@revoke_after='/tokenize'
    assert_raises(SoulCore::RosterMemoryContext::Changed){run_exchange}
    assert_equal %w[/apply-template /tokenize],@calls.map(&:first)
    assert_empty @receipts
  end
  def test_revocation_during_generation_does_not_publish_success
    @revoke=add({'kind'=>'shared'})['id'];@revoke_after='/v1/chat/completions'
    assert_raises(SoulCore::RosterMemoryContext::Changed){run_exchange}
    assert_equal ['generation_intent'],@receipts.map{|r|r['memory']['stage']}
  end
  def test_ambiguous_transport_retains_intent_without_retry
    add({'kind'=>'shared'});@transport_failure=true;e=exchange
    assert_raises(IOError){run_exchange(e)}
    assert_equal ['generation_intent'],@receipts.map{|r|r['memory']['stage']}
    assert_raises(SoulCore::RosterChatExchange::Stopped){run_exchange(e)}
    assert_equal 3,@calls.length
  end
  def test_context_guard_and_cancellation_still_block_generation
    add({'kind'=>'shared'});@tokens=Array.new(2017,1)
    assert_raises(SoulCore::RosterChatAdapter::Invalid){run_exchange}
    assert_equal 2,@calls.length
    @calls.clear;@cancel=true
    assert_raises(SoulCore::RosterChatExchange::Stopped){run_exchange}
    assert_empty @calls
  end
  def test_receipt_failure_blocks_generation
    add({'kind'=>'shared'});@receipt_failure=true
    assert_raises(IOError){run_exchange}
    assert_equal %w[/apply-template /tokenize],@calls.map(&:first)
  end
end
