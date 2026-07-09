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

puts "workflow runtime contract enforcement phase 10 verification:"

paths = [
  "lib/soul_core/app.rb",
  "lib/soul_core/workflow_contract_validator.rb",
  "lib/soul_core/workflow_handler_registry.rb",
  "lib/soul_core/workflows/youtube_play_handler.rb"
]

paths.each do |path|
  ok = File.exist?(path) && system("ruby", "-c", path, out: File::NULL, err: File::NULL)
  puts "- #{path} syntax: #{ok ? 'ok' : 'missing'}"
  errors << "#{path} missing or invalid" unless ok
end

app = File.read("lib/soul_core/app.rb")
validator = File.read("lib/soul_core/workflow_contract_validator.rb")

checks = {
  "app requires validator" => app.include?('require_relative "workflow_contract_validator"'),
  "app validates contracts on initialize" => app.include?("validate_workflow_contracts!"),
  "app exposes doctor command" => app.include?('when "doctor"'),
  "validator has bang validation" => validator.include?("def validate_registry!"),
  "validator has health report" => validator.include?("def health_report")
}

checks.each do |name, ok|
  puts "- #{name}: #{ok ? 'ok' : 'missing'}"
  errors << "#{name} missing" unless ok
end

stdout, stderr, status = run_cmd({}, "ruby", "bin/soul", "doctor")
doctor_ok = status.success? && stdout.include?("Soul Workflow Contract Health") && stdout.include?("[OK] youtube.play") && stdout.include?("Summary:")
puts "- doctor command: #{doctor_ok ? 'ok' : 'missing'}"
errors << "doctor command failed: #{stderr} #{stdout}" unless doctor_ok

stdout, stderr, status = run_cmd({}, "ruby", "bin/soul", "doctor", "--json")
doctor_json = JSON.parse(stdout) rescue nil
doctor_json_ok = status.success? && doctor_json && doctor_json["valid"] == true && doctor_json.dig("summary", "handlers_checked").to_i >= 1
puts "- doctor JSON: #{doctor_json_ok ? 'ok' : 'missing'}"
errors << "doctor JSON failed: #{stderr} #{stdout}" unless doctor_json_ok

stdout, stderr, status = run_cmd({}, "ruby", "bin/soul", "intent", "play Cocaine Blues Johnny Cash on YouTube")
intent_json = JSON.parse(stdout) rescue nil
intent_ok = status.success? && intent_json && intent_json["intent"] == "youtube.play" && intent_json["source"] == "workflow_handler"
puts "- normal CLI still works after startup validation: #{intent_ok ? 'ok' : 'missing'}"
errors << "intent failed after startup validation: #{stderr} #{stdout}" unless intent_ok

fake_dir = Dir.mktmpdir("soul-phase10-runtime-")
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
do_ok = status.success? && stdout.include?("Intent: youtube.play") && stdout.include?("respond \"yes\"")
puts "- workflow run still works: #{do_ok ? 'ok' : 'missing'}"
errors << "workflow run failed: #{stderr} #{stdout}" unless do_ok

stdout, stderr, status = run_cmd(env, "ruby", "bin/soul", "respond", "yes")
captured = File.exist?(capture_file) ? File.read(capture_file).strip : ""
respond_ok = status.success? && stdout.include?("YouTube workflow complete") && captured == "https://www.youtube.com/watch?v=fJ9rUzIMcZQ"
puts "- workflow respond still works: #{respond_ok ? 'ok' : 'missing'}"
errors << "workflow respond failed: #{stderr} #{stdout} captured=#{captured.inspect}" unless respond_ok

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

docs_ok = File.exist?("docs/workflows/RUNTIME_CONTRACT_ENFORCEMENT_PHASE10.md") && File.read("docs/workflows/RUNTIME_CONTRACT_ENFORCEMENT_PHASE10.md").include?("runtime contract enforcement")
puts "- phase 10 docs: #{docs_ok ? 'ok' : 'missing'}"
errors << "phase 10 docs missing" unless docs_ok

if errors.empty?
  puts "Verification complete."
  exit 0
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
