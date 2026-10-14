# frozen_string_literal: true

require_relative "actions"

module SoulCore
  module ContinuityLab
    # Scores a recorded synthetic event against an explicit evidence contract.
    # It only reads supplied values; it does not validate runtime authority or
    # turn a successful score into permission to perform an operation.
    module QualificationScorer
      def self.evaluate(event:, config:, lineage_id:, contract:, before_notes:, after_notes:)
        reasons = []
        matched = []
        unless valid_input?(event, config, lineage_id, contract, before_notes, after_notes)
          return result(false, "failed", ["malformed_input_or_contract"], matched)
        end

        resolved = resolve_lineage(contract, lineage_id)
        unless valid_contract?(resolved, config)
          return result(false, "failed", ["malformed_input_or_contract"], matched)
        end

        missing = subset_missing(resolved.fetch("requires_notes", {}), before_notes)
        unless missing.empty?
          return result(false, "unmet_prerequisite", ["required_before_notes_missing"], matched)
        end

        unless subset_missing(resolved.fetch("final_notes", {}), after_notes).empty?
          reasons << "required_final_notes_missing_or_mismatched"
        end

        terminal = terminal_match?(event, resolved)
        unless terminal
          state = event["state"]
          status = if state.nil? || state == "pending" || state == "blocked_for_human_review" || state == "awaiting_input"
                     "unmet_prerequisite"
                   else
                     "failed"
                   end
          return result(false, status, ["terminal_state_or_reply_mismatch"], matched)
        end

        steps = resolved.fetch("steps", [])
        calls = event.fetch("calls", [])
        matched, sequence_valid = match_steps(steps, calls, config)
        reasons << "successful_tool_call_order_or_evidence_mismatch" unless sequence_valid
        if reasons.empty? && !omission_match?(resolved, steps, calls, matched, config)
          reasons << "omission_reread_evidence_mismatch"
        end

        failed_attempts = calls.count { |call| failed_attempt?(call, config) }
        reasons << "failed_or_malformed_attempts=#{failed_attempts}" if failed_attempts.positive?
        passed = reasons.none? { |reason| !reason.start_with?("failed_or_malformed_attempts=") }
        result(passed, passed ? "passed" : "failed", reasons, matched)
      rescue StandardError
        result(false, "failed", ["malformed_input_or_contract"], [])
      rescue SystemStackError
        result(false, "failed", ["malformed_input_or_contract"], [])
      end

      def self.result(passed, status, reasons, matched)
        { "passed" => passed, "status" => status, "reasons" => reasons,
          "matched_call_indices" => matched }
      end
      private_class_method :result

      def self.valid_input?(event, config, lineage_id, contract, before_notes, after_notes)
        event.is_a?(Hash) && config.instance_of?(Config) && lineage_id.is_a?(String) &&
          lineage_id.match?(/\A[a-f0-9]{32}\z/) && contract.is_a?(Hash) &&
          before_notes.is_a?(Hash) && after_notes.is_a?(Hash) &&
          (!event.key?("calls") || event["calls"].is_a?(Array) && event["calls"].all? { |call| call.is_a?(Hash) })
      end
      private_class_method :valid_input?

      def self.resolve_lineage(value, lineage_id)
        case value
        when String then value == "$lineage" ? lineage_id : value
        when Array then value.map { |entry| resolve_lineage(entry, lineage_id) }
        when Hash then value.each_with_object({}) { |(key, entry), copy| copy[key] = resolve_lineage(entry, lineage_id) }
        else value
        end
      end
      private_class_method :resolve_lineage

      def self.valid_contract?(contract, config)
        return false unless contract.is_a?(Hash)
        allowed = %w[state reason reply reply_contains requires_notes final_notes steps omitted_before_step]
        return false unless (contract.keys - allowed).empty?
        return false if contract.key?("state") && !contract["state"].is_a?(String)
        return false if contract.key?("reason") && !contract["reason"].is_a?(String)
        return false if contract.key?("reply") && !contract["reply"].is_a?(String)
        return false if contract.key?("reply_contains") && !contract["reply_contains"].is_a?(String)
        return false if contract.key?("requires_notes") && !contract["requires_notes"].is_a?(Hash)
        return false if contract.key?("final_notes") && !contract["final_notes"].is_a?(Hash)
        return false if contract.key?("steps") && !contract["steps"].is_a?(Array)

        steps = contract.fetch("steps", [])
        return false unless steps.all? do |step|
          step.is_a?(Hash) && step.keys.sort == %w[action result] && valid_tool_action?(step["action"], config) &&
            step["result"].is_a?(Hash) && step["result"].key?("ok") && [true, false].include?(step["result"]["ok"])
        end
        return false if contract.key?("omitted_before_step") && !valid_omission?(contract["omitted_before_step"], steps.length)

        true
      end
      private_class_method :valid_contract?

      def self.valid_tool_action?(action, config)
        return false unless action.is_a?(Hash) && action["action"] == "tool"

        Actions.parse(ContinuityLab.encode(action), config) == action
      rescue StandardError
        false
      end
      private_class_method :valid_tool_action?

      def self.valid_omission?(value, step_count)
        value.is_a?(Hash) && value.keys.sort == %w[omitted_step reread_step] &&
          value.values.all? { |index| index.is_a?(Integer) && index >= 0 && index < step_count } &&
          value["reread_step"] > value["omitted_step"]
      end
      private_class_method :valid_omission?

      def self.terminal_match?(event, contract)
        return false unless event["state"] == contract.fetch("state", "complete") &&
                            event["reason"] == contract.fetch("reason", "reply")
        return false if contract.key?("reply") && event["reply"] != contract["reply"]
        return false if contract.key?("reply_contains") && (!event["reply"].is_a?(String) || !event["reply"].include?(contract["reply_contains"]))

        true
      end
      private_class_method :terminal_match?

      def self.parsed_action(call, config)
        return {} unless call.is_a?(Hash) && call["response"].is_a?(String)

        Actions.parse(call["response"], config)
      end
      private_class_method :parsed_action

      def self.successful_tool_call?(call, config)
        return false unless call.is_a?(Hash) && call["response"].is_a?(String) && call["result"].is_a?(Hash)
        valid_tool_action?(parsed_action(call, config), config) && successful_result?(call["result"])
      end
      private_class_method :successful_tool_call?

      def self.successful_result?(value)
        value.is_a?(Hash) && value["ok"] == true
      end
      private_class_method :successful_result?

      def self.failed_attempt?(call, config)
        return false unless call.is_a?(Hash)

        action = parsed_action(call, config)
        return true if action.empty?
        return false if %w[reply wait].include?(action["action"]) && !call.key?("result")

        action["action"] == "tool" && (!call["result"].is_a?(Hash) || !successful_result?(call["result"]))
      end
      private_class_method :failed_attempt?

      # Failed attempts may be ignored unless they exactly satisfy an expected
      # negative step. A successful operation can never be skipped.
      def self.match_steps(steps, calls, config)
        matched = []
        step_index = 0
        calls.each_with_index do |call, call_index|
          next unless tool_result_call?(call)

          action = parsed_action(call, config)
          success = successful_result?(call["result"])
          step = steps[step_index]
          exact = step && action == step["action"] && subset_missing(step["result"], call["result"]).empty?
          if exact
            return [matched, false] if success && !successful_tool_call?(call, config)

            matched << call_index
            step_index += 1
          elsif success
            return [matched, false]
          end
        end
        [matched, step_index == steps.length]
      end
      private_class_method :match_steps

      def self.tool_result_call?(call)
        call.is_a?(Hash) && call["result"].is_a?(Hash)
      end
      private_class_method :tool_result_call?

      # Expected values are recursive subsets; extra recorded evidence is retained.
      def self.subset_missing(expected, actual, path = [])
        return [path] unless expected.class == actual.class
        case expected
        when Hash
          expected.flat_map do |key, value|
            actual.key?(key) ? subset_missing(value, actual[key], path + [key]) : [path + [key]]
          end
        when Array
          return [path] unless expected.length == actual.length
          expected.each_with_index.flat_map { |value, index| subset_missing(value, actual[index], path + [index]) }
        else
          expected == actual ? [] : [path]
        end
      end
      private_class_method :subset_missing

      def self.omission_match?(contract, steps, calls, matched, config)
        return true unless contract.key?("omitted_before_step")
        return false unless matched.length == steps.length

        omitted_index = matched.fetch(contract.dig("omitted_before_step", "omitted_step"))
        reread_index = matched.fetch(contract.dig("omitted_before_step", "reread_step"))
        return false unless reread_index > omitted_index

        original, reread = calls.values_at(omitted_index, reread_index)
        original_action = parsed_action(original, config)
        reread_action = parsed_action(reread, config)
        return false unless original_action == reread_action && original_action["tool"] == "read"

        source_a = original.dig("result", "source")
        source_b = reread.dig("result", "source")
        identity = %w[lineage_id collection id revision content_digest span]
        return false unless successful_tool_call?(original, config) && successful_tool_call?(reread, config) &&
                            source_a.is_a?(Hash) && source_b.is_a?(Hash) &&
                            identity.all? { |key| source_a.key?(key) && source_b.key?(key) && source_a[key] == source_b[key] }

        manifest = reread.dig("context", "manifest")
        return false unless manifest.is_a?(Hash) && manifest["omitted_groups"].is_a?(Array) && manifest["included_groups"].is_a?(Array)

        manifest["omitted_groups"].any? { |entry| entry.is_a?(Hash) && entry["call_index"] == omitted_index } &&
          !manifest["included_groups"].include?(omitted_index)
      end
      private_class_method :omission_match?
    end
  end
end
