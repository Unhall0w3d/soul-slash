#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"

errors = []

def run_cmd(*cmd)
  Open3.capture3({}, *cmd)
end

puts "CLI help formatting verification:"

app_path = "lib/soul_core/app.rb"
app = File.exist?(app_path) ? File.read(app_path) : ""

checks = {
  "app syntax valid" => system("ruby", "-c", app_path, out: File::NULL, err: File::NULL),
  "workflow status help line" => app.include?('ruby bin/soul workflow status latest'),
  "workflow list active help line" => app.include?('ruby bin/soul workflow list --active'),
  "clear-complete confirmation help line" => app.include?('ruby bin/soul workflow clear-complete --confirm CLEAR_COMPLETE'),
  "YouTube play example" => app.include?('ruby bin/soul do "play Folsom Prison Blues on YouTube"'),
  "flattened workflow line removed" => !app.include?("workflow show latest ruby bin/soul workflow status latest")
}

checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

stdout, stderr, status = run_cmd("ruby", "bin/soul", "help")
help_ok =
  status.success? &&
  stdout.include?("ruby bin/soul workflow status latest") &&
  stdout.include?("ruby bin/soul workflow clear-complete --confirm CLEAR_COMPLETE") &&
  stdout.include?('ruby bin/soul do "play Folsom Prison Blues on YouTube"') &&
  !stdout.include?("workflow show latest ruby bin/soul workflow status latest")

puts "- runtime help output formatted: #{help_ok ? 'ok' : 'missing'}"
errors << "runtime help output was not formatted correctly: #{stderr} #{stdout}" unless help_ok

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
