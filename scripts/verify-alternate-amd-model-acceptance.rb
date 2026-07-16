#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "socket"
require "tmpdir"
require_relative "../lib/soul_core/alternate_model_acceptance_harness"

errors = []

def check(label, condition, errors)
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

class SuccessfulFixtureHarness < SoulCore::AlternateModelAcceptanceHarness
  private

  def await_health! = true
  def await_idle! = true
  def health(_url) = { "ok" => true, "http_status" => 200 }
  def vram_sample(label) = { "label" => label, "status" => "not_collected" }
  def evaluate(_root) = { "checks" => { "synthetic_fixture" => true } }
end

class FailingFixtureHarness < SuccessfulFixtureHarness
  private

  def evaluate(_root)
    raise RuntimeError, "synthetic failure"
  end
end

class CanceledFixtureHarness < SuccessfulFixtureHarness
  private

  def evaluate(_root)
    raise Interrupt
  end
end

puts "Soul alternate AMD model acceptance verification:"

Dir.mktmpdir("soul-alternate-model-verifier-") do |root|
  server = File.join(root, "fake-server")
  model = File.join(root, "fake-model.gguf")
  File.write(server, "#!/usr/bin/env ruby\nsleep 30\n")
  File.chmod(0o700, server)
  File.write(model, "synthetic model fixture\n")
  server_sha = Digest::SHA256.file(server).hexdigest
  model_sha = Digest::SHA256.file(model).hexdigest
  args = {
    server_path: server,
    model_path: model,
    expected_server_sha256: server_sha,
    expected_model_sha256: model_sha
  }

  harness = SuccessfulFixtureHarness.new(**args)
  check("valid digests and free fixed port pass validation", harness.validate_inputs! == true, errors)
  argv = harness.server_argv
  check("server argv is fixed to loopback alternate port and Vulkan0", argv.each_cons(2).include?(["--host", "127.0.0.1"]) && argv.each_cons(2).include?(["--port", "18082"]) && argv.each_cons(2).include?(["-dev", "Vulkan0"]), errors)
  check("server argv is bounded and exposes slots", argv.each_cons(2).include?(["-n", "512"]) && argv.each_cons(2).include?(["-np", "1"]) && argv.include?("--slots"), errors)

  wrong = SuccessfulFixtureHarness.new(**args.merge(expected_model_sha256: "0" * 64))
  begin
    wrong.validate_inputs!
    wrong_rejected = false
  rescue ArgumentError => error
    wrong_rejected = error.message.include?("digest mismatch")
  end
  check("wrong model digest is rejected before launch", wrong_rejected, errors)

  occupied = TCPServer.new("127.0.0.1", 18_082)
  begin
    harness.validate_inputs!
    occupied_rejected = false
  rescue ArgumentError => error
    occupied_rejected = error.message.include?("already occupied")
  ensure
    occupied.close
  end
  check("occupied alternate port is rejected without signaling occupant", occupied_rejected, errors)

  success = SuccessfulFixtureHarness.new(**args).run
  check("successful foreground child is terminated and port cleanup verified", success["ok"] && success.dig("cleanup", "terminated") && success.dig("cleanup", "port_closed"), errors)

  failed = FailingFixtureHarness.new(**args).run
  check("exception path terminates owned child", !failed["ok"] && failed["failure"].include?("synthetic failure") && failed.dig("cleanup", "terminated") && failed.dig("cleanup", "port_closed"), errors)

  canceled = CanceledFixtureHarness.new(**args).run
  check("interrupt path terminates owned child", !canceled["ok"] && canceled["failure"] == "canceled" && canceled.dig("cleanup", "terminated") && canceled.dig("cleanup", "port_closed"), errors)
end

source = File.read(File.expand_path("../lib/soul_core/alternate_model_acceptance_harness.rb", __dir__))
brief = File.read(File.expand_path("../docs/soul/ALTERNATE_AMD_MODEL_ACCEPTANCE_BRIEF.md", __dir__))
check("process launch uses argv and no shell", source.include?("Process.spawn(*server_argv") && !source.include?("system(") && !source.include?("Open3"), errors)
check("cleanup is in ensure and never sends KILL", source.match?(/ensure\s+cleanup_candidate!/) && source.include?('Process.kill("TERM", @child_pid)') && !source.include?('Process.kill("KILL"'), errors)
check("evaluation is synthetic, local-only, and non-executing", source.include?('"cloud_fallback_allowed" => false') && source.include?('"executed" => false') && source.include?("transcript_retained"), errors)
check("brief persona probe has an explicit word bound", SoulCore::AlternateModelAcceptanceHarness::PERSONA_PROMPTS.fetch(3).include?("at most 20 words"), errors)
check("no configuration or service mutation primitive exists", %w[systemctl .env Caddyfile ufw].none? { |primitive| source.include?(primitive) }, errors)
check("approved brief authorizes only temporary listener", brief.include?("temporary_loopback_listener_authorized: yes") && brief.include?("live_provider_cutover_authorized: no"), errors)
check("working tree whitespace is clean", system("git", "diff", "--check", out: File::NULL, err: File::NULL), errors)

if errors.empty?
  puts "Verification complete."
  puts "Alternate AMD model acceptance harness is candidate-ready."
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
