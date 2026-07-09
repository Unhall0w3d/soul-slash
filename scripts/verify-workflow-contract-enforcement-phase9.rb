#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "json"
require "soul_core/workflow_contract_validator"
require "soul_core/workflow_handler_registry"

puts "workflow handler contract enforcement phase 9 verification:"

result = SoulCore::WorkflowContractValidator
  .new
  .validate_registry(SoulCore::WorkflowHandlerRegistry.new)

puts "- validator loaded: ok"
puts "- handlers checked: #{result['handlers_checked']}"
puts "- registry JSON: #{JSON.generate(result).start_with?('{') ? 'ok' : 'failed'}"

if result["valid"]
  puts "Verification complete."
  exit 0
end

warn "Verification failed:"
result["handlers"].each do |name, handler|
  Array(handler["errors"]).each do |error|
    warn "- #{name}: #{error}"
  end
end

exit 1
