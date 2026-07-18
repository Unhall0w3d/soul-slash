#!/usr/bin/env ruby
# frozen_string_literal: true

root = File.expand_path("..", __dir__)
html = File.read(File.join(root, "assets/dashboard/index.html"))
css = File.read(File.join(root, "assets/dashboard/dashboard.css"))
javascript = File.read(File.join(root, "assets/dashboard/dashboard.js"))
facade = File.read(File.join(root, "lib/soul_core/application_facade.rb"))
failures = []
check = ->(name, value) { puts "- #{name}: #{value ? 'ok' : 'FAILED'}"; failures << name unless value }

check.call("top bar retains three styled primary destinations", html.index('id="chat-tab"') < html.index('id="self-improvement-tab"') && html.index('id="self-improvement-tab"') < html.index('id="music-tab"') && html.include?('class="tab"'))
check.call("Self Improvement menu exposes all three existing pages", %w[studio-tab improvement-tab augmentation-tab].all? { |id| html.include?("id=\"#{id}\"") } && html.include?('role="menu"') && html.include?('role="menuitem"'))
check.call("Skill Studio no longer carries a Beta navigation tag", !html.match?(/Skill Studio\s*<span class="phase-tag">Beta/))
check.call("menu state is explicit, dismissible, and keyboard closable", javascript.include?("setSelfImprovementMenu") && javascript.include?('event.key === "Escape"') && javascript.include?('aria-expanded'))
check.call("active nested surface illuminates the parent destination", javascript.include?('classList.toggle("is-active", selfImprovement)') && javascript.include?('setAttribute("aria-current"'))
check.call("validated URL fragment preserves the active page across refresh", javascript.include?("TAB_LOCATIONS") && javascript.include?("tabFromLocation()") && javascript.include?("window.history.replaceState") && javascript.include?('window.addEventListener("hashchange"') && !javascript.include?("localStorage"))
check.call("visual language remains part of the existing top bar", css.include?(".tab-menu") && css.include?(".self-improvement-menu") && css.include?("var(--gold)") && css.include?("var(--cyan)"))
check.call("bootstrap advertises primary and nested surfaces separately", facade.include?('"product_tabs" => ["Chat", "Self Improvement", "Music Studio"]') && facade.include?('"self_improvement_surfaces" => ["Skill Studio", "Self Assessment", "Self Augmentation"]'))
check.call("navigation adds no polling or unsafe rendering", %w[setInterval setTimeout innerHTML insertAdjacentHTML].none? { |term| javascript.include?(term) })

abort "Self Improvement navigation verification failed: #{failures.join(', ')}" unless failures.empty?
puts "Self Improvement navigation deterministic verification passed."
