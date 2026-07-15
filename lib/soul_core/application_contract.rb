# frozen_string_literal: true

require "json"

module SoulCore
  module ApplicationContract
    SCHEMA_VERSION = "soul.application.v1"
    MAX_REQUEST_BYTES = 128 * 1024
    MAX_STRING_BYTES = 64 * 1024
    MAX_KEYS = 64
    MAX_DEPTH = 8
    REQUEST_ID = /\A[A-Za-z0-9_.:-]{8,128}\z/
    CHAT_ID = /\Achat_[A-Za-z0-9_.-]+\z/
    ARTIFACT_ID = /\Aart_[A-Za-z0-9_.-]+\z/
    DELIVERY_ID = /\Adel_[A-Za-z0-9_.-]+\z/
    INTERFACES = %w[cli dashboard_test internal dashboard].freeze

    OPERATIONS = {
      "application.bootstrap" => [],
      "application.cancel" => [],
      "chats.list" => %w[limit],
      "chats.get" => %w[chat_id],
      "chats.messages" => %w[chat_id limit],
      "chats.create" => %w[title],
      "chats.send" => %w[chat_id message],
      "chats.pin" => %w[chat_id],
      "chats.unpin" => %w[chat_id],
      "workspace.list" => %w[kind lifecycle privacy delivery_state limit],
      "workspace.chat" => %w[chat_id kind lifecycle privacy delivery_state limit],
      "workspace.detail" => %w[artifact_id],
      "inbox.list" => %w[chat_id state limit],
      "inbox.deliver" => %w[chat_id artifact_id],
      "inbox.mark_seen" => %w[chat_id delivery_id],
      "inbox.dismiss" => %w[chat_id delivery_id],
      "system_status.refresh" => [],
      "configuration.show" => [],
      "configuration.explain" => %w[key],
      "configuration.validate" => [],
      "skills.list" => %w[limit],
      "approvals.pending" => %w[limit],
      "activities.recent" => %w[limit filters]
    }.freeze

    module_function

    def validate(request)
      return error("request must be an object") unless request.is_a?(Hash)
      return error("request keys must be strings") unless string_keys?(request)

      unknown = request.keys - %w[schema_version request_id operation parameters context]
      return error("request contains unknown fields") unless unknown.empty?

      schema = request["schema_version"]
      return error("schema_version is required", lifecycle: "awaiting_input") if schema.to_s.empty?
      return error("unsupported schema_version") unless schema == SCHEMA_VERSION

      request_id = request["request_id"].to_s
      return error("request_id is required", lifecycle: "awaiting_input") if request_id.empty?
      return error("request_id is invalid") unless request_id.match?(REQUEST_ID)

      operation = request["operation"].to_s
      return error("operation is required", lifecycle: "awaiting_input") if operation.empty?
      allowed_parameters = OPERATIONS[operation]
      return error("unknown application operation") unless allowed_parameters

      parameters = request.fetch("parameters", {})
      return error("parameters must be an object") unless parameters.is_a?(Hash) && string_keys?(parameters)
      unknown_parameters = parameters.keys - allowed_parameters
      return error("parameters contain unknown fields for #{operation}") unless unknown_parameters.empty?

      context = request.fetch("context", {})
      return error("context must be an object") unless context.is_a?(Hash) && string_keys?(context)
      unknown_context = context.keys - %w[interface current_chat_id]
      return error("context contains unknown fields") unless unknown_context.empty?
      interface = context.fetch("interface", "internal").to_s
      return error("context interface is invalid") unless INTERFACES.include?(interface)

      shape_error = validate_shape(request)
      return error(shape_error) if shape_error

      type_error = validate_parameter_types(parameters, context)
      return error(type_error) if type_error

      identity_error = validate_identities(parameters, context)
      return error(identity_error) if identity_error

      { "ok" => true, "request" => request, "interface" => interface }
    rescue JSON::GeneratorError, Encoding::UndefinedConversionError
      error("request must contain valid UTF-8 JSON values")
    end

    def validate_shape(value, depth = 0, counts = { keys: 0 })
      return "request nesting exceeds #{MAX_DEPTH}" if depth > MAX_DEPTH

      case value
      when Hash
        counts[:keys] += value.length
        return "request contains more than #{MAX_KEYS} keys" if counts[:keys] > MAX_KEYS
        value.each do |key, child|
          return "request keys must be strings" unless key.is_a?(String)
          failure = validate_shape(child, depth + 1, counts)
          return failure if failure
        end
      when Array
        value.each do |child|
          failure = validate_shape(child, depth + 1, counts)
          return failure if failure
        end
      when String
        return "request strings must be valid UTF-8" unless value.valid_encoding?
        return "request string exceeds #{MAX_STRING_BYTES} bytes" if value.bytesize > MAX_STRING_BYTES
      when NilClass, TrueClass, FalseClass, Integer, Float
        return "request numbers must be finite" if value.is_a?(Float) && !value.finite?
      else
        return "request contains unsupported value type"
      end
      return "request exceeds #{MAX_REQUEST_BYTES} bytes" if depth.zero? && JSON.generate(value).bytesize > MAX_REQUEST_BYTES

      nil
    end

    def validate_identities(parameters, context)
      chat_id = parameters["chat_id"] || context["current_chat_id"]
      return "chat_id is invalid" if chat_id && !chat_id.to_s.match?(CHAT_ID)
      artifact_id = parameters["artifact_id"]
      return "artifact_id is invalid" if artifact_id && !artifact_id.to_s.match?(ARTIFACT_ID)
      delivery_id = parameters["delivery_id"]
      return "delivery_id is invalid" if delivery_id && !delivery_id.to_s.match?(DELIVERY_ID)

      nil
    end

    def validate_parameter_types(parameters, context)
      parameters.each do |key, value|
        if key == "limit"
          return "limit must be an integer" unless value.is_a?(Integer)
        elsif key == "filters"
          return "filters must be an object" unless value.is_a?(Hash) && string_keys?(value)
        else
          return "#{key} must be a string" unless value.is_a?(String)
        end
      end
      if context.key?("interface") && !context["interface"].is_a?(String)
        return "context interface must be a string"
      end
      if context.key?("current_chat_id") && !context["current_chat_id"].is_a?(String)
        return "current_chat_id must be a string"
      end

      nil
    end

    def string_keys?(hash)
      hash.keys.all? { |key| key.is_a?(String) }
    end

    def error(reason, lifecycle: "failed")
      { "ok" => false, "lifecycle_state" => lifecycle, "reason" => reason }
    end
  end
end
