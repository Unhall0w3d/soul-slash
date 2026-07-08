#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "fileutils"
require "tmpdir"

errors = []

def run_cmd(env, *cmd)
  Open3.capture3(env, *cmd)
end

puts "workflow registry execution verification:"

app_path = "lib/soul_core/app.rb"
runtime_path = "lib/soul_core/workflow_registry_execution.rb"
app = File.exist?(app_path) ? File.read(app_path) : ""
runtime = File.exist?(runtime_path) ? File.read(runtime_path) : ""

checks = {
  "app syntax valid" => system("ruby", "-c", app_path, out: File::NULL, err: File::NULL),
  "runtime syntax valid" => system("ruby", "-c", runtime_path, out: File::NULL, err: File::NULL),
  "app loads workflow registry execution" => app.include?('require_relative "workflow_registry_execution"'),
  "runner patch present" => runtime.include?("WorkflowRegistryExecutionRunnerPatch"),
  "unregistered workflow block present" => runtime.include?("blocked_unregistered_workflow"),
  "registered metadata attaches to state" => runtime.include?('"registry_execution"')
}

checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

stdout, stderr, status = run_cmd({}, "ruby", "-Ilib", "-e", <<~'RUBY')
  require "json"
  require "soul_core/workflow_runner"
  require "soul_core/workflow_registry"
  require "soul_core/workflow_registry_execution"
  result = SoulCore::WorkflowRunner.new.run(
    intent: "totally.fake.workflow",
    parameters: {},
    original_text: "fake"
  )
  puts JSON.pretty_generate({
    ok: result[:ok],
    status: result.dig(:state, "status"),
    registered: result.dig(:state, "verification", "registered_workflow")
  })
RUBY

blocked = JSON.parse(stdout) rescue nil
blocked_ok =
  status.success? &&
  blocked &&
  blocked["ok"] == false &&
  blocked["status"] == "blocked_unregistered_workflow" &&
  blocked["registered"] == false
puts "- unregistered workflow blocked by registry: #{blocked_ok ? 'ok' : 'missing'}"
errors << "unregistered workflow was not blocked: #{stderr} #{stdout}" unless blocked_ok

fake_dir = Dir.mktmpdir("soul-registry-exec-")
fake_launcher = File.join(fake_dir, "fake-launcher")
capture_file = File.join(fake_dir, "launcher-args.txt")
File.write(fake_launcher, "#!/usr/bin/env ruby\nFile.write(ENV.fetch('SOUL_YOUTUBE_CAPTURE'), ARGV.join(\"\\n\"))\nexit 0\n")
FileUtils.chmod("+x", fake_launcher)

env = {
  "SOUL_YOUTUBE_PLAY_DRY_RUN" => "1",
  "SOUL_YOUTUBE_LAUNCHER" => fake_launcher,
  "SOUL_YOUTUBE_CAPTURE" => capture_file
}

stdout, stderr, status = run_cmd(env, "ruby", "bin/soul", "do", "play Folsom Prison Blues on YouTube")
youtube_plan_ok =
  status.success? &&
  stdout.include?("Intent: youtube.play") &&
  stdout.include?("I found this YouTube result") &&
  stdout.include?("respond \"yes\"")
puts "- registered youtube.play still stages confirmation: #{youtube_plan_ok ? 'ok' : 'missing'}"
errors << "youtube.play did not stage confirmation: #{stderr} #{stdout}" unless youtube_plan_ok

stdout, stderr, status = run_cmd(env, "ruby", "bin/soul", "respond", "cancel")
cancel_ok = status.success? && stdout.include?("cancelled")
puts "- registered workflow response path still works: #{cancel_ok ? 'ok' : 'missing'}"
errors << "workflow response path failed: #{stderr} #{stdout}" unless cancel_ok

FileUtils.rm_rf(fake_dir)

session_files = Dir.glob("Soul/workflows/sessions/*youtube.play.json")
session_files.each do |path|
  begin
    data = JSON.parse(File.read(path))
    File.delete(path) if data["workflow"] == "youtube.play"
  rescue StandardError
    nil
  end
end

stdout, stderr, status = run_cmd({}, "ruby", "bin/soul", "workflows", "--json")
json = JSON.parse(stdout) rescue nil
registry_ok =
  status.success? &&
  json &&
  json.fetch("workflows", []).any? { |workflow| workflow["intent"] == "youtube.play" } &&
  json.dig("verification", "read_only") == true
puts "- registry JSON still works: #{registry_ok ? 'ok' : 'missing'}"
errors << "registry JSON failed: #{stderr} #{stdout}" unless registry_ok

docs_ok = File.exist?("docs/workflows/REGISTRY_EXECUTION.md") &&
          File.read("docs/workflows/REGISTRY_EXECUTION.md").include?("blocked_unregistered_workflow")
puts "- registry execution docs exist: #{docs_ok ? 'ok' : 'missing'}"
errors << "registry execution docs missing" unless docs_ok

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
