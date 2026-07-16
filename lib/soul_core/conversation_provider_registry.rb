# frozen_string_literal: true

require_relative "conversation_provider_contract"

module SoulCore
  class ConversationProviderRegistry
    Contract = ConversationProviderContract

    def initialize(env: ENV)
      @env = env
    end

    def providers
      @providers ||= [
        local_openai_compatible,
        local_ollama,
        cloud_openai_compatible
      ].freeze
    end

    def find(provider_id)
      providers.find { |provider| provider.id == provider_id.to_s }
    end

    def configured
      providers.select(&:configured?)
    end

    def local
      providers.select { |provider| %w[local_only local_network].include?(provider.privacy_class) }
    end

    def cloud
      providers.select { |provider| provider.privacy_class == "cloud" }
    end

    def summary
      {
        "provider_count" => providers.length,
        "configured_count" => configured.length,
        "local_count" => local.length,
        "cloud_count" => cloud.length,
        "providers" => providers.map(&:to_h)
      }
    end

    private

    def local_openai_compatible
      model = first_present(
        @env["SOUL_LOCAL_OPENAI_MODEL"],
        @env["SOUL_LOCAL_MODEL"],
        @env["SOUL_MODEL_ALIAS"]
      )

      Contract::ProviderDefinition.new(
        id: "local.openai_compatible",
        label: "Local OpenAI-compatible provider",
        transport: "openai_compatible",
        endpoint: first_present(
          @env["SOUL_LOCAL_OPENAI_BASE_URL"],
          @env["OPENAI_BASE_URL"],
          @env["SOUL_OPENAI_BASE_URL"],
          "http://127.0.0.1:8080/v1"
        ),
        model: model.to_s,
        privacy_class: "local_only",
        capabilities: %w[chat streaming tools structured_output reasoning_control],
        configured: !model.to_s.empty?,
        metadata: {
          "source" => "environment",
          "model_env" => "SOUL_LOCAL_OPENAI_MODEL",
          "endpoint_env" => "SOUL_LOCAL_OPENAI_BASE_URL"
        }
      )
    end

    def local_ollama
      model = first_present(
        @env["SOUL_OLLAMA_MODEL"],
        @env["OLLAMA_MODEL"]
      )

      Contract::ProviderDefinition.new(
        id: "local.ollama",
        label: "Local Ollama provider",
        transport: "ollama",
        endpoint: first_present(
          @env["OLLAMA_HOST"],
          "http://127.0.0.1:11434"
        ),
        model: model.to_s,
        privacy_class: "local_only",
        capabilities: %w[chat streaming structured_output reasoning_control],
        configured: !model.to_s.empty?,
        metadata: {
          "source" => "environment",
          "model_env" => "SOUL_OLLAMA_MODEL",
          "endpoint_env" => "OLLAMA_HOST"
        }
      )
    end

    def cloud_openai_compatible
      endpoint = first_present(@env["SOUL_CLOUD_OPENAI_BASE_URL"])
      model = first_present(@env["SOUL_CLOUD_OPENAI_MODEL"])
      credential_env = first_present(
        @env["SOUL_CLOUD_OPENAI_CREDENTIAL_ENV"],
        "SOUL_CLOUD_OPENAI_API_KEY"
      )
      credential_present = !@env[credential_env].to_s.empty?

      Contract::ProviderDefinition.new(
        id: "cloud.openai_compatible",
        label: "Cloud OpenAI-compatible provider",
        transport: "openai_compatible",
        endpoint: endpoint.to_s,
        model: model.to_s,
        privacy_class: "cloud",
        capabilities: %w[chat streaming tools structured_output],
        configured: !endpoint.to_s.empty? && !model.to_s.empty? && credential_present,
        credential_env: credential_env,
        metadata: {
          "source" => "environment",
          "endpoint_env" => "SOUL_CLOUD_OPENAI_BASE_URL",
          "model_env" => "SOUL_CLOUD_OPENAI_MODEL",
          "credential_present" => credential_present
        }
      )
    end

    def first_present(*values)
      values.find { |value| !value.nil? && !value.to_s.empty? }
    end
  end
end
