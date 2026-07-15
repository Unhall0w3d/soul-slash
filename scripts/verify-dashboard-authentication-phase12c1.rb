#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def check(label, condition, errors)
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

puts "Soul Phase 12C.1 dashboard authentication verification:"

required = %w[
  assets/dashboard/index.html
  assets/dashboard/dashboard.css
  assets/dashboard/dashboard.js
  docs/soul/PHASE12C1_DASHBOARD_AUTHENTICATION_BRIEF.md
  docs/assessments/CONVERSATIONAL_SOUL_PHASE12C1_DASHBOARD_AUTHENTICATION.md
  lib/soul_core/dashboard_authentication.rb
  lib/soul_core/dashboard_authentication_assessor.rb
  lib/soul_core/dashboard_http_application.rb
  lib/soul_core/dashboard_server.rb
  scripts/verify-dashboard-authentication-phase12c1.rb
]

required.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  check(path, ok, errors)
end

stdout, stderr, status = Open3.capture3("ruby", "bin/soul", "assess", "dashboard-authentication", "--json")
report = JSON.parse(stdout) rescue nil
assessment_ok =
  status.success? && report && report["ok"] == true && report["phase"] == "12C.1" &&
  report["status"] == "blocked_for_human_review" && report.fetch("verification", {}).length >= 20 &&
  report.fetch("verification", {}).values.all?(true) && report["human_visual_review_required"] == true
check("Phase 12C.1 assessment JSON", assessment_ok, errors)
unless assessment_ok
  warn stderr
  warn stdout
end

html = File.read("assets/dashboard/index.html")
css = File.read("assets/dashboard/dashboard.css")
javascript = File.read("assets/dashboard/dashboard.js")
auth_source = File.read("lib/soul_core/dashboard_authentication.rb")
http_source = File.read("lib/soul_core/dashboard_http_application.rb")

check("locked first-visit presentation and forced-change forms exist", html.include?('class="auth-locked"') && html.include?('id="login-form"') && html.include?('id="password-change-form"') && css.include?("filter:blur(9px)"), errors)
check("browser has no client-side credential store", %w[localStorage sessionStorage document.cookie].none? { |primitive| javascript.include?(primitive) }, errors)
check("server protects facade and persists only bounded session digests", http_source.include?("authentication_required") && http_source.include?("password_change_required") && auth_source.include?("clear_sessions!") && auth_source.include?("SESSION_ABSOLUTE_SECONDS = 7 * 24 * 60 * 60") && auth_source.include?("token_digest"), errors)
check("no signup or multi-user route was added", %w[/auth/v1/signup /auth/v1/register].none? { |route| [html, javascript, http_source].any? { |source| source.include?(route) } }, errors)
check("implementation remains foreground and timer-free", %w[setInterval setTimeout WebSocket EventSource serviceWorker Thread.new daemon(].none? { |primitive| [javascript, auth_source, http_source].any? { |source| source.include?(primitive) } }, errors)

stdout, stderr, status = Open3.capture3("ruby", "scripts/verify-phase12c-foreground-dashboard.rb")
check("Phase 12C foreground dashboard regressions", status.success?, errors)
unless status.success?
  warn stderr
  warn stdout
end

stdout, stderr, status = Open3.capture3("ruby", "scripts/verify-phase12d-skill-studio.rb")
check("Phase 12D Skill Studio regressions", status.success?, errors)
unless status.success?
  warn stderr
  warn stdout
end

review = File.read("docs/assessments/CONVERSATIONAL_SOUL_PHASE12C1_DASHBOARD_AUTHENTICATION.md")
review_sections = ["## What was implemented", "## Files changed", "## Commands run", "## Deterministic test results", "## Local LLM eval results", "## Known weaknesses", "## Memory keys", "## Task lifecycle states touched", "## Risk classification", "## Human review checklist"]
check("review artifact contains required sections", review_sections.all? { |heading| review.include?(heading) }, errors)
check("working-tree whitespace check", system("git", "diff", "--check", out: File::NULL, err: File::NULL), errors)
check("staged whitespace check", system("git", "diff", "--cached", "--check", out: File::NULL, err: File::NULL), errors)

if errors.empty?
  puts "Verification complete."
  puts "Phase 12C.1 is blocked for human authentication and visual review."
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
