# frozen_string_literal: true

require_relative "workflow_registry"
require_relative "workflows/youtube_play_handler"

module SoulCore
  class WorkflowHandlerRegistry
    def initialize(registry: WorkflowRegistry.new)
      @registry = registry
      @handlers = {}
      register_defaults
    end

    def register(intent, handler_class)
      key = intent.to_s
      raise ArgumentError, "workflow is not registered: #{key}" unless @registry.include?(key)
      raise ArgumentError, "handler class is required for #{key}" unless handler_class

      @handlers[key] = handler_class
    end

    def include?(intent)
      @handlers.key?(intent.to_s)
    end

    def handler_for(intent)
      key = intent.to_s
      handler_class = @handlers.fetch(key)
      handler_class.new(definition: @registry.get(key))
    end

    def handlers
      @handlers.keys.sort.map { |intent| handler_for(intent) }
    end

    def match_intent(text, result_class:)
      handlers.each do |handler|
        result = handler.match_intent(text, result_class: result_class)
        return result if result
      end

      nil
    end

    def to_h
      {
        "status" => "ok",
        "outcome" => "complete",
        "handler_count" => @handlers.length,
        "handlers" => @handlers.keys.sort.map do |intent|
          handler_class = @handlers.fetch(intent)
          handler = handler_class.new(definition: @registry.get(intent))
          {
            "intent" => intent,
            "handler" => handler_class.name,
            "registered_workflow" => @registry.include?(intent),
            "handler_owned_intent_matching" => handler.respond_to?(:match_intent)
          }
        end,
        "verification" => {
          "read_only" => true,
          "handler_registry_present" => true,
          "registered_handler_intents" => @handlers.keys.sort,
          "handler_owned_intent_matching" => true
        }
      }
    end

    private

    def register_defaults
      register("youtube.play", Workflows::YouTubePlayHandler)
    end
  end
end

require_relative "workflow_session_handler_dispatch"
