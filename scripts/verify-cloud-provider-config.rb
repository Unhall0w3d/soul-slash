#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../lib/soul_core/cloud_provider_config"

path = ARGV[0]
config = SoulCore::CloudProviderConfig.load(path: path)

puts JSON.pretty_generate(config.summary)

if config.valid?
  puts "Cloud provider config verification: ok"
  exit 0
else
  warn "Cloud provider config verification: failed"
  exit 1
end
