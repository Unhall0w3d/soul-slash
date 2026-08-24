#!/usr/bin/env ruby
# frozen_string_literal: true

dashboard = File.read(File.join(__dir__, "../assets/dashboard/dashboard.js"))
errors = []
check = lambda do |label, condition|
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

helper = dashboard[/async function reconcileCoreTransitionSurfaces\(\) \{.*?^\}/m].to_s
check.call("settlement uses the exact two bounded delays", dashboard.include?("Object.freeze([350, 1200])"))
check.call("settlement performs read-only Core status", helper.include?('callSoul("core.status")'))
check.call("settlement cannot repeat Core activation", !helper.include?("core.activate") && !helper.include?("executeModelRuntime"))
check.call("settlement terminates after one complete observation", helper.include?("return true") && helper.include?("return false"))
check.call("both Core execution paths share settlement", dashboard.scan("await reconcileCoreTransitionSurfaces()").length == 2)
check.call("unsettled evidence remains visible", helper.include?("Core status settling"))

abort(errors.map { |error| "- #{error}" }.join("\n")) unless errors.empty?
puts "Core transition settlement A8 is candidate-ready for human review."
