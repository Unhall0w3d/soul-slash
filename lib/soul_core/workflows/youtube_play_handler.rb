# frozen_string_literal: true

require_relative "../workflow_runner"
require_relative "base_handler"

module SoulCore
  module Workflows
    class YouTubePlayHandler < BaseHandler
      def run(parameters:, original_text:)
  runner = WorkflowRunner.new

  unless runner.respond_to?(:run_youtube_play, true)
    raise "youtube.play handler is unavailable because run_youtube_play is not loaded"
  end

  result = runner.send(
    :run_youtube_play,
    parameters: parameters,
    original_text: original_text
  )

  state = result[:state]
  if state.is_a?(Hash)
    state["handler_execution"] = {
      "checked" => true,
      "handler" => self.class.name,
      "intent" => intent,
      "delegated_to_existing_workflow_method" => true
    }

    runner.save_session(state) if runner.respond_to?(:save_session)
  end

  result
end 
    end
  end
end
