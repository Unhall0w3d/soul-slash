#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "run-chat-replacement-usability"
require_relative "support/chat_replacement_adaptation_evaluator"

class ChatReplacementAdaptation < ChatReplacementUsability
  def initialize(assets:)
    super
    @protocol_id = "adaptation-v5"
  end

  private

  def max_generations = 52

  def feasibility
    evaluator = SoulCore::ChatReplacementAdaptationEvaluator
    save("adaptation-design.json", "protocol" => @protocol_id, "scored_replies" => 48,
      "conversations" => 6, "turns_per_conversation" => 2, "independent_samples" => 2,
      "conditions" => evaluator::CONDITIONS, "counterbalanced_condition_order" => true,
      "paired_seed_formula" => "851001 + case_index * 40 + (sample - 1) * 10 + turn_index",
      "guidance" => evaluator::GUIDANCE.rstrip, "context" => "full", "thinking" => false,
      "actual_replies_carried_forward" => true, "no_actual_tools" => true,
      "no_durable_memory" => true, "generation_limit" => generation_limit,
      "context_limit" => CONTEXT, "max_generations" => max_generations)
    # Reuse the original four probes, not the old usability trial's metadata.
    ChatReplacementTrial.instance_method(:feasibility).bind(self).call
  end

  def evaluate(root, &block)
    SoulCore::ChatReplacementAdaptationEvaluator.new(root: root, client: client(root), provider: provider,
      temperature: @asset.fetch("temperature"), reasoning_mode: "disabled").run(&block)
  end

  def source_hashes
    super.merge([__FILE__, File.join(__dir__, "support/chat_replacement_adaptation_cases.rb"),
      File.join(__dir__, "support/chat_replacement_adaptation_evaluator.rb")].to_h do |path|
      [path.delete_prefix("#{ROOT}/"), Digest::SHA256.file(path).hexdigest]
    end)
  end
end

if $PROGRAM_NAME == __FILE__
  abort "Usage: run-chat-replacement-adaptation.rb --approved-adaptation-trial ASSETS_DIRECTORY" unless
    ARGV.length == 2 && ARGV[0] == "--approved-adaptation-trial"
  exit(ChatReplacementAdaptation.new(assets: ARGV[1]).run ? 0 : 1)
end
