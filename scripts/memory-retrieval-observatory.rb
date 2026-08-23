#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../lib/soul_core/conversation_memory_store"
require_relative "../lib/soul_core/memory_paths"
require_relative "../lib/soul_core/memory_retrieval_evaluator"
require_relative "../lib/soul_core/memory_retrieval_index"
require_relative "../lib/soul_core/memory_retrieval_service"

module SoulMemoryRetrievalCLI
  module_function

  def run(argv, env: ENV, root: File.expand_path("..", __dir__))
    command = argv.shift.to_s
    return usage unless %w[evaluate evaluate-live status rebuild query].include?(command)

    if %w[evaluate evaluate-live].include?(command)
      client = command == "evaluate-live" ? embedding_client(env) : nil
      raise ArgumentError, "live evaluation requires local embedding configuration" if command == "evaluate-live" && client.nil?
      puts JSON.pretty_generate(SoulCore::MemoryRetrievalEvaluationHarness.new(
        embedding_client: client,
        query_instruction: env["SOUL_MEMORY_EMBEDDING_QUERY_INSTRUCTION"]
      ).run)
      return 0
    end

    store = SoulCore::ConversationMemoryStore.new(root: root, create: false)
    client = embedding_client(env)
    memory_paths = SoulCore::MemoryPaths.new(root: root)
    index = SoulCore::ApprovedMemoryIndexService.new(
      memory_store: store,
      index_path: memory_paths.write_path("derived/approved-memory-index.json"),
      allowed_root: memory_paths.private_root,
      embedding_client: client
    )
    result = case command
             when "status"
               { "lifecycle_state" => "complete", "data" => index.availability.merge("mutation" => "none") }
             when "rebuild"
               index.rebuild
             when "query"
               query = argv.join(" ").strip
               SoulCore::ApprovedMemoryRetrievalService.new(
                 memory_store: store,
                 index_service: index,
                 embedding_client: client,
                 query_instruction: env["SOUL_MEMORY_EMBEDDING_QUERY_INSTRUCTION"]
               ).query(query: query, limit: 8)
             end
    puts JSON.pretty_generate(result)
    result["lifecycle_state"] == "complete" ? 0 : 1
  rescue StandardError => error
    warn JSON.generate("lifecycle_state" => "failed", "message" => "memory retrieval command failed safely: #{error.class}: #{error.message}", "mutation" => "none")
    1
  end

  def embedding_client(env)
    endpoint = env["SOUL_MEMORY_EMBEDDING_ENDPOINT"].to_s.strip
    profile = env["SOUL_MEMORY_EMBEDDING_PROFILE"].to_s.strip
    dimensions = env["SOUL_MEMORY_EMBEDDING_DIMENSIONS"].to_s.strip
    return nil if endpoint.empty? && profile.empty? && dimensions.empty?
    raise ArgumentError, "embedding endpoint, profile, and dimensions must be configured together" if [endpoint, profile, dimensions].any?(&:empty?)

    SoulCore::LocalLoopbackEmbeddingClient.new(
      endpoint: endpoint,
      profile: { "name" => profile, "dimensions" => Integer(dimensions) },
      protocol: env.fetch("SOUL_MEMORY_EMBEDDING_PROTOCOL", "ollama")
    )
  end

  def usage
    warn "Usage: ruby scripts/memory-retrieval-observatory.rb evaluate|evaluate-live|status|rebuild|query <text>"
    2
  end
end

exit SoulMemoryRetrievalCLI.run(ARGV)
