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

def parse_json_from_intent(stdout)
  JSON.parse(stdout)
rescue JSON::ParserError
  nil
end

puts "youtube.play workflow verification:"

app_text = File.exist?("lib/soul_core/app.rb") ? File.read("lib/soul_core/app.rb") : ""
require_ok = app_text.include?('require_relative "youtube_play_workflow"')
puts "- app loads workflow patch: #{require_ok ? 'ok' : 'missing'}"
errors << "app does not load youtube_play_workflow" unless require_ok

file_ok = File.exist?("lib/soul_core/youtube_play_workflow.rb")
puts "- workflow patch file exists: #{file_ok ? 'ok' : 'missing'}"
errors << "workflow patch file missing" unless file_ok

stdout, stderr, status = run_cmd({}, "ruby", "bin/soul", "intent", "play Bohemian Rhapsody on YouTube")
intent = parse_json_from_intent(stdout)
intent_ok =
  status.success? &&
  intent &&
  intent["intent"] == "youtube.play" &&
  intent.dig("parameters", "query").to_s.downcase.include?("bohemian")
puts "- deterministic intent route: #{intent_ok ? 'ok' : 'missing'}"
errors << "intent route failed: #{stderr} #{stdout}" unless intent_ok

fake_dir = Dir.mktmpdir("soul-youtube-play-workflow-")
fake_launcher = File.join(fake_dir, "fake-launcher")
capture_file = File.join(fake_dir, "launcher-args.txt")
File.write(fake_launcher, "#!/usr/bin/env ruby\nFile.write(ENV.fetch('SOUL_YOUTUBE_CAPTURE'), ARGV.join(\"\\n\"))\nexit 0\n")
FileUtils.chmod("+x", fake_launcher)

env = {
  "SOUL_YOUTUBE_PLAY_DRY_RUN" => "1",
  "SOUL_YOUTUBE_LAUNCHER" => fake_launcher,
  "SOUL_YOUTUBE_CAPTURE" => capture_file
}

stdout, stderr, status = run_cmd(env, "ruby", "bin/soul", "do", "play Bohemian Rhapsody on YouTube")
plan_ok =
  status.success? &&
  stdout.include?("I found this YouTube result") &&
  stdout.include?("Queen") &&
  stdout.include?("respond \"yes\"")
puts "- do stages candidate confirmation: #{plan_ok ? 'ok' : 'missing'}"
errors << "do workflow did not stage confirmation: #{stderr} #{stdout}" unless plan_ok

stdout, stderr, status = run_cmd(env, "ruby", "bin/soul", "respond", "yes")
captured = File.exist?(capture_file) ? File.read(capture_file).strip : ""
respond_ok =
  status.success? &&
  stdout.include?("YouTube workflow complete") &&
  captured == "https://www.youtube.com/watch?v=fJ9rUzIMcZQ"
puts "- respond opens watch URL through fake launcher: #{respond_ok ? 'ok' : 'missing'}"
errors << "respond did not open expected URL: #{stderr} #{stdout} captured=#{captured.inspect}" unless respond_ok

FileUtils.rm_rf(fake_dir)

session_files = Dir.glob("Soul/workflows/sessions/*youtube.play.json")
session_ok = !session_files.empty?
puts "- workflow session written: #{session_ok ? 'ok' : 'missing'}"
errors << "youtube.play workflow session was not written" unless session_ok

session_files.each do |path|
  begin
    data = JSON.parse(File.read(path))
    File.delete(path) if data["workflow"] == "youtube.play"
  rescue StandardError
    nil
  end
end

Dir.glob("Soul/logs/tasks/*youtube.video_resolve.json").each { |path| File.delete(path) rescue nil }
Dir.glob("Soul/logs/tasks/*youtube.song_search.json").each { |path| File.delete(path) rescue nil }

docs_ok = File.exist?("docs/workflows/YOUTUBE_PLAY.md") && File.read("docs/workflows/YOUTUBE_PLAY.md").include?("youtube.play")
puts "- workflow docs exist: #{docs_ok ? 'ok' : 'missing'}"
errors << "workflow docs missing" unless docs_ok

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
