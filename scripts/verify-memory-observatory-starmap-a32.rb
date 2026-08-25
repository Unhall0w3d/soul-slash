#!/usr/bin/env ruby
# frozen_string_literal: true

root = File.expand_path("..", __dir__)
index = File.read(File.join(root, "assets/dashboard/index.html"))
javascript = File.read(File.join(root, "assets/dashboard/dashboard.js"))
stylesheet = File.read(File.join(root, "assets/dashboard/dashboard.css"))
brief = File.read(File.join(root, "docs/soul/MEMORY_OBSERVATORY_STARMAP_A32_BRIEF.md"))

checks = {}
check = ->(name, condition) { checks[name] = condition }
start = javascript.index("function memory3dLayers")
finish = javascript.index("function renderMemoryObservatorySummary", start || 0)
starmap = start && finish ? javascript[start...finish] : ""

check.call("3D starmap is the default visual mode", javascript.include?('memoryObservatoryVisualizationMode: "3d"') && index.include?('id="memory-3d-layout" class="quiet-button is-active"'))
check.call("rotation reset and fullscreen controls are present", %w[memory-3d-rotation memory-3d-reset memory-3d-fullscreen].all? { |id| index.include?(%Q[id="#{id}"]) })
check.call("layout is deterministic and layer centered", starmap.include?("memory3dLayerAnchor") && starmap.include?("memoryHash(node.id)") && starmap.include?("memory-star-x:") && starmap.include?(".sort()"))
check.call("visualization retains strict caps", starmap.include?("slice(0, 240)") && starmap.include?("slice(0, 400)"))
check.call("only supplied explicit edges are rendered", starmap.include?("edge.source") && starmap.include?("edge.target") && starmap.include?('edge.relation === "supersession"') && !starmap.match?(/similarity|semantic|inferred/i))
check.call("animation is one cancellable visible-only chain", starmap.include?("window.requestAnimationFrame(step)") && starmap.include?("window.cancelAnimationFrame") && starmap.include?('document.visibilityState === "hidden"') && starmap.include?("detachMemory3dControls"))
check.call("reduced motion disables automatic rotation", starmap.include?('prefers-reduced-motion: reduce') && brief.include?("Reduced-motion preference disables automatic rotation"))
check.call("no timers polling or unbounded loops exist", !starmap.match?(/setInterval|setTimeout|while\s*\(\s*true/))
check.call("pointer keyboard and zoom controls remain local", %w[pointerdown ArrowLeft Space wheel resetMemory3dView].all? { |token| starmap.include?(token) })
check.call("accessible metadata fallback remains", index.include?('id="memory-3d-node-list"') && starmap.include?("button.textContent") && starmap.include?("memory3dInspect"))
check.call("no network or mutation authority enters renderer", !starmap.match?(/fetch\(|callSoul\(|approveMemory|deleteMemory|forgetMemory|supersedeMemory|writeMemory/i))
check.call("fullscreen and responsive visual surface are bounded", javascript.include?("requestFullscreen") && stylesheet.include?(".memory-constellation-stage:fullscreen") && stylesheet.include?("@media (max-width:820px)"))

checks.each { |name, passed| puts "#{passed ? "PASS" : "FAIL"} #{name}" }
abort "Memory Observatory A32 verifier failed" unless checks.values.all?
puts "Memory Observatory Starmap A32 verification passed (#{checks.length} checks)."
