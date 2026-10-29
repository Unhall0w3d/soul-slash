#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative "run-desktop-coexistence-trial"

class GemmaPlacementTrial < DesktopCoexistenceTrial
  IDS = ["gemma-4-26b-a4b"].freeze
  def self.split = "3,2"
  def create_output = Dir.mktmpdir("gemma-placement-#{self.class.split.tr(',', '-')}-",QUALIFICATION)

  def self.argv(candidate,model)
    raise ArgumentError,"Gemma-only placement trial" unless IDS.include?(candidate)
    args=super
    args[args.index("--tensor-split")+1]=split
    args
  end

  def extra_preflight
    packet={"protocol"=>"gemma-desktop-placement-#{self.class.split.tr(',', '-')}-v1",
      "historical_baseline"=>"desktop-coexistence-20261024-2501475-wu1uuj",
      "baseline_sha256"=>BASELINE_SHA,"candidates"=>IDS,
      "change"=>"Gemma-only AMD:NVIDIA tensor split 2:1 to #{self.class.split.tr(',', ':')}",
      "messages"=>TASK_MESSAGES,"context_tokens"=>4096,"output_tokens"=>2048,
      "seconds"=>BUDGET_SECONDS,"candidate_seconds"=>candidate_seconds,"max_replies"=>2,
      "guards"=>{"foreign_amd_cap_gib"=>7,"amd_free_admission_gib"=>10,
        "amd_free_runtime_gib"=>2,"nvidia_free_admission_mib"=>6656,"nvidia_free_runtime_mib"=>1024,
        "ram_min_gib"=>8,"swap_out_max_mib"=>512,"amd_junction_max_c"=>100,"nvidia_max_c"=>88},
      "acceptance"=>"ready and two final replies; reserves maintained; protected state and cleanup verified",
      "limitations"=>"sampled peaks; uncontrolled desktop/cache; no deliberate OOM or gameplay-smoothness claim; no retry",
      "sources"=>[__FILE__,File.join(__dir__,"run-desktop-coexistence-trial.rb"),File.join(__dir__,"run-roster-adapter-trial.rb")].to_h { |p| [p,Digest::SHA256.file(p).hexdigest] }}
    save("frozen-placement-packet.json",packet)
    {"placement_packet_sha256"=>Digest::SHA256.hexdigest(JSON.generate(packet))}
  end
end

class GemmaEqualPlacementTrial < GemmaPlacementTrial
  def self.split = "1,1"
end

if $PROGRAM_NAME == __FILE__
  klass=case ARGV
        when ["--approved-gemma-placement"] then GemmaPlacementTrial
        when ["--approved-gemma-equal-placement"] then GemmaEqualPlacementTrial
        else abort "Expected explicit Gemma placement approval flag"
        end
  exit(klass.new.run ? 0 : 1)
end
