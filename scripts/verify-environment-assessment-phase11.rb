#!/usr/bin/env ruby
# frozen_string_literal: true
require "json"
require "open3"
errors=[]
def run_cmd(*cmd); Open3.capture3(*cmd); end
puts "environment assessment phase 11 verification:"
paths=%w[lib/soul_core/app.rb lib/soul_core/environment_assessor.rb lib/soul_core/package_manager_assessor.rb lib/soul_core/runtime_assessor.rb lib/soul_core/soul_project_assessor.rb]
paths.each do |p|
  ok=File.exist?(p)&&system("ruby","-c",p,out:File::NULL,err:File::NULL)
  puts "- #{p} syntax: #{ok ? 'ok':'missing'}"
  errors << "#{p} invalid" unless ok
end
app=File.read("lib/soul_core/app.rb")
{"app requires environment assessor"=>app.include?('require_relative "environment_assessor"'),"app exposes assess command"=>app.include?('when "assess"'),"app exposes assess environment"=>app.include?('when "environment"'),"app supports updates"=>app.include?('--updates')}.each{|n,ok| puts "- #{n}: #{ok ? 'ok':'missing'}"; errors << "#{n} missing" unless ok}
out,err,st=run_cmd("ruby","bin/soul","assess","environment")
ok=st.success?&&out.include?("Soul Environment Assessment")&&out.include?("Package Managers")&&out.include?("Runtimes")&&out.include?("Soul Project")
puts "- text assessment: #{ok ? 'ok':'missing'}"; errors << "text failed: #{err} #{out}" unless ok
out,err,st=run_cmd("ruby","bin/soul","assess","environment","--json")
j=JSON.parse(out) rescue nil
ok=st.success?&&j&&j["assessment"]=="environment"&&j["read_only"]==true&&j.dig("verification","no_updates_applied")==true&&j.dig("package_managers","managers").is_a?(Hash)&&j.dig("runtimes","runtimes").is_a?(Hash)
puts "- JSON assessment: #{ok ? 'ok':'missing'}"; errors << "json failed: #{err} #{out}" unless ok
out,err,st=run_cmd("ruby","bin/soul","assess","environment","--updates","--json")
j=JSON.parse(out) rescue nil
ok=st.success?&&j&&j["update_checks_requested"]==true&&j.dig("verification","no_packages_removed")==true
puts "- update-capable read-only assessment: #{ok ? 'ok':'missing'}"; errors << "updates failed: #{err} #{out}" unless ok
ok=File.exist?("docs/assessments/ENVIRONMENT_ASSESSMENT_PHASE11.md")&&File.read("docs/assessments/ENVIRONMENT_ASSESSMENT_PHASE11.md").include?("read-only")
puts "- phase 11 docs: #{ok ? 'ok':'missing'}"; errors << "docs missing" unless ok
if errors.empty?
  puts "Verification complete."; exit 0
else
  warn "Verification failed:"; errors.each{|e| warn "- #{e}"}; exit 1
end
