# frozen_string_literal: true
require_relative 'conversation_creative_workflow_service'
require_relative 'cpu_creative_brief_planner'
require_relative 'cpu_member_adapter'
require_relative 'continuity_lab/chat_gateway'
module SoulCore
  class CpuCreativePreview
    VERSION='cpu_creative_preview_v1'
    StudioUnavailable=Class.new do
      def method_missing(*) = raise('Preview must not call a Studio execution service')
    end
    # The existing flow-store contract stages task state in memory. Only the CPU
    # journal commits it; there is no second durable store or personal memory.
    class StagedFlowStore < ConversationCreativeFlowStore
      attr_reader :record
      def initialize(record,clock:);@record=record&&JSON.parse(JSON.generate(record));@clock=clock;end
      def active(chat_id)
        validate_chat!(chat_id)
        @record if @record&&@record['chat_id']==chat_id&&!TERMINAL_STATES.include?(@record['lifecycle_state'])
      end
      def write(record)
        value=JSON.parse(JSON.generate(record));validate!(value);value['updated_at']=@clock.call.iso8601;@record=value
      end
      def read(flow_id:,chat_id:)
        value=active(chat_id);value if value&&value['flow_id']==flow_id
      end
    end
    def initialize(root:File.expand_path('../..',__dir__),compute_reader:->{},clock:->{Time.now.utc})
      @root=root;@compute_reader=compute_reader;@clock=clock
    end
    def call(text:,conversation_id:,input_digest:,prior:nil)
      validate!(prior) if prior
      return {'state'=>'awaiting_input','preview'=>prior,'message'=>'Creative requests are limited to 4096 bytes. Please shorten this request.'} if text.bytesize>4096
      value=text.strip
      if /\A(?:show creative preview|yes(?:,? please)?|confirm|generate|start|START_CREATIVE_WORKFLOW)[.!]?\z/i.match?(value)
        return {'state'=>'awaiting_input','preview'=>nil,'message'=>'Start with Preview an image: ... or Preview a song: ...'} unless prior
        return {'state'=>prior['flow']['lifecycle_state'],'preview'=>prior,'message'=>value.downcase.start_with?('show') ? 'Retained preview; compute and configuration were not refreshed.' : 'This is a preview only. Generation needs a separately connected exact approval and compute-handoff action; nothing was queued or started.'}
      end
      if value.match?(/\Acancel creative preview[.!]?\z/i)&&prior
        return {'state'=>'canceled','preview'=>prior,'message'=>'Creative preview is already canceled.'} if prior['flow']['lifecycle_state']=='canceled'
        staged=StagedFlowStore.new(prior['flow'],clock:@clock);flow=staged.cancel(prior['flow']['chat_id']).reject{|k,_|k=='pending_action'}
        record=prior.merge('flow'=>flow,'origin_input_sha256'=>input_digest);record['preview_digest']=digest(record.reject{|k,_|k=='preview_digest'})
        return {'state'=>'canceled','preview'=>record,'message'=>'Creative preview canceled. No work was started.'}
      end
      chat_id='chat_cpu_'+Digest::SHA256.hexdigest(conversation_id)
      planner=CpuCreativeBriefPlanner.new(input_digest:input_digest,user_fields:prior ? prior['user_fields'] : [])
      store=StagedFlowStore.new(prior&&prior['flow'],clock:@clock)
      compute=snapshot_compute
      handoff=Struct.new(:snapshot){def status = {'ok'=>true,'data'=>snapshot}}.new(compute)
      messages=Struct.new(:value){def messages(*) = []}.new(nil)
      workflow=ConversationCreativeWorkflowService.new(root:@root,chat_store:messages,provider_client:nil,
        music_generation:StudioUnavailable.new,visual_studio:StudioUnavailable.new,core_orchestration:nil,
        flow_store:store,planner:planner,compute_handoff:handoff,clock:@clock)
      message=value.match?(/\Acancel creative preview[.!]?\z/i) ? 'cancel creative flow' : text
      result=workflow.plan(chat_id:chat_id,message:message,provider:nil)
      if !result||!store.record||result['mode']=='creative_failed'
        return {'state'=>'awaiting_input','preview'=>prior,'message'=>result ? result['content'] : 'Use explicit creative preview wording.'}
      end
      # Native execution cards remain owned by the Studio. Do not expose or
      # repurpose the legacy chat execution action through LibreChat.
      flow=store.record.reject{|k,_|k=='pending_action'}
      record={'version'=>VERSION,'member'=>CpuMemberAdapter::MODEL,'origin_input_sha256'=>input_digest,'flow'=>flow,
        'profiles'=>profile_snapshot,'compute'=>compute,'user_fields'=>planner.user_fields,'generation_available'=>false}
      record['preview_digest']=digest(record);validate!(record)
      {'state'=>flow['lifecycle_state'],'preview'=>record,'message'=>result['mode']=='creative_awaiting_input' ? flow.dig('plan','next_question') : flow['stage']=='canceled' ? 'Creative preview canceled.' : 'Review the brief below. Proposed optional values can be changed before any generation approval.'}
    end
    def self.digest(value)=ContinuityLab.digest(value)
    def digest(value)=self.class.digest(value)
    def validate!(record)
      raise ArgumentError,'preview schema' unless record.is_a?(Hash)&&record.keys.sort==%w[compute flow generation_available member origin_input_sha256 preview_digest profiles user_fields version]&&record['version']==VERSION&&record['member']==CpuMemberAdapter::MODEL&&record['generation_available']==false
      raise ArgumentError,'preview binding' unless /\A[a-f0-9]{64}\z/.match?(record['origin_input_sha256'].to_s)&&digest(record.reject{|k,_|k=='preview_digest'})==record['preview_digest']
      raise ArgumentError,'preview flow' unless record['flow'].is_a?(Hash)&&!record['flow'].key?('pending_action')&&record['flow']['chat_id'].match?(/\Achat_cpu_[a-f0-9]{64}\z/)&&%w[brief ready canceled].include?(record['flow']['stage'])&&%w[awaiting_input blocked_for_human_review canceled].include?(record['flow']['lifecycle_state'])
      raise ArgumentError,'preview fields' unless record['user_fields'].is_a?(Array)&&record['user_fields'].uniq==record['user_fields']&&(record['user_fields']-ConversationCreativePlanner::RESPONSE_KEYS).empty?
      raise ArgumentError,'preview profiles' unless record['profiles'].is_a?(Hash)&&record['profiles'].keys.sort==%w[music visual]&&record['profiles'].values.all?{|p|p.is_a?(Hash)&&p.keys.sort==%w[configuration_sha256 id label]&&p['id'].is_a?(String)&&p['id'].bytesize.between?(1,128)&&p['label'].is_a?(String)&&p['label'].bytesize.between?(1,512)&&/\A[a-f0-9]{64}\z/.match?(p['configuration_sha256'].to_s)}
      c=record['compute'];raise ArgumentError,'preview compute' unless c.is_a?(Hash)&&c.keys.sort==%w[policy revision state]&&%w[available reserved unknown].include?(c['policy'])&&c['state'].is_a?(String)&&c['state'].bytesize<=40&&(c['revision'].nil?||c['revision'].is_a?(Integer))
      raise ArgumentError,'preview bound' if JSON.generate(record).bytesize>24*1024
      true
    end
    def validate_current!(preview,current:)
      validate!(preview);validate!(current)
      raise ArgumentError,'stale creative preview' unless preview['preview_digest']==current['preview_digest']
      true
    end
    def self.markdown_data(text)
      text.gsub(/([\\`*_{}\[\]()<>!#|])/) { |character| '\\'+character }
    end
    def self.render(outcome)
      r=outcome['preview'];lines=['Soul Creative Studio preview — deterministic planning; no model or GPU work.',markdown_data(outcome['message'])]
      return lines.join("\n") unless r
      plan=r['flow']['plan'];music=plan['kind']=='music';user=r['user_fields']
      labels=music ? {'title'=>'Title','music_intent'=>'Intent','duration_seconds'=>'Duration (seconds)','vocal_mode'=>'Mode','rights_status'=>'Rights','caption'=>'Sound and structure','lyrics'=>'Lyrics','bpm'=>'BPM','keyscale'=>'Key','timesignature'=>'Meter','seed'=>'Seed'} : {'visual_title'=>'Title','visual_intent'=>'Intent','visual_prompt'=>'Prompt','negative_prompt'=>'Exclusions','aspect_ratio'=>'Frame','visual_seed'=>'Seed'}
      labels.each{|key,label|value=plan[key];next if value.nil?;required=%w[music_intent duration_seconds vocal_mode rights_status visual_intent].include?(key);mark=user.include?(key) ? 'user supplied' : required ? 'needed' : 'proposed';lines<<"#{label} (#{mark}): #{value.to_s.empty? ? '(empty)' : markdown_data(value.to_s)}"}
      lines<<'Language (existing Studio default): en' if music
      profile=r['profiles'][music ? 'music' : 'visual'];lines<<"Studio profile: #{markdown_data(profile['label'])} (#{markdown_data(profile['id'])})"
      lines<<"Compute policy at preview: #{r['compute']['policy']}. Generation must recheck availability, admission and handoff."
      lines<<"Preview: #{r['flow']['flow_id']}\nDigest: #{r['preview_digest']}"
      lines<<"State: #{outcome['state']}. Preview stores task state only; it is not generation approval."
      lines<<'Change fields using Title:, Intent:, Prompt:, Frame:, Duration:, Mode:, Rights:, Sound:, Lyrics:, BPM:, Key:, Meter:, Seed: or Exclusions: (one field per line, for the relevant Studio).'
      lines<<'Use Show creative preview to inspect it, or Cancel creative preview to cancel.'
      lines.join("\n").strip
    end
    private
    def snapshot_compute
      raw=@compute_reader.call
      {'policy'=>%w[available reserved].include?(raw['policy']) ? raw['policy'] : 'unknown','state'=>raw['state'].to_s[0,40],'revision'=>raw['revision']}
    rescue StandardError
      {'policy'=>'unknown','state'=>'unverified','revision'=>nil}
    end
    def profile_snapshot
      visual,vsha=read_configuration('visual_studio_models.json');music,msha=read_configuration('music_vulkan_models.json')
      v=visual.fetch('default_profile');m=music.fetch('profile')
      {'visual'=>{'id'=>v,'label'=>visual.fetch('profiles').fetch(v).fetch('label'),'configuration_sha256'=>vsha},
       'music'=>{'id'=>m.fetch('id'),'label'=>m.fetch('label'),'configuration_sha256'=>msha}}
    end
    def read_configuration(name)
      path=File.join(@root,'config',name);stat=File.lstat(path)
      raise ArgumentError,'unsafe Studio configuration' unless stat.file?&&!stat.symlink?&&stat.size<=128*1024
      bytes=File.open(path,File::RDONLY|File::NOFOLLOW) do |file|
        raise ArgumentError,'Studio configuration changed' unless [file.stat.dev,file.stat.ino]==[stat.dev,stat.ino]
        file.read(128*1024+1)
      end
      raise ArgumentError,'Studio configuration bound' if bytes.bytesize>128*1024
      [JSON.parse(bytes,allow_duplicate_key:false),Digest::SHA256.hexdigest(bytes)]
    end
  end
end
