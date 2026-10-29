# frozen_string_literal: true
require_relative 'roster_proposal_final_instructions'
require_relative 'roster_tool_proposal_policy'
module SoulCore
  module RosterGptFinalFormat
    SCHEMA = JSON.generate({'anyOf'=>[
      {'type'=>'object','properties'=>{'answer'=>{'type'=>'string','minLength'=>1}},'required'=>['answer'],'additionalProperties'=>false},
      {'type'=>'object','properties'=>{'soul_tool_proposal'=>{'type'=>'object','properties'=>{'tool'=>{'type'=>'string'},'arguments'=>{'type'=>'object'}},'required'=>%w[tool arguments],'additionalProperties'=>false}},'required'=>['soul_tool_proposal'],'additionalProperties'=>false}
    ]}).freeze
    BINDING={'version'=>'gpt-oss-final-json-v1','schema_sha256'=>Digest::SHA256.hexdigest(SCHEMA)}.freeze
    SYSTEM=(RosterProposalFinalInstructions::GPT_OSS+"\n\nNative final JSON format: for ordinary conversation return exactly {\"answer\":\"your answer\"}. For a capability proposal use the existing soul_tool_proposal object instead. The application unwraps answer for display. Do not put a capability proposal inside answer.").freeze
    def self.for_model(model)
      model=='gpt-oss-20b' ? SYSTEM : RosterProposalInstructions::SYSTEM
    end
    def self.response_format
      {'type'=>'json_schema','json_schema'=>{'name'=>'soul_final','strict'=>true,'schema'=>JSON.parse(SCHEMA)}}
    end
    def self.normalize(content)
      value=JSON.parse(content,allow_duplicate_key:false,max_nesting:8)
      raise RosterChatAdapter::Unavailable,'invalid native final envelope' unless value.is_a?(Hash)
      if value.keys==['answer'] && value['answer'].is_a?(String) && !value['answer'].strip.empty? && RosterToolProposalPolicy.resolve(value['answer'])['kind']=='none'
        value['answer']
      elsif value.keys==['soul_tool_proposal'] && RosterToolProposalPolicy.resolve(content)['kind']=='tool'
        content
      else
        raise RosterChatAdapter::Unavailable,'invalid native final envelope'
      end
    rescue JSON::ParserError
      raise RosterChatAdapter::Unavailable,'invalid native final envelope'
    end
  end
end
