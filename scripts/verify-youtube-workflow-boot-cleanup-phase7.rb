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

puts "youtube workflow boot cleanup phase 7 verification:"

paths = [
  "lib/soul_core/app.rb",
  "lib/soul_core/workflow_intent_handler_dispatch.rb",
  "lib/soul_core/workflows/youtube_play_handler.rb",
  "lib/soul_core/workflow_handler_registry.rb",
  "lib/soul_core/workflow_session_handler_dispatch.rb"
]

paths.each do |path|
  ok = File.exist?(path) && system("ruby", "-c", path, out: File::NULL, err: File::NULL)
  puts "- #{path} syntax: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

app = File.exist?("lib/soul_core/app.rb") ? File.read("lib/soul_core/app.rb") : ""
checks = {
  "app loads workflow_intent_handler_dispatch directly" => app.include?('require_relative "workflow_intent_handler_dispatch"'),
  "app does not load youtube_play_workflow" => !app.include?('require_relative "youtube_play_workflow"'),
  "retired youtube_play_workflow file removed" => !File.exist?("lib/soul_core/youtube_play_workflow.rb"),
  "handler still owns intent matching" => File.read("lib/soul_core/workflows/youtube_play_handler.rb").include?("def match_intent"),
  "handler registry still loads session dispatch" => File.read("lib/soul_core/workflow_handler_registry.rb").include?('require_relative "workflow_session_handler_dispatch"')
}

checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

stdout, stderr, status = run_cmd({}, "ruby", "-Ilib", "-e", <<~'RUBY')
  require "json"
  require "soul_core/app"
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
puts "- app boot routes YouTube intent through handler: #{direct_ok ? 'ok' : 'missing'}"
errors << "app boot handler intent failed: #{stderr} #{stdout}" unless direct_ok

stdout, stderr, status = run_cmd({}, "ruby", "bin/soul", "intent", "play Cocaine Blues Johnny Cash on YouTube")
intent_json = JSON.parse(stdout) rescue nil
intent_ok =
  status.success? &&
  intent_json &&
  intent_json["intent"] == "youtube.play" &&
  intent_json["source"] == "workflow_handler" &&
  intent_json.dig("parameters", "query").to_s.downcase.include?("cocaine blues")
puts "- bin/soul intent still routes through handler: #{intent_ok ? 'ok' : 'missing'}"
errors << "bin/soul intent failed: #{stderr} #{stdout}" unless intent_ok

fake_dir = Dir.mktmpdir("soul-phase7-youtube-")
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
errors << "youtube do failed after phase 7: #{stderr} #{stdout}" unless do_ok

session_path = Dir.glob("Soul/workflows/sessions/*youtube.play.json").sort.last
session = session_path && JSON.parse(File.read(session_path)) rescue nil
session_ok =
  session &&
  session.dig("handler_execution", "delegated_to_existing_workflow_method") == false &&
  session.dig("registry_execution", "registered") == true &&
  session["status"] == "waiting_for_youtube_open_confirmation"
puts "- staged session still uses handler path: #{session_ok ? 'ok' : 'missing'}"
errors << "staged session did not use handler/registry path" unless session_ok

stdout, stderr, status = run_cmd(env, "ruby", "bin/soul", "respond", "yes")
captured = File.exist?(capture_file) ? File.read(capture_file).strip : ""
respond_ok =
  status.success? &&
  stdout.include?("YouTube workflow complete") &&
  captured == "https://www.youtube.com/watch?v=fJ9rUzIMcZQ"
puts "- youtube handler response still opens URL: #{respond_ok ? 'ok' : 'missing'}"
errors << "youtube respond failed after phase 7: #{stderr} #{stdout} captured=#{captured.inspect}" unless respond_ok

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

docs_ok = File.exist?("docs/workflows/YOUTUBE_BOOT_CLEANUP_PHASE7.md") &&
          File.read("docs/workflows/YOUTUBE_BOOT_CLEANUP_PHASE7.md").include?("compatibility file retired")
puts "- phase 7 docs exist: #{docs_ok ? 'ok' : 'missing'}"
errors << "phase 7 docs missing" unless docs_ok

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
