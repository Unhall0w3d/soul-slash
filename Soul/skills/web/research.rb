#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require_relative "../../../lib/soul_core/web_research_service"

options = { queries: [], sources: 5 }
parser = OptionParser.new do |opts|
  opts.banner = "Usage: research.rb --query TEXT [--query TEXT] [--sources N]"
  opts.on("--query TEXT", "A bounded public-web research query; repeat up to three times.") { |value| options[:queries] << value }
  opts.on("--sources N", Integer, "Retrieve up to eight sources.") { |value| options[:sources] = value }
end

begin
  parser.parse!(ARGV)
  result = SoulCore::WebResearchService.new.research(queries: options[:queries], source_limit: options[:sources])
  puts JSON.pretty_generate({ "skill" => "web.research" }.merge(result))
  exit(result["ok"] ? 0 : 2)
rescue OptionParser::ParseError => error
  puts JSON.pretty_generate({ "skill" => "web.research", "ok" => false, "lifecycle_state" => "awaiting_input", "reason" => error.message, "mutation" => "none" })
  exit 2
end
