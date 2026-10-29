#!/usr/bin/env ruby
# frozen_string_literal: true
require 'timeout'
require_relative '../lib/soul_core/cpu_reference_reader'
require_relative '../lib/soul_core/dotenv_reader'
if $PROGRAM_NAME==__FILE__
  raise ArgumentError,'no command-line arguments accepted' unless ARGV.empty?
  root=File.expand_path('..',__dir__)
  query=STDIN.read(1025).force_encoding('UTF-8')
  parsed=SoulCore::CpuReferenceRequests.parse(query);raise ArgumentError,'explicit reference request' unless parsed
  env={}
  unless parsed['operation'].start_with?('reference.')
    dotenv=SoulCore::DotenvReader.new(root:root).read;raise 'configuration unavailable' unless dotenv.ok?
    keys=%w[SOUL_WEATHER_LOCATION SOUL_WEATHER_UNITS SOUL_WEB_SEARCH_PROVIDER SOUL_WEB_SEARXNG_URL SOUL_WEB_ALLOW_PRIVATE_SEARXNG SOUL_WEB_BRAVE_API_KEY]
    env=dotenv.values.slice(*keys).merge(ENV.to_h.slice(*keys))
  end
  outcome=Timeout.timeout(55){SoulCore::CpuReferenceReader.new(root:root,env:env).call(query:query)}
  puts JSON.generate(SoulCore::CpuMemberOperations.validate!(outcome))
end
