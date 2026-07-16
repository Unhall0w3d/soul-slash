#!/usr/bin/env ruby
# frozen_string_literal: true

failures = []
check = lambda do |name, passed|
  puts "#{passed ? 'PASS' : 'FAIL'}: #{name}"
  failures << name unless passed
end

puts "Conversational Soul Phase 13B local-model/dashboard verification:"

runner = File.read("scripts/run-phase13b-local-model-acceptance.rb")
html = File.read("assets/dashboard/index.html")
javascript = File.read("assets/dashboard/dashboard.js")
review = File.read("docs/assessments/CONVERSATIONAL_SOUL_PHASE13B_LOCAL_MODEL_AND_DASHBOARD_ACCEPTANCE.md")

check.call("local evaluation is exactly twenty foreground turns", runner.include?("TURN_LIMIT = 20") && runner.include?("TOTAL_TIMEOUT_SECONDS = 600"))
check.call("local evaluation forbids cloud fallback", runner.include?('"SOUL_ALLOW_CLOUD_CONVERSATION" => "false"') && runner.include?('provider.privacy_class != "cloud"'))
check.call("local evaluation does not retain transcript", runner.include?('"transcript_retained" => false') && !runner.include?("File.write"))
check.call("local evaluation reports hashes rather than response prose", runner.include?("response_sha256") && !runner.include?('"content" => result.content'))
check.call("dashboard exposes three primary tabs", %w[chat-tab studio-tab improvement-tab].all? { |id| html.include?("id=\"#{id}\"") })
check.call("dashboard exposes Review Center and authentication", html.include?('id="review-center"') && html.include?('id="auth-gate"'))
check.call("dashboard exposes initial and manual system status", javascript.include?("system_status.refresh") && html.include?("refresh-status"))
check.call("dashboard remains timer and polling free", %w[setInterval setTimeout WebSocket EventSource].none? { |primitive| javascript.include?(primitive) })
check.call("review records completed local model evidence", review.include?("20/20") && review.include?("transcript retained: no") && review.include?("Human review outcome"))

if failures.empty?
  puts "Phase 13B local-model/dashboard verification complete."
  exit 0
end

warn "Phase 13B verification failed: #{failures.join('; ')}"
exit 1
