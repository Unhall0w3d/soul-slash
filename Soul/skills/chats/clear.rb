#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require "time"
require_relative "../../../lib/soul_core/conversation_clear_service"

options = { title: nil, chat_ids: [], all: false, execute: false, confirm: nil, expected_digest: nil }
parser = OptionParser.new do |opts|
  opts.banner = "Usage: clear.rb (--title TITLE|--chat-id ID [--chat-id ID ...]|--all) [--execute --confirm CLEAR_CONVERSATIONS --expected-digest SHA256]"
  opts.on("--title TITLE", "Match one exact conversation title; all duplicate-title matches are disclosed.") { |value| options[:title] = value }
  opts.on("--chat-id ID", "Select one exact active conversation ID; repeat for multiple conversations.") { |value| options[:chat_ids] << value }
  opts.on("--all", "Match all active conversations.") { options[:all] = true }
  opts.on("--execute", "Archive the previewed conversations from the active list.") { options[:execute] = true }
  opts.on("--confirm TEXT", "Exact execution confirmation: CLEAR_CONVERSATIONS") { |value| options[:confirm] = value }
  opts.on("--expected-digest SHA256", "Match-set digest returned by preview.") { |value| options[:expected_digest] = value }
end

begin
  parser.parse!(ARGV)
  selectors = [!options[:title].nil?, !options[:chat_ids].empty?, options[:all]].count(true)
  raise OptionParser::InvalidArgument, "choose exactly one of --title, one or more --chat-id values, or --all" unless selectors == 1

  mode = options[:all] ? "all" : (options[:chat_ids].empty? ? "title" : "selected")
  service = SoulCore::ConversationClearService.new(root: Dir.pwd)
  result = if options[:execute]
             service.execute(
               mode: mode,
               title: options[:title],
               chat_ids: options[:chat_ids],
               confirmation: options[:confirm],
               expected_digest: options[:expected_digest]
             )
           else
             service.preview(mode: mode, title: options[:title], chat_ids: options[:chat_ids])
           end
  puts JSON.pretty_generate(result.merge("skill" => "chats.clear", "generated_at" => Time.now.iso8601))
  exit(result.fetch("ok") ? 0 : 1)
rescue OptionParser::ParseError => error
  puts JSON.pretty_generate(
    "skill" => "chats.clear",
    "generated_at" => Time.now.iso8601,
    "ok" => false,
    "lifecycle_state" => "awaiting_input",
    "data" => {},
    "mutation" => "none",
    "reason" => error.message,
    "usage" => parser.to_s
  )
  exit 2
end
