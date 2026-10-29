#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative "run-roster-interface-trial"

# Exercises existing settings with the operator's desktop left intact.
# This is coexistence evidence, not a new model-quality comparison.
class WorkdayCoexistenceTrial < RosterInterfaceTrial
  IDS = RosterInterfaceTrial::IDS
  BUDGET_SECONDS = 600
  def candidate_seconds = 240
  def max_generations = 2
  def create_output = Dir.mktmpdir("workday-coexistence-", QUALIFICATION)
  def extra_preflight
    packet = {"protocol"=>"workday-coexistence-v1", "candidates"=>IDS,
      "tasks"=>TASKS.select { |t| %w[dispatch cache].include?(t["id"]) },
      "condition"=>"economy", "output_tokens"=>generation_limit,
      "context_tokens"=>4096, "request_seconds"=>120,
      "candidate_seconds"=>candidate_seconds, "batch_seconds"=>BUDGET_SECONDS,
      "max_replies_per_candidate"=>max_generations,
      "acceptance"=>"existing resource guards, protected-state preservation and cleanup; desktop usability requires operator observation",
      "limitations"=>"two reused calibration tasks per model; no quality ranking, no larger-context qualification, no active-call qualification",
      "source_sha256"=>Digest::SHA256.file(__FILE__).hexdigest,
      "interface_source_sha256"=>Digest::SHA256.file(File.join(__dir__, "run-roster-interface-trial.rb")).hexdigest}
    save("frozen-workday-packet.json", packet)
    {"workday_packet_sha256"=>Digest::SHA256.hexdigest(JSON.generate(packet))}
  end
  def probe
    @condition = "economy"
    TASKS.select { |t| %w[dispatch cache].include?(t["id"]) }.each_with_index do |task, index|
      @paired_seed = 852_000 + index
      collect(task.fetch("id"), messages(task))
    end
  end
end

class WorkdayNoMmapTrial < WorkdayCoexistenceTrial
  def self.argv(candidate, model)
    args = super
    candidate == "gemma-4-26b-a4b" ? args + ["--no-mmap"] : args
  end

  def extra_preflight
    result = super
    save("loading-intervention.json", {
      "baseline"=>"workday-coexistence-20261022-522466-r226b4",
      "change"=>"Gemma only: --no-mmap; all other launch arguments and guards unchanged",
      "limitation"=>"host workload and disk cache state uncontrolled"
    })
    result.merge("loading_intervention"=>"gemma_no_mmap")
  end
end

if $PROGRAM_NAME == __FILE__
  klass = case ARGV
          when ["--approved-workday-trial"] then WorkdayCoexistenceTrial
          when ["--approved-workday-no-mmap"] then WorkdayNoMmapTrial
          else abort "Expected explicit workday trial flag"
          end
  exit(klass.new.run ? 0 : 1)
end
