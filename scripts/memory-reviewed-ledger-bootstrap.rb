#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../lib/soul_core/conversation_memory_store"
require_relative "../lib/soul_core/reviewed_memory_ledger_bootstrap_service"

root = File.expand_path("..", __dir__)
store = SoulCore::ConversationMemoryStore.new(root: root)
service = SoulCore::ReviewedMemoryLedgerBootstrapService.new(root: root, memory_store: store)
command = ARGV.shift.to_s

result = case command
         when "preview"
           service.preview
         when "execute"
           service.execute(confirmation: ARGV.shift, expected_digest: ARGV.shift)
         else
           {
             "lifecycle_state" => "awaiting_input",
             "message" => "usage: memory-reviewed-ledger-bootstrap.rb preview|execute CONFIRMATION EXPECTED_DIGEST",
             "data" => { "mutation" => "none" }
           }
         end

puts JSON.pretty_generate(result)
exit(result["lifecycle_state"] == "complete" || result["lifecycle_state"] == "blocked_for_human_review" ? 0 : 1)
