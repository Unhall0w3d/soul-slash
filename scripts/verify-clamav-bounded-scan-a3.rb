#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"

ROOT = File.expand_path("..", __dir__)
SCRIPT = File.join(ROOT, "scripts", "soul-clamav-scan")
failures = []

check = lambda do |description, condition|
  puts "- #{description}: #{condition ? 'ok' : 'FAIL'}"
  failures << description unless condition
end

run = lambda do |home:, state:, fake:, mode:, path: nil, timeout: nil|
  env = {
    "SOUL_CLAMAV_TEST_MODE" => "1",
    "SOUL_CLAMAV_HOME" => home,
    "SOUL_CLAMAV_STATE_ROOT" => state,
    "SOUL_CLAMSCAN_BIN" => fake,
    "FAKE_CLAM_MODE" => mode
  }
  env["SOUL_CLAMAV_TIMEOUT_SECONDS"] = timeout.to_s if timeout
  argv = [SCRIPT, "--target", "downloads"]
  argv += ["--path", path] if path
  stdout, stderr, status = Open3.capture3(env, *argv)
  [JSON.parse(stdout), stderr, status.exitstatus]
end

puts "ClamAV bounded scan A3 verification:"
Dir.mktmpdir("soul-clamav-a3-") do |root|
  home = File.join(root, "home")
  downloads = File.join(home, "Downloads")
  state = File.join(root, "state")
  FileUtils.mkdir_p(downloads)
  File.write(File.join(downloads, "sample.txt"), "bounded fixture\n")
  fake = File.join(root, "clamscan")
  File.write(fake, <<~'RUBY')
    #!/usr/bin/env ruby
    mode = ENV.fetch("FAKE_CLAM_MODE", "clean")
    sleep 3 if mode == "sleep"
    infected = mode == "infected" ? 1 : 0
    puts "Known viruses: 9000000"
    puts "Scanned directories: 1"
    puts "Scanned files: 1"
    puts "Infected files: #{infected}"
    puts "Data scanned: 0.01 MB"
    puts "Time: 0.010 sec"
    exit(mode == "infected" ? 1 : (mode == "error" ? 2 : 0))
  RUBY
  FileUtils.chmod(0o700, fake)

  clean, clean_stderr, clean_exit = run.call(home: home, state: state, fake: fake, mode: "clean")
  check.call("clean scan terminates complete with no mutation", clean_exit.zero? && clean["lifecycle_state"] == "complete" && clean["outcome"] == "clean" && clean["source_files_mutated"] == false && clean_stderr.empty?)
  check.call("private receipt and log are owner-only", File.stat(clean.fetch("receipt_path")).mode & 0o777 == 0o600 && File.stat(clean.fetch("log_path")).mode & 0o777 == 0o600)

  detected, = run.call(home: home, state: state, fake: fake, mode: "infected")
  check.call("detection blocks for human review without deletion", detected["lifecycle_state"] == "blocked_for_human_review" && detected["outcome"] == "detections" && detected["automatic_delete"] == false && File.exist?(File.join(downloads, "sample.txt")))

  failed, = run.call(home: home, state: state, fake: fake, mode: "error")
  check.call("scanner error terminates failed", failed["lifecycle_state"] == "failed" && failed["outcome"] == "scanner_error")

  timed, = run.call(home: home, state: state, fake: fake, mode: "sleep", timeout: 1)
  check.call("operation timeout terminates failed", timed["lifecycle_state"] == "failed" && timed["outcome"] == "timeout")

  outside = File.join(root, "outside.txt")
  File.write(outside, "outside\n")
  rejected, = run.call(home: home, state: state, fake: fake, mode: "clean", path: outside)
  check.call("path outside the approved ingress root is rejected", rejected["lifecycle_state"] == "failed" && rejected["message"].include?("escapes"))
end

abort("ClamAV bounded scan A3 verification failed: #{failures.join(', ')}") unless failures.empty?
puts "ClamAV bounded scan A3 verification passed."
