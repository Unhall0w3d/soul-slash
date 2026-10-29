# frozen_string_literal: true

require "json"

module SoulCore
  # Pure wire-format boundary for the qualified llama.cpp chat endpoint. It owns
  # neither a connection nor a model process. The caller must attest the runtime,
  # hold its resource lease, enforce deadlines and durably record accepted replies.
  class RosterChatAdapter
    VERSION = "roster_chat_v1"
    MODELS = %w[gpt-oss-20b gemma-4-26b-a4b].freeze
    ISOLATED_MODELS = %w[qwen3.8-27b].freeze
    MAX_BYTES = 65_536
    class Invalid < StandardError; end
    class Unavailable < StandardError; end
    attr_reader :model, :mode, :context_tokens, :output_tokens

    def initialize(model:, mode: "conversation", context_tokens: 4096, output_tokens: 2048, isolated: false)
      raise Invalid, "explicit isolation flag required" unless [true, false].include?(isolated)
      raise Invalid, "unsupported roster model" unless MODELS.include?(model) || (isolated && ISOLATED_MODELS.include?(model))
      raise Invalid, "unsupported mode" unless %w[conversation work deliberate].include?(mode)
      raise Invalid, "unsupported context" unless [4096, 8192].include?(context_tokens)
      raise Invalid, "unsupported output allowance" unless [1024, 2048, 4096].include?(output_tokens) && output_tokens + 32 < context_tokens
      @model, @mode = model.dup.freeze, mode.dup.freeze
      @context_tokens, @output_tokens = context_tokens, output_tokens
      freeze
    end

    def native_controls
      if model == "gpt-oss-20b"
        { "reasoning_effort" => mode == "conversation" ? "low" : "medium" }
      elsif model == "qwen3.8-27b"
        { "enable_thinking" => mode == "deliberate", "preserve_thinking" => false,
          "reasoning_effort" => "low" }
      else
        # Work does not silently enable the thinking mode that exhausted its
        # allowance in qualification. Deliberate remains an explicit experiment.
        { "enable_thinking" => mode == "deliberate" }
      end
    end

    def binding
      { "version" => VERSION, "model" => model, "mode" => mode,
        "context_tokens" => context_tokens, "output_tokens" => output_tokens,
        "native_controls" => native_controls }
    end

    def payload(messages:)
      unless messages.is_a?(Array) && messages.length.between?(1, 64) && messages.all? { |m|
        m.is_a?(Hash) && m.keys.sort == %w[content role] &&
          %w[system user assistant].include?(m["role"]) && text?(m["content"])
      } && messages.last["role"] == "user"
        raise Invalid, "bounded text-only conversation required"
      end
      raise Invalid, "message budget exceeded" if JSON.generate(messages).bytesize > MAX_BYTES
      # This native template accepts system instructions only at the beginning.
      # Reject rather than relocating a late instruction across trust boundaries.
      if model == "qwen3.8-27b" && messages.drop(1).any? { |m| m["role"] == "system" }
        raise Invalid, "Qwen system message must be first"
      end
      # Snapshot the caller's messages; later edits must not change the request
      # whose native template was token-counted for admission.
      result = { "model" => model, "messages" => JSON.parse(JSON.generate(messages)),
        "max_tokens" => output_tokens, "stream" => false, "cache_prompt" => false,
        "temperature" => 1.0, "top_p" => 0.95, "chat_template_kwargs" => native_controls }
      result["top_k"] = 64 if model == "gemma-4-26b-a4b"
      if model == "qwen3.8-27b"
        thinking = mode == "deliberate"
        result.merge!("temperature" => thinking ? 1.0 : 0.7, "top_p" => thinking ? 0.95 : 0.8,
          "top_k" => 20, "min_p" => 0.0, "repeat_penalty" => 1.0,
          "presence_penalty" => thinking ? 0.0 : 1.5)
      end
      result
    end

    def validate_input_tokens!(tokens)
      unless tokens.is_a?(Array) && !tokens.empty? && tokens.all? { |v| v.is_a?(Integer) && v >= 0 }
        raise Invalid, "invalid native tokenization"
      end
      # The qualified Gemma GGUF has add_bos_token=true. /apply-template omits
      # BOS and our /tokenize call uses add_special=false; chat completion adds
      # it. GPT-OSS has no corresponding overhead. Keep the correction exact.
      count = tokens.length + (model == "gemma-4-26b-a4b" ? 1 : 0)
      raise Invalid, "context allowance exceeded" if count + output_tokens > context_tokens - 32
      count
    end

    def final_reply(response)
      unless response.is_a?(Hash) && !response.key?("error") && response["model"] == model &&
             response["choices"].is_a?(Array) && response["choices"].length == 1
        raise Unavailable, "invalid response identity or choices"
      end
      choice = response["choices"].first
      raise Unavailable, "invalid choice" unless choice.is_a?(Hash) && choice["index"] == 0
      raise Unavailable, "incomplete or non-answer completion" unless choice["finish_reason"] == "stop"
      message = choice["message"]
      unless message.is_a?(Hash) && message["role"] == "assistant" &&
             (!message.key?("tool_calls") || message["tool_calls"] == []) &&
             !message.key?("function_call") && text?(message["content"]) && !message["content"].strip.empty?
        raise Unavailable, "final text absent or unexpected tool request"
      end
      usage = response["usage"]
      unless usage.is_a?(Hash) && %w[prompt_tokens completion_tokens total_tokens].all? { |k| usage[k].is_a?(Integer) && usage[k] >= 0 } &&
             usage["completion_tokens"].between?(1, output_tokens) &&
             usage["prompt_tokens"] + usage["completion_tokens"] == usage["total_tokens"] &&
             usage["prompt_tokens"] + output_tokens <= context_tokens - 32
        raise Unavailable, "invalid or excessive token usage"
      end
      # No reasoning field is returned, interpreted as an action, or used as a
      # fallback when final text is absent. JSON-looking prose remains prose.
      { "content" => message["content"].dup, "model" => model,
        "usage" => usage.slice("prompt_tokens", "completion_tokens", "total_tokens"),
        "adapter" => binding }
    end

    private

    def text?(value)
      value.is_a?(String) && value.encoding == Encoding::UTF_8 && value.valid_encoding? && value.bytesize <= MAX_BYTES
    end
  end
end
