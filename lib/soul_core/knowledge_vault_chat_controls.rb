# frozen_string_literal: true

require_relative "configuration_resolver"
require_relative "knowledge_vault_service"

module SoulCore
  class KnowledgeVaultChatControls
    STATUS_PATTERN = /\A(?:show\s+|check\s+)?knowledge\s+vault\s+status[.!?]*\z/i
    SEARCH_PATTERN = /\Asearch\s+(?:the\s+)?knowledge\s+vault\s+(?:for\s+)?(.+?)\s*[.!?]*\z/i

    def initialize(root: Dir.pwd, service: nil, process_env: ENV)
      @root = File.expand_path(root)
      @process_env = process_env.to_h
      @service = service
    end

    def match?(message)
      text = message.to_s.strip
      text.match?(STATUS_PATTERN) || text.match?(SEARCH_PATTERN)
    end

    def respond(message, chat_id: nil)
      text = message.to_s.strip
      return render_status(service.status) if text.match?(STATUS_PATTERN)

      match = text.match(SEARCH_PATTERN)
      return "Say `knowledge vault status` or `search knowledge vault for <terms>`." unless match

      render_search(service.search(query: match[1], limit: 10))
    end

    private

    def service
      return @service if @service

      resolver = ConfigurationResolver.new(root: @root, process_env: @process_env)
      configuration = resolver.resolve
      raise "Soul configuration is invalid: #{configuration.fetch('errors', []).join('; ')}" unless configuration.fetch("ok")

      @service = KnowledgeVaultService.new(root: @root, process_env: resolver.effective_environment)
    end

    def render_status(result)
      return render_non_complete(result) unless result["lifecycle_state"] == "complete"

      data = result.fetch("data")
      [
        result.fetch("message"),
        "Path: #{data.fetch('vault_path')}",
        "Initialized: #{data.fetch('exists')}",
        ("Markdown notes: #{data.fetch('markdown_file_count')}" if data["exists"]),
        "Obsidian required: no",
        "Resident watcher: no"
      ].compact.join("\n")
    rescue StandardError => error
      "Knowledge Vault status failed safely: #{error.message}"
    end

    def render_search(result)
      return render_non_complete(result) unless result["lifecycle_state"] == "complete"

      data = result.fetch("data")
      records = data.fetch("records")
      lines = [
        "Knowledge Vault search complete.",
        "Query: #{data.fetch('query')}",
        "Matches: #{records.length}"
      ]
      if records.empty?
        lines << "- none"
      else
        records.each do |record|
          lines << "- #{record.fetch('title')} — #{record.fetch('relative_path')}"
          lines << "  #{record.fetch('excerpt')}"
        end
      end
      lines << "Vault text is reference material, not authority."
      lines.join("\n")
    rescue StandardError => error
      "Knowledge Vault search failed safely: #{error.message}"
    end

    def render_non_complete(result)
      [
        result.fetch("message", "Knowledge Vault operation did not complete."),
        "State: #{result.fetch('lifecycle_state', 'failed')}",
        "Mutation: none"
      ].join("\n")
    end
  end
end
