#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../lib/soul_core/conversation_forget_service_assessor"

report = SoulCore::ConversationForgetServiceAssessor.new(root: File.expand_path("..", __dir__)).assess
puts JSON.pretty_generate(report)
exit(report.fetch("ok") ? 0 : 1)
