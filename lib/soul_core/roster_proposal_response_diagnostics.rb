# frozen_string_literal: true
module SoulCore
  # Metadata only: never serialize model text, reasoning, tool arguments or errors.
  module RosterProposalResponseDiagnostics
    REASONS = {
      'invalid response identity or choices'=>'identity_or_choices',
      'invalid choice'=>'choice',
      'incomplete or non-answer completion'=>'finish_reason',
      'final text absent or unexpected tool request'=>'final_text_or_tool_request',
      'invalid or excessive token usage'=>'token_usage',
      'native template and generation token counts differ'=>'template_token_count'
    }.freeze
    FINISHES = %w[stop length tool_calls function_call content_filter other absent].freeze
    TYPES = %w[absent null string array object other].freeze
    def self.type(h,k)
      return 'absent' unless h.key?(k)
      case h[k];when NilClass then 'null';when String then 'string';when Array then 'array';when Hash then 'object';else 'other';end
    end
    def self.number(n) = n.is_a?(Integer) && n.between?(0,1_000_000) ? n : nil
    def self.capture(response, model:)
      r=response.is_a?(Hash) ? response : {};choices=r['choices'];c=choices.is_a?(Array) && choices.first.is_a?(Hash) ? choices.first : {}
      m=c['message'].is_a?(Hash) ? c['message'] : {};u=r['usage'].is_a?(Hash) ? r['usage'] : {}
      finish=c.key?('finish_reason') ? (FINISHES.include?(c['finish_reason']) ? c['finish_reason'] : 'other') : 'absent'
      {'response_object'=>response.is_a?(Hash),'error_present'=>r.key?('error'),'model_matches'=>r['model']==model,
       'choice_count'=>choices.is_a?(Array) ? number(choices.length) : nil,'choice_index_zero'=>c['index']==0,
       'finish_reason'=>finish,'message_object'=>c['message'].is_a?(Hash),'assistant_role'=>m['role']=='assistant',
       'content_type'=>type(m,'content'),'content_bytes'=>m['content'].is_a?(String) ? number(m['content'].bytesize) : nil,
       'tool_calls_type'=>type(m,'tool_calls'),'tool_call_count'=>m['tool_calls'].is_a?(Array) ? number(m['tool_calls'].length) : nil,
       'function_call_present'=>m.key?('function_call'),
       'usage'=>%w[prompt_tokens completion_tokens total_tokens].to_h{|k|[k,number(u[k])]}}
    end
    def self.valid?(d)
      return false unless d.is_a?(Hash) && d.keys.sort==(capture(nil,model:'').keys+['reason']).sort
      return false unless (REASONS.values+['unclassified']).include?(d['reason'])
      return false unless %w[response_object error_present model_matches choice_index_zero message_object assistant_role function_call_present].all?{|k|[true,false].include?(d[k])}
      return false unless FINISHES.include?(d['finish_reason']) && %w[content_type tool_calls_type].all?{|k|TYPES.include?(d[k])}
      return false unless %w[choice_count content_bytes tool_call_count].all?{|k|d[k].nil? || number(d[k])==d[k]}
      d['usage'].is_a?(Hash) && d['usage'].keys.sort==%w[completion_tokens prompt_tokens total_tokens] && d['usage'].values.all?{|v|v.nil? || number(v)==v}
    end
  end
end
