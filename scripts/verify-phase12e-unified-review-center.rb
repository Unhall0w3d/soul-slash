#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "tmpdir"

require_relative "../lib/soul_core/application_facade"

errors = []
check = lambda do |description, condition|
  puts "#{condition ? 'PASS' : 'FAIL'}: #{description}"
  errors << description unless condition
end

class Phase12eApprovalFixture
  def pending
    [{
      "token_id" => "private-token-value-sentinel",
      "skill_id" => "downloads.move_to_trash",
      "status" => "pending",
      "issued_at" => "2026-07-15T20:00:00Z",
      "expires_at" => "2026-07-15T20:15:00Z",
      "scope_digest" => "a" * 64,
      "scope" => { "target_path" => "/private/home/sentinel", "candidate_count" => 3 }
    }]
  end
end

class Phase12eActivityFixture
  attr_reader :calls

  def initialize
    @calls = []
    @rows = [
      {
        "timestamp" => "2026-07-15T20:01:00Z", "source" => "chat", "skill_id" => "system.status",
        "status" => "executed", "ok" => true, "executed" => true, "risk" => "read_only",
        "confirmation_required" => false, "exit_status" => 0, "blocked_by" => [],
        "message" => "private-user-message-sentinel", "path" => "/private/export/sentinel"
      },
      {
        "timestamp" => "2026-07-15T20:02:00Z", "source" => "chat", "skill_id" => "downloads.move_to_trash",
        "status" => "blocked", "ok" => false, "executed" => false, "risk" => "approval_required",
        "confirmation_required" => true, "exit_status" => nil,
        "blocked_by" => ["approval_required", "unsafe value with spaces", "private/path"]
      },
      {
        "timestamp" => "2026-07-15T20:03:00Z", "source" => "chat", "skill_id" => "fixture.failure",
        "status" => "failed", "ok" => false, "executed" => false, "risk" => "read_only",
        "confirmation_required" => false, "exit_status" => 1, "blocked_by" => []
      }
    ]
  end

  def entries(limit:, filters:)
    @calls << { limit: limit, filters: filters }
    rows = @rows
    filters.each { |key, value| rows = rows.select { |row| row[key] == value } }
    rows.last(limit)
  end
end

def request(operation, parameters = {})
  {
    "schema_version" => "soul.application.v1",
    "request_id" => "phase12e-#{operation.tr('.', '-')}",
    "operation" => operation,
    "parameters" => parameters,
    "context" => { "interface" => "dashboard_test" }
  }
end

puts "Phase 12E unified Review Center verification:"
Dir.mktmpdir("soul-phase12e-") do |root|
  activity = Phase12eActivityFixture.new
  facade = SoulCore::ApplicationFacade.new(root: root, approval_store: Phase12eApprovalFixture.new, activity_store: activity)

  bootstrap = facade.call(request("application.bootstrap"))
  check.call("Review Center is supporting UI, not a fourth product tab",
    bootstrap.dig("data", "product_tabs") == ["Chat", "Skill Studio", "Self Improvement"] &&
    bootstrap.dig("data", "unified_operations", "surface") == "Review Center" &&
    bootstrap.dig("data", "unified_operations", "read_only") == true)

  approvals = facade.call(request("approvals.pending", { "limit" => 50 }))
  approval_json = JSON.generate(approvals)
  check.call("approval projection is bounded, redacted, and non-authorizing",
    approvals["lifecycle_state"] == "complete" && approvals.dig("data", "count") == 1 &&
    approvals.dig("data", "records", 0, "approval_ref").to_s.length == 16 &&
    approvals.dig("data", "records", 0, "authorization_value_exposed") == false &&
    !approval_json.include?("private-token-value-sentinel") &&
    !approval_json.include?("/private/home/sentinel"))

  activities = facade.call(request("activities.recent", { "limit" => 100, "filters" => {} }))
  activity_json = JSON.generate(activities)
  check.call("activity projection omits private messages and paths",
    activities["lifecycle_state"] == "complete" && activities.dig("data", "count") == 3 &&
    activities.dig("data", "private_messages_exposed") == false &&
    !activity_json.include?("private-user-message-sentinel") && !activity_json.include?("/private/export/sentinel"))
  check.call("blocked categories are syntax-filtered and bounded",
    activities.dig("data", "records", 1, "blocked_categories") == ["approval_required"] &&
    activities.dig("data", "records", 1, "blocked_count") == 3)

  filtered = facade.call(request("activities.recent", { "limit" => 100, "filters" => { "status" => "failed" } }))
  check.call("activity filters remain server-side and bounded",
    filtered.dig("data", "records").map { |row| row["status"] } == ["failed"] &&
    activity.calls.last == { limit: 100, filters: { "status" => "failed" } })

  invalid = facade.call(request("activities.recent", { "filters" => { "private_message" => "sentinel" } }))
  check.call("unknown activity filters fail closed", invalid["lifecycle_state"] == "failed")
end

root = File.expand_path("..", __dir__)
html = File.read(File.join(root, "assets/dashboard/index.html"))
css = File.read(File.join(root, "assets/dashboard/dashboard.css"))
javascript = File.read(File.join(root, "assets/dashboard/dashboard.js"))
brief = File.read(File.join(root, "docs/soul/PHASE12E_UNIFIED_REVIEW_CENTER_BRIEF.md"))
review = File.read(File.join(root, "docs/assessments/CONVERSATIONAL_SOUL_PHASE12E_UNIFIED_REVIEW_CENTER.md"))

required_ids = %w[review-center-button review-center review-pending-count review-activity-count review-blocked-count review-failed-count review-approvals-tab review-activity-tab approval-review-list approval-review-detail activity-review-list activity-review-detail refresh-review-center close-review-center review-center-status]
check.call("dashboard exposes the complete Review Center surface", required_ids.all? { |id| html.include?("id=\"#{id}\"") })
check.call("primary hierarchy remains exactly three named tabs", %w[chat-tab studio-tab improvement-tab].all? { |id| html.include?("id=\"#{id}\"") } && !html.include?('id="review-tab"'))
check.call("frontend uses only registered read projections", javascript.include?('callSoul("approvals.pending"') && javascript.include?('callSoul("activities.recent"'))
forbidden_operations = %w[approvals.revoke approvals.execute approvals.clear activities.replay activities.retry activities.clear activities.prune activities.export]
check.call("Review Center adds no approval or history mutation", forbidden_operations.none? { |operation| javascript.include?(operation) })
check.call("Review Center adds no polling or unsafe HTML rendering", !javascript.match?(/setInterval|setTimeout|WebSocket|EventSource|innerHTML|insertAdjacentHTML/) && javascript.include?("textContent") && javascript.include?("replaceChildren"))
check.call("responsive, focus, and human-attention styling is present", css.include?(".review-center") && css.include?(".review-state-chip") && css.include?("@media (max-width: 760px)") && css.include?("var(--gold)"))
check.call("brief preserves authority and visual review gates", brief.include?("Inspection is not approval") && brief.include?("material_visual_review_required: yes") && brief.include?("must not") && brief.include?("No polling"))
required_review_sections = ["## What was implemented", "## Files changed", "## Commands run", "## Deterministic test results", "## Local LLM eval results", "## Known weaknesses", "## Memory keys", "## Task lifecycle states touched", "## Risk classification", "## Human review checklist"]
check.call("human review artifact contains required sections", required_review_sections.all? { |heading| review.include?(heading) })

abort "Phase 12E verification failed: #{errors.join(', ')}" unless errors.empty?
puts "Phase 12E unified Review Center verification complete."
