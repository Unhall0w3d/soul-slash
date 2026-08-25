#!/usr/bin/env ruby
# frozen_string_literal: true

root = File.expand_path("..", __dir__)
index = File.read(File.join(root, "assets/dashboard/index.html"))
javascript = File.read(File.join(root, "assets/dashboard/dashboard.js"))
stylesheet = File.read(File.join(root, "assets/dashboard/dashboard.css"))
brief = File.read(File.join(root, "docs/soul/MEMORY_OBSERVATORY_3D_CONSTELLATION_A28_BRIEF.md"))

checks = {}
check = lambda { |name, condition| checks[name] = condition }
panel_start = index.index('<section id="memory-observatory-panel"')
panel_end = index.index('<section id="maintenance-panel"', panel_start || 0)
panel = panel_start && panel_end ? index[panel_start...panel_end] : ""
observatory_start = javascript.index("function observatoryText")
observatory_end = javascript.index("const TIMELINE_HORIZONS", observatory_start || 0)
observatory_javascript = observatory_start && observatory_end ? javascript[observatory_start...observatory_end] : ""
a28_start = javascript.index("function memory3dCoordinates")
a28_javascript = a28_start ? javascript[a28_start...(javascript.index("function renderMemoryObservatorySummary", a28_start) || javascript.length)] : ""

check.call("3D Canvas and accessible metadata controls are in Observatory", %w[memory-constellation-3d memory-3d-layout memory-3d-reset memory-3d-metadata memory-3d-node-list].all? { |id| panel.include?(%Q[id="#{id}"]) })
check.call("SVG constellation and lifecycle fallback remain present", panel.include?('id="memory-constellation"') && panel.include?('id="memory-constellation-layout"') && panel.include?('id="memory-lifecycle-layout"'))
check.call("projection consumes the existing bounded schema", observatory_javascript.include?("value.nodes") && observatory_javascript.include?("value.edges") && observatory_javascript.include?("slice(0, 240)") && observatory_javascript.include?("slice(0, 400)"))
check.call("coordinates are deterministic and depth is rendered", observatory_javascript.include?("memory3dCoordinates") && observatory_javascript.include?("memoryHash(node.id)") && observatory_javascript.include?("perspective") && observatory_javascript.include?("globalAlpha"))
check.call("only explicit relationships are drawn", observatory_javascript.include?("edge.relation === \"supersession\"") && observatory_javascript.include?("edge.source") && observatory_javascript.include?("edge.target") && !observatory_javascript.match?(/similarity|semantic|inferred|cluster/i))
check.call("drag and keyboard controls render on demand", observatory_javascript.include?("pointerdown") && observatory_javascript.include?("ArrowLeft") && observatory_javascript.include?("resetMemory3dView") && !observatory_javascript.match?(/requestAnimationFrame|setInterval|setTimeout/))
check.call("mode changes detach Canvas listeners", observatory_javascript.include?("detachMemory3dControls") && observatory_javascript.include?("state.memoryObservatory3d.cleanup = ()") && observatory_javascript.include?("removeEventListener"))
check.call("leaving Observatory detaches Canvas listeners", javascript.include?('if (!memoryObservatory) detachMemory3dControls();'))
check.call("dynamic labels use text nodes", !observatory_javascript.match?(/memory3dMetadata[\s\S]*innerHTML|memory3dMetadata[\s\S]*outerHTML/) && observatory_javascript.include?("button.textContent"))
check.call("reduced-motion styling is explicit", stylesheet.include?("prefers-reduced-motion") && brief.include?("Render on demand only"))
check.call("3D mode exposes no mutation or network controls", panel.scan(/<button\b[^>]*>(.*?)<\/button>/mi).flatten.none? { |label| label.match?(/\b(?:approve|delete|forget|supersede|execute|mutat|write)\b/i) } && !a28_javascript.match?(/fetch\(|callSoul\(/))

checks.each { |name, passed| puts "#{passed ? "PASS" : "FAIL"} #{name}" }
abort "Memory Observatory A28 verifier failed" unless checks.values.all?
puts "Memory Observatory 3D Constellation A28 verification passed (#{checks.length} checks)."
