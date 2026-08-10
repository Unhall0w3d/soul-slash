#!/usr/bin/env ruby
# frozen_string_literal: true

root = File.expand_path("..", __dir__)
service = File.binread(File.join(root, "lib/soul_core/blender_scene_service.rb"))
contract = File.binread(File.join(root, "lib/soul_core/application_contract.rb"))
facade = File.binread(File.join(root, "lib/soul_core/application_facade.rb"))
html = File.binread(File.join(root, "assets/dashboard/index.html"))
javascript = File.binread(File.join(root, "assets/dashboard/dashboard.js"))

checks = {
  "service closes the operator look-profile vocabulary" => service.include?("LOOK_PROFILES = {") && service.include?('raise ArgumentError, "Blender look profile is invalid"'),
  "look selection is confirmation-bound and retained" => service.include?('"look_profile" => look_profile') && service.include?('"look_profile" => scope.fetch("look_profile")'),
  "application boundary transports the look profile" => contract.include?("quality look_profile source_blender_scene_id") && facade.scan('parameters.fetch("look_profile", "template")').length == 2,
  "Visual Studio exposes the closed look selector" => html.include?('id="visual-blender-look"') && html.include?('value="crystalline_void"'),
  "Dashboard submits the exact selected look" => javascript.include?('look_profile: byId("visual-blender-look").value'),
  "two richer scene families are exposed" => service.include?("void_sanctuary signal_forge") && html.include?('value="void_sanctuary"') && html.include?('value="signal_forge"')
}

checks.each do |label, passed|
  raise "FAIL: #{label}" unless passed
  puts "PASS: #{label}"
end

puts "Blender Scene A6 Dashboard checks passed: #{checks.length}"
