#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../lib/soul_core/bulk_conversation_forget_assessor"

result = SoulCore::BulkConversationForgetAssessor.new(root: File.expand_path("..", __dir__)).assess
puts JSON.pretty_generate(result)
exit(result.fetch("ok") ? 0 : 1)
