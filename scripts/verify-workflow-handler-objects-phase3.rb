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

puts "workflow handler objects phase 3 verification:"

paths = [
  "lib/soul_core/app.rb",
  "lib/soul_core/workflow_registry_execution.rb",
  "lib/soul_core/workflow_handler_registry.rb",
  "lib/soul_core/workflows/base_handler.rb",
  "lib/soul_core/workflows/youtube_play_handler.rb"
]

paths.each do |path|
  ok = File.exist?(path) && system("ruby", "-c", path, out: File::NULL, err: File::NULL)
  puts "- #{path} syntax: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

app = File.read("lib/soul_core/app.rb")
exec = File.read("lib/soul_core/workflow_registry_execution.rb")
handler_registry = File.read("lib/soul_core/workflow_handler_registry.rb")

checks = {
  "app loads handler registry" => app.include?('require_relative "workflow_handler_registry"'),
  "execution requires handler registry" => exec.include?('require_relative "workflow_handler_registry"'),
  "execution dispatches handlers" => exec.include?("handler_registry.handler_for(intent).run"),
  "youtube handler registered" => handler_registry.include?('register("youtube.play"'),
  "handler registry is read-only inspectable" => handler_registry.include?("def to_h")
}

checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

stdout, stderr, status = run_cmd({}, "ruby", "-Ilib", "-e", <<~'RUBY')
  require "json"
  require "soul_core/workflow_handler_registry"
  puts JSON.pretty_generate(SoulCore::WorkflowHandlerRegistry.new.to_h)
RUBY

json = JSON.parse(stdout) rescue nil
handler_json_ok =
  status.success? &&
  json &&
  json["handler_count"].to_i >= 1 &&
  json.fetch("handlers", []).any? { |handler| handler["intent"] == "youtube.play" && handler["registered_workflow"] == true } &&
  json.dig("verification", "read_only") == true
puts "- handler registry JSON: #{handler_json_ok ? 'ok' : 'missing'}"
errors << "handler registry JSON failed: #{stderr} #{stdout}" unless handler_json_ok

stdout, stderr, status = run_cmd({}, "ruby", "-Ilib", "-e", <<~'RUBY')
  require "json"
  require "soul_core/workflow_runner"
  require "soul_core/workflow_registry"
  require "soul_core/workflow_handler_registry"
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
puts "- unregistered workflows still blocked: #{blocked_ok ? 'ok' : 'missing'}"
errors << "unregistered workflow block failed: #{stderr} #{stdout}" unless blocked_ok

fake_dir = Dir.mktmpdir("soul-handler-phase3-")
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
youtube_ok =
  status.success? &&
  stdout.include?("Intent: youtube.play") &&
  stdout.include?("I found this YouTube result") &&
  stdout.include?("respond \"yes\"")
puts "- youtube.play handler stages confirmation: #{youtube_ok ? 'ok' : 'missing'}"
errors << "youtube.play did not stage confirmation through handler: #{stderr} #{stdout}" unless youtube_ok

session_path = Dir.glob("Soul/workflows/sessions/*youtube.play.json").sort.last
session = session_path && JSON.parse(File.read(session_path)) rescue nil
handler_state_ok =
  session &&
  session.dig("handler_execution", "handler").to_s.include?("YouTubePlayHandler") &&
  session.dig("registry_execution", "registered") == true
puts "- session records handler and registry execution: #{handler_state_ok ? 'ok' : 'missing'}"
errors << "session missing handler/registry execution metadata" unless handler_state_ok

stdout, stderr, status = run_cmd(env, "ruby", "bin/soul", "respond", "cancel")
cancel_ok = status.success? && stdout.include?("cancelled")
puts "- response path still works: #{cancel_ok ? 'ok' : 'missing'}"
errors << "respond cancel failed: #{stderr} #{stdout}" unless cancel_ok

Dir.glob("Soul/workflows/sessions/*youtube.play.json").each do |path|
  begin
    data = JSON.parse(File.read(path))
    File.delete(path) if data["workflow"] == "youtube.play"
  rescue StandardError
    nil
  end
end

FileUtils.rm_rf(fake_dir)

docs_ok = File.exist?("docs/workflows/HANDLER_OBJECTS_PHASE3.md") &&
          File.read("docs/workflows/HANDLER_OBJECTS_PHASE3.md").include?("WorkflowHandlerRegistry")
puts "- handler objects docs exist: #{docs_ok ? 'ok' : 'missing'}"
errors << "handler objects docs missing" unless docs_ok

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
