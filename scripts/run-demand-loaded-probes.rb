#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative "run-mixed-gpu-pilot"

# Interface feasibility only; no actual tools or production service mutations.
class DemandLoadedProbes < MixedGpuPilot
  BUDGET_SECONDS = 2400
  IDS = %w[gpt-oss-20b gemma-4-26b-a4b devstral-small-2-24b].freeze
  MANIFEST = File.join(__dir__, "support/demand_loaded_candidate_assets.json")
  ASSETS = JSON.parse(File.read(MANIFEST)).freeze
  TOOL = {"type"=>"function", "function"=>{"name"=>"lookup_parcel",
    "description"=>"Look up a synthetic parcel by code.", "parameters"=>{"type"=>"object",
      "properties"=>{"code"=>{"type"=>"string"}}, "required"=>["code"], "additionalProperties"=>false}}}.freeze

  def self.argv(candidate, model)
    raise ArgumentError, "unknown candidate" unless IDS.include?(candidate)
    args = super("amd_nvidia", model)
    {"--alias"=>candidate, "--tensor-split"=>"2,1", "--predict"=>"1024",
     "--reasoning"=>"auto"}.each { |flag, value| args[args.index(flag)+1] = value }
    args
  end

  def generation_limit = 1024
  def max_generations = 5
  def candidate_seconds = 600
  def completion_state = "completed_pending_interface_review"
  def extra_preflight = {}
  def candidate_assets = ASSETS
  def candidate_manifest = MANIFEST
  def create_output = Dir.mktmpdir("demand-loaded-probes-", QUALIFICATION)
  def runtime_lease_store = SoulCore::ModelRuntimeLeaseStore.new(root: ROOT)
  def inspect_metadata(id, path)
    result = @commands.run("python",File.join(__dir__,"inspect-demand-loaded-gguf.py"),path,
      {"gpt-oss-20b"=>"gpt-oss", "gemma-4-26b-a4b"=>"gemma4",
       "devstral-small-2-24b"=>"mistral3"}.fetch(id), timeout_seconds:30,max_output_bytes:16_384)
    raise Abort,"GGUF metadata preflight failed" unless result.success? && !result.truncated
    JSON.parse(result.stdout)
  end

  def prepare_payload(payload)
    result = super.merge("temperature"=>1.0,
      "top_p"=>0.95, "chat_template_kwargs"=>native_kwargs)
    result["top_k"] = 64 if @candidate.start_with?("gemma")
    if @candidate == "devstral-small-2-24b"
      result["temperature"] = 0.15
      result.delete("top_p") # Leave unspecified publisher defaults to the native runtime.
    end
    result
  end

  def native_kwargs
    return {} if @candidate == "devstral-small-2-24b"
    @candidate == "gpt-oss-20b" ? {"reasoning_effort"=>"medium"} : {"enable_thinking"=>true}
  end

  def memory_context
    paths = %w[/proc/meminfo /proc/pressure/memory /proc/swaps /proc/vmstat
      /proc/sys/vm/swappiness /sys/block/zram0/mm_stat]
    {"observed_at"=>Time.now.utc.iso8601(6), "files"=>paths.to_h do |path|
      value = begin
        File.read(path, 65_536)
      rescue SystemCallError => error
        {"unavailable"=>error.class.name}
      end
      [path, value]
    end}
  end

  def sample_resources
    super.merge("memory_context"=>memory_context)
  end

  def validate_resources!(sample, admission: false)
    super
  rescue Abort => error
    # Startup validates without appending to @samples. Preserve its exact input,
    # not a later observation after the model has been stopped and RAM released.
    begin
      save("resource-rejection.json", {"error"=>error.message,
        "candidate"=>@candidate, "owned_pid"=>@pid, "admission"=>admission,
        "generation_count"=>@generation_count, "sample"=>sample})
    rescue StandardError => capture_error
      warn "Resource rejection capture unavailable: #{capture_error.class}"
    end
    raise
  end

  def self.tool_call(message)
    calls = message["tool_calls"]
    return nil unless calls.is_a?(Array) && calls.length == 1
    call = calls.first
    return nil unless call["id"].is_a?(String) && !call["id"].empty? &&
      call.dig("function", "name") == "lookup_parcel"
    args = JSON.parse(call.dig("function", "arguments"))
    args == {"code"=>"PROBE-17"} ? call : nil
  rescue JSON::ParserError, TypeError
    nil
  end

  def probe_request(messages, tools: nil)
    cool_down
    payload = {"model"=>@candidate, "messages"=>messages, "max_tokens"=>generation_limit, "stream"=>false}
    payload["tools"] = tools if tools
    response, latency = generate(payload)
    return {"http_status"=>response.code.to_i, "eligible"=>false} unless response.code == "200"
    parsed = JSON.parse(response.body)
    {"http_status"=>200, "message"=>parsed.dig("choices",0,"message"),
     "finish_reason"=>parsed.dig("choices",0,"finish_reason"), "latency_ms"=>latency,
     "usage"=>parsed["usage"], "timings"=>parsed["timings"]}
  end

  def probe
    props = JSON.parse(File.read(File.join(@output,"props.json")))
    template = props.fetch("chat_template")
    marker = {"gpt-oss-20b"=>"analysis", "gemma-4-26b-a4b"=>"enable_thinking"}[@candidate]
    raise Abort, "native template absent" if template.to_s.empty?
    raise Abort, "native template marker absent" if marker && !template.include?(marker)
    basic = probe_request([{"role"=>"user","content"=>"In this fictional record the access word is apricot. Return just that word."}])
    save("probe-basic.json", basic)
    reasoning = probe_request([{"role"=>"user","content"=>"A robot starts with 23 tokens. It spends 7, doubles what remains, then gives away 9. How many remain? Explain briefly and end with the number."}])
    save("probe-reasoning.json", reasoning)
    messages = [{"role"=>"user","content"=>"Use lookup_parcel to look up PROBE-17. Do not guess its status."}]
    tool = probe_request(messages, tools: [TOOL])
    save("probe-tool.json", tool)
    call = self.class.tool_call(tool.fetch("message", {}) || {})
    followup = nil
    if call
      # A literal synthetic result, never an invocation of model-selected code.
      messages += [tool.fetch("message"), {"role"=>"tool", "tool_call_id"=>call.fetch("id"),
        "content"=>JSON.generate("status"=>"awaiting violet seal")}]
      followup = probe_request(messages, tools: [TOOL])
      save("probe-tool-result.json", followup)
    end
    checks = {"basic_final"=>basic.dig("message","content").to_s.strip.downcase == "apricot",
      "reasoning_final"=>reasoning.dig("message","content").to_s.match?(/\b23\b/),
      "reasoning_channel_present"=>!reasoning.dig("message","reasoning_content").to_s.empty?,
      "tool_call"=>!call.nil?, "tool_result"=>followup && followup.dig("message","content").to_s.include?("violet seal"),
      "not_truncated"=>[basic,reasoning,tool,followup].compact.none?{|r|r["finish_reason"]=="length"}}
    save("interface-review.json", {"checks"=>checks, "state"=>"pending_native_format_review",
      "reasoning_channel_required"=>@candidate != "devstral-small-2-24b",
      "note"=>"Probe outcomes are not scored capability results or automatic promotion."})
  end

  def run
    File.umask(0o077)
    @root_output = create_output
    @output = @root_output
    state, error, lease = "failed", nil, nil
    started = now
    signals = %w[INT TERM].to_h{|s|[s,Signal.trap(s){raise Abort,"Canceled by #{s}"}]}
    begin
      Timeout.timeout(self.class::BUDGET_SECONDS, Abort, "probe batch deadline") do
        @before = protected_state
        raise Abort, "production runtime active" unless @before.fetch("unit").include?("ActiveState=inactive") &&
          @before.fetch("amd_units").scan(/^ActiveState=(.*)$/).flatten == ["inactive","inactive"]
        raise Abort, "endpoint occupied" unless port_closed?
        raise Abort, "binary changed" unless Digest::SHA256.file(BINARY).hexdigest == BINARY_SHA
        metadata = self.class::IDS.to_h do |id|
          a = candidate_assets.fetch(id)
          verify_file!(a.fetch("path"),a.fetch("size_bytes"),a.fetch("sha256"))
          [id,inspect_metadata(id,a.fetch("path"))]
        end
        save("asset-metadata.json",metadata)
        start_telemetry
        initial = sample_resources
        @desktop_baseline = desktop_baseline(initial)
        validate_resources!(initial, admission: true)
        @leases = runtime_lease_store
        lease = @leases.acquire_exclusive(provider_id:"external.codex.amd",model_id:"demand-loaded-probes",
          request_id:File.basename(@root_output),resource_group:"amd-vulkan-generation",ttl_seconds:self.class::BUDGET_SECONDS+120)
        save("preflight.json", {"assets"=>candidate_assets,"protected"=>@before,"batch_seconds"=>self.class::BUDGET_SECONDS,
          "protocol"=>self.class.name,"candidate_ids"=>self.class::IDS,
          "candidate_seconds"=>candidate_seconds,"swap_out_limit_pages"=>MixedGpuPilot::SWAP_OUT_LIMIT_PAGES,
          "source_sha256"=>Digest::SHA256.file(__FILE__).hexdigest,
          "dependencies"=>%w[run-mixed-gpu-pilot.rb run-chat-replacement-trial.rb support/mixed_gpu_telemetry.rb inspect-mixed-gpu-telemetry.rb inspect-demand-loaded-gguf.py].to_h{|p|[p,Digest::SHA256.file(File.join(__dir__,p)).hexdigest]},
          "manifest_sha256"=>Digest::SHA256.file(candidate_manifest).hexdigest}.merge(extra_preflight))
        self.class::IDS.each do |id|
          @candidate, @model = id, candidate_assets.fetch(id).fetch("path")
          @output = File.join(@root_output,id)
          Dir.mkdir(@output,0o700)
          @generation_count, @reaped_pid = 0, nil
          cool_down
          validate_resources!(sample_resources, admission:true)
          puts JSON.generate(state:"starting",candidate:id,output:@root_output); $stdout.flush
          begin
            Timeout.timeout(candidate_seconds,Abort,"candidate deadline") do
              load_started = now
              start
              save("load-timing.json",{"process_cold_ready_ms"=>(now-load_started)*1000,"disk_cache"=>"uncontrolled"})
              start_monitor
              probe
            end
          ensure
            stopped_pid = @pid
            cleanup_owned_runtime
          end
          raise Abort,"endpoint survived cleanup" unless port_closed?
          wait_for_release(stopped_pid)
        end
        state = completion_state
      end
    rescue Abort, StandardError => problem
      error = "#{problem.class}: #{problem.message}"
    ensure
      begin
        cleanup_owned_runtime
        stop_telemetry
        @leases.release(lease.fetch("lease_id")) if lease
        @after = protected_state
        raise Abort,"protected state changed" unless @before == @after
      rescue Abort, StandardError => problem
        state = "failed"; error = [error,"cleanup: #{problem.class}: #{problem.message}"].compact.join("; ")
      end
      @output = @root_output
      save("resource-samples.json",@samples)
      save("receipt.json",{"state"=>state,"error"=>error,"elapsed_seconds"=>now-started,
        "owned_pid_if_unreaped"=>@pid,"protected_before"=>@before,"protected_after"=>@after})
      signals.each{|s,h|Signal.trap(s,h)}
    end
    puts JSON.generate(state:state,error:error,output:@root_output)
    state == completion_state
  end
end

class DevstralIsolatedProbe < DemandLoadedProbes
  IDS = ["devstral-small-2-24b"].freeze
  BUDGET_SECONDS = 900
end

class DevstralNoMmapProbe < DevstralIsolatedProbe
  def self.argv(candidate, model)
    super + ["--no-mmap"]
  end
end

if $PROGRAM_NAME == __FILE__
  runner = {"--approved-native-probes"=>DemandLoadedProbes,
    "--approved-devstral-isolated"=>DevstralIsolatedProbe,
    "--approved-devstral-no-mmap"=>DevstralNoMmapProbe}[ARGV.first]
  abort "Expected one explicit probe flag" unless ARGV.length == 1 && runner
  exit(runner.new.run ? 0 : 1)
end
