#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require_relative "../lib/soul_core/application_facade"
require_relative "../lib/soul_core/conversation_orchestrator"
require_relative "../lib/soul_core/project_tracker_chat_controls"
require_relative "../lib/soul_core/project_tracker_service"

errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

puts "Project Timeline A1 verification:"

Dir.mktmpdir("soul-project-timeline-") do |root|
  FileUtils.mkdir_p(File.join(root, "config"))
  seed_source = File.expand_path("../config/project_tracker_seed.json", __dir__)
  FileUtils.cp(seed_source, File.join(root, "config/project_tracker_seed.json"))
  clock = -> { Time.utc(2026, 7, 25, 12, 0, 0) }
  service = SoulCore::ProjectTrackerService.new(root: root, clock: clock, id_generator: -> { "abc123def0" })

  first = service.snapshot
  state_path = File.join(root, "Soul/private/project_tracker/state.json")
  check.call("first snapshot initializes the private ledger from the public seed",
             first["lifecycle_state"] == "complete" &&
               first.dig("data", "items").length >= 20 &&
               first.dig("data", "items").any? { |record| %w[done validated].include?(record["status"]) && !record["implementation"].to_s.empty? && !record["technologies"].to_s.empty? } &&
               File.file?(state_path) &&
               (File.stat(state_path).mode & 0o777) == 0o600)

  reconciled = first.dig("data", "items").to_h { |record| [record.fetch("item_id"), record] }
  check.call("public seed preserves reviewed completion and pending human gates",
             reconciled.dig("track_managed_switch_snmp_inventory", "status") == "validated" &&
               reconciled.dig("track_managed_switch_snmp_inventory", "horizon") == "archive" &&
               reconciled.dig("track_youtube_description_sync", "status") == "needs_review" &&
               reconciled.dig("track_winboat_windows_inventory", "status") == "needs_review" &&
               reconciled.dig("track_noctalia_core_control", "status") == "needs_review")
  check.call("public seed inventories accepted companion and completed hardening scope",
             reconciled.dig("track_noctalia_companion", "status") == "validated" &&
               reconciled.dig("track_noctalia_companion", "horizon") == "archive" &&
               reconciled.dig("track_harden_crucible_sudo_policy", "status") == "done" &&
               reconciled.dig("track_host_cis_hardening", "status") == "done" &&
               reconciled.dig("track_host_cis_hardening", "horizon") == "archive" &&
               reconciled.dig("track_portable_fleet_discovery", "status") == "validated" &&
               reconciled.dig("track_portable_fleet_discovery", "horizon") == "archive")
  check.call("multi-endpoint Wazuh acceptance is recorded without a fleet score",
             reconciled.dig("track_wazuh_clamav_security", "notes").include?("PR #137") &&
               reconciled.dig("track_wazuh_clamav_security", "notes").include?("without inventing a fleet compliance score"))
  check.call("creative qualification work is grouped without prematurely expanding long-form support",
             reconciled.dig("track_music_variable_duration", "horizon") == "now" &&
               reconciled.dig("track_music_variable_duration", "status") == "in_progress" &&
               reconciled.dig("track_music_finishing_refinement", "horizon") == "now" &&
               reconciled.dig("track_visual_motion_quality", "horizon") == "now" &&
               reconciled.dig("track_visual_motion_quality", "status") == "in_progress" &&
               reconciled.dig("track_music_long_form", "horizon") == "next" &&
               reconciled.dig("track_music_long_form", "status") == "planned")

  item = {
    "title" => "Timeline verifier",
    "area" => "Tests",
    "horizon" => "next",
    "status" => "planned",
    "priority" => "medium",
    "summary" => "Exercise one bounded implementation ledger entry.",
    "acceptance" => "Create and update produce explicit lifecycle receipts.",
    "notes" => "",
    "source" => "Project Timeline A1 verification"
  }
  created = service.create(attributes: item)
  created_item = created.dig("data", "item")
  check.call("one explicit create persists a revisioned item",
             created["lifecycle_state"] == "complete" &&
               created["mutation"] == "project_tracker_item_created" &&
               created_item["revision"] == 1)

  updated = service.update(
    item_id: created_item.fetch("item_id"),
    expected_revision: created_item.fetch("revision"),
    attributes: { "status" => "needs_review", "notes" => "Ready for Operator review." }
  )
  check.call("one explicit update changes only supplied editable fields",
             updated["lifecycle_state"] == "complete" &&
               updated.dig("data", "item", "status") == "needs_review" &&
               updated.dig("data", "item", "revision") == 2 &&
               updated.dig("data", "item", "title") == item.fetch("title"))

  stale = service.update(
    item_id: created_item.fetch("item_id"),
    expected_revision: 1,
    attributes: { "status" => "done" }
  )
  check.call("stale edit is blocked without overwriting state",
             stale["lifecycle_state"] == "blocked_for_human_review" &&
               service.find(created_item.fetch("item_id")).dig("item", "status") == "needs_review")

  controls = SoulCore::ProjectTrackerChatControls.new(root: root, service: service)
  listing = controls.respond("show project timeline")
  inspected = controls.respond("show timeline item track_foundation_creative_studios")
  changed = controls.respond("mark timeline item #{created_item.fetch('item_id')} as validated")
  detailed = controls.respond("update timeline item #{created_item.fetch('item_id')} technologies: Ruby and JavaScript")
  check.call("Chat reads and mutates only unmistakable timeline commands",
             controls.match?("show project timeline") &&
               !controls.match?("We should validate this feature later") &&
               listing.include?("Project Timeline") &&
               inspected.include?("Models, languages, and technologies") &&
               inspected.include?("ACE-Step 1.5") &&
               changed.include?("Timeline item updated") &&
               detailed.include?("Timeline item updated") &&
               service.find(created_item.fetch("item_id")).dig("item", "status") == "validated" &&
               service.find(created_item.fetch("item_id")).dig("item", "technologies") == "Ruby and JavaScript")

  orchestrator = SoulCore::ConversationOrchestrator.new
  decision = orchestrator.plan(message: "show project timeline", provider_available: true)
  ordinary = orchestrator.plan(message: "I was thinking about the project timeline today.", provider_available: true)
  check.call("orchestration separates explicit controls from ordinary conversation",
             decision.kind == "deterministic_passthrough" &&
               decision.flags["project_tracker_control"] == true &&
               ordinary.kind != "deterministic_passthrough")

  facade = SoulCore::ApplicationFacade.new(root: root, clock: clock, project_tracker_service: service)
  request = {
    "schema_version" => "soul.application.v1",
    "request_id" => "timeline-test-0001",
    "operation" => "project_tracker.snapshot",
    "parameters" => {},
    "context" => { "interface" => "dashboard_test" }
  }
  envelope = facade.call(request)
  check.call("dashboard facade exposes the same ledger",
             envelope["lifecycle_state"] == "complete" &&
               envelope.dig("data", "revision") == service.snapshot.dig("data", "revision"))

  current_item = service.find(created_item.fetch("item_id")).fetch("item")
  update_request = {
    "schema_version" => "soul.application.v1",
    "request_id" => "timeline-test-0002",
    "operation" => "project_tracker.items.update",
    "parameters" => {
      "item_id" => current_item.fetch("item_id"),
      "item" => { "horizon" => "now" },
      "expected_revision" => current_item.fetch("revision")
    },
    "context" => { "interface" => "dashboard_test" }
  }
  update_envelope = facade.call(update_request)
  check.call("dashboard editor contract accepts an item object and integer revision",
             update_envelope["lifecycle_state"] == "complete" &&
               update_envelope.dig("data", "item", "horizon") == "now" &&
               update_envelope.dig("data", "item", "revision") == current_item.fetch("revision") + 1)
end

html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
javascript = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
check.call("dashboard exposes four horizons, filters, and one bounded editor",
           %w[timeline-now timeline-next timeline-later timeline-backlog timeline-inventory timeline-implemented-items timeline-editor timeline-status-filter timeline-item-implementation timeline-item-technologies timeline-item-interfaces timeline-item-commands timeline-item-references].all? { |id| html.include?("id=\"#{id}\"") } &&
             html.include?('value="implemented"') &&
             javascript.include?('"project_tracker.snapshot"') &&
             javascript.include?('"project_tracker.items.create"') &&
             javascript.include?('"project_tracker.items.update"'))
check.call("timeline client contains no timer or automatic completion inference",
           !javascript.match?(/timeline.{0,120}(?:setInterval|setTimeout)/m) &&
             !javascript.include?("inferTimeline"))

if errors.empty?
  puts "Project Timeline A1 verification passed."
  exit 0
end

warn "Project Timeline A1 verification failed: #{errors.join(', ')}"
exit 1
