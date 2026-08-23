#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require_relative "../lib/soul_core/chat_store"
require_relative "../lib/soul_core/conversation_context_builder"
require_relative "../lib/soul_core/conversation_memory_store"
require_relative "../lib/soul_core/semantic_conversation_memory_context"

include SoulCore

class RetrievalFixture
  attr_accessor :mode, :ids, :raise_error

  def initialize(mode: "hybrid", ids: [])
    @mode = mode
    @ids = ids
    @raise_error = false
  end

  def query(query:, limit:)
    _unused = [query, limit]
    raise "synthetic retrieval failure" if @raise_error

    {
      "lifecycle_state" => "complete",
      "data" => {
        "retrieval_mode" => @mode,
        "index_available" => @mode == "hybrid",
        "results" => @ids.map { |identifier| { "memory_id" => identifier, "excerpt" => "untrusted derived text" } }
      }
    }
  end
end

errors = []
check = ->(name, condition) { errors << name unless condition }

Dir.mktmpdir("soul-semantic-chat-a3") do |directory|
  chats = ChatStore.new(root: directory)
  chat = chats.create_chat(initial_title: "Semantic context fixture")
  chat_id = chat.fetch("id")
  memory = ConversationMemoryStore.new(root: directory)

  create_approved = lambda do |content, **options|
    record = memory.propose(
      layer: options.fetch(:layer, "semantic"),
      content: content,
      source: { "kind" => "reviewed_fixture", "reference" => options.fetch(:reference, "a3") },
      confidence: options.fetch(:confidence, 0.95),
      chat_id: options[:chat_id],
      metadata: options.fetch(:metadata, {})
    )
    memory.approve(record.fetch("id"))
  end

  always = create_approved.call("The operator always prefers concise technical summaries.", metadata: { "always_include" => true })
  same_chat = create_approved.call("This conversation is reviewing semantic memory integration.", chat_id: chat_id)
  semantic = create_approved.call("The operator uses a private observability service for fleet history.")
  lexical = create_approved.call("A spacecraft uses rotating-frame conversion.")
  candidate = memory.propose(
    layer: "semantic",
    content: "Candidate content must never enter chat context.",
    source: { "kind" => "fixture", "reference" => "candidate" },
    confidence: 0.9
  )
  superseded = create_approved.call("An obsolete private observability statement.")
  memory.supersede(superseded.fetch("id"), by: semantic.fetch("id"), reason: "fixture replacement")
  deleted = create_approved.call("A deleted private observability statement.")
  memory.delete(deleted.fetch("id"), reason: "fixture deletion")

  retrieval = RetrievalFixture.new(ids: [semantic.fetch("id"), candidate.fetch("id"), superseded.fetch("id"), deleted.fetch("id")])
  adapter = SemanticConversationMemoryContext.new(memory_store: memory, retrieval_service: retrieval)
  events_before = memory.events.length
  context = adapter.context_for(query: "What keeps historical fleet trends?", chat_id: chat_id, limit: 4)

  check.call("hybrid semantic result enters bounded chat context", context.fetch("record_ids").include?(semantic.fetch("id")) && context.fetch("count") <= 4)
  protected_ids = context.fetch("record_ids").first(2)
  check.call("always-include memory is preserved before semantic additions", protected_ids.include?(always.fetch("id")))
  check.call("same-chat memory is preserved before semantic additions", protected_ids.include?(same_chat.fetch("id")))
  check.call("non-approved semantic identifiers are rejected", [candidate, superseded, deleted].none? { |record| context.fetch("record_ids").include?(record.fetch("id")) })
  check.call("canonical content replaces untrusted index excerpt", context.fetch("rendered").include?(semantic.fetch("content")) && !context.fetch("rendered").include?("untrusted derived text"))
  check.call("semantic provenance is observable", context.fetch("retrieval_mode") == "hybrid" && context.fetch("semantic_record_ids").include?(semantic.fetch("id")))
  check.call("retrieval performs no memory mutation", memory.events.length == events_before)

  baseline = memory.context_for(query: "rotating-frame conversion", chat_id: chat_id, limit: 4)
  retrieval.mode = "lexical_fallback"
  fallback = adapter.context_for(query: "rotating-frame conversion", chat_id: chat_id, limit: 4)
  check.call("non-hybrid retrieval preserves legacy context exactly", fallback == baseline)
  retrieval.raise_error = true
  failed = adapter.context_for(query: "rotating-frame conversion", chat_id: chat_id, limit: 4)
  check.call("retrieval failure preserves legacy context exactly", failed == baseline)

  retrieval.raise_error = false
  retrieval.mode = "hybrid"
  retrieval.ids = [semantic.fetch("id")]
  chats.add_message(chat_id, role: "user", content: "What keeps historical fleet trends?")
  built = ConversationContextBuilder.new(store: chats, memory_store: adapter, max_memory_records: 4).build(chat_id: chat_id)
  system_prompt = built.fetch("messages").first.fetch("content")
  check.call("ordinary chat system prompt receives semantic memory", system_prompt.include?(semantic.fetch("content")))
  check.call("ordinary chat reports semantic retrieval diagnostics", built.dig("memory", "retrieval_mode") == "hybrid" && built.dig("memory", "semantic_record_ids").include?(semantic.fetch("id")))
end

if errors.empty?
  puts "Semantic memory Chat context A3 verifier passed (11 checks)."
else
  warn "Semantic memory Chat context A3 verifier failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
