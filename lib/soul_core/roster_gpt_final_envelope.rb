# frozen_string_literal: true
require_relative 'roster_gpt_final_format'
module SoulCore
  module RosterGptFinalEnvelope
    BINDING=RosterGptFinalFormat::BINDING
    def self.response_format = RosterGptFinalFormat.response_format
    def self.normalize(content)
      value=JSON.parse(content,allow_duplicate_key:false,max_nesting:8)
      proposal=value.is_a?(Hash) && value.keys==['soul_tool_proposal'] && value['soul_tool_proposal']
      # The native envelope validates shape. The unchanged dispatcher decides
      # scope and retains its correction response for unsupported proposals.
      if proposal.is_a?(Hash) && proposal.keys.sort==%w[arguments tool] && proposal['tool'].is_a?(String) && proposal['arguments'].is_a?(Hash)
        content
      else
        RosterGptFinalFormat.normalize(content)
      end
    rescue JSON::ParserError
      raise RosterChatAdapter::Unavailable,'invalid native final envelope'
    end
  end
end
