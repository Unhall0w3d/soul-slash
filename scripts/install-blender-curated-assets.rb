#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require_relative "../lib/soul_core/blender_curated_asset_registry"

options = {
  registry: File.expand_path("../config/blender_curated_assets.json", __dir__),
  root: File.expand_path("..", __dir__)
}
command = ARGV.shift
OptionParser.new do |parser|
  parser.banner = "Usage: #{$PROGRAM_NAME} preview|install|check [options]"
  parser.on("--registry PATH") { |value| options[:registry] = value }
  parser.on("--root PATH") { |value| options[:root] = value }
  parser.on("--expected-digest DIGEST") { |value| options[:expected_digest] = value }
  parser.on("--confirmation PHRASE") { |value| options[:confirmation] = value }
end.parse!

registry = SoulCore::BlenderCuratedAssetRegistry.new(registry_path: options.fetch(:registry), root: options.fetch(:root))
result = case command
         when "preview" then registry.preview
         when "install" then registry.install(expected_digest: options[:expected_digest].to_s, confirmation: options[:confirmation].to_s)
         when "check" then registry.verify
         else
           warn "command must be preview, install, or check"
           exit 2
         end
puts JSON.pretty_generate(result)
exit(result.fetch("ok", true) ? 0 : 1)
