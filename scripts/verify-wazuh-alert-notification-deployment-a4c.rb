#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "../lib/soul_core/wazuh_alert_notification_deployment"

def check(label, condition)
  raise "FAIL: #{label}" unless condition
  puts "PASS: #{label}"
end

Dir.mktmpdir("soul-wazuh-alert-deployment-") do |root|
  home = File.join(root, "home")
  project = File.join(root, "project")
  FileUtils.mkdir_p(File.join(home, ".config", "systemd", "user"))
  FileUtils.mkdir_p(File.join(project, "scripts"))
  FileUtils.mkdir_p(File.join(project, "Soul", "private", "security", "wazuh"), mode: 0o700)
  File.write(File.join(project, "scripts", "poll-wazuh-alert-notifications"), "#!/usr/bin/env ruby\n", mode: "w", perm: 0o755)
  manifest = File.join(project, "Soul", "private", "security", "wazuh", "alerts-integration.json")
  File.write(manifest, "{}\n", mode: "w", perm: 0o600)
  systemctl = File.join(root, "systemctl")
  ruby = File.join(root, "ruby")
  [systemctl, ruby].each { |path| File.write(path, "#!/bin/sh\nexit 0\n", mode: "w", perm: 0o755) }
  calls = []
  runner = ->(command) { calls << command; {"success" => true, "stdout" => "ActiveState=active\n", "stderr" => ""} }
  deployment = SoulCore::WazuhAlertNotificationDeployment.new(root: project, home: home, integration_file: manifest, ruby_path: ruby, systemctl_path: systemctl, runner: runner)

  plan = deployment.plan
  service = plan.dig("data", "units", SoulCore::WazuhAlertNotificationDeployment::SERVICE)
  timer = plan.dig("data", "units", SoulCore::WazuhAlertNotificationDeployment::TIMER)
  check("plan requires exact human confirmation", plan["lifecycle_state"] == "blocked_for_human_review" && plan.dig("data", "confirmation") == "INSTALL_SOUL_WAZUH_ALERT_NOTIFICATIONS")
  check("service is bounded and has no remediation authority", service.include?("ProtectSystem=strict") && service.include?("ProtectHome=read-only") && service.include?("ReadWritePaths=") && plan.dig("data", "remediation_authority") == false)
  check("timer is durable and rate-bounded", timer.include?("OnUnitActiveSec=60s") && timer.include?("RandomizedDelaySec=10s") && timer.include?("Persistent=true"))
  rejected = deployment.install(confirmation: "wrong")
  check("installation rejects the wrong phrase", rejected["lifecycle_state"] == "awaiting_input" && calls.empty?)
  installed = deployment.install(confirmation: "INSTALL_SOUL_WAZUH_ALERT_NOTIFICATIONS")
  check("exact installation writes and enables both units", installed["ok"] && calls.any? { |command| command.include?("enable") } && File.file?(File.join(home, ".config", "systemd", "user", SoulCore::WazuhAlertNotificationDeployment::SERVICE)))
  check("installed unit text matches the reviewed plan", deployment.status.dig("data", "installed_exact") == true)
end

puts "Wazuh alert notification deployment A4c verification complete."
