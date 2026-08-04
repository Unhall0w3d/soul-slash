#!/usr/bin/env ruby
# frozen_string_literal: true

html = File.read(File.expand_path("../assets/dashboard/index.html", __dir__))
js = File.read(File.expand_path("../assets/dashboard/dashboard.js", __dir__))
css = File.read(File.expand_path("../assets/dashboard/dashboard.css", __dir__))
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
check.call("topology snapshot actions share one equal control grid", css.include?(".local-topology-toolbar { display:grid; grid-template-columns:repeat(2,minmax(220px,1fr))") && css.include?(".local-topology-toolbar .refresh-button,.local-topology-toolbar .gate-button"))
check.call("shared Wazuh actions align buttons and links identically", css.include?(".wazuh-security-actions .quiet-button { display:inline-flex; align-items:center; justify-content:center") && css.include?("flex:0 0 180px; width:180px; min-height:36px"))
check.call("topology navigation has a stable hash", js.include?('topology: "#local-topology-panel"'))
check.call("shared renderer targets the dedicated topology canvas", js.include?('renderMaintenanceTopology(data.topology, { canvasId: "local-topology" })'))
check.call("Wazuh health is projected without moving remediation authority",
           html.include?('id="maintenance-wazuh-summary"') && html.include?('id="topology-wazuh-summary"') &&
             js.include?('callSoul(operation)') && js.include?('"security.wazuh.snapshot"') && js.include?('"security.wazuh.status"') &&
             js.include?("Read-only normalized evidence · no acknowledgement, suppression, or remediation authority") &&
             js.include?("security.wazuh.alerts.snapshot") && js.include?("security.wazuh.alerts.status"))
check.call("adapted compliance remains beside the unaltered Wazuh result",
           js.include?("security.wazuh.posture.snapshot") && js.include?("security.wazuh.posture.status") &&
             js.include?("raw CIS") && js.include?("raw Wazuh score remains unchanged and authoritative"))
check.call("Wazuh investigations open only as isolated HTTPS links",
           html.scan('rel="noopener noreferrer"').length >= 2 && js.include?('url.protocol === "https:"'))

check.call("rich maintenance cards provide a keyboard-accessible disclosure control",
           js.include?('setMaintenanceDeviceExpanded(card, expanded)') &&
             js.include?('toggleMaintenanceDeviceExpansion(event, card)') &&
             js.include?('maintenance-device-expand-toggle') &&
             js.include?('expandToggle.addEventListener("click"') &&
             js.include?('expandToggle.setAttribute("aria-controls"'))
check.call("rich maintenance cards expose collapsible details with stable compact state",
           js.include?('maintenance-device-card--compact') &&
             js.include?('maintenance-device-details') &&
             js.include?('setMaintenanceDeviceExpanded(card, state.maintenanceDeviceExpanded.has(card.dataset.deviceId))') &&
             js.include?('card.setAttribute("aria-controls"') &&
             js.include?('card.setAttribute("aria-expanded"'))
check.call("compact styling keeps rich card details hidden until expanded",
           css.include?('.maintenance-device-details { display:none; }') &&
             css.include?('.maintenance-device-card--expanded .maintenance-device-details { display:block; }') &&
             css.include?('.maintenance-device-card--expanded.maintenance-device-card--compact { padding:20px; }'))
check.call("rich card interaction guards preserve button/link actions",
           js.include?("isMaintenanceCardInteractiveElement") && js.include?("target !== card") && js.include?("closest(\"button, a, input, select, textarea, details, summary, label, [role='button'], [role='link']\")"))

check.call("status-only cards remain compact and separate from expanded controls",
           js.include?("card.classList.add(\"maintenance-device-card--status-only\")") &&
             js.include?('role.remove()'))

abort("Local topology A1 verification failed: #{errors.join(', ')}") unless errors.empty?

puts "Local topology A1 verification passed."
