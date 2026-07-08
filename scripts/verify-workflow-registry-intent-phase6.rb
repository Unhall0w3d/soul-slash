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

puts "workflow registry intent phase 6 verification:"

paths = [
  "lib/soul_core/workflows/base_handler.rb",
  "lib/soul_core/workflows/youtube_play_handler.rb",
  "lib/soul_core/workflow_handler_registry.rb",
  "lib/soul_core/workflow_intent_handler_dispatch.rb",
  "lib/soul_core/youtube_play_workflow.rb"
]

paths.each do |path|
  ok = File.exist?(path) && system("ruby", "-c", path, out: File::NULL, err: File::NULL)
  puts "- #{path} syntax: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

base = File.read("lib/soul_core/workflows/base_handler.rb")
handler = File.read("lib/soul_core/workflows/youtube_play_handler.rb")
registry = File.read("lib/soul_core/workflow_handler_registry.rb")
dispatch = File.read("lib/soul_core/workflow_intent_handler_dispatch.rb")
glue = File.read("lib/soul_core/youtube_play_workflow.rb")

checks = {
  "base handler exposes match_intent" => base.include?("def match_intent"),
  "youtube handler owns intent matching" => handler.include?("def match_intent"),
  "youtube handler owns query extraction" => handler.include?("def extract_youtube_query"),
  "handler registry can match intent" => registry.include?("def match_intent"),
  "intent dispatch prepends IntentRouter" => dispatch.include?("IntentRouter.prepend"),
  "youtube glue only requires dispatch" => glue.include?('require_relative "workflow_intent_handler_dispatch"'),
  "youtube glue has no intent patch module" => !glue.include?("YouTubePlayIntentPatch"),
  "youtube glue has no route method" => !glue.include?("def route"),
  "youtube glue has no workflow runner patch" => !glue.include?("WorkflowRunner"),
  "youtube glue has no workflow session patch" => !glue.include?("WorkflowSession"),
  "youtube glue has no response renderer patch" => !glue.include?("ResponseRenderer")
}

checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

stdout, stderr, status = run_cmd({}, "ruby", "-Ilib", "-e", <<~'RUBY')
  require "json"
  require "soul_core/intent_router"
  require "soul_core/workflow_intent_handler_dispatch"
  result = SoulCore::IntentRouter.new.route("play Cocaine Blues Johnny Cash on YouTube")
  puts JSON.pretty_generate({
    ok: result.ok,
    intent: result.intent,
    parameters: result.parameters,
    source: result.source
  })
RUBY

direct = JSON.parse(stdout) rescue nil
direct_ok =
  status.success? &&
  direct &&
  direct["intent"] == "youtube.play" &&
  direct["source"] == "workflow_handler" &&
  direct.dig("parameters", "query").to_s.downcase.include?("cocaine blues")
puts "- direct intent router dispatch uses handler: #{direct_ok ? 'ok' : 'missing'}"
errors << "direct handler intent dispatch failed: #{stderr} #{stdout}" unless direct_ok

stdout, stderr, status = run_cmd({}, "ruby", "bin/soul", "intent", "play Cocaine Blues Johnny Cash on YouTube")
intent_json = JSON.parse(stdout) rescue nil
intent_ok =
  status.success? &&
  intent_json &&
  intent_json["intent"] == "youtube.play" &&
  intent_json["source"] == "workflow_handler" &&
  intent_json.dig("parameters", "query").to_s.downcase.include?("cocaine blues")
puts "- bin/soul intent routes through handler: #{intent_ok ? 'ok' : 'missing'}"
errors << "bin/soul intent failed through handler: #{stderr} #{stdout}" unless intent_ok

stdout, stderr, status = run_cmd({}, "ruby", "-Ilib", "-e", <<~'RUBY')
  require "json"
  require "soul_core/workflow_handler_registry"
  puts JSON.pretty_generate(SoulCore::WorkflowHandlerRegistry.new.to_h)
RUBY

registry_json = JSON.parse(stdout) rescue nil
registry_ok =
  status.success? &&
  registry_json &&
  registry_json.dig("verification", "handler_owned_intent_matching") == true &&
  registry_json.fetch("handlers", []).any? { |item| item["intent"] == "youtube.play" && item["handler_owned_intent_matching"] == true }
puts "- handler registry reports handler-owned intent matching: #{registry_ok ? 'ok' : 'missing'}"
errors << "handler registry intent metadata failed: #{stderr} #{stdout}" unless registry_ok

fake_dir = Dir.mktmpdir("soul-phase6-youtube-")
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
do_ok =
  status.success? &&
  stdout.include?("Intent: youtube.play") &&
  stdout.include?("I found this YouTube result") &&
  stdout.include?("respond \"yes\"")
puts "- youtube workflow still stages confirmation: #{do_ok ? 'ok' : 'missing'}"
errors << "youtube do failed after phase 6: #{stderr} #{stdout}" unless do_ok

session_path = Dir.glob("Soul/workflows/sessions/*youtube.play.json").sort.last
session = session_path && JSON.parse(File.read(session_path)) rescue nil
session_ok =
  session &&
  session.dig("handler_execution", "delegated_to_existing_workflow_method") == false &&
  session.dig("registry_execution", "registered") == true &&
  session["status"] == "waiting_for_youtube_open_confirmation"
puts "- staged session uses handler path: #{session_ok ? 'ok' : 'missing'}"
errors << "staged session did not use handler/registry path" unless session_ok

stdout, stderr, status = run_cmd(env, "ruby", "bin/soul", "respond", "yes")
captured = File.exist?(capture_file) ? File.read(capture_file).strip : ""
respond_ok =
  status.success? &&
  stdout.include?("YouTube workflow complete") &&
  captured == "https://www.youtube.com/watch?v=fJ9rUzIMcZQ"
puts "- youtube handler response still opens URL: #{respond_ok ? 'ok' : 'missing'}"
errors << "youtube respond failed after phase 6: #{stderr} #{stdout} captured=#{captured.inspect}" unless respond_ok

Dir.glob("Soul/workflows/sessions/*youtube.play.json").each do |path|
  begin
    data = JSON.parse(File.read(path))
    File.delete(path) if data["workflow"] == "youtube.play"
  rescue StandardError
    nil
  end
end

Dir.glob("Soul/logs/tasks/*youtube.video_resolve.json").each { |path| File.delete(path) rescue nil }
Dir.glob("Soul/logs/tasks/*youtube.song_search.json").each { |path| File.delete(path) rescue nil }
FileUtils.rm_rf(fake_dir)

docs_ok = File.exist?("docs/workflows/REGISTRY_INTENT_PHASE6.md") &&
          File.read("docs/workflows/REGISTRY_INTENT_PHASE6.md").include?("handler-owned intent matching")
puts "- phase 6 docs exist: #{docs_ok ? 'ok' : 'missing'}"
errors << "phase 6 docs missing" unless docs_ok

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
