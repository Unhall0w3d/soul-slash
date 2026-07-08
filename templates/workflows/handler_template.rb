# frozen_string_literal: true

# Template for a Soul workflow handler.
#
# Copy this file to:
#
#   lib/soul_core/workflows/<workflow_name>_handler.rb

require "fileutils"
require "json"
require "time"

require_relative "base_handler"

module SoulCore
  module Workflows
    class TemplateHandler < BaseHandler
      SESSION_ROOT = "Soul/workflows/sessions"

      HANDLED_STATUSES = [
        "waiting_for_template_confirmation"
      ].freeze

      def match_intent(text, result_class:)
        input = text.to_s.strip
        return nil unless input.downcase.include?("template workflow")

        result_class.new(
          ok: true,
          intent: intent,
          parameters: { "example" => input },
          confidence: 0.70,
          reason: "Matched template workflow phrasing.",
          source: "workflow_handler"
        )
      end

      def responds_to_status?(status)
        HANDLED_STATUSES.include?(status.to_s)
      end

      def run(parameters:, original_text:)
        state = base_state(
          status: "waiting_for_template_confirmation",
          original_text: original_text,
          parameters: parameters,
          next_expected: "template_confirmation",
          verification: {
            "write_attempted" => false,
            "requires_confirmation_before_write" => true,
            "complete" => false
          }
        )

        workflow_path = write_workflow_state(state)

        {
          ok: true,
          workflow_path: workflow_path,
          state: enrich_handler_state(state),
          user_message: render_confirmation(state)
        }
      end

      def respond(state:, text:)
        normalized = text.to_s.downcase.strip

        if normalized.include?("cancel")
          state["status"] = "cancelled"
          state["updated_at"] = Time.now.iso8601
          state["next_expected"] = "none"
          state["handler_response"] = handler_response_metadata("cancelled")
          state["verification"]["complete"] = false
          save_state(state)
          return { ok: true, message: "Template workflow cancelled.", state: state }
        end

        unless normalized.match?(/\byes\b|\bconfirm\b/)
          return { ok: false, message: render_confirmation(state), state: state }
        end

        state["status"] = "complete"
        state["updated_at"] = Time.now.iso8601
        state["next_expected"] = "reflection_offer"
        state["handler_response"] = handler_response_metadata("confirmed")
        state["verification"]["write_attempted"] = true
        state["verification"]["complete"] = true
        save_state(state)

        { ok: true, message: "Template workflow complete.", state: state }
      end

      private

      def base_state(status:, original_text:, parameters:, next_expected:, verification:, skill_runs: [])
        {
          "workflow" => intent,
          "status" => status,
          "generated_at" => Time.now.iso8601,
          "updated_at" => Time.now.iso8601,
          "original_text" => original_text,
          "parameters" => parameters,
          "skill_runs" => skill_runs,
          "next_expected" => next_expected,
          "verification" => verification
        }
      end

      def enrich_handler_state(state)
        state["handler_execution"] = {
          "checked" => true,
          "handler" => self.class.name,
          "intent" => intent,
          "delegated_to_existing_workflow_method" => false
        }
        save_state(state) if state["workflow_path"]
        state
      end

      def handler_response_metadata(action)
        {
          "checked" => true,
          "handler" => self.class.name,
          "intent" => intent,
          "action" => action,
          "handled_at" => Time.now.iso8601
        }
      end

      def write_workflow_state(state)
        FileUtils.mkdir_p(SESSION_ROOT)
        timestamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
        safe_intent = intent.gsub(/[^a-zA-Z0-9_.-]/, "_")
        path = File.join(SESSION_ROOT, "#{timestamp}-#{safe_intent}.json")
        state["workflow_path"] = path
        File.write(path, JSON.pretty_generate(state))
        path
      end

      def save_state(state)
        path = state.fetch("workflow_path")
        File.write(path, JSON.pretty_generate(state))
        path
      end

      def render_confirmation(_state)
        [
          "Template workflow is staged and waiting for confirmation.",
          "",
          '- `ruby bin/soul respond "yes"`',
          '- `ruby bin/soul respond "cancel"`'
        ].join("\n")
      end
    end
  end
end
