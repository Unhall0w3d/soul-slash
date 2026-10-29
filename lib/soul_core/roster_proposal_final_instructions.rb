# frozen_string_literal: true
require_relative 'roster_proposal_instructions'
module SoulCore
  module RosterProposalFinalInstructions
    GPT_OSS = (RosterProposalInstructions::SYSTEM + "\n\n" + <<~TEXT.strip).freeze
      GPT-OSS native response-channel contract:
      No native function tools are registered in this inference call. The catalog
      above describes application capabilities, not callable native functions.
      Your role is to write a proposal for the application as your final reply
      to the user. Use the final channel for that reply, with no recipient or
      function address. Do not end the turn after analysis or a tool-directed
      message. Private analysis is not an answer and cannot dispatch a capability.
      For a capability request, put the entire proposal JSON in the final reply.
      For example, a request to list reviewed snapshots has this final reply:
      {"soul_tool_proposal":{"tool":"list_snapshots","arguments":{}}}
      That JSON is ordinary final-answer text, not a native function call.
      For ordinary conversation, write the normal answer in the final channel.
      Never claim an operation ran; only the application can validate and run it.
    TEXT
    def self.for_model(model)
      model=='gpt-oss-20b' ? GPT_OSS : RosterProposalInstructions::SYSTEM
    end
  end
end
