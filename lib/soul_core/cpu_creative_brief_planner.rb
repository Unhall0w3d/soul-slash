# frozen_string_literal: true
require_relative 'conversation_creative_planner'
module SoulCore
  class CpuCreativeBriefPlanner < ConversationCreativePlanner
    START=/\A(?:please\s+)?(?:preview|draft|prepare|create|make)\s+(?:an?\s+)?(image|picture|visual|song|music)(?:\s+(?:preview|brief))?(?:\s*:\s*(.*)|\s+(?:of|showing|about)\s+(.+))?\z/i
    FIELDS={'title'=>'title','prompt'=>'visual_prompt','intent'=>'intent','frame'=>'aspect_ratio','duration'=>'duration_seconds','mode'=>'vocal_mode','rights'=>'rights_status','bpm'=>'bpm','key'=>'keyscale','meter'=>'timesignature','seed'=>'seed','exclusions'=>'negative_prompt','lyrics'=>'lyrics','sound'=>'caption'}.freeze
    attr_reader :user_fields
    def initialize(input_digest:,user_fields:[]);@input_digest=input_digest;@user_fields=user_fields.dup;end
    def explicit_request?(message)=!!START.match(message.to_s.lines.first.to_s.strip)
    def self.candidate?(text,prior)
      return false unless text.is_a?(String)
      return true if START.match?(text.lines.first.to_s.strip)||/\A(?:show|cancel) creative preview[.!]?\z/i.match?(text.strip)
      return false unless prior&&!%w[canceled failed complete].include?(prior.dig('flow','lifecycle_state'))
      return true if /\A(?:yes(?:,? please)?|confirm|generate|start|START_CREATIVE_WORKFLOW)[.!]?\z/i.match?(text.strip)
      return true if text.lines.any?{|l|/\A(?:#{FIELDS.keys.join('|')}):/i.match?(l)}
      text.strip.match?(/\A(?:\d+(?:\s*(?:s|seconds?|minutes?))?|\d+:\d\d|instrumental|vocal|vocals|original|licensed|public[_ ]domain)[.!]?\z/i)
    end
    def draft(provider:,chat_id:,messages:,prior:nil)
      text=messages.last.fetch('content');lines=text.lines.map(&:strip).reject(&:empty?)
      start=START.match(lines.first.to_s)
      if start
        @user_fields=[]
        kind=%w[song music].include?(start[1].downcase) ? 'music' : 'visual'
        plan=RESPONSE_KEYS.to_h{|key|[key,'']}.merge('related'=>true,'kind'=>kind,'duration_seconds'=>0,'bpm'=>0,'seed'=>seed(0),'visual_seed'=>seed(8),'user_provided_required'=>[])
        intent=(start[2]||start[3]).to_s.strip
        set(plan,kind=='music' ? 'music_intent' : 'visual_intent',intent) unless intent.empty?
        lines.shift
      else
        raise ArgumentError,'Start with Preview an image: ... or Preview a song: ...' unless prior
        plan=JSON.parse(JSON.generate(prior.fetch('plan')))
        if lines.length==1&&!lines[0].include?(':')
          field=missing_required(plan).first
          prefix={'duration'=>'Duration','mode'=>'Mode','rights status'=>'Rights'}[field]
          lines=["#{prefix}: #{lines[0]}"] if prefix
        elsif lines.length==1&&lines[0].match?(/\A\d+:\d\d\z/)&&missing_required(plan).first=='duration'
          lines=["Duration: #{lines[0]}"]
        end
      end
      seen=[]
      lines.each do |line|
        label,value=line.split(':',2);key=FIELDS[label.to_s.downcase]
        raise ArgumentError,'Use one supported Field: value per line; see Show creative preview for wording.' unless key&&value
        raise ArgumentError,'Duplicate creative field' if seen.include?(key);seen<<key;value=value.strip
        raise ArgumentError,'Creative field exceeds its bound' if value.bytesize>(key=='title' ? 120 : 2000)
        music=plan['kind']=='music'
        raise ArgumentError,'That field belongs to a different Studio' if (music&&%w[visual_prompt aspect_ratio negative_prompt].include?(key))||(!music&&%w[duration_seconds vocal_mode rights_status bpm keyscale timesignature lyrics caption].include?(key))
        actual_key=key=='intent' ? (music ? 'music_intent' : 'visual_intent') : key=='title'&&!music ? 'visual_title' : key=='seed'&&!music ? 'visual_seed' : key
        @user_fields|=[actual_key]
        case key
        when 'intent'
          set(plan,music ? 'music_intent' : 'visual_intent',value)
          plan['visual_prompt']='' if !music&&!@user_fields.include?('visual_prompt')
        when 'duration_seconds'
          m=/\A(\d+)(?:\s*(s|seconds?|minutes?))?[.!]?\z/i.match(value)
          clock=/\A(\d+):([0-5]\d)\z/.match(value)
          number=clock ? clock[1].to_i*60+clock[2].to_i : m ? m[1].to_i*(m[2].to_s.downcase.start_with?('minute') ? 60 : 1) : nil
          raise ArgumentError,'Choose 30–300 whole seconds or exactly 600 seconds.' unless number&&supported_duration?(number)
          set(plan,key,number)
        when 'vocal_mode'
          mode=value.downcase.sub(/[.!]\z/,'').sub(/\Avocals\z/,'vocal');raise ArgumentError,'Choose vocal or instrumental.' unless %w[vocal instrumental].include?(mode);set(plan,key,mode)
        when 'rights_status'
          rights=value.downcase.sub(/[.!]\z/,'').tr(' ','_');raise ArgumentError,'State rights as original, licensed or public_domain.' unless %w[original licensed public_domain].include?(rights);set(plan,key,rights)
        when 'bpm','seed'
          raise ArgumentError,'Use a whole number for BPM/seed.' unless /\A\d+\z/.match?(value)
          number=value.to_i;raise ArgumentError,'BPM/seed is outside its bound.' unless (key=='bpm' ? (30..300) : (0..2_147_483_647)).cover?(number)
          plan[!music&&key=='seed' ? 'visual_seed' : key]=number
        when 'aspect_ratio' then raise ArgumentError,'Choose landscape, square or portrait.' unless %w[landscape square portrait].include?(value.downcase);plan[key]=value.downcase
        when 'title' then plan[music ? key : 'visual_title']=value
        when 'timesignature' then raise ArgumentError,'Use meter 2, 3, 4, 5, 6, 7, 9 or 12.' unless %w[2 3 4 5 6 7 9 12].include?(value);plan[key]=value
        else plan[key]=value
        end
      end
      # Keep supplied scene instructions intact; do not add a "no text" default.
      if plan['kind']=='visual'&&plan['visual_prompt'].empty?&&!plan['visual_intent'].empty?
        plan['visual_prompt']="#{plan['visual_intent']}. Compose a coherent image with deliberate framing and light."
      end
      if plan['kind']=='music'&&plan['vocal_mode']=='vocal'&&plan['lyrics'].empty?
        plan['lyrics']="[Verse]\nA light beyond the quiet door\nA path we have not walked before\n[Chorus]\nWe carry the morning home"
      end
      plan['lyrics']='' if plan['vocal_mode']=='instrumental'
      completed=complete_optional(validate(plan))
      %w[seed visual_seed].each{|key|completed[key]=0 if @user_fields.include?(key)&&plan[key]==0}
      missing=missing_required(completed)
      completed['next_question']={'intent'=>'What should the song convey? Reply Intent: ...','duration'=>'How long should it be? Reply Duration: 90 seconds (30–300, or exactly 600).','mode'=>'Should it be vocal or instrumental? Reply Mode: instrumental.','rights status'=>'What is the rights status? Reply Rights: original, licensed or public_domain.','visual intent'=>'What should the image show? Reply Intent: ...'}[missing.first].to_s
      success(completed)
    rescue ArgumentError=>e
      failed(e.message)
    end
    private
    def set(plan,key,value)
      raise ArgumentError,'Required creative value is empty' if value.to_s.empty?
      raise ArgumentError,'Creative intent exceeds 2000 bytes' if value.is_a?(String)&&value.bytesize>2000
      plan[key]=value;plan['user_provided_required']|=[key];@user_fields|=[key]
    end
    def seed(offset)=(@input_digest[offset,8].to_i(16)%2_147_483_646)+1
  end
end
