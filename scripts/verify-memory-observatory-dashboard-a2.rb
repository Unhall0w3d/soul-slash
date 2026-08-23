#!/usr/bin/env ruby
# frozen_string_literal: true

root = File.expand_path("..", __dir__)
index = File.read(File.join(root, "assets/dashboard/index.html"))
javascript = File.read(File.join(root, "assets/dashboard/dashboard.js"))
stylesheet = File.read(File.join(root, "assets/dashboard/dashboard.css"))

checks = {}
check = lambda do |name, condition|
  checks[name] = condition
end

panel_start = index.index('<section id="memory-observatory-panel"')
panel_end = index.index('<section id="maintenance-panel"', panel_start || 0)
panel = panel_start && panel_end ? index[panel_start...panel_end] : ""
observatory_start = javascript.index("function observatoryText")
observatory_end = javascript.index("const TIMELINE_HORIZONS", observatory_start || 0)
observatory_javascript = observatory_start && observatory_end ? javascript[observatory_start...observatory_end] : ""

check.call("Administration menu exposes one Memory Observatory entry", index.scan('id="memory-observatory-tab"').length == 1 && index.include?("aria-controls=\"memory-observatory-panel\""))
check.call("panel is nested under authenticated Administration navigation", panel.include?("role=\"tabpanel\"") && panel.include?("aria-labelledby=\"administration-tab memory-observatory-tab\""))
check.call("panel covers bounded summary and index evidence", %w[memory-observatory-state-counts memory-observatory-layer-counts memory-observatory-source-counts memory-observatory-index-details].all? { |id| panel.include?(%Q[id="#{id}"]) })
check.call("panel covers lifecycle and relationship observations", %w[memory-observatory-events memory-observatory-relationships].all? { |id| panel.include?(%Q[id="#{id}"]) })
check.call("panel provides explicit diagnostic query and review guidance", panel.include?("memory-observatory-query-form") && panel.include?("memory-observatory-review-guidance"))
check.call("panel has no mutation buttons", panel.scan(/<button\b[^>]*>(.*?)<\/button>/mi).flatten.none? { |label| label.match?(/\b(?:approve|delete|forget|supersede|execute|mutat|write)\b/i) })
check.call("observatory operations use the authenticated callSoul path", observatory_javascript.include?('callSoul("memory.observatory.summary")') && observatory_javascript.include?('callSoul("memory.observatory.query"'))
check.call("diagnostic query is explicitly bounded", observatory_javascript.include?("slice(0, 200)") && observatory_javascript.include?("limit: 20"))
check.call("dynamic Observatory output uses safe text nodes", !observatory_javascript.match?(/innerHTML|insertAdjacentHTML|outerHTML/) && observatory_javascript.scan(/\.textContent\s*=/).length >= 12)
check.call("no Observatory polling or background continuation", !observatory_javascript.match?(/setInterval|setTimeout|requestAnimationFrame|while\s*\(\s*true/))
check.call("navigation maps and toggles the panel", javascript.include?('"memory-observatory": "#memory-observatory-panel"') && javascript.include?('const memoryObservatory = name === "memory-observatory"') && javascript.include?('byId("memory-observatory-panel").hidden = !memoryObservatory'))
check.call("existing navigation remains present", %w[chat-tab host-stewardship-tab timeline-tab maintenance-tab local-topology-tab backup-tab].all? { |id| index.include?(%Q[id="#{id}"]) })
check.call("responsive collapsible styling exists", stylesheet.include?(".memory-observatory-disclosure") && stylesheet.include?("@media (max-width:820px)") && stylesheet.include?(".memory-observatory-columns { grid-template-columns:1fr"))

checks.each { |name, passed| puts "#{passed ? "PASS" : "FAIL"} #{name}" }
abort "Memory Observatory dashboard verification failed" unless checks.values.all?

puts "Memory Observatory dashboard verification passed (#{checks.length} checks)."
