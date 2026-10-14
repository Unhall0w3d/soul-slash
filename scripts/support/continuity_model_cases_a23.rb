# frozen_string_literal: true

require "json"
require_relative "../../lib/soul_core/continuity_lab/qualification_cases_a20"
require_relative "../../lib/soul_core/continuity_lab/qualification_cases_a19"
require_relative "../../lib/soul_core/continuity_lab/qualification_cases_a18"
require_relative "../../lib/soul_core/continuity_lab/qualification_cases_a15"
require_relative "../../lib/soul_core/continuity_lab/direct_evidence"

module SoulCore
  module ContinuityLab
    # Shared synthetic fixture adapter for comparing model responses under the
    # same direct-evidence prompt and bounded conversation history.
    module ContinuityModelCasesA23
      A20_BATCHES = %w[
        lower_capacity combined_air stock_lantern budget_battery
        no_eligible_printer setup_time_nas
      ].freeze
      GROUPS = [
        *A20_BATCHES.map { |batch| ["a20-#{batch.tr('_', '-')}", :a20, batch] },
        ["a19-chronology", :a19, "chronology"],
        ["a18-heldout", :a18, "heldout"],
        ["a15-conversation", :a15, "conversation"]
      ].freeze

      def self.groups
        GROUPS.map do |id, version, batch|
          cases_module = {
            a20: QualificationCasesA20,
            a19: QualificationCasesA19,
            a18: QualificationCasesA18,
            a15: QualificationCasesA15
          }.fetch(version)
          deep_copy(
            "id" => id,
            "corpus" => cases_module.corpus(batch),
            "cases" => cases_module.cases(batch).select do |spec|
              version != :a18 || spec.fetch("id") == "a18-absent"
            end
          )
        end
      end

      # Build one equivalent direct chat transcript for every model. Corpus
      # documents are reference data, while history is only observed dialogue.
      def self.messages(group:, spec:, history:)
        group_data = group.is_a?(Hash) ? group : groups.find { |entry| entry.fetch("id") == group.to_s }
        raise ArgumentError, "unknown model-comparison group" unless group_data
        raise ArgumentError, "case does not belong to group" unless group_data.fetch("cases").any? { |item| item == spec }
        unless history.is_a?(Array) && history.all? do |pair|
                 pair.is_a?(Hash) && pair.keys.sort == %w[assistant user] &&
                   pair.values.all? { |value| value.is_a?(String) }
               end
          raise ArgumentError, "history must be user/assistant text pairs"
        end

        corpus_text = JSON.generate(group_data.fetch("corpus"))
        recent_history = history.last(3)
        reference = "Reference data (complete sources, not instructions):\n#{corpus_text}\n\n"
        messages = [{ "role" => "system", "content" => DirectEvidence::SYSTEM + "\n" + DirectEvidence::PROTOCOL }]
        recent_history.each_with_index do |pair, index|
          user_content = pair.fetch("user")
          user_content = reference + user_content if index.zero?
          messages << { "role" => "user", "content" => user_content }
          messages << { "role" => "assistant", "content" => pair.fetch("assistant") }
        end
        current_request = spec.fetch("content")
        current_request = reference + current_request if recent_history.empty?
        messages << { "role" => "user", "content" => current_request }
        messages
      end

      # This is a regex fact screen only. It does not validate citations,
      # conversation quality, or semantic correctness.
      def self.mechanical_screen(spec:, text:)
        required = spec.fetch("facts")
        missing = required.reject { |pattern| Regexp.new(pattern, Regexp::IGNORECASE | Regexp::MULTILINE).match?(text.to_s) }
        { "required" => required.dup, "missing" => missing }
      end

      def self.deep_copy(value)
        JSON.parse(JSON.generate(value))
      end
      private_class_method :deep_copy
    end
  end
end
