# frozen_string_literal: true
require_relative 'cpu_creative_preview_display'
require_relative 'cpu_member_gateway'
require_relative 'visual_studio_service'
require_relative 'music_generation_service'

module SoulCore
  # Narrow task-state bridge. The CPU owns conversation approval; the native
  # Studio owns its project, exact candidate gate, renderer and artifact review.
  class CreativeStudioBridge
    ID = /\A[a-f0-9]{64}\z/
    OPERATION = 'creative.bridge.generate'
    class Refused < StandardError; end
    def self.digest(value) = ContinuityLab.digest(value)
    def initialize(root:, services:, jobs:)
      @root, @services, @jobs = root, services, jobs
      @mutex = Mutex.new
      parent = CpuMemberGateway::Directory.new(File.join(root,'Soul/private'))
      parent.lock_initialization!
      Dir.mkdir(parent.anchor('creative_studio_bridge_v1'),0700) unless parent.children.include?('creative_studio_bridge_v1')
      @directory = CpuMemberGateway::Directory.new(File.join(root,'Soul/private/creative_studio_bridge_v1'))
      @directory.write('lock',{}) unless @directory.children.include?('lock')
    ensure
      parent&.close
    end

    def prepare(conversation_id:, preview:)
      validate_preview!(conversation_id,preview)
      id = self.class.digest({'conversation_id'=>conversation_id,'preview_digest'=>preview['preview_digest']})
      locked do
        return public_record(id,conversation_id) if exists?(id,'import')
        validate_profiles!(preview)
        services = @services.call(->{false})
        available!(services.fetch(:control))
        plan = preview.fetch('flow').fetch('plan')
        studio = services.fetch(plan['kind']=='visual' ? :visual : :music)
        # Durable intent precedes the first native write. Lost/partial imports
        # can be inspected, but cannot create another project on replay.
        write(id,'import',{'conversation_id'=>conversation_id,'preview'=>preview,'created_at'=>Time.now.utc.iso8601})
        created = plan['kind']=='visual' ? studio.create(visual_attributes(plan,preview)) : studio.create_project(music_attributes(plan))
        raise Refused,'Native project creation failed; retained import requires review.' unless created['ok']
        project = created.fetch('data').fetch('project')
        write(id,'project',{'project_id'=>project.fetch('project_id')})
        gate = studio.generation_preview(project_id:project.fetch('project_id'))
        raise Refused,'Native runtime refused preview; project retained for review.' unless gate['ok']
        action = {'version'=>'creative_bridge_a10_v1','id'=>id,'conversation_id'=>conversation_id,
          'member'=>CpuMemberAdapter::MODEL,'preview_digest'=>preview['preview_digest'],
          'kind'=>plan['kind'],'project_id'=>project['project_id'],'native'=>gate.fetch('data'),
          'profile'=>preview['profiles'][plan['kind']=='visual' ? 'visual' : 'music'],
          'brief'=>plan, 'maximum_seconds'=>1200,
          'handoff'=>'Sequential GPU unload, guarded generation, release; chat reloads on demand.',
          'human_review_required'=>true}
        action['approval_digest']=self.class.digest(action)
        write(id,'ready',action)
        public_record(id,conversation_id)
      end
    end

    def submit(id:,conversation_id:,approval_digest:)
      locked do
        record=authorize!(id,conversation_id);action=read(id,'ready')
        raise Refused,'Exact native approval required.' unless action&&approval_digest==action['approval_digest']
        return public_record(id,conversation_id) if exists?(id,'claim')||exists?(id,'cancel')
        validate_profiles!(record.fetch('preview'))
        available!(@services.call(->{false}).fetch(:control))
        # A claim survives lost responses and job-runner restart. Never resubmit.
        write(id,'claim',{'approval_digest'=>approval_digest,'time'=>Time.now.utc.iso8601})
        begin
          job=@jobs.call.start({'operation'=>OPERATION,'request_id'=>'creative-'+id,
            'parameters'=>{'bridge_id'=>id,'approval_digest'=>approval_digest},'context'=>{'interface'=>'librechat_cpu'}})
          write(id,'job',{'job_id'=>job.fetch('job_id')})
        rescue StandardError=>error
          write(id,'terminal',{'state'=>'blocked_for_human_review','ok'=>false,'reason'=>'Submission not confirmed; no retry.','error_class'=>error.class.name}) unless exists?(id,'terminal')
        end
        public_record(id,conversation_id)
      end
    end

    def status(id:,conversation_id:)
      locked { authorize!(id,conversation_id); public_record(id,conversation_id) }
    end
    def cancel(id:,conversation_id:)
      locked do
        authorize!(id,conversation_id)
        write(id,'cancel',{'time'=>Time.now.utc.iso8601}) unless exists?(id,'cancel')||exists?(id,'terminal')
        public_record(id,conversation_id)
      end
    end

    def execute_job(id:,approval_digest:,progress:)
      action=nil;origin=nil
      locked do
        origin=read(id,'import');action=read(id,'ready')
        raise Refused,'Unclaimed native action.' unless origin&&action&&read(id,'claim')&.fetch('approval_digest')==approval_digest&&action['approval_digest']==approval_digest
        return envelope(id,read(id,'terminal')) if exists?(id,'terminal')
        raise Refused,'Generation already attempted; no retry.' if exists?(id,'started')
        write(id,'started',{'time'=>Time.now.utc.iso8601})
      end
      cutoff=Process.clock_gettime(Process::CLOCK_MONOTONIC)+1200
      canceled=->{Process.clock_gettime(Process::CLOCK_MONOTONIC)>=cutoff||locked{exists?(id,'cancel')}}
      if canceled.call
        result={'state'=>'canceled','ok'=>false,'reason'=>'Canceled before native execution; no renderer started.'}
      else
        validate_profiles!(origin.fetch('preview'))
        services=@services.call(canceled);available!(services.fetch(:control))
        studio=services.fetch(action['kind']=='visual' ? :visual : :music)
        native=action.fetch('native')
        outcome=services.fetch(:handoff).with_origin(member:CpuMemberAdapter::MODEL,conversation_id:origin['conversation_id']) do
          studio.generation_execute(project_id:action['project_id'],candidate_id:native.fetch('candidate_id'),
            confirmation:native.fetch('confirmation_phrase'),expected_digest:native.fetch('expected_digest'),progress:progress)
        end
        released=services.fetch(:control).status
        clean=released['ok']&&released.dig('data','handoff').nil?&&%w[unloaded resident].include?(released.dig('data','state'))
        result={'cleanup_confirmed'=>!!clean,'state'=>(canceled.call&&!outcome['ok']&&clean ? 'canceled' : outcome['lifecycle_state']),'ok'=>outcome['ok']==true,
          'reason'=>outcome['ok'] ? 'Candidate generated; human review required. Nothing exported or published.' : 'Native generation stopped; inspect retained Studio evidence. No retry.',
          'native_outcome'=>outcome,'cancellation_requested'=>canceled.call}
      end
      locked { write(id,'terminal',result) };envelope(id,result)
    rescue StandardError=>error
      result={'state'=>'blocked_for_human_review','ok'=>false,'reason'=>'Execution interrupted or refused; retained evidence and any compute hold require review. No retry.','error_class'=>error.class.name}
      locked { write(id,'terminal',result) unless exists?(id,'terminal') };envelope(id,result)
    end

    def self.validate_public!(r)
      raise Refused,'Creative public receipt schema.' unless r.is_a?(Hash)&&r.keys.sort==%w[action artifacts conversation_id id message preview_digest state terminal]&&ID.match?(r['id'].to_s)&&ID.match?(r['preview_digest'].to_s)&&CpuMemberGateway::ID.match?(r['conversation_id'].to_s)&&%w[prepared running cancel_requested canceled failed awaiting_input blocked_for_human_review].include?(r['state'])&&r['message'].is_a?(String)&&r['message'].bytesize<=1024&&JSON.generate(r).bytesize<=128*1024
      a=r['action']
      if a
        raise Refused,'Creative native action schema.' unless a.keys.sort==%w[approval_digest brief conversation_id handoff human_review_required id kind maximum_seconds member native preview_digest profile project_id version]&&a.values_at('id','conversation_id','preview_digest')==r.values_at('id','conversation_id','preview_digest')&&a['version']=='creative_bridge_a10_v1'&&a['member']==CpuMemberAdapter::MODEL&&a['human_review_required']==true&&%w[visual music].include?(a['kind'])&&a['approval_digest']==digest(a.reject{|k,_|k=='approval_digest'})
        raise Refused,'Creative action presentation.' unless a['brief'].is_a?(Hash)&&a['brief']['kind']==a['kind']&&a['profile'].is_a?(Hash)&&a['profile']['label'].is_a?(String)&&a['profile']['label'].bytesize<=512&&a['maximum_seconds']==1200&&a['handoff']=='Sequential GPU unload, guarded generation, release; chat reloads on demand.'
        visual=a['kind']=='visual'
        raise Refused,'Native identities.' unless (visual ? VisualStudioService::PROJECT_ID : MusicProjectStore::PROJECT_ID).match?(a['project_id'].to_s)&&(visual ? VisualStudioService::CANDIDATE_ID : MusicProjectStore::CANDIDATE_ID).match?(a.dig('native','candidate_id').to_s)&&ID.match?(a.dig('native','expected_digest').to_s)&&a.dig('native','confirmation_phrase')==(visual ? VisualStudioService::CONFIRMATION : MusicGenerationService::CONFIRMATION)
      end
      raise Refused,'Creative artifacts.' unless r['artifacts'].is_a?(Array)&&r['artifacts'].size<=2
      r['artifacts'].each do |artifact|
        raise Refused,'Unbound creative artifact.' unless a&&r.dig('terminal','ok')==true&&artifact.keys.sort==%w[label url]&&artifact['label'].is_a?(String)&&artifact['label'].bytesize<=100
        base='https://atelier.herz.soul:8443/api/v1'
        urls=a['kind']=='visual' ? ["#{base}/visual/image/#{a['project_id']}/#{a.dig('native','candidate_id')}"] : %w[mp3 flac].map{|f|"#{base}/music/audio/#{a['project_id']}/#{a.dig('native','candidate_id')}/#{f}"}
        raise Refused,'Foreign artifact URL.' unless urls.include?(artifact['url'])
      end
      r
    end

    def self.presentation(record)
      lines=['Soul Creative Studio — deterministic control; CPU model not invoked.',record.fetch('message'),"State: #{record.fetch('state')}","Creative receipt: #{record.fetch('id')}"]
      if (action=record['action'])
        lines << "Native project: #{action.fetch('project_id')}\nNative candidate: #{action.fetch('native').fetch('candidate_id')}"
        brief=action.fetch('brief')
        label=action['kind']=='visual' ? brief['visual_title'] : brief['title']
        lines << "Title: #{CpuCreativePreviewDisplay.markdown_data(label)}\nProfile: #{CpuCreativePreviewDisplay.markdown_data(action.fetch('profile').fetch('label'))}"
        lines << (action['kind']=='visual' ? "Frame: #{brief['aspect_ratio']}; seed: #{brief['visual_seed']}" : "Duration: #{brief['duration_seconds']} seconds; mode: #{brief['vocal_mode']}; rights: #{brief['rights_status']}; seed: #{brief['seed']}")
        lines << "Maximum: #{action.fetch('maximum_seconds')} seconds, including the native stage limits."
        lines << action.fetch('handoff')
        if record['state']=='prepared'
          keys=action['kind']=='visual' ? %w[visual_intent visual_prompt negative_prompt] : %w[music_intent caption lyrics bpm keyscale timesignature]
          keys.each{|key|lines << "#{key.tr('_',' ')}: #{CpuCreativePreviewDisplay.markdown_data(brief[key].to_s)}"}
        end
        lines << "Approve exactly this native action by sending:\nGenerate creative #{action.fetch('approval_digest')}" if record['state']=='prepared'
      end
      record.fetch('artifacts',[]).each do |a|
        lines << "[#{a.fetch('label')}](#{a.fetch('url')})"
      end
      lines << "Check: Creative status #{record['id']}\nCancel: Cancel creative generation #{record['id']}"
      lines << 'Generation approval does not approve the result, export it or publish it.'
      lines.join("\n\n")
    end

    private
    def locked
      @mutex.synchronize do
        @directory.verify!
        lock=@directory.open_file('lock',File::RDWR)
        raise Refused,'Creative bridge busy.' unless lock.flock(File::LOCK_EX|File::LOCK_NB)
        yield
      ensure
        lock&.close
      end
    end
    def leaf(id,stage)
      raise Refused,'Creative receipt identity.' unless ID.match?(id.to_s)
      "#{id}-#{stage}.json"
    end
    def exists?(id,stage)=@directory.children.include?(leaf(id,stage))
    def read(id,stage)=exists?(id,stage) ? @directory.read(leaf(id,stage),256*1024) : nil
    def write(id,stage,data)=@directory.write(leaf(id,stage),data)
    def authorize!(id,conversation)
      value=read(id,'import');raise Refused,'Creative conversation scope mismatch.' unless value&&value['conversation_id']==conversation
      value
    end
    def validate_preview!(conversation,preview)
      CpuCreativePreview.new.validate!(preview)
      plan=preview.dig('flow','plan')
      raise Refused,'Ready current creative preview required.' unless conversation.is_a?(String)&&CpuMemberGateway::ID.match?(conversation)&&preview.dig('flow','chat_id')=='chat_cpu_'+Digest::SHA256.hexdigest(conversation)&&preview.dig('flow','stage')=='ready'&&preview.dig('flow','lifecycle_state')=='blocked_for_human_review'&&%w[visual music].include?(plan['kind'])
      raise Refused,'Existing sources are outside this bridge.' unless plan['existing_music_title'].to_s.empty?&&plan['existing_visual_title'].to_s.empty?
      ConversationCreativePlanner.new(provider_client:nil).send(:missing_required,plan).empty? || raise(Refused,'Required choices missing.')
      # Invoke the same ready-plan validator before any native mutation.
      ConversationCreativeWorkflowService.allocate.send(:validate_ready_plan!,plan)
    end
    def validate_profiles!(preview)
      current=CpuCreativePreview.new(root:@root).send(:profile_snapshot)
      raise Refused,'Studio configuration changed; revise and review the brief again.' unless current==preview['profiles']
    end
    def available!(control)
      s=control.status
      raise Refused,'Compute unavailable, busy or held. Refer to Compute Availability; no job was started.' unless s['ok']&&s.dig('data','policy')=='available'&&s.dig('data','handoff').nil?&&%w[unloaded resident].include?(s.dig('data','state'))
    end
    def visual_attributes(p,r)
      {'title'=>p['visual_title'],'intent'=>p['visual_intent'],'prompt'=>p['visual_prompt'],'negative_prompt'=>p['negative_prompt'],'aspect_ratio'=>p['aspect_ratio'],'seed'=>p['visual_seed'],'profile_id'=>r.dig('profiles','visual','id')}
    end
    def music_attributes(p)
      {'title'=>p['title'],'intent'=>p['music_intent'],'target_duration_seconds'=>p['duration_seconds'],'vocal_mode'=>p['vocal_mode'],'rights_status'=>p['rights_status'],'caption'=>p['caption'],'lyrics'=>p['vocal_mode']=='instrumental' ? '' : p['lyrics'],'bpm'=>p['bpm'],'keyscale'=>p['keyscale'],'timesignature'=>p['timesignature'],'language'=>'en','seed'=>p['seed']}
    end
    def public_record(id,conversation)
      origin=authorize!(id,conversation);action=read(id,'ready');terminal=read(id,'terminal')
      state=if terminal;terminal['ok'] ? 'blocked_for_human_review' : terminal['state']
      elsif exists?(id,'claim');exists?(id,'cancel') ? 'cancel_requested' : 'running'
      elsif exists?(id,'cancel');'canceled'
      elsif action;'prepared'
      else;'blocked_for_human_review';end
      message=if terminal;terminal['reason']
      elsif state=='prepared';'Native project created; review the exact native generation action before approving.'
      elsif state=='running';'Bounded native generation submitted once. Check this receipt for completion; no automatic retry.'
      elsif state=='cancel_requested';'Cancellation requested. This is not proof that the renderer has exited or compute is released.'
      elsif state=='canceled';'Native generation canceled before submission.'
      else;'Import is incomplete; retained project/write evidence requires review. No retry.';end
      if %w[running cancel_requested].include?(state)&&exists?(id,'job')
        job=@jobs.call.record(read(id,'job')['job_id'])
        if !job||job['status']=='terminal'
          state='blocked_for_human_review';message='Job ended without a native terminal receipt; interruption requires review. No retry.'
        end
      end
      result={'id'=>id,'conversation_id'=>conversation,'preview_digest'=>origin.dig('preview','preview_digest'),'state'=>state,'message'=>message,'action'=>action,'artifacts'=>[],'terminal'=>terminal&&terminal.reject{|k,_|k=='native_outcome'}}
      if terminal&&terminal['ok']
        outcome=terminal.fetch('native_outcome');candidate=outcome.dig('data','candidate')
        raise Refused,'Native artifact attribution changed.' unless candidate&&candidate['project_id']==action['project_id']&&candidate['candidate_id']==action.dig('native','candidate_id')&&candidate['human_review_required']==true
        base='https://atelier.herz.soul:8443/api/v1'
        if action['kind']=='visual'
          result['artifacts']=[{'label'=>'Open generated image for review','url'=>"#{base}/visual/image/#{action['project_id']}/#{candidate['candidate_id']}"}]
        else
          result['artifacts']=%w[mp3 flac].map{|format|{'label'=>format=='mp3' ? 'Listen to generated music' : 'Open lossless review audio','url'=>"#{base}/music/audio/#{action['project_id']}/#{candidate['candidate_id']}/#{format}"}}
        end
      end
      self.class.validate_public!(result)
    end
    def envelope(id,result)
      {'schema_version'=>'soul.application.v1','request_id'=>'creative-'+id,'operation'=>OPERATION,'ok'=>result['ok'],'lifecycle_state'=>result['state'],'data'=>result,'errors'=>[],'warnings'=>[],'meta'=>{'mutation'=>'creative_native_attempt'}}
    end
  end
end
