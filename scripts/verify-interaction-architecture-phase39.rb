#!/usr/bin/env ruby
# frozen_string_literal: true

errors = []
puts "Interaction architecture phase 39 verification:"

required = {
  "docs/INTERACTION_ARCHITECTURE.md" => [
    "Soul Interaction Architecture",
    "human utterance",
    "intent router",
    "Voice should not have a separate brain",
    "If being wrong is merely annoying"
  ],
  "docs/FRONTEND_RESEARCH.md" => [
    "Frontend Research Notes",
    "Open WebUI",
    "LibreChat",
    "LobeChat",
    "AnythingLLM",
    "Build Soul's own interaction core"
  ],
  "docs/INFRASTRUCTURE_PLAN.md" => [
    "Soul Interaction Infrastructure Plan",
    "SQLite",
    "Proxmox",
    "NUC10FNH",
    "usable local terminal chat"
  ],
  "docs/CHAT_DATA_MODEL.md" => [
    "Soul Chat Data Model",
    "chats",
    "messages",
    "skill_invocations",
    "assistant_decisions",
    "SQLite FTS5"
  ],
  "docs/maintenance/PHASE39_INTERACTION_ARCHITECTURE.md" => [
    "Phase 39",
    "documentation-only",
    "terminal chat foundation"
  ]
}

required.each do |path, needles|
  exists = File.exist?(path)
  puts "- #{path}: #{exists ? 'ok' : 'missing'}"
  errors << "#{path} missing" unless exists
  next unless exists

  content = File.read(path)
  needles.each do |needle|
    ok = content.include?(needle)
    puts "  - contains #{needle.inspect}: #{ok ? 'ok' : 'missing'}"
    errors << "#{path} missing #{needle.inspect}" unless ok
  end
end

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
