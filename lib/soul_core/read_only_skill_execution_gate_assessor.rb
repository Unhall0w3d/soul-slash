
# frozen_string_literal: true

require "json"
require "time"
require_relative "read_only_skill_execution_gate"

module SoulCore
  class ReadOnlySkillExecutionGateAssessor
    SAMPLE_MESSAGES = {
      "inspect my downloads" => {
        "expected_status" => "blocked",
        "expected_skill" => "downloads.inspect",
        "expected_blocker" => "adapter_not_implemented"
      },
      "what is the weather?" => {
        "expected_status" => "blocked",
        "expected_skill" => "weather.report",
        "expected_blocker" => "adapter_not_implemented"
      },
      "what skills do you have?" => {
        "expected_status" => "ready",
        "expected_skill" => "assistant-skill-catalog",
        "expected_blocker" => "phase47_dry_run_default"
      },
      "move approved downloads to trash" => {
        "expected_status" => "blocked",
        "expected_skill" => "downloads.move_to_trash",
        "expected_blocker" => "owner_confirmation_required"
      },
      "tell me about the moonlit gears" => {
        "expected_status" => "blocked",
        "expected_skill" => nil,
        "expected_blocker" => "no_candidate_skill"
      }
    }.freeze

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
      @gate = ReadOnlySkillExecutionGate.new(root: @root)
    end

    def assess
      samples = SAMPLE_MESSAGES.map do |message, expected|
        result = @gate.evaluate(message)
        matched =
          result.status == expected["expected_status"] &&
          result.skill_id == expected["expected_skill"] &&
          result.executed == false &&
          result.blocked_by.include?(expected["expected_blocker"])

        {
          "message" => message,
          "expected" => expected,
          "actual" => {
            "status" => result.status,
            "skill_id" => result.skill_id,
            "executed" => result.executed,
            "blocked_by" => result.blocked_by
          },
          "matched" => matched,
          "result" => result.to_h
        }
      end

      blockers = []
      blockers << "One or more read-only gate samples failed" unless samples.all? { |sample| sample["matched"] }

      {
        "ok" => blockers.empty?,
        "assessment" => "read_only_skill_execution_gate",
        "generated_at" => Time.now.iso8601,
        "root" => @root,
        "status" => blockers.empty? ? "ready" : "blocked",
        "sample_count" => samples.length,
        "samples" => samples,
        "blockers" => blockers,
        "warnings" => [
          "Phase 47 models the read-only execution gate.",
          "Phase 47 still defaults to dry-run behavior.",
          "Approval-required skills remain blocked.",
          "Adapters for some read-only skills are intentionally not implemented yet."
        ],
        "verification" => {
          "no_skill_execution" => true,
          "dry_run_default" => true,
          "approval_required_blocked" => true,
          "no_filesystem_mutation_beyond_chat_transcripts" => true
        }
      }
    end

    def render(report)
      lines = []
      lines << "Soul Read-Only Skill Execution Gate Assessment"
      lines << "Generated: #{report['generated_at']}"
      lines << "Status: #{report['status']}"
      lines << ""
      lines << "Samples"
      report.fetch("samples").each do |sample|
        status = sample["matched"] ? "ok" : "mismatch"
        actual = sample.fetch("actual")
        lines << "- #{sample['message'].inspect}: #{status}"
        lines << "  skill_id: #{actual['skill_id'] || 'none'}"
        lines << "  status: #{actual['status']}"
        lines << "  executed: #{actual['executed']}"
        lines << "  blocked_by: #{actual['blocked_by'].join(', ')}"
      end
      lines << ""
      lines << "Warnings"
      report.fetch("warnings").each { |warning| lines << "- #{warning}" }
      lines << ""
      lines << "Blockers"
      if report.fetch("blockers").empty?
        lines << "- None"
      else
        report.fetch("blockers").each { |blocker| lines << "- #{blocker}" }
      end
      lines.join("\n")
    end
  end
end
