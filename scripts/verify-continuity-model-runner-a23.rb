#!/usr/bin/env ruby
# frozen_string_literal: true
require "tmpdir"
require_relative "compare-continuity-models-a23"
Runner = ContinuityModelComparisonA23
checks = 0
check = ->(name, &block) { raise "FAIL #{name}" unless block.call; checks += 1; puts "PASS #{name}" }
rejects = lambda do |kind, &block|
  begin
    block.call
    false
  rescue kind
    true
  end
end
runner = Runner.new
check.call("fixed candidate loopback and NVIDIA placement") do
  args = runner.candidate_args("qwen35", "/synthetic.gguf")
  args.each_cons(2).include?(["--host", "127.0.0.1"]) && args.each_cons(2).include?(["--port", "8095"]) && args.include?("--cpu-moe") &&
    !runner.candidate_args("ministral14", "/synthetic.gguf").include?("--cpu-moe")
end
check.call("unapproved HTTP route refuses before IO") { rejects.call(RuntimeError) { runner.http("/unapproved") } }
check.call("samplers and output contracts adapted explicitly") do
  Runner::SETTINGS.values.all? { |settings| settings["n_predict"] == 768 && settings["grammar"] == Runner::GRAMMAR && settings["stream"] && !settings["cache_prompt"] } &&
    Runner::SETTINGS["qwen35"]["presence_penalty"] == 1.5 && Runner::SETTINGS["ministral14"]["temperature"] < 0.1
end
Dir.mktmpdir("continuity-a23-verify-") do |dir|
  file = File.join(dir, "asset")
  File.write(file, "fixture")
  check.call("exact asset accepted") { runner.verify_asset(file, 7, Digest::SHA256.hexdigest("fixture")).nil? }
  check.call("altered bytes rejected") { rejects.call(RuntimeError) { runner.verify_asset(file, 7, "0" * 64) } }
  File.symlink(file, File.join(dir, "link"))
  check.call("asset symlink rejected") { rejects.call(RuntimeError) { runner.verify_asset(File.join(dir, "link"), 7, Digest::SHA256.hexdigest("fixture")) } }
end
sample = { "gpu" => "NVIDIA GeForce GTX 1070, 6000, 2000, 50, 0", "memory_kib" => { "MemAvailable" => 8 * 1024 * 1024 } }
check.call("normal resources accepted") { runner.validate_resources(sample).nil? }
check.call("thermal failure exits model catch boundary") do
  !Runner::ResourceStop.ancestors.include?(StandardError) && rejects.call(Runner::ResourceStop) { runner.validate_resources(sample.merge("gpu" => "GPU, 6000, 2000, 80, 0")) }
end
check.call("RAM floor enforced") { rejects.call(Runner::ResourceStop) { runner.validate_resources(sample.merge("memory_kib" => { "MemAvailable" => 1 })) } }
check.call("suite deadline is not swallowed by candidate error handling") { !Runner::SuiteDeadline.ancestors.include?(StandardError) }
fake = Class.new(Runner) do
  attr_reader :restored
  def restore = @restored = true
end
[nil, RuntimeError, Interrupt, Runner::SuiteDeadline, Runner::ResourceStop].each do |exception|
  trial = fake.new
  begin
    trial.with_restoration { raise exception, "synthetic" if exception }
  rescue StandardError, Interrupt, Runner::SuiteDeadline, Runner::ResourceStop
    nil
  end
  check.call("restoration runs after #{exception || 'success'}") { trial.restored }
end
pid = Process.spawn(RbConfig.ruby, "-e", "sleep 30", pgroup: true)
runner.instance_variable_set(:@child, pid)
runner.stop_candidate
check.call("owned child terminated and reaped before identity cleared") do
  runner.instance_variable_get(:@child).nil? && rejects.call(Errno::ECHILD) { Process.waitpid(pid, Process::WNOHANG) }
end
oversized = Class.new(Runner) do
  def check_idle(_) = {}
  def http(path, *args, **kwargs)
    return { "prompt" => "synthetic" } if path == "/apply-template"
    return { "tokens" => Array.new(3073, 1) } if path == "/tokenize"
    raise "Unexpected inference"
  end
end
check.call("oversized model-specific tokenizer result rejected before generation") do
  begin
    oversized.new.generate("qwen35", "synthetic", [], 0)
    false
  rescue RuntimeError => error
    error.message == "Input token bound"
  end
end
puts "PASS #{checks} bounded runner checks; no model/network/service operations"
