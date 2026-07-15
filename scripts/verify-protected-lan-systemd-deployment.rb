#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

errors = []

def check(label, condition, errors)
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

puts "Soul protected LAN and systemd deployment verification:"

required = %w[
  Makefile
  docs/soul/PROTECTED_LAN_SYSTEMD_DEPLOYMENT_BRIEF.md
  docs/soul/LOCAL_SYSTEMD_HTTPS_DEPLOYMENT.md
  docs/assessments/PROTECTED_LAN_SYSTEMD_DEPLOYMENT.md
  lib/soul_core/dashboard_deployment.rb
  lib/soul_core/dashboard_deployment_assessor.rb
  scripts/soul-dashboard-service
  scripts/verify-protected-lan-systemd-deployment.rb
]

required.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb") || path.start_with?("scripts/")
  check(path, ok, errors)
end

stdout, stderr, status = Open3.capture3("ruby", "bin/soul", "assess", "dashboard-deployment", "--json")
report = JSON.parse(stdout) rescue nil
assessment_ok = status.success? && report && report["ok"] == true && report["status"] == "blocked_for_human_review" && report.fetch("verification", {}).length >= 14 && report.fetch("verification", {}).values.all?(true)
check("deployment assessment JSON", assessment_ok, errors)
unless assessment_ok
  warn stderr
  warn stdout
end

deployment = File.read("lib/soul_core/dashboard_deployment.rb")
makefile = File.read("Makefile")
check("exact service allowlist", deployment.include?("SERVICE_NAMES = %w[soul-dashboard.service soul-dashboard-proxy.service]") && deployment.include?("SERVICE_NAMES.length") == false, errors)
make_targets = %w[dashboard-service-plan dashboard-service-install dashboard-service-status dashboard-service-logs dashboard-service-uninstall]
check("Makefile exposes gated deployment lifecycle", make_targets.all? { |target| makefile.match?(/^#{Regexp.escape(target)}:/) } && makefile.include?("CONFIRM=INSTALL_SOUL_LAN_SERVICES") && makefile.include?("CONFIRM=REMOVE_SOUL_LAN_SERVICES"), errors)
check("no package firewall router or privileged-port mutation", %w[pacman apt dnf iptables nftables firewall-cmd setcap port-forward].none? { |primitive| deployment.match?(/\b#{Regexp.escape(primitive)}\b/i) }, errors)
check("no timer watcher or application retry loop", %w[.timer inotify setInterval setTimeout Thread.new].none? { |primitive| deployment.include?(primitive) }, errors)

regressions = [
  ["Phase 12A configuration", %w[ruby bin/soul assess phase12a-configuration --json]],
  ["dashboard authentication", %w[ruby scripts/verify-dashboard-authentication-phase12c1.rb]],
  ["Self Improvement dashboard", %w[ruby scripts/verify-phase12d3-self-improvement-dashboard.rb]],
  ["runtime privacy", %w[ruby scripts/verify-runtime-privacy-hygiene-phase44.rb]]
]
regressions.each do |label, command|
  stdout, stderr, status = Open3.capture3(*command)
  check("#{label} regressions", status.success?, errors)
  unless status.success?
    warn stderr
    warn stdout
  end
end

review = File.read("docs/assessments/PROTECTED_LAN_SYSTEMD_DEPLOYMENT.md")
sections = ["## What was implemented", "## Files changed", "## Commands run", "## Deterministic test results", "## Local LLM eval results", "## Known weaknesses", "## Memory keys", "## Task lifecycle states touched", "## Risk classification", "## Human review checklist"]
check("review artifact contains required sections", sections.all? { |heading| review.include?(heading) }, errors)
check("working-tree whitespace check", system("git", "diff", "--check", out: File::NULL, err: File::NULL), errors)
check("staged whitespace check", system("git", "diff", "--cached", "--check", out: File::NULL, err: File::NULL), errors)

if errors.empty?
  puts "Verification complete."
  puts "Deployment is blocked for local service and client trust review."
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
