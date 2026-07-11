# frozen_string_literal: true

require "json"
require "securerandom"
require "time"

module SoulCore
  class ConversationProviderContract
    TRANSPORTS = %w[openai_compatible ollama].freeze
    PRIVACY_CLASSES = %w[local_only local_network cloud].freeze
    MESSAGE_ROLES = %w[system user assistant tool].freeze
    CAPABILITIES = %w[chat streaming tools structured_output embeddings].freeze

    class ProviderDefinition
      attr_reader :id,
                  :label,
                  :transport,
                  :endpoint,
                  :model,
                  :privacy_class,
                  :capabilities,
                  :configured,
                  :credential_env,
                  :metadata

      def initialize(
        id:,
        label:,
        transport:,
        endpoint:,
        model:,
        privacy_class:,
        capabilities:,
        configured:,
        credential_env: nil,
        metadata: {}
      )
        @id = id.to_s
        @label = label.to_s
        @transport = transport.to_s
        @endpoint = endpoint.to_s
        @model = model.to_s
        @privacy_class = privacy_class.to_s
        @capabilities = Array(capabilities).map(&:to_s).uniq.freeze
        @configured = configured == true
        @credential_env = credential_env&.to_s
        @metadata = stringify_keys(metadata).freeze
        validate!
      end

      def configured?
        @configured
      end

      def supports?(capability)
        @capabilities.include?(capability.to_s)
      end

      def to_h
        {
          "id" => id,
          "label" => label,
          "transport" => transport,
          "endpoint" => endpoint,
          "model" => model,
          "privacy_class" => privacy_class,
          "capabilities" => capabilities,
          "configured" => configured?,
          "credential_env" => credential_env,
          "metadata" => metadata
        }.reject { |_key, value| value.nil? }
      end

      private

      def validate!
        errors = []
        errors << "provider id is required" if id.empty?
        errors << "provider label is required" if label.empty?
        errors << "unsupported transport: #{transport}" unless TRANSPORTS.include?(transport)
        errors << "unsupported privacy class: #{privacy_class}" unless PRIVACY_CLASSES.include?(privacy_class)
        invalid_capabilities = capabilities - CAPABILITIES
        errors << "unsupported capabilities: #{invalid_capabilities.join(', ')}" unless invalid_capabilities.empty?
        raise ArgumentError, errors.join("; ") unless errors.empty?
      end

      def stringify_keys(hash)
        hash.each_with_object({}) do |(key, value), output|
          output[key.to_s] = value
        end
      end
    end

    class RequestEnvelope
      attr_reader :request_id,
                  :conversation_id,
                  :messages,
                  :model,
                  :temperature,
                  :max_output_tokens,
                  :tools,
                  :privacy_requirement,
                  :metadata,
                  :created_at

      def initialize(
        conversation_id:,
        messages:,
        model: nil,
        temperature: nil,
        max_output_tokens: nil,
        tools: [],
        privacy_requirement: "local_only",
        metadata: {},
        request_id: SecureRandom.uuid,
        created_at: Time.now.iso8601
      )
        @request_id = request_id.to_s
        @conversation_id = conversation_id.to_s
        @messages = normalize_messages(messages).freeze
        @model = model&.to_s
        @temperature = temperature
        @max_output_tokens = max_output_tokens
        @tools = Array(tools).map { |tool| stringify_keys(tool) }.freeze
        @privacy_requirement = privacy_requirement.to_s
        @metadata = stringify_keys(metadata).freeze
        @created_at = created_at.to_s
      end

      def validation_errors
        errors = []
        errors << "request_id is required" if request_id.empty?
        errors << "conversation_id is required" if conversation_id.empty?
        errors << "messages must not be empty" if messages.empty?
        errors << "unsupported privacy requirement: #{privacy_requirement}" unless PRIVACY_CLASSES.include?(privacy_requirement)

        messages.each_with_index do |message, index|
          role = message["role"].to_s
          content = message["content"]
          errors << "message #{index} has unsupported role: #{role}" unless MESSAGE_ROLES.include?(role)
          errors << "message #{index} content must be a string" unless content.is_a?(String)
        end

        if !temperature.nil? && (!temperature.is_a?(Numeric) || temperature.negative? || temperature > 2.0)
          errors << "temperature must be between 0.0 and 2.0"
        end

        if !max_output_tokens.nil? && (!max_output_tokens.is_a?(Integer) || max_output_tokens <= 0)
          errors << "max_output_tokens must be a positive integer"
        end

        errors
      end

      def valid?
        validation_errors.empty?
      end

      def to_h
        {
          "request_id" => request_id,
          "conversation_id" => conversation_id,
          "messages" => messages,
          "model" => model,
          "temperature" => temperature,
          "max_output_tokens" => max_output_tokens,
          "tools" => tools,
          "privacy_requirement" => privacy_requirement,
          "metadata" => metadata,
          "created_at" => created_at
        }.reject { |_key, value| value.nil? }
      end

      def to_json(*args)
        JSON.generate(to_h, *args)
      end

      private

      def normalize_messages(items)
        Array(items).map { |message| stringify_keys(message) }
      end

      def stringify_keys(hash)
        hash.each_with_object({}) do |(key, value), output|
          output[key.to_s] = value
        end
      end
    end

    class ResponseEnvelope
      attr_reader :request_id,
                  :provider_id,
                  :model,
                  :content,
                  :finish_reason,
                  :usage,
                  :tool_calls,
                  :latency_ms,
                  :error,
                  :metadata,
                  :created_at

      def initialize(
        request_id:,
        provider_id:,
        model:,
        content:,
        finish_reason: nil,
        usage: {},
        tool_calls: [],
        latency_ms: nil,
        error: nil,
        metadata: {},
        created_at: Time.now.iso8601
      )
        @request_id = request_id.to_s
        @provider_id = provider_id.to_s
        @model = model.to_s
        @content = content.to_s
        @finish_reason = finish_reason&.to_s
        @usage = stringify_keys(usage).freeze
        @tool_calls = Array(tool_calls).map { |call| stringify_keys(call) }.freeze
        @latency_ms = latency_ms
        @error = error && stringify_keys(error)
        @metadata = stringify_keys(metadata).freeze
        @created_at = created_at.to_s
      end

      def validation_errors
        errors = []
        errors << "request_id is required" if request_id.empty?
        errors << "provider_id is required" if provider_id.empty?
        errors << "model is required" if model.empty?
        errors << "content must be a string" unless content.is_a?(String)
        errors << "latency_ms must be non-negative" if !latency_ms.nil? && (!latency_ms.is_a?(Numeric) || latency_ms.negative?)
        errors
      end

      def valid?
        validation_errors.empty?
      end

      def success?
        error.nil?
      end

      def to_h
        {
          "request_id" => request_id,
          "provider_id" => provider_id,
          "model" => model,
          "content" => content,
          "finish_reason" => finish_reason,
          "usage" => usage,
          "tool_calls" => tool_calls,
          "latency_ms" => latency_ms,
          "error" => error,
          "metadata" => metadata,
          "created_at" => created_at
        }.reject { |_key, value| value.nil? }
      end

      def to_json(*args)
        JSON.generate(to_h, *args)
      end

      private

      def stringify_keys(hash)
        hash.each_with_object({}) do |(key, value), output|
          output[key.to_s] = value
        end
      end
    end
  end
end
