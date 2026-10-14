#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

SOURCE = File.expand_path("download-amd-reviewer-m3b.rb", __dir__)
FIXTURE_DATA = { "qwen35" => "synthetic-qwen35-model-bytes\n", "phi4" => "synthetic-phi4-model-bytes\n" }.freeze
ASSETS = {
  "qwen35" => { "repo" => "bartowski/Qwen_Qwen3.5-9B-GGUF", "revision" => "a" * 40,
    "file" => "fixture-qwen35.gguf", "size" => FIXTURE_DATA.fetch("qwen35").bytesize,
    "sha256" => Digest::SHA256.hexdigest(FIXTURE_DATA.fetch("qwen35")) },
  "phi4" => { "repo" => "microsoft/phi-4-gguf", "revision" => "b" * 40,
    "file" => "fixture-phi4.gguf", "size" => FIXTURE_DATA.fetch("phi4").bytesize,
    "sha256" => Digest::SHA256.hexdigest(FIXTURE_DATA.fetch("phi4")) }
}.freeze

checks = 0
failures = []
check = lambda do |label, condition|
  checks += 1
  puts "- #{label}: #{condition ? 'ok' : 'FAIL'}"
  failures << label unless condition
end

def fixture_run(mode:, existing: {}, lock: false, race_bytes: "race-winner\n")
  Dir.mktmpdir("amd-reviewer-download-m3b-") do |temporary|
    root = File.join(temporary, "models")
    target = File.join(root, "amd-reviewer-m3b")
    support = File.join(temporary, "scripts", "support")
    FileUtils.mkdir_p([target, support], mode: 0o700)
    FIXTURE_DATA.each { |name, data| File.binwrite(File.join(temporary, "#{name}.bin"), data) }
    File.binwrite(File.join(temporary, "race.bin"), race_bytes)
    File.write(File.join(support, "amd_reviewer_assets_m3b.json"), JSON.generate(ASSETS))
    source = File.read(SOURCE)
    source = source.sub('root = "/home/bhones/ai_models"', "root = #{root.dump}")
    raise "source root substitution failed" if source.include?('root = "/home/bhones/ai_models"')
    fake_kernel = <<~RUBY
      module Kernel
        def system(*arguments)
          raise "unexpected system invocation" unless arguments.first == "curl"
          fixture_dir = ENV.fetch("M3B_FIXTURE_DIR")
          output = arguments.fetch(arguments.index("--output") + 1)
          name = File.basename(output).delete_suffix(".gguf.part")
          fixture_name = name.include?("qwen35") ? "qwen35" : "phi4"
          File.open(File.join(fixture_dir, "curl-calls"), "ab") { |file| file.write("\#{fixture_name}\\n") }
          File.binwrite(output, File.binread(File.join(fixture_dir, "\#{fixture_name}.bin")))
          if ENV["M3B_FIXTURE_MODE"] == "race"
            File.binwrite(output.delete_suffix(".part"), File.binread(File.join(fixture_dir, "race.bin")))
          end
          true
        end
      end
    RUBY
    marker = "# frozen_string_literal: true\n"
    raise "frozen marker missing" unless source.include?(marker)
    source = source.sub(marker, marker + fake_kernel)
    script = File.join(temporary, "scripts", "download-amd-reviewer-m3b.rb")
    File.write(script, source, mode: "wb", perm: 0o600)
    existing.each do |name, content|
      asset = ASSETS.fetch(name)
      path = File.join(target, asset.fetch("file"))
      if content.is_a?(Hash) && content.fetch(:symlink)
        File.symlink(content.fetch(:symlink), path)
      else
        File.binwrite(path, content)
      end
    end
    lock_file = nil
    if lock
      lock_file = File.open(File.join(target, ".download.lock"), File::RDWR | File::CREAT, 0o600)
      raise "fixture could not acquire download lock" unless lock_file.flock(File::LOCK_EX | File::LOCK_NB)
    end
    environment = { "M3B_FIXTURE_DIR" => temporary, "M3B_FIXTURE_MODE" => mode }
    stdout, stderr, status = Open3.capture3(environment, RbConfig.ruby, script, "--approved-download")
    yield({ "temporary" => temporary, "target" => target, "stdout" => stdout,
      "stderr" => stderr, "status" => status, "lock_file" => lock_file })
    lock_file&.flock(File::LOCK_UN)
    lock_file&.close
  ensure
    if lock_file && !lock_file.closed?
      lock_file.flock(File::LOCK_UN)
      lock_file.close
    end
  end
end

puts "AMD reviewer M3b downloader deterministic safety verification (temporary fixtures only):"

completed = false
fixture_run(mode: "normal") do |run|
  paths_match = ASSETS.all? do |name, asset|
    File.binread(File.join(run.fetch("target"), asset.fetch("file"))) == FIXTURE_DATA.fetch(name) &&
      !File.exist?(File.join(run.fetch("target"), "#{asset.fetch('file')}.part"))
  end
  completed = run.fetch("status").success? && paths_match &&
    run.fetch("stdout").include?("VERIFIED qwen35") && run.fetch("stdout").include?("VERIFIED phi4") &&
    File.read(File.join(run.fetch("temporary"), "curl-calls")).lines.length == 2
end
check.call("fake downloads verify both fixture assets and publish without partial names", completed)

already_complete = false
fixture_run(mode: "normal", existing: FIXTURE_DATA) do |run|
  already_complete = run.fetch("status").success? &&
    run.fetch("stdout").include?("VERIFIED existing qwen35") && run.fetch("stdout").include?("VERIFIED existing phi4") &&
    !File.exist?(File.join(run.fetch("temporary"), "curl-calls"))
end
check.call("already-complete assets are verified without invoking curl", already_complete)

mismatch_refused = false
fixture_run(mode: "normal", existing: { "qwen35" => "wrong bytes" }) do |run|
  path = File.join(run.fetch("target"), ASSETS.fetch("qwen35").fetch("file"))
  mismatch_refused = !run.fetch("status").success? && run.fetch("stderr").include?("Existing asset mismatch") &&
    File.binread(path) == "wrong bytes" && !File.exist?(File.join(run.fetch("temporary"), "curl-calls"))
end
check.call("completed-asset digest mismatch refuses and preserves the existing file", mismatch_refused)

symlink_refused = false
fixture_run(mode: "normal", existing: { "qwen35" => { symlink: "missing-fixture-target" } }) do |run|
  path = File.join(run.fetch("target"), ASSETS.fetch("qwen35").fetch("file"))
  symlink_refused = !run.fetch("status").success? && run.fetch("stderr").include?("Unsafe existing file") &&
    File.symlink?(path) && File.readlink(path) == "missing-fixture-target" && !File.exist?(File.join(run.fetch("temporary"), "curl-calls"))
end
check.call("symlinked completed asset is refused without following it", symlink_refused)

lock_refused = false
fixture_run(mode: "normal", lock: true) do |run|
  lock_refused = !run.fetch("status").success? && run.fetch("stderr").include?("Another download owns this directory") &&
    !File.exist?(File.join(run.fetch("temporary"), "curl-calls"))
end
check.call("concurrent lock owner prevents work before any download call", lock_refused)

race_preserved = false
fixture_run(mode: "race") do |run|
  asset = ASSETS.fetch("qwen35")
  final_path = File.join(run.fetch("target"), asset.fetch("file"))
  partial_path = final_path + ".part"
  race_preserved = !run.fetch("status").success? && run.fetch("stderr").include?("Errno::EEXIST") &&
    File.binread(final_path) == "race-winner\n" && File.binread(partial_path) == FIXTURE_DATA.fetch("qwen35")
end
check.call("exclusive final link preserves a concurrently created target on EEXIST", race_preserved)

puts "#{checks - failures.length}/#{checks} checks passed"
exit(failures.empty? ? 0 : 1)
