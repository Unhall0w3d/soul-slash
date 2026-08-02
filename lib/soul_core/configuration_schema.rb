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
        setting("providers.local_openai.dialect", "SOUL_LOCAL_OPENAI_DIALECT", :enum, "", values: ["", "auto", "ollama"], effect: "Selects the bounded request dialect for a local OpenAI-compatible endpoint; auto follows the reviewed runtime profile."),
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
        setting("dashboard.bind_host", "SOUL_DASHBOARD_BIND_HOST", :loopback_host, "127.0.0.1", effect: "Defines the loopback bind host used by the current foreground Dashboard.", risk: "The Dashboard accepts loopback only."),
        setting("dashboard.port", "SOUL_DASHBOARD_PORT", :integer, 4567, range: 1..65_535, effect: "Defines the port used by the current foreground Dashboard."),
        setting("dashboard.public_origin", "SOUL_DASHBOARD_PUBLIC_ORIGIN", :https_origin, "", allow_empty: true, effect: "Allows one exact HTTPS reverse-proxy origin while Soul remains loopback-bound.", risk: "Enables secure remote browser authority only; does not widen the Soul listener."),
        setting("maintenance.a2_live", "SOUL_MAINTENANCE_A2_LIVE", :boolean, false, effect: "Keeps the reviewed A2 foreground package executor disabled until a supervised live-run gate.", risk: "Enabling permits one digest-bound visible update transaction; A2 still cannot reboot."),
        setting("maintenance.a3_live", "SOUL_MAINTENANCE_A3_LIVE", :boolean, false, effect: "Keeps the distinct reboot-only and one-shot restoration path disabled until a supervised A3 gate.", risk: "Enabling permits one exact reviewed transaction with empty package-command vectors to request a reboot after durable snapshot capture."),
        setting("maintenance.passwordless", "SOUL_MAINTENANCE_PASSWORDLESS", :boolean, false, effect: "Uses the separately installed root-owned fixed-operation authority for unattended local maintenance.", risk: "Any process already running as the desktop owner may request the same fixed full-update operation; arbitrary commands, targets, flags, paths, and answers remain prohibited."),
        setting("maintenance.remote_live", "SOUL_MAINTENANCE_REMOTE_LIVE", :boolean, false, effect: "Keeps Forge and Pi-hole package and reboot execution disabled until a supervised device-scoped gate.", risk: "Enabling permits one exact fixed-target SSH mutation after device-specific preview and confirmation."),
        setting("maintenance.fleet.workstation_address", "SOUL_FLEET_WORKSTATION_ADDRESS", :string, "local", aliases: %w[SOUL_FLEET_MAVEN_ADDRESS], effect: "Provides a display-only workstation address or label for the fleet dashboard."),
        setting("maintenance.fleet.workstation_label", "SOUL_FLEET_WORKSTATION_LABEL", :string, "Workstation", aliases: %w[SOUL_FLEET_MAVEN_LABEL], effect: "Provides the human-readable workstation label while the portable internal identity remains workstation."),
        setting("maintenance.fleet.forge_address", "SOUL_FLEET_FORGE_ADDRESS", :string, "proxmox-maintenance", effect: "Provides a display-only Forge address or SSH-alias label for the fleet dashboard."),
        setting("maintenance.fleet.foundry_control_enabled", "SOUL_FLEET_FOUNDRY_CONTROL_ENABLED", :boolean, false, effect: "Promotes only the enrolled Proxmox record matching the configured Foundry SSH alias into the fixed device controller.", risk: "Enabling exposes preview-gated Foundry package maintenance and reboot controls; live execution still requires SOUL_MAINTENANCE_REMOTE_LIVE."),
        setting("maintenance.fleet.foundry_address", "SOUL_FLEET_FOUNDRY_ADDRESS", :string, "foundry", effect: "Provides a display-only Foundry address or SSH-alias label for the fleet dashboard."),
        setting("maintenance.fleet.foundry_label", "SOUL_FLEET_FOUNDRY_LABEL", :string, "Foundry", effect: "Provides the human-readable label for the separately enrolled Foundry Proxmox host."),
        setting("maintenance.fleet.foundry_ssh_alias", "SOUL_FLEET_FOUNDRY_SSH_ALIAS", :string, "foundry", effect: "Selects one exact literal owner-local SSH Host alias for Foundry's fixed controller.", risk: "The alias must refer to the separately reviewed root Proxmox maintenance identity; request data can never override it."),
        setting("maintenance.fleet.pihole_address", "SOUL_FLEET_PIHOLE_ADDRESS", :string, "pihole-maintenance", effect: "Provides a display-only Pi-hole address or SSH-alias label for the fleet dashboard."),
        setting("maintenance.fleet.pihole_label", "SOUL_FLEET_PIHOLE_LABEL", :string, "Pi-hole", effect: "Provides a human-readable appliance label while preserving its Pi-hole role and stable internal device identity."),
        setting("maintenance.fleet.cisco_phone_enabled", "SOUL_FLEET_CISCO_PHONE_ENABLED", :boolean, false, effect: "Adds one optional status-only Cisco phone to bounded fleet collection.", risk: "The configured LAN address receives one bounded ICMP reachability probe per fleet collection."),
        setting("maintenance.fleet.cisco_phone_address", "SOUL_FLEET_CISCO_PHONE_ADDRESS", :string, "", effect: "Selects the exact IPv4 address or hostname for the optional Cisco phone probe.", risk: "Keep private network addresses in ignored local configuration."),
        setting("maintenance.fleet.cisco_phone_label", "SOUL_FLEET_CISCO_PHONE_LABEL", :string, "Cisco 8851", effect: "Provides the human-readable label for the optional status-only Cisco phone."),
        setting("maintenance.fleet.chancery_enabled", "SOUL_FLEET_CHANCERY_ENABLED", :boolean, false, effect: "Adds one optional read-only host-local WinBoat/Windows identity to fleet status.", risk: "The adapter reads fixed Docker state, address, and port-binding fields only; it never inspects container environment data or grants guest mutation authority."),
        setting("maintenance.fleet.chancery_label", "SOUL_FLEET_CHANCERY_LABEL", :string, "Chancery", effect: "Provides the human-readable label for the host-local Windows work environment."),
        setting("maintenance.fleet.chancery_fqdn", "SOUL_FLEET_CHANCERY_FQDN", :string, "", effect: "Provides the private logical FQDN displayed for the Windows work environment.", risk: "Keep deployment-specific internal names in ignored local configuration."),
        setting("maintenance.fleet.chancery_guest_address", "SOUL_FLEET_CHANCERY_GUEST_ADDRESS", :string, "172.30.0.2", effect: "Records the fixed private guest address inside WinBoat's isolated QEMU network; this does not modify networking."),
        setting("maintenance.fleet.chancery_container_name", "SOUL_FLEET_CHANCERY_CONTAINER_NAME", :string, "WinBoat", effect: "Selects the exact local Docker container inspected by the read-only WinBoat adapter."),
        setting("voice.transcription.runtime_root", "SOUL_VOICE_TRANSCRIPTION_ROOT", :string, "", effect: "Overrides the user-local root containing Soul's pinned foreground transcription runtime."),
        setting("voice.transcription.manifest", "SOUL_VOICE_TRANSCRIPTION_MANIFEST", :string, "", effect: "Overrides the repository transcription manifest used by Chat push-to-talk."),
        setting("voice.transcription.model", "SOUL_VOICE_TRANSCRIPTION_MODEL", :string, "ggml-small.en.bin", effect: "Selects one exact model filename declared by the transcription manifest."),
        setting("voice.synthesis.runtime_root", "SOUL_VOICE_SYNTHESIS_ROOT", :string, "", effect: "Overrides the user-local root containing Soul's pinned foreground synthesis runtime."),
        setting("voice.synthesis.manifest", "SOUL_VOICE_SYNTHESIS_MANIFEST", :string, "", effect: "Overrides the repository synthesis manifest used by Chat message playback."),
        setting("voice.synthesis.voice", "SOUL_VOICE_SYNTHESIS_VOICE", :enum, "F3", values: %w[F1 F2 F3 F4 F5 M1 M2 M3 M4 M5], effect: "Selects one exact default voice profile declared by the synthesis manifest."),
        setting("voice.synthesis.speed", "SOUL_VOICE_SYNTHESIS_SPEED", :float, 1.0, range: 0.7..2.0, effect: "Controls the bounded local speaking-rate multiplier."),
        setting("voice.synthesis.expressive_root", "SOUL_VOICE_EXPRESSIVE_ROOT", :string, "", effect: "Overrides the user-local root containing the pinned Chatterbox expressive runtime."),
        setting("voice.synthesis.expressive_manifest", "SOUL_VOICE_EXPRESSIVE_MANIFEST", :string, "", effect: "Overrides the repository manifest for bounded expressive speech."),
        setting("knowledge_vault.path", "SOUL_KNOWLEDGE_VAULT_PATH", :string, "", effect: "Selects an optional external Markdown knowledge vault shared with the human's preferred editor.", risk: "The vault may contain private project knowledge; no content is sent over the network or promoted into memory automatically.")
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
