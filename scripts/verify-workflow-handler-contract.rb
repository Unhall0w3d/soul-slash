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

def syntax_ok?(path)
  File.exist?(path) && system("ruby", "-c", path, out: File::NULL, err: File::NULL)
end

puts "workflow handler contract verification:"

paths = [
  "lib/soul_core/workflows/base_handler.rb",
  "lib/soul_core/workflows/youtube_play_handler.rb",
  "lib/soul_core/workflow_handler_registry.rb",
  "lib/soul_core/workflow_intent_handler_dispatch.rb",
  "lib/soul_core/workflow_session_handler_dispatch.rb",
  "lib/soul_core/workflow_registry_execution.rb"
]

paths.each do |path|
  ok = syntax_ok?(path)
  puts "- #{path} syntax: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

doc_paths = [
  "docs/workflows/HANDLER_CONTRACT.md",
  "docs/workflows/HANDLER_CONTRACT_CHECKLIST.md",
  "templates/workflows/handler_template.rb"
]

doc_paths.each do |path|
  ok = File.exist?(path)
  puts "- #{path} exists: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing" unless ok
end

if File.exist?("templates/workflows/handler_template.rb")
  ok = syntax_ok?("templates/workflows/handler_template.rb")
  puts "- handler template syntax: #{ok ? 'ok' : 'missing'}"
  errors << "handler template syntax invalid" unless ok
end

base = File.exist?("lib/soul_core/workflows/base_handler.rb") ? File.read("lib/soul_core/workflows/base_handler.rb") : ""
youtube = File.exist?("lib/soul_core/workflows/youtube_play_handler.rb") ? File.read("lib/soul_core/workflows/youtube_play_handler.rb") : ""
registry = File.exist?("lib/soul_core/workflow_handler_registry.rb") ? File.read("lib/soul_core/workflow_handler_registry.rb") : ""
contract = File.exist?("docs/workflows/HANDLER_CONTRACT.md") ? File.read("docs/workflows/HANDLER_CONTRACT.md") : ""

checks = {
  "base handler declares match_intent" => base.include?("def match_intent"),
  "base handler declares responds_to_status" => base.include?("def responds_to_status?"),
  "base handler declares run" => base.include?("def run(parameters:, original_text:)"),
  "base handler declares respond" => base.include?("def respond(state:, text:)"),
  "youtube handler owns match_intent" => youtube.include?("def match_intent(text, result_class:)"),
  "youtube handler owns run" => youtube.include?("def run(parameters:, original_text:)"),
  "youtube handler owns respond" => youtube.include?("def respond(state:, text:)"),
  "youtube handler records handler_execution" => youtube.include?("handler_execution"),
  "youtube handler records handler_response" => youtube.include?("handler_response"),
  "registry exposes handlers" => registry.include?("def handlers"),
  "registry exposes match_intent" => registry.include?("def match_intent"),
  "contract documents confirmation rule" => contract.include?("Confirmation rule"),
  "contract documents no green lights without gauges" => contract.include?("No green lights without gauges")
}

checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

stdout, stderr, status = run_cmd({}, "ruby", "-Ilib", "-e", <<~'RUBY')
  require "json"
  require "soul_core/workflow_handler_registry"
  registry = SoulCore::WorkflowHandlerRegistry.new
  handlers = registry.handlers.map do |handler|
    {
      "class" => handler.class.name,
      "intent" => handler.intent,
      "has_match_intent" => handler.respond_to?(:match_intent),
      "has_run" => handler.respond_to?(:run),
      "has_respond" => handler.respond_to?(:respond),
      "has_responds_to_status" => handler.respond_to?(:responds_to_status?)
    }
  end
  puts JSON.pretty_generate({ "handler_count" => handlers.length, "handlers" => handlers })
RUBY

handler_json = JSON.parse(stdout) rescue nil
handler_contract_ok =
  status.success? &&
  handler_json &&
  handler_json["handler_count"].to_i >= 1 &&
  handler_json.fetch("handlers", []).all? do |handler|
    handler["intent"].to_s.length.positive? &&
      handler["has_match_intent"] &&
      handler["has_run"] &&
      handler["has_respond"] &&
      handler["has_responds_to_status"]
  end
puts "- registered handlers expose contract methods: #{handler_contract_ok ? 'ok' : 'missing'}"
errors << "registered handler contract introspection failed: #{stderr} #{stdout}" unless handler_contract_ok

stdout, stderr, status = run_cmd({}, "ruby", "bin/soul", "intent", "play Cocaine Blues Johnny Cash on YouTube")
intent_json = JSON.parse(stdout) rescue nil
intent_ok =
  status.success? &&
  intent_json &&
  intent_json["intent"] == "youtube.play" &&
  intent_json["source"] == "workflow_handler" &&
  intent_json.dig("parameters", "query").to_s.downcase.include?("cocaine blues")
puts "- handler-owned intent still works: #{intent_ok ? 'ok' : 'missing'}"
errors << "handler-owned intent failed: #{stderr} #{stdout}" unless intent_ok

fake_dir = Dir.mktmpdir("soul-phase8-contract-")
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
puts "- handler-owned run still stages confirmation: #{do_ok ? 'ok' : 'missing'}"
errors << "handler-owned run failed: #{stderr} #{stdout}" unless do_ok

session_path = Dir.glob("Soul/workflows/sessions/*youtube.play.json").sort.last
session = session_path && JSON.parse(File.read(session_path)) rescue nil
session_ok =
  session &&
  session.dig("handler_execution", "delegated_to_existing_workflow_method") == false &&
  session.dig("registry_execution", "registered") == true &&
  session["status"] == "waiting_for_youtube_open_confirmation"
puts "- staged session records contract metadata: #{session_ok ? 'ok' : 'missing'}"
errors << "staged session missing contract metadata" unless session_ok

stdout, stderr, status = run_cmd(env, "ruby", "bin/soul", "respond", "yes")
captured = File.exist?(capture_file) ? File.read(capture_file).strip : ""
respond_ok =
  status.success? &&
  stdout.include?("YouTube workflow complete") &&
  captured == "https://www.youtube.com/watch?v=fJ9rUzIMcZQ"
puts "- handler-owned respond still works: #{respond_ok ? 'ok' : 'missing'}"
errors << "handler-owned respond failed: #{stderr} #{stdout} captured=#{captured.inspect}" unless respond_ok

session = session_path && File.exist?(session_path) ? JSON.parse(File.read(session_path)) : nil
respond_metadata_ok =
  session &&
  session.dig("handler_response", "handler").to_s.include?("YouTubePlayHandler") &&
  session.dig("handler_response", "action") == "open_confirmation" &&
  session.dig("verification", "complete") == true
puts "- response records contract metadata: #{respond_metadata_ok ? 'ok' : 'missing'}"
errors << "response missing contract metadata" unless respond_metadata_ok

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

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
