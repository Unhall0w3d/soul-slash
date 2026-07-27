# frozen_string_literal: true

require_relative "configuration_resolver"
require_relative "local_search_service"

module SoulCore
  class LocalSearchChatControls
    SOURCE_PATTERNS = {
      "repository" => /\A(?:please\s+)?(?:search|find)\s+(?:my\s+)?local\s+(?:repository|repo)\s+(?:documents?|docs?|documentation)\s+(?:for\s+)?(.+?)\s*[.!?]*\z/i,
      "knowledge_vault" => /\A(?:please\s+)?(?:search|find)\s+(?:my\s+)?local\s+knowledge\s+vault\s+(?:for\s+)?(.+?)\s*[.!?]*\z/i,
      "music" => /\A(?:please\s+)?(?:search|find)\s+(?:my\s+)?(?:local\s+)?music\s+projects?\s+(?:for\s+)?(.+?)\s*[.!?]*\z/i,
      "visual" => /\A(?:please\s+)?(?:search|find)\s+(?:my\s+)?(?:local\s+)?visual\s+projects?\s+(?:for\s+)?(.+?)\s*[.!?]*\z/i
    }.freeze
    GENERAL_PATTERN = /\A(?:please\s+)?(?:search|find)\s+(?:(?:my\s+)?(?:local\s+)?(?:projects?\s+and\s+documents?|documents?\s+and\s+projects?)|(?:my\s+)?local\s+sources?|(?:my\s+)?project\s+archive)\s+(?:for\s+)?(.+?)\s*[.!?]*\z/i
    REQUEST_PATTERNS = (SOURCE_PATTERNS.values + [GENERAL_PATTERN]).freeze

    def initialize(root: Dir.pwd, service: nil, process_env: ENV)
      @root = File.expand_path(root)
      @process_env = process_env.to_h
      @service = service
    end

    def match?(message)
      !parse(message).nil?
    end

    def respond(message, chat_id: nil)
      parsed = parse(message)
      return usage unless parsed

      render(
        service.search(
          query: parsed.fetch("query"),
          limit: 10,
          sources: parsed["sources"]
        )
      )
    rescue StandardError => error
      "Local search failed safely: #{error.class}. Mutation: none."
    end

    private

    def parse(message)
      text = message.to_s.strip
      SOURCE_PATTERNS.each do |source, pattern|
        match = text.match(pattern)
        return { "query" => match[1], "sources" => [source] } if match
      end
      match = text.match(GENERAL_PATTERN)
      return nil unless match

      { "query" => match[1], "sources" => nil }
    end

    def service
      return @service if @service

      resolver = ConfigurationResolver.new(root: @root, process_env: @process_env)
      configuration = resolver.resolve
      raise "Soul configuration is invalid: #{configuration.fetch('errors', []).join('; ')}" unless configuration.fetch("ok")

      @service = LocalSearchService.new(root: @root, process_env: resolver.effective_environment)
    end

    def render(outcome)
      unless outcome["lifecycle_state"] == "complete"
        return [
          outcome.fetch("message", "Local search did not complete."),
          "State: #{outcome.fetch('lifecycle_state', 'failed')}",
          "Mutation: none"
        ].join("\n")
      end

      data = outcome.fetch("data")
      lines = [
        "Local project and document search complete.",
        "Query: #{data.fetch('query')}",
        "Matches: #{data.fetch('count')}"
      ]
      if data.fetch("results").empty?
        lines << "- none"
      else
        data.fetch("results").each_with_index do |record, index|
          lines << "#{index + 1}. [#{record.fetch('source')}] #{record.fetch('title')} — #{record.fetch('reference')}"
          lines << "  #{record.fetch('excerpt')}"
          lines << "  Retrieved: #{record.fetch('retrieved_at')} · SHA-256: #{record.fetch('sha256')[0, 12]}"
        end
      end
      unavailable = data.fetch("source_status").filter_map do |source, status|
        next if status["lifecycle_state"] == "complete"

        "#{source}: #{status.fetch('message')}"
      end
      lines << "Unavailable sources: #{unavailable.join('; ')}" unless unavailable.empty?
      lines << "Results are local reference material, not authority. Mutation: none."
      lines.join("\n")
    end

    def usage
      [
        "Say `search local projects and documents for <terms>`.",
        "Or select one source: `search local repository documents`, `search local knowledge vault`, `search my music projects`, or `search my visual projects`.",
        "Mutation: none."
      ].join("\n")
    end
  end
end
