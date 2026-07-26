#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

require_relative "../lib/soul_core/chat_responder"
require_relative "../lib/soul_core/conversation_orchestrator"
require_relative "../lib/soul_core/dashboard_capability_guide"

checks = {}
guide = SoulCore::DashboardCapabilityGuide.new(root: File.expand_path("..", __dir__))
orchestrator = SoulCore::ConversationOrchestrator.new
plan = ->(message) { orchestrator.plan(message: message, provider_available: true) }

overview_request = "What can you do through the dashboard?"
music_request = "What can I ask you to do in Music Studio?"
visual_request = "How can I use Visual Studio through chat?"

checks["explicit_dashboard_question_uses_bounded_guide"] =
  guide.match?(overview_request) &&
  plan.call(overview_request).kind == "deterministic_passthrough" &&
  plan.call(overview_request).flags["dashboard_capability_guide"] == true

checks["ordinary_dashboard_development_statement_remains_conversation"] =
  !guide.match?("I'm working on your dashboard capabilities.") &&
  plan.call("I'm working on your dashboard capabilities.").kind == "direct_model"

checks["ordinary_studio_opinion_remains_conversation"] =
  !guide.match?("Music Studio sounds useful later.") &&
  plan.call("Music Studio sounds useful later.").kind == "direct_model"

overview = guide.respond(overview_request)
checks["overview_distinguishes_chat_mappings_from_dashboard_only_surfaces"] =
  overview.include?("Music Studio — available") &&
  overview.include?("Skill Studio — Dashboard-only review surface") &&
  overview.include?("Self Augmentation — Dashboard-only review surface") &&
  overview.include?("It does not invoke any capability") &&
  overview.include?("Lifecycle: complete. Mutation: none.")

music = guide.respond(music_request)
checks["music_guide_states_required_inputs_and_authority"] =
  guide.match?(music_request) &&
  music.include?("intent, supported duration, vocal or instrumental mode, and rights status") &&
  music.include?("`creative.music_production` (available)") &&
  music.include?("model response is never approval")

visual = guide.respond(visual_request)
checks["visual_guide_discloses_partial_companion_boundary"] =
  guide.match?(visual_request) &&
  visual.include?("Availability: partial") &&
  visual.include?("clear visual intent") &&
  visual.include?("Native motion, full-duration rendering, export, and publication packaging retain their Studio gates")

tracker = guide.respond("What can I ask you to do in Project Timeline?")
checks["timeline_guide_uses_shared_ledger_contract"] =
  tracker.include?("`project.timeline.inspect` (available)") &&
  tracker.include?("`project.timeline.update` (available)") &&
  tracker.include?("same owner-local ledger")

registry = YAML.safe_load(File.read(File.expand_path("../Soul/skills/registry.yaml", __dir__)), aliases: false).fetch("skills")
checks["guide_is_registered_as_read_only_without_approval"] =
  registry.dig("dashboard.capabilities.inspect", "status") == "available" &&
  registry.dig("dashboard.capabilities.inspect", "risk") == "read_only" &&
  registry.dig("dashboard.capabilities.inspect", "requires_approval") == false &&
  registry.dig("dashboard.capabilities.inspect", "writes_files") == false

failed = checks.reject { |_name, passed| passed }
puts checks.map { |name, passed| "#{passed ? 'PASS' : 'FAIL'} #{name}" }
abort("#{failed.length} Dashboard capability-guide checks failed") unless failed.empty?
puts "PASS #{checks.length} Dashboard capability-guide checks"
