#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "compare-continuity-models-a23"

# Separate, declared configuration comparison. Never replaces first-run receipts.
class ContinuityPlacementComparisonA23 < ContinuityModelComparisonA23
  MODELS = %w[qwen35 qwen30].freeze

  def candidate_args(id, path)
    raise "Unapproved placement candidate" unless MODELS.include?(id)
    args = super.reject { |arg| arg == "--cpu-moe" }
    args[args.index("--flash-attn") + 1] = "auto"
    args
  end

  def run
    File.umask(0o077)
    @output = File.join(ROOT, "Soul/runtime/qualification/continuity-placement-a23-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}")
    Dir.mkdir(@output, 0o700)
    puts "EVIDENCE #{@output}"
    assets = JSON.parse(File.read(ASSETS)).select { |id, _| MODELS.include?(id) }
    raise "Missing placement candidate" unless assets.keys == MODELS
    raise "Runtime digest changed" unless Digest::SHA256.file(SERVER).hexdigest == SERVER_SHA
    verify_asset(MODEL8, 5_027_783_488, MODEL8_SHA)
    assets.each_value { |asset| verify_asset(File.join(MODEL_ROOT, asset.fetch("file")), asset.fetch("size"), asset.fetch("sha256")) }
    @unit_sha = Digest::SHA256.file(UNIT).hexdigest
    sources = [__FILE__, File.join(ROOT, "scripts/compare-continuity-models-a23.rb"), ASSETS,
      File.join(ROOT, "scripts/support/continuity_model_cases_a23.rb")] + Dir.glob(File.join(ROOT, "lib/soul_core/continuity_lab/*.rb"))
    save("protocol.json", { "schema" => "soul.continuity.placement_comparison.a23b", "assets" => assets,
      "baseline_model_sha256" => MODEL8_SHA, "runtime_sha256" => SERVER_SHA, "unit_sha256" => @unit_sha,
      "settings" => SETTINGS.slice(*MODELS), "groups" => Cases.groups,
      "sources" => sources.to_h { |path| [path, Digest::SHA256.file(path).hexdigest] }, "budget_seconds" => 2700,
      "changes" => ["remove CPU-only expert override; auto-fit complete layers", "flash-attention auto instead of off"],
      "expected_generations" => 32, "semantic_review_required" => true, "production_qualification" => false,
      "comparison" => "Configuration replay, not fresh held-out evaluation or isolated single-factor attribution" })
    leases = SoulCore::ModelRuntimeLeaseStore.new(root: ROOT)
    leases.with_control_lock do
      raise "Retained model leases" unless leases.leases_for_quiescent_admission_unlocked.empty?
      state = unit
      pid = Integer(state.fetch("MainPID"))
      observer = Lab::QwenHostObserver.new(root: ROOT, client: Lab::QwenTransport.new, expected_pid: pid)
      observer.call
      save("initial.json", { "unit" => state, "host" => observer.last_evidence, "snapshot" => check_idle(pid) })
      with_restoration do
        Timeout.timeout(2700, SuiteDeadline) do
          observer.call
          check_idle(pid)
          command("systemctl", "--user", "stop", "llama-server.service", seconds: 45)
          raise "Baseline failed to stop" unless unit["ActiveState"] == "inactive"
          assets.each do |id, asset|
            begin
              puts "LOAD #{id} auto-layer/flash-auto"
              candidate_pid = start_candidate(id, File.join(MODEL_ROOT, asset.fetch("file")))
              evaluate_model(id, candidate_pid)
            rescue StandardError => error
              save("#{id}-model-failure.json", { "class" => error.class.name, "message" => error.message })
              puts "MODEL_FAILED #{id}: #{error.message}"
            ensure
              stop_candidate
            end
          end
        end
      end
    end
    puts "FINISHED #{@output}"
  rescue StandardError, Interrupt, SuiteDeadline, ResourceStop => error
    save("failure.json", { "class" => error.class.name, "message" => error.message, "restoration_required" => @restore_required }) if @output
    warn "FAILED: #{error.class}: #{error.message}"
    raise
  end
end

if $PROGRAM_NAME == __FILE__
  abort "Use --approved-placement-comparison" unless ARGV == ["--approved-placement-comparison"]
  $stdout.sync = true
  Signal.trap("TERM") { raise Interrupt, "termination requested" }
  ContinuityPlacementComparisonA23.new.run
end
