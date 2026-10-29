#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "run-chat-replacement-trial"
require_relative "support/chat_replacement_usability_evaluator"

class ChatReplacementUsability < ChatReplacementTrial
  class UsabilityClient < Client
    def chat(provider:, request:, **options)
      @owner.with_usability_seed(request.metadata["usability_seed"]) { super }
    end
  end

  def initialize(assets:)
    super(candidate: "gemma4-e4b-it", assets: assets, protocol: "cooling-v2")
    @protocol_id = "usability-v4"
    @usability_seed = nil
    @request_active = false
  end

  def self.argv(candidate, model)
    raise ArgumentError, "Gemma-only usability trial" unless candidate == "gemma4-e4b-it"
    args = super
    args[args.index("--predict") + 1] = "1536"
    args
  end

  def with_usability_seed(seed)
    raise Abort, "Overlapping usability requests" if @request_active
    raise Abort, "Invalid usability seed" unless seed.nil? || (seed.is_a?(Integer) && seed.between?(851_001, 851_399))
    @request_active = true
    @usability_seed = seed
    begin
      yield
    ensure
      @usability_seed = nil
      @request_active = false
    end
  end

  def generate(payload)
    response, latency = super
    message = JSON.parse(response.body).fetch("choices", [{}]).first.fetch("message", {})
    observation = { "thinking_requested" => false,
      "reasoning_present" => !message["reasoning_content"].to_s.empty?,
      "final_characters" => message["content"].to_s.length }
    save(format("request-%02d-usability.json", @generation_count), observation)
    raise Abort, "Unexpected reasoning emitted in direct-mode trial" if observation.fetch("reasoning_present")
    [response, latency]
  end

  private

  def generation_limit = 1536
  def max_generations = 28

  def prepare_payload(payload)
    payload = super
    payload["seed"] = @usability_seed if @usability_seed
    payload["chat_template_kwargs"] = { "enable_thinking" => false }
    payload["reasoning_format"] = "deepseek" # llama.cpp split-field format, not a model dependency.
    payload
  end

  def json_http(path, payload = nil, **options)
    result = super
    raise Abort, "Native thinking unexpectedly enabled" if path == "/apply-template" && result.fetch("prompt").include?("<|think|>")
    result
  end

  def client(root)
    UsabilityClient.new(owner: self, root: root, env: { "SOUL_LOCAL_OPENAI_DIALECT" => "llamacpp" })
  end

  def feasibility
    save("usability-design.json", "protocol" => @protocol_id, "scored_replies" => 24,
      "conversations" => 4, "turns_per_conversation" => 3, "independent_samples" => 2,
      "context" => "full", "thinking" => false, "actual_replies_carried_forward" => true,
      "no_actual_tools" => true, "no_durable_memory" => true,
      "generation_limit" => generation_limit, "context_limit" => CONTEXT)
    super
  end

  def evaluate(root, &block)
    SoulCore::ChatReplacementUsabilityEvaluator.new(root: root, client: client(root), provider: provider,
      temperature: @asset.fetch("temperature"), reasoning_mode: "disabled").run(&block)
  end

  def source_hashes
    super.merge([__FILE__, File.join(__dir__, "support/chat_replacement_usability_cases.rb"),
      File.join(__dir__, "support/chat_replacement_usability_evaluator.rb"),
      File.join(__dir__, "support/chat_replacement_calibration_evaluator.rb"),
      File.join(__dir__, "support/chat_replacement_calibration_cases.rb")].to_h do |path|
      [path.delete_prefix("#{ROOT}/"), Digest::SHA256.file(path).hexdigest]
    end)
  end
end

if $PROGRAM_NAME == __FILE__
  abort "Usage: run-chat-replacement-usability.rb --approved-practical-trial ASSETS_DIRECTORY" unless
    ARGV.length == 2 && ARGV[0] == "--approved-practical-trial"
  exit(ChatReplacementUsability.new(assets: ARGV[1]).run ? 0 : 1)
end
