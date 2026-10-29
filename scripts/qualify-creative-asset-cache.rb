# frozen_string_literal: true
# Read-only installed-asset timing. No project creation, model load or rendering.
require "json"
require "timeout"
require_relative "../lib/soul_core/application_facade"

output = ARGV.fetch(0)
raise "new receipt path required" if File.exist?(output)
root = File.expand_path("..", __dir__)
facade = SoulCore::ApplicationFacade.new(root: root)
deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 180
cancel = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline }
rows = []
receipt = {"mode" => "read_only_asset_verification_no_inference", "rows" => rows}
begin
  Timeout.timeout(180) do
    2.times do |pass|
      services = facade.creative_bridge_services(cancel: cancel)
      cache = services[:visual].instance_variable_get(:@asset_verifier)
      %i[visual music].each do |kind|
        before = cache.stats
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        if kind == :visual
          result = services[:visual].resources
          raise "installed visual resources refused" unless result.dig("data", "ready")
          identity = result.dig("data", "runtime_identity")
        else
          raise "installed music resources refused" unless services[:music].send(:verify_checkpoints!)
          identity = services[:music].send(:model_profile)
        end
        row = {"pass" => pass + 1, "kind" => kind.to_s, "seconds" => Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
          "identity" => identity, "cache_before" => before, "cache_after" => cache.stats}
        rows << row
        puts JSON.generate(row.slice("pass", "kind", "seconds")); STDOUT.flush
      end
    end
  end
  receipt["state"] = "passed"
rescue StandardError => error
  receipt.merge!("state" => "failed", "error_class" => error.class.name)
ensure
  File.write(output, JSON.pretty_generate(receipt) + "\n", mode: "wx", perm: 0600)
end
exit(receipt["state"] == "passed" ? 0 : 1)
