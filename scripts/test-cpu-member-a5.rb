# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/soul_core/cpu_member_service'
require_relative '../lib/soul_core/roster_dashboard_runtime'
class CpuMemberA5Test < Minitest::Test
  class Owner
    attr_accessor :state,:fail,:text
    attr_reader :payloads,:stops
    def initialize;@state='loaded';@payloads=[];@stops=0;@text='Hello';end
    def admitted? = true
    def status = {'state'=>@state}
    def touch = nil
    def tick = nil
    def stop;@stops+=1;@state='unloaded';true;end
    def request(_,path,payload,**)
      return {'prompt'=>'native'} if path=='/apply-template'
      return {'tokens'=>[1,2]} if path=='/tokenize'
      @payloads<<payload;@state='loaded';raise 'synthetic failure' if @fail
      {'model'=>SoulCore::CpuMemberAdapter::MODEL,'choices'=>[{'index'=>0,'finish_reason'=>'stop','message'=>{'role'=>'assistant','content'=>@text}}],'usage'=>{'prompt_tokens'=>3,'completion_tokens'=>2,'total_tokens'=>5}}
    end
  end
  def setup;@root=Dir.mktmpdir;@owner=Owner.new;open_service;end
  def open_service;@service=SoulCore::CpuMemberService.new(path:@root,owner:@owner);end
  def teardown;@service.close;FileUtils.remove_entry(@root);end
  def call(text,id:,conversation:'a',history:[],cancel:->{false})
    @service.complete(conversation_id:conversation,request_id:id,messages:history+[{'role'=>'user','content'=>text}],deadline:Process.clock_gettime(Process::CLOCK_MONOTONIC)+10,cancel:cancel)
  end
  def history(text,result)=[{'role'=>'user','content'=>text},{'role'=>'assistant','content'=>result['content']}]
  def command = '/calculate '+JSON.generate(operation:'subtract',sources:{budget:847,deposit:286},left:'budget',right:'deposit')
  def test_explicit_calculation_and_restart_replay
    r=call(command,id:'r');assert_includes r['content'],'561';assert_equal [],@owner.payloads
    assert_equal 'deterministic.calculation',r.dig('execution','provider')
    @service.close;open_service;assert call(command,id:'r')['replayed'];assert_equal [],@owner.payloads
    assert_raises(SoulCore::CpuMemberGateway::Refused){call(command.sub('847','848'),id:'r')}
    assert_equal 'Hello',call('Thank you',id:'r2',history:history(command,r))['content']
  end
  def test_cache_same_conversation_switch_restart_replay_and_bad_history
    r=call('Hello',id:'r');refute @owner.payloads.last['cache_prompt']
    r2=call('Continue',id:'r2',history:history('Hello',r));assert @owner.payloads.last['cache_prompt']
    before=@owner.payloads.length;assert call('Continue',id:'r2',history:history('Hello',r))['replayed'];assert_equal before,@owner.payloads.length
    assert_raises(SoulCore::CpuMemberGateway::Refused){call('Changed',id:'bad',history:history('WRONG',r))}
    assert_equal before,@owner.payloads.length
    call('Hello',id:'b1',conversation:'b');refute @owner.payloads.last['cache_prompt']
    call('Next',id:'r3',history:history('Hello',r)+history('Continue',r2));refute @owner.payloads.last['cache_prompt']
    @service.close;open_service;call('Hello',id:'c1',conversation:'c');refute @owner.payloads.last['cache_prompt']
  end
  def test_failed_request_and_cancellation_never_reuse_or_retry
    @owner.fail=true;assert_raises(RuntimeError){call('Hello',id:'r')};@owner.fail=false
    before=@owner.payloads.length;assert_raises(SoulCore::CpuMemberGateway::Refused){call('Hello',id:'r')};assert_equal before,@owner.payloads.length
    call('Fresh',id:'f',conversation:'f');refute @owner.payloads.last['cache_prompt']
    assert_raises(StandardError){call('Cancel',id:'cancel',conversation:'cancel',cancel:->{true})}
    call('Another',id:'g',conversation:'g');refute @owner.payloads.last['cache_prompt']
  end
  def test_legacy_unchanged_and_unknown_version_refused
    path=File.join(@root,'conversations',SoulCore::CpuMemberGateway.digest('old'))
    SoulCore::CpuMemberHandoffGateway.create(path:path,owner:SoulCore::CpuMemberAdapter.new)
    original=File.binread(File.join(path,'roster.json'))
    r=call('Hello',id:'a');call('Legacy',id:'old',conversation:'old');refute @owner.payloads.last['cache_prompt']
    call('Again',id:'a2',history:history('Hello',r));refute @owner.payloads.last['cache_prompt']
    assert_equal original,File.binread(File.join(path,'roster.json'))
    manifest=JSON.parse(original);manifest['service_version']='unknown';File.write(File.join(path,'roster.json'),JSON.generate(manifest))
    assert_raises(SoulCore::CpuMemberGateway::Refused){call('Legacy',id:'old',conversation:'old')}
  end
  def test_model_output_is_not_command
    @owner.text=command;r=call('Hello',id:'r');assert_equal 'text',r['kind'];refute r.key?('execution')
  end
  def test_calculation_rejects_invalid_inputs
    ['{}','{"operation":"eval"}', '{"sources":{},"sources":{}}', 'null', '[]'].each{|x|assert_raises(ArgumentError){call('/calculate '+x,id:'bad'+x.bytesize.to_s,conversation:'invalid')}}
    d=JSON.parse(command.delete_prefix('/calculate '))
    [true,1.5,'847',1_000_001,nil].each{|v|bad=Marshal.load(Marshal.dump(d));bad['sources']['budget']=v;assert_raises(ArgumentError){SoulCore::CpuMemberCalculation.evaluate(bad)}}
    bad=d.merge('left'=>'missing');assert_raises(ArgumentError){SoulCore::CpuMemberCalculation.evaluate(bad)}
    assert_equal 1_000_000_000_000,SoulCore::CpuMemberCalculation.evaluate(d.merge('operation'=>'multiply','sources'=>{'budget'=>1_000_000,'deposit'=>1_000_000}))['result']
    assert_equal [],@owner.payloads
  end
  def test_dashboard_recomputes_receipt
    r=call(command,id:'r');runtime=SoulCore::CpuMemberDashboardRuntime.new(store:nil)
    args=[{'conversation_id'=>'a','request_id'=>'r'},SoulCore::CpuMemberAdapter.new,[{'role'=>'user','content'=>command}],r['content'],SoulCore::CpuMemberAdapter::MODEL]
    runtime.send(:validate_execution!,r['execution'],*args)
    assert_raises(RuntimeError){runtime.send(:validate_execution!,r['execution'].merge('result_sha256'=>'0'*64),*args)}
    args[3]=r['content'].sub('561','999');forged=r['execution'].merge('result_sha256'=>Digest::SHA256.hexdigest(args[3]))
    assert_raises(RuntimeError){runtime.send(:validate_execution!,forged,*args)}
  end
  def test_cache_lineage_restart_and_post_response_cancel
    cache=SoulCore::CpuMemberConversationCache.new(@owner)
    args=['POST','/v1/chat/completions',{}]
    opts={deadline:Process.clock_gettime(Process::CLOCK_MONOTONIC)+10,cancel:->{false}}
    a=cache.client(['same-conversation','lineage-a']);b=cache.client(['same-conversation','lineage-b'])
    a.request(*args,**opts);refute @owner.payloads.last['cache_prompt']
    a.request(*args,**opts);assert @owner.payloads.last['cache_prompt']
    b.request(*args,**opts);refute @owner.payloads.last['cache_prompt']
    @owner.state='unloaded';b.request(*args,**opts);refute @owner.payloads.last['cache_prompt']
    assert_raises(SoulCore::CpuMemberGateway::Refused){b.request(*args,**opts.merge(cancel:->{true}))}
    b.request(*args,**opts);refute @owner.payloads.last['cache_prompt']
  end

end
