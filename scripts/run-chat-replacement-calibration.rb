#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "run-chat-replacement-trial"
require_relative "support/chat_replacement_calibration_evaluator"

# Reuses the qualified foreground lifecycle and resource guards. Only this
# isolated development runner understands the calibration metadata; production
# provider contracts, profiles, and context policy remain unchanged.
class ChatReplacementCalibration < ChatReplacementTrial
  class CalibrationClient < Client
    def chat(provider:, request:, **options)
      @owner.with_calibration_controls(request.metadata["calibration"]) { super }
    end
  end

  def initialize(candidate:, assets:, probe_revision: "simple-v1")
    raise ArgumentError, "Unapproved feasibility probe revision" unless %w[simple-v1 constraint-v2 interface-v3].include?(probe_revision)
    raise ArgumentError, "Revised probe is approved for Gemma only" if probe_revision != "simple-v1" && candidate != "gemma4-e4b-it"
    super(candidate: candidate, assets: assets, protocol: "cooling-v2")
    @probe_revision = probe_revision
    @protocol_id = { "simple-v1" => "calibration-v3", "constraint-v2" => "calibration-v3-probe2",
      "interface-v3" => "calibration-v3-interface3" }.fetch(probe_revision)
    @calibration_controls = nil
  end

  def self.argv(candidate, model)
    args = super
    args[args.index("--predict") + 1] = "1536"
    args
  end

  def with_calibration_controls(controls)
    previous = @calibration_controls
    raise Abort, "Overlapping calibration requests" if previous
    @calibration_controls = controls
    yield
  ensure
    @calibration_controls = previous
  end

  def generate(payload)
    response, latency = super
    body = JSON.parse(response.body)
    message = body.fetch("choices", [{}]).first.fetch("message", {})
    # Retain reasoning privately in the original raw response. Never feed it
    # into another sample or expose it as the user's answer.
    save(format("request-%02d-calibration.json", @generation_count),
      "controls" => @calibration_controls,
      "reasoning_present" => !message["reasoning_content"].to_s.empty?,
      "reasoning_characters" => message["reasoning_content"].to_s.length,
      "final_characters" => message["content"].to_s.length)
    [response, latency]
  end

  private

  def generation_limit = 1536
  def max_generations = @candidate == "gemma4-e4b-it" ? 54 : 36

  def prepare_payload(payload)
    payload = super
    controls = @calibration_controls
    return payload unless controls
    raise Abort, "Invalid calibration metadata" unless controls.is_a?(Hash) &&
      controls["seed"].is_a?(Integer) && controls["seed"].between?(840_001, 841_082) &&
      [true, false].include?(controls["thinking"])
    raise Abort, "Thinking is only approved for Gemma" if controls["thinking"] && @candidate != "gemma4-e4b-it"
    payload["seed"] = controls.fetch("seed")
    if @candidate == "gemma4-e4b-it"
      payload["chat_template_kwargs"] = { "enable_thinking" => controls.fetch("thinking") }
      # This is llama.cpp's model-agnostic split-field format name, not a
      # DeepSeek model, dependency, template, or external provider.
      payload["reasoning_format"] = "deepseek"
    end
    payload
  end

  def json_http(path, payload = nil, **options)
    result = super
    if path == "/apply-template" && @calibration_controls && @candidate == "gemma4-e4b-it"
      activated = result.fetch("prompt").include?("<|think|>")
      raise Abort, "Native thinking template does not match declared condition" unless activated == @calibration_controls.fetch("thinking")
    end
    result
  end

  def client(root)
    CalibrationClient.new(owner: self, root: root, env: { "SOUL_LOCAL_OPENAI_DIALECT" => "llamacpp" })
  end

  def evaluate(root, &block)
    SoulCore::ChatReplacementCalibrationEvaluator.new(root: root, client: client(root), provider: provider,
      temperature: @asset.fetch("temperature"), reasoning_mode: @asset.fetch("reasoning_mode")).run(&block)
  end

  def source_hashes
    super.merge([__FILE__, File.join(__dir__, "support/chat_replacement_calibration_cases.rb"),
      File.join(__dir__, "support/chat_replacement_calibration_evaluator.rb")].to_h do |path|
        [path.delete_prefix("#{ROOT}/"), Digest::SHA256.file(path).hexdigest]
      end)
  end

  def thinking_probe
    if %w[constraint-v2 interface-v3].include?(@probe_revision)
      {
        "revision" => @probe_revision,
        "prompt" => "Six fictional teams (Aster, Birch, Cedar, Dune, Elm, Frost) occupy positions 1 through 6, one team per position. Frost is immediately before Birch. Dune is immediately before Elm. Aster is earlier than Cedar, and Cedar is earlier than Frost. Birch is exactly three positions after Aster (for example, if Aster were first, Birch would be fourth). Elm is later than Birch. Find the unique first-to-last ordering satisfying every constraint. Give the order on the first line in the form ORDER: name, name, name, name, name, name. You may add a short explanation after that.",
        "answer" => "ORDER: Aster, Cedar, Frost, Birch, Dune, Elm"
      }
    else
      {
        "revision" => "simple-v1",
        "prompt" => "A fictional tray has 19 red tokens and 23 green tokens. How many tokens in total? Give the total as a numeral only.",
        "answer" => "42"
      }
    end
  end

  def thinking_answer_valid?(content)
    probe = thinking_probe
    text = content.to_s.strip
    probe.fetch("revision") == "simple-v1" ? text == probe.fetch("answer") : text.lines.first.to_s.strip == probe.fetch("answer")
  end

  def feasibility
    save("calibration-design.json", "protocol" => @protocol_id, "max_generations" => max_generations,
      "generation_limit" => generation_limit, "context_limit" => CONTEXT,
      "thinking_feasibility_probe" => thinking_probe,
      "semantic_admission_required" => @probe_revision != "interface-v3",
      "scored_samples" => @candidate == "gemma4-e4b-it" ? 48 : 32,
      "fresh_context_each_sample" => true, "no_actual_tools" => true,
      "equal_token_ceiling_not_equal_compute" => true)
    super
    return unless @candidate == "gemma4-e4b-it"
    root = Dir.mktmpdir("thinking-feasibility-", @output)
    probe_client = client(root)
    observations = []
    [true, false].each_with_index do |thinking, index|
      controls = { "thinking" => thinking, "seed" => 840_001 + index,
        "condition" => "feasibility-#{thinking ? 'thinking' : 'direct'}", "context_mode" => "feasibility" }
      request = Contract::RequestEnvelope.new(conversation_id: "thinking-feasibility-#{index}",
        messages: [{ "role" => "system", "content" => "You are a concise assistant. Use only supplied evidence." },
          { "role" => "user", "content" => thinking_probe.fetch("prompt") }],
        model: @candidate, temperature: @asset.fetch("temperature"), max_output_tokens: generation_limit,
        reasoning_mode: thinking ? "default" : "disabled", metadata: { "calibration" => controls })
      answer = probe_client.chat(provider: provider, request: request)
      capture = JSON.parse(File.read(File.join(@output, format("request-%02d-calibration.json", @generation_count))))
      observation = {
        "thinking" => thinking, "answer_correct" => thinking_answer_valid?(answer.content),
        "semantic_admission_required" => @probe_revision != "interface-v3",
        "finish_reason" => answer.finish_reason, "response_error" => answer.error,
        "tool_call_count" => answer.tool_calls.length, "final_present" => !answer.content.to_s.strip.empty?,
        "reasoning_present" => capture.fetch("reasoning_present")
      }
      observations << observation
      save("thinking-probe-#{index + 1}.json", observation)
      raise Abort, "Thinking-mode feasibility response failed" unless answer.error.nil? &&
        answer.finish_reason == "stop" && answer.tool_calls.empty? && observation.fetch("final_present")
      raise Abort, "Thinking-mode output separation failed" unless capture.fetch("reasoning_present") == thinking
      # This revision qualifies the native transport/mode path, not the model's
      # puzzle-solving ability. Keep semantic errors as observations rather than
      # selecting only successful modes into the scored comparison.
      if observation.fetch("semantic_admission_required") && !observation.fetch("answer_correct")
        raise Abort, "Thinking-mode feasibility response failed"
      end
    end
    save("thinking-feasibility.json", "state" => "passed", "probes" => 2, "probe_revision" => thinking_probe.fetch("revision"),
      "activation_and_split_output_verified" => true, "separate_from_scored_cases" => true,
      "semantic_admission_required" => @probe_revision != "interface-v3", "observations" => observations)
  end
end

if $PROGRAM_NAME == __FILE__
  revisions = { "--approved-calibration" => "simple-v1", "--approved-gemma-probe2" => "constraint-v2",
    "--approved-gemma-interface3" => "interface-v3" }
  abort "Usage: run-chat-replacement-calibration.rb (#{revisions.keys.join(' | ')}) CANDIDATE ASSETS_DIRECTORY" unless
    ARGV.length == 3 && revisions.key?(ARGV[0])
  revision = revisions.fetch(ARGV[0])
  exit(ChatReplacementCalibration.new(candidate: ARGV[1], assets: ARGV[2], probe_revision: revision).run ? 0 : 1)
end
