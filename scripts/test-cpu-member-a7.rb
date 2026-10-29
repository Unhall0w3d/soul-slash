# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/soul_core/cpu_member_service'
class CpuMemberA7Test < Minitest::Test
  class Owner
    attr_reader :calls
    attr_accessor :hook,:token_count
    def initialize;@calls=[];@token_count=2;end
    def status = {'state'=>'loaded'}
    def admitted? = true
    def touch = nil
    def tick = nil
    def stop = true
    def request(_,path,payload,**)
      @calls<<[path,payload];@hook&.call(path)
      return {'prompt'=>'native template'} if path=='/apply-template'
      return {'tokens'=>Array.new(@token_count,1)} if path=='/tokenize'
      {'model'=>SoulCore::CpuMemberAdapter::MODEL,'choices'=>[{'index'=>0,'finish_reason'=>'stop','message'=>{'role'=>'assistant','content'=>'Cabinet LARK-842.'}}],'usage'=>{'prompt_tokens'=>3,'completion_tokens'=>4,'total_tokens'=>7}}
    end
  end
  def setup
    @tmp=Dir.mktmpdir;@store=SoulCore::ConversationMemoryStore.new(root:@tmp)
    @memory=SoulCore::CpuMemberMemoryContext.new(store:@store);@owner=Owner.new
    @path=File.join(@tmp,'service');Dir.mkdir(@path,0700)
    @service=SoulCore::CpuMemberService.new(path:@path,owner:@owner,assistance:true,scoped_memory:true,memory:@memory,compute_reader:->{})
  end
  def teardown;@service.close;FileUtils.remove_entry(@tmp);end
  def add(scope:{'kind'=>'shared'},approved:true,content:'Cabinet LARK-842')
    r=@store.propose(layer:'preference',content:content,source:{kind:'fixture',reference:'a7'},confidence:1,metadata:{'roster_scope'=>scope})
    approved ? @store.approve(r['id']) : r
  end
  def call(text='Which cabinet?',id:'one',history:[],cancel:->{false})
    @service.complete(conversation_id:'fixture',request_id:id,messages:history+[{'role'=>'user','content'=>text}],deadline:Process.clock_gettime(Process::CLOCK_MONOTONIC)+10,cancel:cancel)
  end
  def test_scope_ranking_and_read_only
    a=add;b=add(scope:{'kind'=>'member','member_id'=>SoulCore::CpuMemberAdapter::MODEL},content:'Cabinet CPU-specific')
    add(scope:nil);add(approved:false);add(scope:{'kind'=>'member','member_id'=>'gpt-oss-20b'},content:'Cabinet secret')
    before=File.binread(@store.path);sel=@memory.select(query:'cabinet')
    assert_equal [a['id'],b['id']].sort,sel['records'].map{|r|r['id']}.sort
    assert @memory.validate_current!(sel);assert_equal before,File.binread(@store.path)
  end
  def test_memory_is_native_reference_and_replay_does_not_retrieve
    record=add;r=call;assert_equal [record['id']],r['memory']['revisions'].map{|x|x['id']}
    template=@owner.calls.find{|p,_|p=='/apply-template'}[1];generation=@owner.calls.last[1]
    assert_equal template['messages'],generation['messages'];assert_includes generation['messages'][0]['content'],'Reference-only approved memory'
    assert_includes generation['messages'][0]['content'],'LARK-842';assert_equal false,generation['cache_prompt']
    @store.delete(record['id'],reason:'fixture');count=@owner.calls.length
    def @memory.select(**) = raise('replay must not retrieve')
    replay=call;assert replay['replayed'];assert_equal r['memory'],replay['memory'];assert_equal count,@owner.calls.length
  end
  def test_revocation_between_template_and_generation_stops_dispatch
    record=add;@owner.hook=->(path){@store.delete(record['id'],reason:'fixture') if path=='/tokenize'}
    assert_raises(SoulCore::RosterMemoryContext::Changed){call}
    refute @owner.calls.any?{|p,_|p=='/v1/chat/completions'}
    assert_raises(SoulCore::CpuMemberGateway::Refused){call}
  end
  def test_revocation_after_response_does_not_publish_completion
    record=add;@owner.hook=->(path){@store.delete(record['id'],reason:'fixture') if path=='/v1/chat/completions'}
    assert_raises(SoulCore::RosterMemoryContext::Changed){call}
    assert_raises(SoulCore::CpuMemberGateway::Refused){call}
  end
  def test_deterministic_commands_never_read_memory
    def @memory.select(**) = raise('unexpected lookup')
    r=call('What is 7 minus 3?');assert_includes r['content'],'4';refute r.key?('memory');assert_empty @owner.calls
  end
  def test_memory_budget_and_exact_token_guard
    add(content:'Cabinet '+('x'*2500));assert_empty @memory.select(query:'cabinet')['records']
    add;@owner.token_count=3040
    assert_raises(SoulCore::CpuMemberGateway::Refused){call}
    refute @owner.calls.any?{|p,_|p=='/v1/chat/completions'}
  end
  def test_cancel_before_lookup
    add;assert_raises(StandardError){call(cancel:->{true})};assert_empty @owner.calls
  end
  def test_memory_changes_invalidate_prefix_reuse
    add;r=call;h=[{'role'=>'user','content'=>'Which cabinet?'},{'role'=>'assistant','content'=>r['content']}]
    r2=call('Which cabinet?',id:'two',history:h);assert @owner.calls.last[1]['cache_prompt']
    add(content:'Cabinet new detail');h+=[{'role'=>'user','content'=>'Which cabinet?'},{'role'=>'assistant','content'=>r2['content']}]
    call('Which cabinet?',id:'three',history:h);refute @owner.calls.last[1]['cache_prompt']
  end
  def test_replay_survives_restart_and_changed_history_is_refused
    add;r=call;count=@owner.calls.length;@service.close
    @service=SoulCore::CpuMemberService.new(path:@path,owner:@owner,assistance:true,scoped_memory:true,memory:@memory,compute_reader:->{})
    replay=call;assert replay['replayed'];assert_equal r['memory'],replay['memory'];assert_equal count,@owner.calls.length
    assert_raises(SoulCore::CpuMemberGateway::Refused){call('Different question',id:'one')}
  end

end
