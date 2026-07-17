#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require_relative "../../../lib/soul_core/web_research_service"

options = {}
parser = OptionParser.new do |opts|
  opts.banner = "Usage: lookup.rb --query TEXT"
  opts.on("--query TEXT", "A narrow definition, entity, or factual lookup.") { |value| options[:query] = value }
end

begin
  parser.parse!(ARGV)
  result = SoulCore::WebResearchService.new.lookup(options[:query])
  puts JSON.pretty_generate({ "skill" => "web.lookup" }.merge(result))
  exit(result["ok"] ? 0 : 2)
rescue OptionParser::ParseError => error
  puts JSON.pretty_generate({ "skill" => "web.lookup", "ok" => false, "lifecycle_state" => "awaiting_input", "reason" => error.message, "mutation" => "none" })
  exit 2
end
