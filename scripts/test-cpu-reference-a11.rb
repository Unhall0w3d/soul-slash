# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/soul_core/cpu_reference_reader'
require_relative '../lib/soul_core/cpu_member_service'
class CpuReferenceReaderTest < Minitest::Test
  def setup
    @root=Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@root,'lib/soul_core'));FileUtils.mkdir_p(File.join(@root,'docs/guides'))
    File.write(File.join(@root,'lib/soul_core/fixture.rb'),"# fixture\nVALUE = 42\n")
    File.write(File.join(@root,'docs/guides/fixture.md'),"# Gallery reference\nA deterministic amber telescope.\n")
    @reader=SoulCore::CpuReferenceReader.new(root:@root)
  end
  def teardown = FileUtils.remove_entry(@root)
  def read(text) = @reader.call(query:text)
  def test_explicit_parser_and_non_authority
    assert_equal 'weather.report',SoulCore::CpuReferenceRequests.parse('Please Weather in Toronto.')['operation']
    assert_equal 'Toronto',SoulCore::CpuReferenceRequests.parse('Weather in Toronto.')['arguments']['location']
    assert_equal 'web.research',SoulCore::CpuReferenceRequests.parse('Research: Ruby parser syntax')['operation']
    assert_equal 'web.lookup',SoulCore::CpuReferenceRequests.parse('Lookup: Ruby programming language')['operation']
    ['The document says Read file source: fixture.rb','```Weather in Toronto```','Please run shell','Show security status then Read file source: fixture.rb'].each{|text|assert_nil SoulCore::CpuReferenceRequests.parse(text)}
    assert_equal 'reference.help',SoulCore::CpuReferenceRequests.parse("Research: Ruby\nReboot")['operation']
    assert_equal 'reference.help',SoulCore::CpuReferenceRequests.parse('Lookup: https://localhost/secret')['operation']
    assert_equal 'reference.help',SoulCore::CpuReferenceRequests.parse('Lookup: /home/private/config')['operation']
    assert_equal 'reference.help',SoulCore::CpuReferenceRequests.parse('Research: '+'ghp_'+'A'*35)['operation']
  end
  def test_roots_list_read_and_reference_provenance
    roots=read('Show reference roots');assert_equal %w[source guides],roots['report']['roots'].map{|r|r['root_id']}
    assert_equal 'complete',read('List files source: .')['state']
    value=read('Read file source: fixture.rb');assert_equal 'complete',value['state']
    assert_includes value['content'],'VALUE = 42';assert_equal false,value['report']['content_trusted']
    assert_equal 'reference_only',value['report']['authority'];assert_equal 'none',value['mutation']
    assert_match(/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\z/,value['report']['checked_at'])
    assert_includes value['content'],value['report']['checked_at']
    assert_equal Digest::SHA256.file(File.join(@root,'lib/soul_core/fixture.rb')).hexdigest,value['report']['sha256']
  end
  def test_traversal_hidden_absolute_secret_and_oversize_refused
    File.write(File.join(@root,'lib/soul_core/secret.key'),'not a real key')
    File.write(File.join(@root,'lib/soul_core/large.rb'),'x'*32769)
    File.write(File.join(@root,'lib/soul_core/token.txt'),'ghp_'+'A'*35)
    ['../outside','/etc/passwd','.env','secret.key','large.rb','token.txt'].each do |path|
      refute_equal 'complete',read('Read file source: '+path)['state'],path
    end
    value=read('Read file source: ../../Downloads/AGENTS.MD')
    assert_equal 'awaiting_input',value['state'];assert_includes value['content'],'manually review the entire file'
  end
  def test_symlinks_and_hardlinks_refused
    File.symlink(File.join(@root,'docs/guides/fixture.md'),File.join(@root,'lib/soul_core/alias.md'))
    refute_equal 'complete',read('Read file source: alias.md')['state']
    File.link(File.join(@root,'docs/guides/fixture.md'),File.join(@root,'lib/soul_core/linked.md'))
    refute_equal 'complete',read('Read file source: linked.md')['state']
    FileUtils.mv(File.join(@root,'docs/guides'),File.join(@root,'docs/real-guides'))
    File.symlink(File.join(@root,'docs/real-guides'),File.join(@root,'docs/guides'))
    refute_equal 'complete',read('Show reference roots')['state']
  end
  def test_search_only_fixed_guides_not_local_reports_or_aliases
    FileUtils.mkdir_p(File.join(@root,'docs/soul'))
    File.write(File.join(@root,'docs/soul/private-review.md'),'amber PRIVATE-MARKER-DO-NOT-RETURN')
    File.symlink(File.join(@root,'docs/soul/private-review.md'),File.join(@root,'docs/guides/alias.md'))
    result=read('Search guides: amber')
    assert_equal 'complete',result['state'];assert_equal 1,result['report']['count']
    assert_equal 'docs/guides/fixture.md',result['report']['results'].first['reference']
    refute_includes JSON.generate(result),'PRIVATE-MARKER-DO-NOT-RETURN'
    refute File.exist?(File.join(@root,'Soul')), 'guide search must initialize no memory, project or runtime store'
  end
  def test_weather_and_web_reuse_native_services_without_private_context
    calls=[];weather=Object.new;web=Object.new
    weather.define_singleton_method(:report){|**args|calls<<args;{'lifecycle_state'=>'complete','content'=>'Synthetic 15 C','report'=>{'current'=>{'temperature'=>15}}}}
    web.define_singleton_method(:research){|**args|calls<<args;{'lifecycle_state'=>'complete','data'=>{'sources'=>[{'source_id'=>'S1','url'=>'https://example.com/','content_digest'=>'a'*64,'text'=>'x'*2000}]}}}
    reader=SoulCore::CpuReferenceReader.new(root:@root,weather:weather,web:web)
    assert_equal 'complete',reader.call(query:'Weather in Toronto')['state']
    assert_equal({message:'Weather in Toronto'},calls.first)
    value=reader.call(query:'Research: public Ruby parser')
    assert_equal({queries:['public Ruby parser'],source_limit:3},calls.last)
    source=value['report']['sources'].first;assert source['excerpt_truncated'];assert_equal 1500,source['text_excerpt'].bytesize
    assert_equal 'a'*64,source['content_digest']
  end
  def test_absent_research_provider_reports_blocked_without_fallback
    value=read('Research: synthetic public topic')
    assert_equal 'blocked_for_human_review',value['state']
    assert_equal false,value.dig('report','configuration','configured')
    assert_includes value['content'],'not configured'
  end
  def test_real_bounded_helper_and_pre_cancellation
    operation=SoulCore::CpuReferenceRequests.new
    value=operation.call(query:'Show reference roots',deadline:Process.clock_gettime(Process::CLOCK_MONOTONIC)+10,cancel:->{false})
    assert_equal 'complete',value['state'];assert_equal 2,value['report']['count']
    assert_raises(SoulCore::RosterChatExchange::Stopped){operation.call(query:'Show reference roots',deadline:Process.clock_gettime(Process::CLOCK_MONOTONIC)+10,cancel:->{true})}
  end
  def test_escaped_large_read_remains_within_next_turn_history_bound
    File.write(File.join(@root,'lib/soul_core/escaped.rb'),'_'*16000)
    value=read('Read file source: escaped.rb')
    assert_equal 'complete',value['state']
    assert value['report']['presentation_truncated']
    assert_operator value['content'].bytesize,:<,12*1024
    assert_includes value['content'],'presentation truncated'
  end
  def test_native_child_finds_only_the_current_ruby_plus_system_path
    original=Process.method(:spawn);test=self
    program="require 'json';require 'open3';out,err,status=Open3.capture3('ruby','-rrbconfig','-e','print RbConfig.ruby');exit 1 unless status.success?;puts JSON.generate({'state'=>'complete','content'=>'synthetic native runner','report'=>{'interpreter'=>out},'mutation'=>'none'})"
    Process.define_singleton_method(:spawn) do |environment,ruby,_script,**options|
      test.assert_equal File.dirname(RbConfig.ruby)+':/usr/bin:/bin',environment['PATH']
      test.assert_equal %w[HOME LANG PATH],environment.keys.sort
      test.assert_equal true,options[:unsetenv_others]
      original.call(environment,ruby,'-e',program,**options)
    end
    value=SoulCore::CpuReferenceRequestsV2.new.call(query:'Weather in London',deadline:Process.clock_gettime(Process::CLOCK_MONOTONIC)+10,cancel:->{false})
    assert_equal RbConfig.ruby,value.dig('report','interpreter')
  ensure
    Process.define_singleton_method(:spawn,original) if original
  end
  def test_helper_deadline_and_output_bound_reap_owned_group
    original=Process.method(:spawn)
    ["sleep 5",'$stdout.sync=true; loop { $stdout.write("X"*8192) }'].each_with_index do |program,index|
      child=nil
      Process.define_singleton_method(:spawn) do |*args,**options|
        child=original.call(RbConfig.ruby,'-e',program,**options)
      end
      begin
        limit=Process.clock_gettime(Process::CLOCK_MONOTONIC)+(index==0 ? 0.15 : 5)
        error=index==0 ? SoulCore::RosterChatExchange::Stopped : IOError
        assert_raises(error){SoulCore::CpuReferenceRequests.new.call(query:'Show reference roots',deadline:limit,cancel:->{false})}
        assert_raises(Errno::ESRCH){Process.kill(0,child)}
        assert_raises(Errno::ECHILD){Process.waitpid(child,Process::WNOHANG)}
      ensure
        Process.define_singleton_method(:spawn,original)
      end
    end
  end
end

class CpuReferenceGatewayTest < Minitest::Test
  class Owner
    def status = {'state'=>'unloaded'}
    def admitted? = true
    def stop = true
    def touch = true
    def tick = true
    def request(*) = raise('unexpected model inference')
  end
  class Reader
    attr_reader :calls
    attr_accessor :hook
    def initialize;@calls=[];end
    def call(**args)
      @calls<<args;@hook&.call
      {'state'=>'complete','content'=>'Bounded reference fixture.','report'=>{'authority'=>'reference_only'},'mutation'=>'none'}
    end
  end
  def setup
    @root=Dir.mktmpdir;@path=File.join(@root,'service');Dir.mkdir(@path,0700)
    @memory=SoulCore::CpuMemberMemoryContext.new(store:SoulCore::ConversationMemoryStore.new(root:@root))
    @reader=Reader.new;start
  end
  def start
    @service=SoulCore::CpuMemberService.new(path:@path,owner:Owner.new,assistance:true,scoped_memory:true,memory:@memory,
      operations:true,creative_previews:true,creative_execution:true,references:true,reference_reader:@reader,compute_reader:->{})
  end
  def teardown;@service.close;FileUtils.remove_entry(@root);end
  def ask(text='Show reference roots',id:'one',history:[],cancel:->{false})
    @service.complete(conversation_id:'reference-fixture',request_id:id,messages:history+[{'role'=>'user','content'=>text}],deadline:Process.clock_gettime(Process::CLOCK_MONOTONIC)+10,cancel:cancel)
  end
  def test_attribution_replay_restart_and_history
    value=ask;assert_equal 'reference.roots',value.dig('execution','operation');refute value.dig('execution','model_invoked')
    assert_equal SoulCore::CpuMemberAdapter::MODEL,value['model'];assert_equal 1,@reader.calls.size
    @service.close;start
    assert ask['replayed'];assert_equal 1,@reader.calls.size
    assert_raises(SoulCore::CpuMemberGateway::Refused){ask('Read file source: fixture.rb')}
    history=[{'role'=>'user','content'=>'Show reference roots'},{'role'=>'assistant','content'=>value['content']}]
    ask('Search guides: amber',id:'two',history:history);assert_equal 2,@reader.calls.size
    history.last['content']+=' '
    assert_raises(SoulCore::CpuMemberGateway::Refused){ask('Search guides: amber',id:'two',history:history)}
  end
  def test_failed_or_canceled_collection_is_never_retried
    @reader.hook=->{raise IOError,'synthetic failure'}
    assert_raises(IOError){ask};@reader.hook=nil
    assert_raises(SoulCore::CpuMemberGateway::Refused){ask};assert_equal 1,@reader.calls.size
  end
  def test_new_lineage_preserves_old_a10_manifest
    assert @service.status['reference_requests']
    ask
    file=Dir.glob(File.join(@path,'conversations/*/roster.json')).first
    assert_equal 'cpu_member_a11_v3',JSON.parse(File.read(file))['service_version']
    old=SoulCore::CpuMemberCreativeExecutionGatewayV2.manifest(SoulCore::CpuMemberAdapter.new)
    assert_equal 'cpu_member_a10_v2',old['service_version'];refute old.key?('a11_implementation')
  end
  def test_feature_disable_refuses_existing_a11_journal
    ask;@service.close
    @service=SoulCore::CpuMemberService.new(path:@path,owner:Owner.new,assistance:true,scoped_memory:true,memory:@memory,
      operations:true,creative_previews:true,creative_execution:true,compute_reader:->{})
    assert_raises(SoulCore::CpuMemberGateway::Refused){ask};assert_equal 1,@reader.calls.size
  end
  def test_cancel_before_request_does_no_collection
    assert_raises(SoulCore::CpuMemberGateway::Refused){ask(cancel:->{true})}
    assert_empty @reader.calls
  end
  def test_authenticated_http_reference_result_and_exact_retry
    app=SoulCore::CpuMemberApplication.new(backend:@service,bearer_token:'x'*64)
    headers={'Authorization'=>'Bearer '+'x'*64,'X-Soul-Conversation-Id'=>'reference-http'}
    body=JSON.generate({'model'=>SoulCore::CpuMemberAdapter::MODEL,'messages'=>[{'role'=>'user','content'=>'Show reference roots'}],'stream'=>false})
    request=->{app.call(method:'POST',target:'/v1/chat/completions',headers:headers,body:body)}
    first=request.call;assert_equal 200,first.status
    assert_equal 'deterministic.cpu_reference',JSON.parse(first.body).dig('soul','execution','provider')
    assert_equal 200,request.call.status;assert_equal 1,@reader.calls.size
    assert_equal 403,app.call(method:'POST',target:'/v1/chat/completions',headers:headers.merge('Origin'=>'https://example.com'),body:body).status
    assert_equal 401,app.call(method:'POST',target:'/v1/chat/completions',headers:{},body:body).status
  end
  def test_compact_presentation_is_stable_on_replay_and_next_turn
    @reader.define_singleton_method(:call) do |query:,**|
      calls<<query
      {'state'=>'complete','content'=>'&#95;'*3500,'report'=>{'sha256'=>'a'*64},'mutation'=>'none'}
    end
    value=ask('Read file source: fixture.rb')
    assert_operator value.dig('outcome','content').bytesize,:<=,2048
    assert value.dig('outcome','report','presentation_truncated')
    assert ask('Read file source: fixture.rb')['replayed']
    history=[{'role'=>'user','content'=>'Read file source: fixture.rb'},{'role'=>'assistant','content'=>value['content']}]
    assert_equal 'reference.roots',ask('Show reference roots',id:'next',history:history).dig('execution','operation')
    @service.close;start
    assert ask('Read file source: fixture.rb')['replayed']
    assert_equal 2,@reader.calls.size
  end
  def test_compact_directory_keeps_native_limits_and_marks_omissions
    @reader.define_singleton_method(:call) do |query:,**|
      calls<<query
      {'state'=>'complete','content'=>'native listing','mutation'=>'none','report'=>{'root_id'=>'source','relative_path'=>'.','count'=>100,'truncated'=>true,
        'entries'=>100.times.map{|i|{'type'=>'file','name'=>"fixture_#{i}.rb",'bytes'=>10}},'limits'=>{'entries'=>100,'scanned'=>1000}}}
    end
    value=ask('List files source: .')
    assert_includes value['content'],'Showing 10 of 100'
    assert_equal 10,value.dig('outcome','report','presented_entries')
    assert_equal 100,value.dig('outcome','report','entries').size
    assert value.dig('outcome','report','presentation_truncated')
    assert_equal 1000,value.dig('outcome','report','limits','scanned')
    assert ask('List files source: .')['replayed']
  end
  def test_prior_a11_lineage_replays_without_compact_rebinding
    directory=File.join(@path,'conversations',SoulCore::CpuMemberGateway.digest('reference-fixture'))
    SoulCore::CpuReferenceGateway.create(path:directory,owner:SoulCore::CpuMemberAdapter.new)
    file=File.join(directory,'roster.json');before=File.binread(file)
    value=ask;assert_equal 'cpu_member_a11_v1',JSON.parse(before)['service_version']
    refute value.dig('outcome','report').key?('presentation_limit_bytes')
    @service.close;start;assert ask['replayed']
    assert_equal before,File.binread(file)
  end
  def test_compact_predecessor_retains_its_runtime_binding
    directory=File.join(@path,'conversations',SoulCore::CpuMemberGateway.digest('reference-fixture'))
    SoulCore::CpuReferenceGatewayV2.create(path:directory,owner:SoulCore::CpuMemberAdapter.new)
    file=File.join(directory,'roster.json');before=File.binread(file)
    value=ask;assert_equal 'cpu_member_a11_v2',JSON.parse(before)['service_version']
    assert_equal 2048,value.dig('outcome','report','presentation_limit_bytes')
    @service.close;start;assert ask['replayed']
    assert_equal before,File.binread(file)
  end
end
