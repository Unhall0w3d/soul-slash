#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative "run-demand-loaded-probes"

class DemandLoadedComparison < DemandLoadedProbes
  BUDGET_SECONDS = 2640
  CASE_PATH = File.join(__dir__, "support/demand_loaded_heldout_cases.json")
  SPECIALIST = [
    {"id"=>"code_interface", "category"=>"coding",
     "messages"=>[{"role"=>"user","content"=>"Synthetic Python repository: api.py defines fetch_user(uid): return {'name': 'Ada', 'enabled': False}. view.py imports fetch_user and defines label(uid): return fetch_user(uid).name. repair.py proposes changing fetch_user to return an object. Existing consumers require a dictionary and enabled=False must be preserved. Propose the smallest fix, identify the affected file, and give tests covering the existing dictionary contract and label output. Do not change the API return type."}],
     "rubric"=>{"required"=>["view.py dictionary indexing for name", "preserves fetch_user dict contract", "test label Ada", "test enabled remains False"],"failure"=>["changes API return type","drops enabled"]}},
    {"id"=>"code_regression", "category"=>"coding",
     "messages"=>[{"role"=>"user","content"=>"A Python cache uses: if cache.get(key): return cache[key]; otherwise compute and store. Valid cached values include 0, False, empty string and None. Its contract distinguishes a missing key from a present key with any value. Explain the defect, propose a minimal repair and specify tests that catch it, including a compute-call counter. No new dependencies."}],
     "rubric"=>{"required"=>["membership check not truthiness", "all four falsey values reused", "compute zero times on hit", "compute once on miss then reuse"]}},
    {"id"=>"code_patch_review", "category"=>"coding",
     "messages"=>[{"role"=>"user","content"=>"Review a proposed Python patch to retained_last(values), intended to preserve the order of last occurrences without mutating input. Patch: return list(dict.fromkeys(values)). For ['x','y','x'], the expected result is ['y','x']. Is the patch correct? Give a counterexample, a minimal correct algorithm, and tests including input preservation. Do not execute code."}],
     "rubric"=>{"required"=>["rejects first-occurrence patch", "counterexample x y x", "last-occurrence algorithm", "input preservation test"]}}
  ].freeze
  # Keep every domain and both independent repetitions within the fixed live window.
  CORE_IDS = %w[source_revision source_unknown reason_capacity reason_order conversation_correction review_stale review_idle].freeze
  CASES = (JSON.parse(File.read(CASE_PATH)).fetch("cases").select { |c| CORE_IDS.include?(c.fetch("id")) } + SPECIALIST).freeze
  OUTPUT_TOKENS = 2048
  def generation_limit = OUTPUT_TOKENS
  def candidate_seconds = 780
  def completion_state = "completed_pending_rubric_review"
  def max_generations = CASES.length * 2
  def create_output = Dir.mktmpdir("demand-loaded-comparison-", QUALIFICATION)
  def self.argv(candidate, model)
    args = super
    args[args.index("--predict") + 1] = OUTPUT_TOKENS.to_s
    candidate == "devstral-small-2-24b" ? args + ["--no-mmap"] : args
  end
  def self.cooling_needed?(sample)
    sample.fetch("temperature_c") >= 75 || sample.fetch("amd_temperatures").fetch("junction") >= 85
  end
  def self.cooling_ready?(sample)
    sample.fetch("temperature_c") <= 65 && sample.fetch("amd_temperatures").fetch("junction") <= 70
  end
  def cool_down
    deadline = now + 180
    cooling = false
    since = nil
    loop do
      sample = sample_resources
      @samples << sample
      # Admission and hard limits still apply even when no pacing delay is needed.
      validate_resources!(sample)
      cooling ||= self.class.cooling_needed?(sample)
      return unless cooling
      since = self.class.cooling_ready?(sample) ? (since || now) : nil
      return if since && now - since >= 5
      raise Abort, "cooling deadline" if now >= deadline
      sleep 1
    end
  end
  def extra_preflight
    packet = {"cases"=>CASES, "repetitions"=>2, "output_tokens"=>OUTPUT_TOKENS,
      "protocol"=>"revised pilot v2; prior cases reused, not fresh confirmatory evidence",
      "pacing"=>{"trigger_nvidia_c"=>75,"trigger_amd_junction_c"=>85,"resume_nvidia_c"=>65,"resume_amd_junction_c"=>70,"stable_seconds"=>5,"maximum_cooling_seconds"=>180},
      "request_seconds"=>120, "coding_evidence"=>"static review only; never execute generated code",
      "scoring"=>"required criteria individually pass/fail; human rubric 0/1/2 per dimension; no aggregate ranking before review",
      "limitations"=>"fixed model order, uncontrolled disk cache, model-native sampling; equal token caps are not equal compute",
      "source_sha256"=>Digest::SHA256.file(__FILE__).hexdigest,
      "case_file_sha256"=>Digest::SHA256.file(CASE_PATH).hexdigest}
    save("frozen-evaluation-packet.json", packet)
    {"evaluation_packet_sha256"=>Digest::SHA256.hexdigest(JSON.generate(packet)),
     "comparison_source_sha256"=>packet["source_sha256"], "max_replies_per_candidate"=>max_generations}
  end
  def self.classify(result)
    return "http_failure" unless result["http_status"] == 200
    return "truncated" if result["finish_reason"] == "length"
    message = result["message"]
    return "invalid_output" unless message.is_a?(Hash) && message["content"].is_a?(String) && !message["content"].strip.empty?
    return "unexpected_tool_call" unless Array(message["tool_calls"]).empty?
    "pending_rubric_review"
  end
  def probe
    results = []
    2.times do |rep|
      # Each request has only the fixed case's messages, never a prior sampled answer.
      order = rep.zero? ? CASES : CASES.reverse
      order.each do |entry|
        result = probe_request(entry.fetch("messages"))
        record = result.merge("case_id"=>entry.fetch("id"), "repetition"=>rep+1,
          "status"=>self.class.classify(result), "request_index"=>@generation_count)
        save("case-#{entry.fetch('id')}-#{rep+1}.json", record)
        results << record.slice("case_id","repetition","status","latency_ms","request_index")
      end
    end
    save("case-index.json", {"results"=>results,"quality_scores"=>"pending independent rubric review"})
  end
end

if $PROGRAM_NAME == __FILE__
  abort "Expected explicit comparison flag" unless ARGV == ["--approved-scored-comparison"]
  exit(DemandLoadedComparison.new.run ? 0 : 1)
end
