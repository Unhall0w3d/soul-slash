#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative "run-demand-loaded-comparison"

# One foreground window, one existing read-only telemetry helper. No retry loop.
class RosterInterfaceTrial < DemandLoadedComparison
  IDS = %w[gpt-oss-20b gemma-4-26b-a4b].freeze
  BUDGET_SECONDS = 2640
  STYLE = "Give a concise final answer: at most 180 words, excluding code. For code, provide only the minimal function and compact assertions; avoid scaffolding. State uncertainty rather than inventing missing facts."
  TASKS = [
    {"id"=>"dispatch", "text"=>"Use only this fictional record: parcel K9 reached locker 12 at 14:10; a signature was recorded. A later note corrects the locker to 15. Nothing identifies contents or signer. State the supported locker and whether the signer was Morgan or the parcel contained a battery.", "required"=>["locker 15", "signer unknown", "contents unknown"]},
    {"id"=>"capacity", "text"=>"Independent bins hold 13 and 8 units. Reserve 3 in each. An indivisible item needs 11; a splittable item needs 14. Which fit alone? Give an allocation where possible.", "required"=>["usable 10 and 5", "indivisible does not fit", "split fits with valid total 14"]},
    {"id"=>"cache", "text"=>"Repair Python lookup(cache, key, compute), currently using if cache.get(key): return cache[key], otherwise computing and storing compute(key). Cached 0, False, '', and None must be reused. Give the function and compact tests with a call counter: zero calls for each prefilled hit, one for a miss then zero additional calls for reuse. No dependencies.", "required"=>["membership lookup", "four falsey hits", "counter zero on prefilled hits", "one miss computation and reuse", "tests internally consistent"]},
    {"id"=>"correction", "text"=>"In this fictional conversation I said the studio was Elm with Tuesday appointments. Correction: studio is Birch, appointments remain Tuesday. Write one short note for a colleague. No address or contact details are supplied.", "required"=>["Birch", "Tuesday", "no invented details"]}
  ].freeze
  def candidate_seconds = 1200
  def max_generations = 20
  def create_output = Dir.mktmpdir("roster-interface-trial-", QUALIFICATION)
  def self.argv(candidate, model)
    raise ArgumentError, "candidate outside selected roster" unless IDS.include?(candidate)
    super
  end
  def native_kwargs
    raise Abort, "unknown interface condition" unless %w[economy deliberate].include?(@condition)
    @candidate == "gpt-oss-20b" ? {"reasoning_effort"=>(@condition == "economy" ? "low" : "medium")} : {"enable_thinking"=>(@condition == "deliberate")}
  end
  def prepare_payload(payload)
    result = super
    result["seed"] = @paired_seed if @paired_seed
    result
  end
  def extra_preflight
    packet = {"protocol"=>"roster-interface-v1", "candidates"=>IDS, "tasks"=>TASKS,
      "style"=>STYLE, "repetitions"=>2, "conditions"=>{"gpt-oss-20b"=>["low","medium"],"gemma-4-26b-a4b"=>[false,true]},
      "output_tokens"=>generation_limit, "context_tokens"=>4096, "request_seconds"=>120,
      "candidate_seconds"=>candidate_seconds,"batch_seconds"=>BUDGET_SECONDS,"max_replies_per_candidate"=>max_generations,
      "controls"=>"cache answer: independent extra sample versus source-check revision of deliberate repetition 1; same cap, not equal FLOPs",
      "scoring"=>"required criteria individually; classify truncation separately; static code review only, never execute generated code",
      "limitations"=>"two samples; fixed model order; same numeric seeds do not equalize model RNG; equal caps not equal compute; no global optimality claim",
      "source_sha256"=>Digest::SHA256.file(__FILE__).hexdigest,
      "comparison_sha256"=>Digest::SHA256.file(File.join(__dir__,"run-demand-loaded-comparison.rb")).hexdigest}
    save("frozen-interface-packet.json",packet)
    {"interface_packet_sha256"=>Digest::SHA256.hexdigest(JSON.generate(packet))}
  end
  def messages(task)
    [{"role"=>"system","content"=>STYLE},{"role"=>"user","content"=>task.fetch("text")}]
  end
  def collect(name, input, tools: nil)
    result = probe_request(input, tools: tools)
    save("answer-#{name}.json",result.merge("condition"=>@condition,"seed"=>@paired_seed,
      "request_index"=>@generation_count,"status"=>(tools && self.class.tool_call(result.fetch("message",{})) ? "synthetic_tool_call_pending_review" : self.class.classify(result))))
    result
  end
  def probe
    source = nil
    2.times do |rep|
      order = rep.zero? ? %w[economy deliberate] : %w[deliberate economy]
      order.each do |condition|
        @condition=condition
        TASKS.each_with_index do |task,index|
          @paired_seed=842_000 + rep*100 + index
          result=collect("#{task.fetch('id')}-#{condition}-#{rep+1}",messages(task))
          source=result if rep.zero? && condition=="deliberate" && task["id"]=="cache"
        end
      end
    end
    @condition="deliberate"
    task=TASKS.find{|t|t["id"]=="cache"}
    @paired_seed=843_000
    collect("cache-independent-control",messages(task))
    if self.class.classify(source)=="pending_rubric_review"
      @paired_seed=843_001
      collect("cache-source-check",messages(task)+[
        {"role"=>"assistant","content"=>source.fetch("message").fetch("content")},
        {"role"=>"user","content"=>"Check that answer against the original requirements. Trace the test expectations and call counts, including None. Return a corrected compact answer if needed; otherwise retain it. Do not claim you ran the tests."}])
    else
      save("source-check-skipped.json",{"reason"=>"source answer incomplete; no fabricated continuation"})
    end
    @paired_seed=844_000
    input=[{"role"=>"user","content"=>"Use lookup_parcel to look up PROBE-17; do not invent a result."}]
    result=collect("tool-request",input,tools:[TOOL])
    call=self.class.tool_call(result.fetch("message",{}))
    if result["http_status"]==200 && result["finish_reason"]!="length" && call
      @paired_seed=844_001
      # This is a fixed synthetic result, never a tool dispatcher.
      collect("tool-result",input+[result.fetch("message"),{"role"=>"tool","tool_call_id"=>call.fetch("id"),"content"=>'{"code":"PROBE-17","status":"violet seal"}'}],tools:[TOOL])
    else
      save("tool-result-skipped.json",{"reason"=>"exact synthetic tool contract not satisfied"})
    end
  end
end

if $PROGRAM_NAME == __FILE__
  abort "Expected explicit roster trial flag" unless ARGV == ["--approved-roster-interface-trial"]
  exit(RosterInterfaceTrial.new.run ? 0 : 1)
end
