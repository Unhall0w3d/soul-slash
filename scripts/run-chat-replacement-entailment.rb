#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative 'run-chat-replacement-source-check'
require_relative 'support/chat_replacement_entailment_evaluator'

class ChatReplacementEntailment < ChatReplacementSourceCheck
  private
  def max_generations = 52
  public
  def initialize(assets:)
    super
    @protocol_id = 'entailment-v7'
  end
  private
  def feasibility
    save('entailment-design.json', 'protocol' => @protocol_id, 'scored_replies' => 48,
      'source_pairs' => 6, 'samples' => 2, 'conditions' => %w[baseline entailment],
      'scope' => 'Fresh synthetic entailment comparison only; no rewrites or production promotion.',
      'acceptance' => 'Guided: >=11/12 distorted B labels with grounded reasoning, >=11/12 faithful drafts and >=23/24 invariant A accepted; no family missed twice. Improvement: >=2 paired corrections with no new false alarms. Output length and latency descriptive, not equal-compute.',
      'guidance' => SoulCore::ChatReplacementEntailmentEvaluator::GUIDANCE,
      'generation_limit' => generation_limit, 'max_generations' => max_generations)
    ChatReplacementTrial.instance_method(:feasibility).bind(self).call
  end
  def evaluate(root, &block)
    SoulCore::ChatReplacementEntailmentEvaluator.new(root: root, client: client(root), provider: provider,
      temperature: @asset.fetch('temperature'), reasoning_mode: 'disabled').run(&block)
  end
  def source_hashes
    super.merge([__FILE__, File.join(__dir__, 'support/chat_replacement_entailment_cases.rb'),
      File.join(__dir__, 'support/chat_replacement_entailment_evaluator.rb')].to_h do |path|
      [path.delete_prefix("#{ROOT}/"), Digest::SHA256.file(path).hexdigest]
    end)
  end
end
if $PROGRAM_NAME == __FILE__
  abort 'Usage: run-chat-replacement-entailment.rb --approved-entailment ASSETS_DIRECTORY' unless
    ARGV.length == 2 && ARGV[0] == '--approved-entailment'
  exit(ChatReplacementEntailment.new(assets: ARGV[1]).run ? 0 : 1)
end
