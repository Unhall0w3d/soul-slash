#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "socket"
require "timeout"

errors = []

def check(label, condition, errors)
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

puts "Conversational Soul Phase 12C foreground dashboard verification:"

required = %w[
  assets/dashboard/index.html
  assets/dashboard/dashboard.css
  assets/dashboard/dashboard.js
  docs/CONVERSATIONAL_SOUL_ROADMAP.md
  docs/assessments/CONVERSATIONAL_SOUL_PHASE12C_FOREGROUND_DASHBOARD.md
  docs/soul/FOREGROUND_LOOPBACK_DASHBOARD.md
  docs/soul/PHASE12C_FOREGROUND_LOOPBACK_DASHBOARD_BRIEF.md
  lib/soul_core/dashboard_command.rb
  lib/soul_core/dashboard_http_application.rb
  lib/soul_core/dashboard_server.rb
  lib/soul_core/phase12c_foreground_dashboard_assessor.rb
  scripts/verify-phase12c-foreground-dashboard.rb
]

required.each do |path|
  ok = File.exist?(path)
  ok &&= system("ruby", "-c", path, out: File::NULL, err: File::NULL) if path.end_with?(".rb")
  check(path, ok, errors)
end

stdout, stderr, status = Open3.capture3("ruby", "bin/soul", "assess", "phase12c-foreground-dashboard", "--json")
report = JSON.parse(stdout) rescue nil
assessment_ok = status.success? && report && report["ok"] == true && report["phase"] == "12C" && report["status"] == "blocked_for_human_review" && report.fetch("verification", {}).length == 21 && report.fetch("verification", {}).values.all?(true) && report["human_visual_review_required"] == true
check("Phase 12C assessment JSON", assessment_ok, errors)
unless assessment_ok
  warn stderr
  warn stdout
end

stdout, stderr, status = Open3.capture3("ruby", "bin/soul", "assess", "phase12c-foreground-dashboard")
check("Phase 12C assessment text", status.success? && stdout.include?("Status: blocked_for_human_review") && stdout.include?("Blockers\n- None"), errors)

html = File.read("assets/dashboard/index.html")
css = File.read("assets/dashboard/dashboard.css")
js = File.read("assets/dashboard/dashboard.js")
server = File.read("lib/soul_core/dashboard_server.rb")
check("dashboard has approved two-tab visual hierarchy", html.index("Chat") < html.index("Skill Studio") && html.include?("Human visual review"), errors)
check("browser remains timer-free and same-origin", %w[setInterval setTimeout WebSocket EventSource serviceWorker innerHTML].none? { |needle| js.include?(needle) } && ![html, css, js].any? { |source| source.match?(%r{https?://}) }, errors)
check("server is sequential foreground-only", server.include?("listener.accept") && %w[Thread.new fork( daemon( Process.spawn].none? { |needle| server.include?(needle) }, errors)

probe = TCPServer.new("127.0.0.1", 0)
port = probe.addr[1]
probe.close
pid = Process.spawn("ruby", "bin/soul", "dashboard", "--set", "dashboard.port=#{port}", "--max-requests", "1", out: File::NULL, err: File::NULL)
connected = false
response = ""
process_status = nil
begin
  40.times do
    begin
      socket = TCPSocket.new("127.0.0.1", port)
      socket.write("GET / HTTP/1.1\r\nHost: 127.0.0.1:#{port}\r\nConnection: close\r\n\r\n")
      response = socket.read
      socket.close
      connected = true
      break
    rescue Errno::ECONNREFUSED
      IO.select(nil, nil, nil, 0.025)
    end
  end
  _, process_status = Timeout.timeout(3) { Process.wait2(pid) } if connected
ensure
  unless process_status
    Process.kill("TERM", pid) rescue nil
    Process.wait(pid) rescue nil
  end
end
check("foreground max-request bound terminates cleanly", connected && response.start_with?("HTTP/1.1 200 OK") && process_status&.success?, errors)

review = File.read("docs/assessments/CONVERSATIONAL_SOUL_PHASE12C_FOREGROUND_DASHBOARD.md")
review_sections = ["## Implementation summary", "## Files changed", "## Commands run", "## Deterministic test results", "## Local LLM eval results", "## Memory keys", "## Lifecycle states touched", "## Risk classification", "## Safety and persistence check", "## Known weaknesses", "## Human review checklist", "## Human review outcome"]
check("review artifact contains required sections", review_sections.all? { |heading| review.include?(heading) }, errors)

stdout, stderr, status = Open3.capture3("ruby", "scripts/verify-phase12b-in-process-application-api.rb")
check("Phase 12B and earlier regressions", status.success?, errors)
unless status.success?
  warn stderr
  warn stdout
end

check("working-tree whitespace check", system("git", "diff", "--check", out: File::NULL, err: File::NULL), errors)
check("staged whitespace check", system("git", "diff", "--cached", "--check", out: File::NULL, err: File::NULL), errors)

if errors.empty?
  puts "Verification complete."
  puts "Phase 12C is blocked for the required human visual review."
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
