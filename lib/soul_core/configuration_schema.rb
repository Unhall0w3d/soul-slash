# frozen_string_literal: true

module SoulCore
  module ConfigurationSchema
    MAX_SETTINGS = 64

    module_function

    def definitions
      @definitions ||= build.freeze
    end

    def find(key)
      definitions.find { |definition| definition.fetch("key") == key.to_s }
    end

    def build
      definitions = [
        setting("conversation.provider", "SOUL_CONVERSATION_PROVIDER", :enum, "", values: ["", "local.openai_compatible", "local.ollama", "cloud.openai_compatible"], effect: "Selects the preferred conversation provider."),
        setting("conversation.mode", "SOUL_CONVERSATION_MODE", :enum, "auto", values: %w[auto model deterministic], effect: "Controls model-backed versus deterministic conversation routing."),
        setting("conversation.allow_cloud", "SOUL_ALLOW_CLOUD_CONVERSATION", :boolean, false, effect: "Explicitly opts conversation into eligible cloud providers.", risk: "Cloud transmission remains subject to provider and artifact privacy gates."),
        setting("conversation.max_messages", "SOUL_CONVERSATION_MAX_MESSAGES", :integer, 12, range: 1..100, effect: "Bounds recent messages supplied to a conversation request."),
        setting("conversation.max_characters", "SOUL_CONVERSATION_MAX_CHARACTERS", :integer, 24_000, range: 1_000..500_000, effect: "Bounds conversation-context characters."),
        setting("conversation.max_tool_steps", "SOUL_CONVERSATION_MAX_TOOL_STEPS", :integer, 4, range: 1..20, effect: "Bounds deterministic tool steps per turn."),
        setting("conversation.temperature", "SOUL_CONVERSATION_TEMPERATURE", :float, 0.65, range: 0.0..2.0, effect: "Controls model response variation."),
        setting("conversation.max_output_tokens", "SOUL_CONVERSATION_MAX_OUTPUT_TOKENS", :integer, 1_024, range: 1..32_768, effect: "Bounds model output tokens per conversation call."),
        setting("conversation.timeout_seconds", "SOUL_CONVERSATION_TIMEOUT_SECONDS", :float, 120.0, range: 1.0..600.0, effect: "Bounds one foreground provider request."),
        setting("artifact.approval_ttl_seconds", "SOUL_ARTIFACT_APPROVAL_TTL_SECONDS", :integer, 900, range: 30..86_400, effect: "Controls bounded artifact approval-token lifetime."),
        setting("artifact.max_output_tokens", "SOUL_ARTIFACT_MAX_OUTPUT_TOKENS", :integer, 4_096, range: 1..32_768, effect: "Bounds local-model artifact draft output."),
        setting("web_research.provider", "SOUL_WEB_SEARCH_PROVIDER", :enum, "", values: ["", "searxng", "brave"], effect: "Selects the explicitly configured bounded public-web search adapter.", risk: "Search sends validated query text only; source retrieval remains separately bounded."),
        setting("web_research.searxng_url", "SOUL_WEB_SEARXNG_URL", :url, "", allow_empty: true, effect: "Locates an explicit SearXNG JSON endpoint.", risk: "HTTP is accepted only for loopback or for the exact private endpoint enabled by SOUL_WEB_ALLOW_PRIVATE_SEARXNG; public endpoints require HTTPS."),
        setting("web_research.allow_private_searxng", "SOUL_WEB_ALLOW_PRIVATE_SEARXNG", :boolean, false, effect: "Allows the exact configured SearXNG provider to resolve to RFC1918 or ULA space.", risk: "This exception applies only to the search provider; retrieved result URLs remain public-HTTPS-only."),
        setting("web_research.brave_api_key", "SOUL_WEB_BRAVE_API_KEY", :secret, nil, effect: "Authenticates optional Brave Search API requests.", risk: "Secret; presence never authorizes source instructions or memory promotion.", secret: true),
        setting("providers.local_openai.endpoint", "SOUL_LOCAL_OPENAI_BASE_URL", :url, "http://127.0.0.1:8080/v1", aliases: %w[OPENAI_BASE_URL SOUL_OPENAI_BASE_URL], effect: "Locates a local OpenAI-compatible provider.", risk: "May point to an explicitly configured LAN host."),
        setting("providers.local_openai.model", "SOUL_LOCAL_OPENAI_MODEL", :string, "", aliases: %w[SOUL_LOCAL_MODEL SOUL_MODEL_ALIAS], effect: "Names the model exposed by the local OpenAI-compatible provider."),
        setting("providers.ollama.endpoint", "OLLAMA_HOST", :url, "http://127.0.0.1:11434", effect: "Locates a local Ollama provider.", risk: "May point to an explicitly configured LAN host."),
        setting("providers.ollama.model", "SOUL_OLLAMA_MODEL", :string, "", aliases: %w[OLLAMA_MODEL], effect: "Names the Ollama model used for conversation."),
        setting("providers.cloud_openai.endpoint", "SOUL_CLOUD_OPENAI_BASE_URL", :url, "", allow_empty: true, effect: "Locates an explicitly configured cloud OpenAI-compatible provider.", risk: "Cloud transmission requires separate explicit opt-in."),
        setting("providers.cloud_openai.model", "SOUL_CLOUD_OPENAI_MODEL", :string, "", effect: "Names the explicitly configured cloud model.", risk: "Cloud transmission requires separate explicit opt-in."),
        setting("providers.cloud_openai.credential_env", "SOUL_CLOUD_OPENAI_CREDENTIAL_ENV", :env_name, "SOUL_CLOUD_OPENAI_API_KEY", effect: "Names the environment variable containing the cloud credential.", risk: "The named secret is never returned through public configuration output."),
        setting("providers.cloud_openai.api_key", "SOUL_CLOUD_OPENAI_API_KEY", :secret, nil, effect: "Authenticates an explicitly configured cloud provider.", risk: "Secret; presence never authorizes cloud use.", secret: true),
        setting("model_runtime.control", "SOUL_MODEL_RUNTIME_CONTROL", :boolean, false, effect: "Allows preview-gated control of one existing local model user service.", risk: "Starting or stopping the configured model service requires authenticated exact confirmation."),
        setting("model_runtime.service", "SOUL_MODEL_RUNTIME_SERVICE", :string, "", effect: "Names the narrowly allowlisted systemd user service that owns the local model runtime.", risk: "Only llama-server.service or a soul-*.service unit is accepted by runtime control."),
        setting("model_runtime.slots_url", "SOUL_MODEL_RUNTIME_SLOTS_URL", :url, "http://127.0.0.1:8082/slots", effect: "Locates the loopback llama.cpp slots endpoint used to block unsafe unloads.", risk: "Runtime control accepts loopback HTTP only."),
        setting("model_runtime.profile", "SOUL_MODEL_RUNTIME_PROFILE", :string, "local-model", effect: "Provides a human-readable label for the currently configured model runtime profile."),
        setting("model_runtime.profiles_file", "SOUL_MODEL_RUNTIME_PROFILES_FILE", :string, "", effect: "Selects an ignored project-local YAML inventory of one to four manually controlled runtime profiles.", risk: "Profile files accept only IDs, labels, and narrowly allowlisted systemd user-service names."),
        setting("dashboard.bind_host", "SOUL_DASHBOARD_BIND_HOST", :loopback_host, "127.0.0.1", effect: "Defines the inert bind host reserved for the future foreground dashboard.", risk: "Phase 12 accepts loopback only."),
        setting("dashboard.port", "SOUL_DASHBOARD_PORT", :integer, 4567, range: 1..65_535, effect: "Defines the inert port reserved for the future foreground dashboard."),
        setting("dashboard.public_origin", "SOUL_DASHBOARD_PUBLIC_ORIGIN", :https_origin, "", allow_empty: true, effect: "Allows one exact HTTPS reverse-proxy origin while Soul remains loopback-bound.", risk: "Enables secure remote browser authority only; does not widen the Soul listener.")
      ]
      raise "configuration schema exceeds #{MAX_SETTINGS} settings" if definitions.length > MAX_SETTINGS

      definitions
    end

    def setting(key, env, type, default, aliases: [], values: nil, range: nil, allow_empty: false, effect:, risk: "Local runtime behavior only.", secret: false)
      {
        "key" => key,
        "environment" => env,
        "aliases" => aliases.freeze,
        "type" => type.to_s,
        "default" => default,
        "values" => values,
        "range" => range,
        "allow_empty" => allow_empty,
        "description" => effect,
        "behavioral_effect" => effect,
        "privacy_risk" => risk,
        "restart_required" => false,
        "secret" => secret
      }.freeze
    end
    private_class_method :build, :setting
  end
end
