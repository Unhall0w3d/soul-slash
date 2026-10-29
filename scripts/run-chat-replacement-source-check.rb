#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "run-chat-replacement-usability"
require_relative "support/chat_replacement_source_check_evaluator"

class ChatReplacementSourceCheck < ChatReplacementUsability
  def initialize(assets:)
    super
    @protocol_id = "source-check-v6"
  end

  private

  def max_generations = 36

  def feasibility
    save("source-check-design.json", "protocol" => @protocol_id,
      "scored_replies" => 32, "independent_samples" => 2, "fresh_source_pairs" => 8,
      "conditions" => %w[faithful distorted], "thinking" => false,
      "acceptance" => "At least 14/16 distorted claims correctly classified with source-grounded explanation; at least 15/16 faithful drafts accepted; at least 31/32 invariant A claims accepted; no error family missed in both repeats. This qualifies only further evaluation, not deployment.",
      "scope" => "Verifier capability only; no automatic rewriting, production changes, or equal-compute improvement claim.",
      "instruction" => SoulCore::ChatReplacementSourceCheckEvaluator::INSTRUCTION,
      "generation_limit" => generation_limit, "max_generations" => max_generations)
    ChatReplacementTrial.instance_method(:feasibility).bind(self).call
  end

  def evaluate(root, &block)
    SoulCore::ChatReplacementSourceCheckEvaluator.new(root: root, client: client(root), provider: provider,
      temperature: @asset.fetch("temperature"), reasoning_mode: "disabled").run(&block)
  end

  def source_hashes
    super.merge([__FILE__, File.join(__dir__, "support/chat_replacement_source_check_cases.rb"),
      File.join(__dir__, "support/chat_replacement_source_check_evaluator.rb")].to_h do |path|
      [path.delete_prefix("#{ROOT}/"), Digest::SHA256.file(path).hexdigest]
    end)
  end
end

if $PROGRAM_NAME == __FILE__
  abort "Usage: run-chat-replacement-source-check.rb --approved-source-check ASSETS_DIRECTORY" unless
    ARGV.length == 2 && ARGV[0] == "--approved-source-check"
  exit(ChatReplacementSourceCheck.new(assets: ARGV[1]).run ? 0 : 1)
end
