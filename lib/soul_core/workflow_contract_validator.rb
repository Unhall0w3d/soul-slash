# frozen_string_literal: true

module SoulCore
  class WorkflowContractValidator
    Result = Struct.new(:valid, :errors, :warnings, :metadata, keyword_init: true)

    def validate_handler(handler)
      errors = []
      warnings = []

      unless handler
        return Result.new(valid: false, errors: ["handler missing"], warnings: [], metadata: {})
      end

      errors << "missing run(parameters:, original_text:)" unless handler.respond_to?(:run)
      warnings << (handler.respond_to?(:match_intent) ? "owns intent matching" : "does not own intent matching")

      if handler.respond_to?(:responds_to_status?)
        warnings << "owns response status matching"
        errors << "missing respond(state:, text:)" unless handler.respond_to?(:respond)
      else
        warnings << "does not own response lifecycle"
      end

      Result.new(
        valid: errors.empty?,
        errors: errors,
        warnings: warnings,
        metadata: {
          "handler" => handler.class.name,
          "intent" => safe_intent(handler),
          "run" => handler.respond_to?(:run),
          "match_intent" => handler.respond_to?(:match_intent),
          "responds_to_status" => handler.respond_to?(:responds_to_status?),
          "respond" => handler.respond_to?(:respond)
        }
      )
    end

    def validate_registry(registry)
      checks = {}

      registry.handlers.each do |handler|
        result = validate_handler(handler)
        checks[handler.intent] = {
          "valid" => result.valid,
          "errors" => result.errors,
          "warnings" => result.warnings,
          "metadata" => result.metadata
        }
      end

      {
        "valid" => checks.values.all? { |value| value["valid"] },
        "handlers_checked" => checks.length,
        "handlers" => checks
      }
    end

    def validate_registry!(registry)
      result = validate_registry(registry)
      return result if result.fetch("valid")

      details = result.fetch("handlers").flat_map do |intent, handler|
        handler.fetch("errors", []).map { |error| "#{intent}: #{error}" }
      end

      raise "Workflow handler contract validation failed: #{details.join('; ')}"
    end

    def health_report(registry)
      result = validate_registry(registry)
      valid_count = result.fetch("handlers").values.count { |handler| handler.fetch("valid") }
      blocked_count = result.fetch("handlers").values.count { |handler| !handler.fetch("valid") }

      lines = []
      lines << "Soul Workflow Contract Health"
      lines << ""

      result.fetch("handlers").each do |intent, handler|
        status = handler.fetch("valid") ? "OK" : "BLOCKED"
        metadata = handler.fetch("metadata", {})
        lines << "[#{status}] #{intent}"
        lines << "     Handler: #{metadata['handler'] || 'unknown'}"
        lines << "     Intent matching: #{metadata['match_intent'] ? 'owned' : 'not owned'}"
        lines << "     Run: #{metadata['run'] ? 'valid' : 'missing'}"
        lines << "     Respond: #{metadata['respond'] ? 'available' : 'not available'}"
        Array(handler["errors"]).each { |error| lines << "     Error: #{error}" }
        lines << ""
      end

      lines << "Summary:"
      lines << "#{result.fetch('handlers_checked')} workflows checked"
      lines << "#{valid_count} valid"
      lines << "#{blocked_count} blocked"

      {
        "valid" => result.fetch("valid"),
        "summary" => {
          "handlers_checked" => result.fetch("handlers_checked"),
          "valid" => valid_count,
          "blocked" => blocked_count
        },
        "result" => result,
        "message" => lines.join("\n")
      }
    end

    private

    def safe_intent(handler)
      handler.intent
    rescue StandardError
      nil
    end
  end
end
