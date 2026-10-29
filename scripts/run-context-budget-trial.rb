#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative "run-workday-coexistence-trial"

class ContextBudgetTrial < WorkdayNoMmapTrial
  BUDGET_SECONDS = 2640
  CONTEXT_TOKENS = 8192
  def context_limit = CONTEXT_TOKENS
  def request_seconds = 180
  def candidate_seconds = 1200
  def max_generations = 12
  def generation_limit = @output_cap || 4096
  def create_output = Dir.mktmpdir("context-budget-trial-", QUALIFICATION)

  def self.argv(candidate, model)
    args = super
    args[args.index("--ctx-size") + 1] = CONTEXT_TOKENS.to_s
    args[args.index("--predict") + 1] = "4096"
    args
  end

  def self.source_task(expanded:)
    facts = ["Record A: Project Juniper uses room 7. Delivery is Thursday.",
      "Record B supersedes A only for the room: use room 19. Delivery remains Thursday.",
      "Record C: The seal color is amber. No courier identity is recorded."]
    distractors = expanded ? (1..120).map { |i| "Archive #{i}: unrelated project Sample#{i} uses shelf #{i + 30}; its label is gray. This record does not concern Juniper." } : []
    text = ([facts[0]] + distractors.first(60) + [facts[1]] + distractors.drop(60) + [facts[2]]).join("\n")
    {"id"=>expanded ? "source-expanded" : "source-short",
      "text"=>"Use only this synthetic packet. Report Juniper's current room, delivery day, seal color, and courier identity; identify supporting record letters.\n#{text}",
      "required"=>["room 19 from B", "Thursday from A or B", "amber from C", "courier unknown from C"]}
  end

  def extra_preflight
    packet = {"protocol"=>"context-budget-v1", "candidates"=>IDS,
      "context_tokens"=>context_limit, "request_seconds"=>request_seconds,
      "candidate_seconds"=>candidate_seconds, "batch_seconds"=>BUDGET_SECONDS,
      "max_replies_per_candidate"=>max_generations,
      "output_comparison"=>{"caps"=>[2048,4096], "condition"=>"deliberate", "repetitions"=>2,
        "tasks"=>TASKS.select { |t| %w[capacity cache].include?(t["id"]) }},
      "input_comparison"=>{"output_cap"=>1024, "condition"=>"economy", "repetitions"=>2,
        "tasks"=>[self.class.source_task(expanded:false), self.class.source_task(expanded:true)]},
      "scoring"=>"required criteria, final availability, truncation, latency, measured prompt/output tokens; static code review only",
      "loading"=>"Gemma no-mmap; GPT-OSS unchanged",
      "limitations"=>"8K allocation fixed throughout, not a 4K versus 8K allocation comparison; paired seeds not equal compute; fixed model order; host/cache uncontrolled; repeated calibration plus fresh synthetic retrieval, not broad long-context qualification",
      "source_sha256"=>Digest::SHA256.file(__FILE__).hexdigest,
      "dependencies"=>%w[run-workday-coexistence-trial.rb run-roster-interface-trial.rb run-demand-loaded-comparison.rb run-chat-replacement-trial.rb].to_h { |p| [p,Digest::SHA256.file(File.join(__dir__,p)).hexdigest] }}
    save("frozen-context-budget-packet.json",packet)
    {"context_budget_packet_sha256"=>Digest::SHA256.hexdigest(JSON.generate(packet))}
  end

  def probe
    @condition = "deliberate"
    2.times do |rep|
      (rep.zero? ? [2048,4096] : [4096,2048]).each do |cap|
        @output_cap = cap
        TASKS.select { |t| %w[capacity cache].include?(t["id"]) }.each_with_index do |task,index|
          @paired_seed = 862_000 + rep*100 + index
          collect("#{task['id']}-cap#{cap}-rep#{rep+1}", messages(task))
        end
      end
    end
    @condition, @output_cap = "economy", 1024
    2.times do |rep|
      (rep.zero? ? [false,true] : [true,false]).each do |expanded|
        @paired_seed = 863_000 + rep
        task = self.class.source_task(expanded:expanded)
        collect("#{task['id']}-rep#{rep+1}", messages(task))
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  abort "Expected explicit context-budget flag" unless ARGV == ["--approved-context-budget-trial"]
  exit(ContextBudgetTrial.new.run ? 0 : 1)
end
