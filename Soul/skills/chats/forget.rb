#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require "time"
require_relative "../../../lib/soul_core/conversation_forget_service"

options = { execute: false, chat_id: nil, confirm: nil, expected_digest: nil }
parser = OptionParser.new do |opts|
  opts.banner = "Usage: forget.rb --chat-id CHAT_ID [--execute --confirm DELETE_AND_FORGET_CONVERSATION --expected-digest SHA256]"
  opts.on("--chat-id CHAT_ID", "Canonical conversation ID.") { |value| options[:chat_id] = value }
  opts.on("--execute", "Permanently delete the previewed conversation-owned files and forget linked memory.") { options[:execute] = true }
  opts.on("--confirm TEXT", "Exact irreversible-action confirmation.") { |value| options[:confirm] = value }
  opts.on("--expected-digest SHA256", "Inventory digest returned by preview.") { |value| options[:expected_digest] = value }
end

begin
  parser.parse!(ARGV)
  service = SoulCore::ConversationForgetService.new(root: Dir.pwd)
  result = if options[:execute]
             service.execute(chat_id: options[:chat_id], confirmation: options[:confirm], expected_digest: options[:expected_digest])
           else
             service.preview(chat_id: options[:chat_id])
           end
  puts JSON.pretty_generate(result.merge("skill" => "chats.forget", "generated_at" => Time.now.iso8601))
  exit(result.fetch("ok") ? 0 : 1)
rescue OptionParser::ParseError => error
  puts JSON.pretty_generate("skill" => "chats.forget", "ok" => false, "lifecycle_state" => "awaiting_input", "mutation" => "none", "reason" => error.message)
  exit 2
end
