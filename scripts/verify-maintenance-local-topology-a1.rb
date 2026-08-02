#!/usr/bin/env ruby
# frozen_string_literal: true

html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
js = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
errors = []

check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

puts "Local topology A1 verification:"
check.call("Administration exposes a dedicated Local Topology panel", html.include?('id="local-topology-tab"') && html.include?('id="local-topology-panel"'))
check.call("Guided Maintenance no longer owns the topology canvas", !html.include?('id="maintenance-topology"'))
check.call("Local Topology has saved-snapshot and explicit collection controls", html.include?('id="refresh-local-topology-fleet"') && html.include?('id="collect-local-topology-fleet"'))
check.call("topology reuses the bounded maintenance snapshot contract", js.include?('callSoul("maintenance.fleet.snapshot")') && js.include?('callSoul("maintenance.fleet.status"'))
check.call("topology navigation has a stable hash", js.include?('topology: "#local-topology-panel"'))
check.call("shared renderer targets the dedicated topology canvas", js.include?('renderMaintenanceTopology(data.topology, { canvasId: "local-topology" })'))
check.call("Wazuh health is projected without moving remediation authority",
           html.include?('id="maintenance-wazuh-summary"') && html.include?('id="topology-wazuh-summary"') &&
             js.include?('callSoul(operation)') && js.include?('"security.wazuh.snapshot"') && js.include?('"security.wazuh.status"') &&
             js.include?("alert evidence not integrated · no remediation authority"))
check.call("Wazuh investigations open only as isolated HTTPS links",
           html.scan('rel="noopener noreferrer"').length >= 2 && js.include?('url.protocol === "https:"'))

abort("Local topology A1 verification failed: #{errors.join(', ')}") unless errors.empty?

puts "Local topology A1 verification passed."
