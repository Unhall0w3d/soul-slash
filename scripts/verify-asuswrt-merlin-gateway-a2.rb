#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"

ROOT = File.expand_path("..", __dir__)
errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

puts "ASUSWRT-Merlin gateway A2 verification:"

output, status = Open3.capture2e("ruby", File.join(ROOT, "scripts", "verify-asuswrt-merlin-inventory-a1.rb"))
check.call("extended deterministic adapter suite passes", status.success? && output.include?("PASS"))

adapter = File.read(File.join(ROOT, "lib", "soul_core", "asuswrt_merlin_inventory_adapter.rb"))
fleet = File.read(File.join(ROOT, "lib", "soul_core", "maintenance_fleet_status_service.rb"))
dashboard = File.read(File.join(ROOT, "assets", "dashboard", "dashboard.js"))
brief = File.read(File.join(ROOT, "docs", "soul", "ASUSWRT_MERLIN_GATEWAY_A2_BRIEF.md"))

check.call("remote collection remains bounded and read-only",
           adapter.include?("COMMAND_TIMEOUT_SECONDS = 8") &&
           adapter.include?("MAX_OUTPUT_BYTES = 32 * 1024") &&
           !adapter.match?(/opkg update|nvram (?:show|dump)|service restart|reboot/))
check.call("private device and storage identity are not projected",
           !adapter.match?(/serial|uuid|filesystem_label|device_name/) &&
           adapter.include?("usb_storage_summary") && adapter.include?("swap_summary"))
check.call("firmware state remains explicitly uninterpreted",
           adapter.include?('"update_available" => nil') &&
           adapter.include?('"interpretation" => "raw_vendor_state_only"'))
check.call("fleet projection has no mutation or reboot authority",
           fleet.include?('"status_adapter" => "asuswrt_merlin_read_only"') &&
           fleet.include?('"mutation_supported" => false') &&
           fleet.include?('reboot: {"required" => false, "reason" => "not assessed · inventory only"}'))
check.call("Dashboard exposes bounded gateway evidence and the authority boundary",
           %w[merlinEntware merlinSwap merlinStorage merlinFirmware merlinDiagnostics].all? { |token| dashboard.include?(token) } &&
           dashboard.include?("package, firmware, configuration, maintenance, and reboot authority remain disabled"))
check.call("human brief records privacy and lifecycle exclusions",
           brief.include?("router mutation authorized: no") && brief.include?("No retries, listener, watcher, timer, daemon") && brief.include?("No NVRAM dump"))

if errors.empty?
  puts "PASS"
else
  warn "FAIL: #{errors.join(', ')}"
  exit 1
end
