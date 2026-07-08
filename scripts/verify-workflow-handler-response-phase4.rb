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

puts "workflow handler response phase 4 verification:"

paths = [
  "lib/soul_core/workflows/base_handler.rb",
  "lib/soul_core/workflows/youtube_play_handler.rb",
  "lib/soul_core/workflow_handler_registry.rb",
  "lib/soul_core/workflow_session_handler_dispatch.rb"
]

paths.each do |path|
  ok = File.exist?(path) && system("ruby", "-c", path, out: File::NULL, err: File::NULL)
  puts "- #{path} syntax: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

base = File.read("lib/soul_core/workflows/base_handler.rb")
youtube = File.read("lib/soul_core/workflows/youtube_play_handler.rb")
registry = File.read("lib/soul_core/workflow_handler_registry.rb")
dispatch = File.read("lib/soul_core/workflow_session_handler_dispatch.rb")

checks = {
  "base handler has responds_to_status" => base.include?("def responds_to_status?"),
  "youtube handler implements respond" => youtube.include?("def respond(state:, text:)"),
  "youtube handler owns open confirmation" => youtube.include?("def handle_open_confirmation"),
  "youtube handler owns rendering" => youtube.include?("def render_candidate_confirmation"),
  "youtube handler no longer delegates run" => youtube.include?('"delegated_to_existing_workflow_method" => false'),
  "handler registry loads session dispatch" => registry.include?('require_relative "workflow_session_handler_dispatch"'),
  "session dispatch prepends WorkflowSession" => dispatch.include?("WorkflowSession.prepend")
}

checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

fake_dir = Dir.mktmpdir("soul-handler-response-phase4-")
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
puts "- youtube.play handler run stages confirmation: #{do_ok ? 'ok' : 'missing'}"
errors << "youtube.play do failed: #{stderr} #{stdout}" unless do_ok

session_path = Dir.glob("Soul/workflows/sessions/*youtube.play.json").sort.last
session = session_path && JSON.parse(File.read(session_path)) rescue nil
run_state_ok =
  session &&
  session.dig("handler_execution", "delegated_to_existing_workflow_method") == false &&
  session.dig("registry_execution", "registered") == true &&
  session["status"] == "waiting_for_youtube_open_confirmation"
puts "- run session has handler and registry metadata: #{run_state_ok ? 'ok' : 'missing'}"
errors << "run session missing expected phase 4 metadata" unless run_state_ok

stdout, stderr, status = run_cmd(env, "ruby", "bin/soul", "respond", "yes")
captured = File.exist?(capture_file) ? File.read(capture_file).strip : ""
respond_ok =
  status.success? &&
  stdout.include?("YouTube workflow complete") &&
  captured == "https://www.youtube.com/watch?v=fJ9rUzIMcZQ"
puts "- handler respond opens watch URL through fake launcher: #{respond_ok ? 'ok' : 'missing'}"
errors << "handler respond failed: #{stderr} #{stdout} captured=#{captured.inspect}" unless respond_ok

session = session_path && File.exist?(session_path) ? JSON.parse(File.read(session_path)) : nil
respond_state_ok =
  session &&
  session.dig("handler_response", "handler").to_s.include?("YouTubePlayHandler") &&
  session.dig("handler_response", "action") == "open_confirmation" &&
  session.dig("verification", "complete") == true
puts "- response session records handler_response metadata: #{respond_state_ok ? 'ok' : 'missing'}"
errors << "response session missing handler_response metadata" unless respond_state_ok

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

docs_ok = File.exist?("docs/workflows/HANDLER_RESPONSE_PHASE4.md") &&
          File.read("docs/workflows/HANDLER_RESPONSE_PHASE4.md").include?("handler_response")
puts "- phase 4 docs exist: #{docs_ok ? 'ok' : 'missing'}"
errors << "phase 4 docs missing" unless docs_ok

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
