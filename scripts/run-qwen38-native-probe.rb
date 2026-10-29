#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative "run-desktop-coexistence-trial"

# Optional candidate only. No production adapter, preset or journal binding.
class Qwen38NativeProbe < DemandLoadedProbes
  IDS = ["qwen3.8-27b"].freeze
  BUDGET_SECONDS = 900
  PREPARATION = File.join(__dir__, "support/qwen38_candidate_preparation.json")
  def candidate_manifest = PREPARATION
  def candidate_assets
    a = JSON.parse(File.read(PREPARATION))
    {IDS.first => a.merge("path" => File.join(QUALIFICATION, "demand-loaded-assets", a.fetch("filename")))}
  end
  def create_output = Dir.mktmpdir("qwen38-native-probe-", QUALIFICATION)
  def candidate_seconds = 600
  def generation_limit = 2048
  def max_generations = 5
  def request_seconds = 120
  def self.argv(candidate, model)
    raise ArgumentError, "unknown candidate" unless IDS.include?(candidate)
    args = MixedGpuPilot.argv("amd_nvidia", model)
    {"--alias"=>candidate,"--tensor-split"=>"2,1","--predict"=>"2048",
     "--batch-size"=>"32","--reasoning"=>"auto"}.each { |flag,value| args[args.index(flag)+1]=value }
    args + ["--no-mmap"]
  end
  def self.validate_amd!(sample, previous:, owned_pid:)
    DesktopCoexistenceTrial.validate_amd!(sample, previous:previous, owned_pid:owned_pid)
  end
  def validate_resources!(sample, admission:false)
    super
    raise Abort, "NVIDIA runtime reserve below 1024 MiB" if sample.fetch("free_mib") < 1024
  end
  def inspect_metadata(id,path)
    raise Abort, "wrong candidate" unless IDS.include?(id)
    result=@commands.run("python",File.join(__dir__,"inspect-demand-loaded-gguf.py"),path,"qwen35",
      timeout_seconds:30,max_output_bytes:16_384)
    raise Abort,"Qwen metadata preflight failed" unless result.success? && !result.truncated
    JSON.parse(result.stdout)
  end
  def prepare_payload(payload)
    thinking = @thinking == true
    payload.merge("temperature"=>thinking ? 1.0 : 0.7,"top_p"=>thinking ? 0.95 : 0.8,
      "top_k"=>20,"min_p"=>0.0,"presence_penalty"=>thinking ? 0.0 : 1.5,
      "repeat_penalty"=>1.0,"chat_template_kwargs"=>{
        "enable_thinking"=>thinking,"preserve_thinking"=>false,"reasoning_effort"=>"low"})
  end
  def extra_preflight
    {"probe_source_sha256"=>Digest::SHA256.file(__FILE__).hexdigest,
     "desktop_policy_sha256"=>Digest::SHA256.file(File.join(__dir__,"run-desktop-coexistence-trial.rb")).hexdigest,
     "baseline_sha256"=>DesktopCoexistenceTrial::BASELINE_SHA,
     "max_generations"=>max_generations,"request_seconds"=>request_seconds,
     "acceptance"=>"review finals, actual native controls, tool schema, resource fit and cleanup separately; no promotion"}
  end
  def probe
    props=JSON.parse(File.read(File.join(@output,"props.json")))
    template=props.fetch("chat_template")
    raise Abort,"thinking control absent" unless template.include?("enable_thinking")
    @thinking=false
    basic=probe_request([{"role"=>"user","content"=>"Fictional record: the access word is apricot. Reply with only that word."}])
    save("probe-basic.json",basic)
    follow=probe_request([{"role"=>"user","content"=>"The green cabinet has six maps."},
      {"role"=>"assistant","content"=>"Six maps."},
      {"role"=>"user","content"=>"Two are removed. Reply with only the number remaining."}])
    save("probe-history.json",follow)
    @thinking=true
    reasoning=probe_request([{"role"=>"user","content"=>"A robot starts with 23 tokens, spends 7, doubles the remainder, then gives away 9. Reply with only the final number."}])
    save("probe-thinking.json",reasoning)
    @thinking=false
    messages=[{"role"=>"user","content"=>"Use lookup_parcel to look up PROBE-17. Do not guess its status."}]
    tool=probe_request(messages,tools:[TOOL]); save("probe-tool.json",tool)
    call=self.class.tool_call(tool.fetch("message",{}) || {})
    if call
      # Only a fixed synthetic response; never invoke a requested tool.
      messages += [tool.fetch("message"),{"role"=>"tool","tool_call_id"=>call.fetch("id"),"content"=>'{"status":"awaiting violet seal"}'}]
      save("probe-tool-result.json",probe_request(messages,tools:[TOOL]))
    end
    save("interface-review.json",{"state"=>"pending_native_format_review",
      "template_controls_present"=>%w[enable_thinking preserve_thinking reasoning_effort].to_h{|k|[k,template.include?(k)]},
      "note"=>"Control presence is not behavioral proof. Missing finals/truncation and tool eligibility require retained-result review."})
  end
end

if $PROGRAM_NAME == __FILE__
  abort "Expected explicit probe flag" unless ARGV==["--approved-qwen38-native-probe"]
  exit(Qwen38NativeProbe.new.run ? 0 : 1)
end
