#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative "run-roster-adapter-trial"

# Explicit game/desktop coexistence experiment, not a production admission policy.
class DesktopCoexistenceTrial < RosterAdapterTrial
  BUDGET_SECONDS = 900
  BASELINE = File.join(QUALIFICATION,"desktop-baseline-20261024-UAjUponi/telemetry.jsonl")
  BASELINE_SHA = "8ba2bcee0c00bf2be925dd203c4320faf266c5d78a303d83cbd01f4561d850ad"
  FOREIGN_LIMIT = 7 * 1024**3
  def candidate_seconds = 300
  def create_output = Dir.mktmpdir("desktop-coexistence-",QUALIFICATION)

  def self.baseline_holders
    raise Abort,"desktop baseline changed" unless Digest::SHA256.file(BASELINE).hexdigest == BASELINE_SHA
    rows=File.readlines(BASELINE).map { |line| JSON.parse(line) }
    raise Abort,"desktop baseline incomplete" unless rows.last["state"]=="complete"
    rows.select { |r| r["state"]=="sample" }.flat_map { |r| r.fetch("clients") }
      .flat_map { |c| c.fetch("holders") }.map { |h| h.values_at("uid","exe") }.uniq.freeze
  end

  def self.validate_desktop_amd!(sample, owned_pid:, allowed:)
    foreign=sample.fetch("clients").reject do |client|
      holders=client.fetch("holders")
      owned_pid && !holders.empty? && holders.all? { |h| h["pid"]==owned_pid && h["uid"]==Process.uid }
    end
    raise Abort,"desktop aggregate AMD allocation bound (7 GiB)" if foreign.sum { |c| c.fetch("bytes") } >= FOREIGN_LIMIT
    foreign.each do |client|
      holders=client.fetch("holders")
      raise Abort,"unrecognized desktop GPU holder" if holders.empty? || holders.any? { |h| !allowed.include?(h.values_at("uid","exe")) }
    end
    # Expected graphics applications use compute queues too. Their compute
    # counters are retained, not mistaken for competing model identification.
    true
  end

  def self.validate_amd!(sample, previous:, owned_pid:)
    validate_desktop_amd!(sample,owned_pid:owned_pid,allowed:(@allowed_holders ||= baseline_holders))
  end

  def validate_resources!(sample, admission: false)
    super
    raise Abort,"NVIDIA runtime reserve below 1024 MiB" if sample.fetch("free_mib") < 1024
  end

  def sample_resources
    sample=super
    (@all_samples ||= []) << sample.merge("candidate"=>@candidate,"owned_pid"=>@pid)
    sample
  end

  def extra_preflight
    result=super
    packet={"protocol"=>"desktop-coexistence-v1","baseline_sha256"=>BASELINE_SHA,
      "expected_workload"=>"operator desktop including Warframe; no app closure",
      "seconds"=>BUDGET_SECONDS,"candidate_seconds"=>candidate_seconds,"max_replies"=>4,
      "foreign_amd_cap_gib"=>7,"amd_free_admission_gib"=>10,"amd_free_runtime_gib"=>2,
      "nvidia_free_admission_mib"=>6656,"nvidia_free_runtime_mib"=>1024,
      "unchanged"=>"thermal cutoffs, RAM >=8 GiB, 512 MiB swap-out, fresh complete telemetry, NVIDIA foreign compute refusal, cleanup, sequential 2:1 split, native adapters",
      "acceptance"=>"both candidates load and reply, no guard/allocator failure, reserves maintained, protected state and cleanup verified",
      "limitations"=>"sampled peaks; no deliberate OOM, no smooth-gameplay claim, no simultaneous model residency; first failure stops batch",
      "source_sha256"=>Digest::SHA256.file(__FILE__).hexdigest}
    save("frozen-desktop-packet.json",packet)
    result.merge("desktop_packet_sha256"=>Digest::SHA256.hexdigest(JSON.generate(packet)))
  end

  def run
    super
  ensure
    if @root_output
      @output=@root_output
      save("all-resource-samples.json",@all_samples || [])
    end
  end
end

if $PROGRAM_NAME == __FILE__
  abort "Expected --approved-desktop-coexistence" unless ARGV==["--approved-desktop-coexistence"]
  exit(DesktopCoexistenceTrial.new.run ? 0 : 1)
end
