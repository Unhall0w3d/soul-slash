#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"

root = File.expand_path("..", __dir__)
commands = [
  %w[ruby scripts/verify-memory-projection-hybrid-qualification-a25.rb],
  %w[ruby scripts/verify-memory-retrieval-policy-a26.rb],
  %w[ruby scripts/verify-memory-fusion-chat-voice-a27.rb],
  %w[ruby scripts/verify-memory-observatory-3d-a28.rb],
  %w[ruby scripts/verify-memory-production-qualification-a29.rb],
  %w[ruby scripts/verify-memory-audit-reconstruction-a10.rb],
  %w[ruby scripts/verify-memory-live-qualification-a14.rb],
  %w[ruby scripts/verify-memory-core-aware-worker-a17.rb],
  %w[ruby scripts/verify-memory-projection-reconciliation-a21.rb],
  %w[ruby scripts/verify-core-transition-settlement-a8.rb],
  %w[ruby scripts/verify-backup-administration-a2.rb]
].freeze

commands.each do |command|
  stdout, stderr, status = Open3.capture3(*command, chdir: root)
  unless status.success?
    warn stdout
    warn stderr
    abort "Memory production closure A29 failed: #{command.join(' ')}"
  end
  puts "PASS #{command.last}"
end

backup_brief = File.read(File.join(root, "docs/soul/BACKUP_AND_DISASTER_RECOVERY_A0_BRIEF.md"))
abort "Memory production closure A29 failed: private memory backup scope is absent" unless backup_brief.include?("`Soul/private/`, including approved memory")

puts "Memory production closure A29 passed (#{commands.length + 1} checks)."
