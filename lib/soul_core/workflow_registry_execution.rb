# frozen_string_literal: true

require "json"

require "time"
require_relative "workflow_registry"
require_relative "workflow_handler_registry"

module SoulCore
  class WorkflowRegistryExecution
    def initialize(registry: WorkflowRegistry.new)
      @registry = registry
    end

    def registered?(intent)
      @registry.include?(intent.to_s)
    end

    def metadata(intent)
      workflow = @registry.get(intent.to_s)

      {
        "intent" => workflow.intent,
        "description" => workflow.description,
        "runner" => workflow.runner,
        "requires_confirmation" => workflow.requires_confirmation,
        "write_capable" => workflow.write_capable,
        "skills" => workflow.skills,
        "session_statuses" => workflow.session_statuses
      }
    end

    def blocked_result(intent:, parameters:, original_text:)
      {
        ok: false,
        workflow_path: nil,
        state: {
          "workflow" => intent.to_s,
          "status" => "blocked_unregistered_workflow",
          "generated_at" => Time.now.iso8601,
          "updated_at" => Time.now.iso8601,
          "original_text" => original_text.to_s,
          "parameters" => parameters || {},
          "next_expected" => "none",
          "verification" => {
            "registry_checked" => true,
            "registered_workflow" => false,
            "browser_launch_attempted" => false,
            "write_attempted" => false,
            "complete" => false
          }
        },
        user_message: [
          "No registered workflow matched this intent.",
          "",
          "- Intent: #{intent}",
          "",
          "Use `ruby bin/soul workflows` to see registered workflows."
        ].join("\n")
      }
    end
  end

  module WorkflowRegistryExecutionRunnerPatch
  def persist_registry_execution_state(state)
    return unless state.is_a?(Hash)

    path = state["workflow_path"].to_s
    return if path.empty?
    return unless File.exist?(path)

    File.write(path, JSON.pretty_generate(state))
  rescue StandardError
    nil
  end

  def run(intent:, parameters:, original_text:)
    registry_execution = WorkflowRegistryExecution.new

    unless registry_execution.registered?(intent)
      return registry_execution.blocked_result(
        intent: intent,
        parameters: parameters,
        original_text: original_text
      )
    end

    handler_registry = WorkflowHandlerRegistry.new

    result =
      if handler_registry.include?(intent)
        handler_registry.handler_for(intent).run(
          parameters: parameters,
          original_text: original_text
        )
      else
        super
      end

    if result.is_a?(Hash)
      metadata = registry_execution.metadata(intent)
      result[:registry] = metadata

      state = result[:state]
      if state.is_a?(Hash)
        state["registry_execution"] = {
          "checked" => true,
          "registered" => true,
          "intent" => metadata.fetch("intent"),
          "runner" => metadata.fetch("runner"),
          "requires_confirmation" => metadata.fetch("requires_confirmation"),
          "write_capable" => metadata.fetch("write_capable")
        }

        persist_registry_execution_state(state)
      end
    end

    result
  end
end
end

SoulCore::WorkflowRunner.prepend(SoulCore::WorkflowRegistryExecutionRunnerPatch)
