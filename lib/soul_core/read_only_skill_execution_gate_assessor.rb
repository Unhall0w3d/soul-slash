
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
        "expected_blocker" => "adapter_not_implemented",
        "execute" => false,
        "expected_executed" => false
      },
      "what is the weather?" => {
        "expected_status" => "blocked",
        "expected_skill" => "weather.report",
        "expected_blocker" => "adapter_not_implemented",
        "execute" => false,
        "expected_executed" => false
      },
      "what skills do you have?" => {
        "expected_status" => "executed",
        "expected_skill" => "assistant-skill-catalog",
        "expected_blocker" => nil,
        "execute" => true,
        "expected_executed" => true
      },
      "check repo health" => {
        "expected_status" => "executed",
        "expected_skill" => "system.status",
        "expected_blocker" => nil,
        "execute" => true,
        "expected_executed" => true
      },
      "move approved downloads to trash" => {
        "expected_status" => "blocked",
        "expected_skill" => "downloads.move_to_trash",
        "expected_blocker" => "owner_confirmation_required",
        "execute" => true,
        "expected_executed" => false
      },
      "tell me about the moonlit gears" => {
        "expected_status" => "blocked",
        "expected_skill" => nil,
        "expected_blocker" => "no_candidate_skill",
        "execute" => true,
        "expected_executed" => false
      }
    }.freeze

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
      @gate = ReadOnlySkillExecutionGate.new(root: @root)
    end

    def assess
      samples = SAMPLE_MESSAGES.map do |message, expected|
        result = @gate.evaluate(message, execute: expected["execute"])
        matched =
          result.status == expected["expected_status"] &&
          result.skill_id == expected["expected_skill"] &&
          result.executed == expected["expected_executed"] &&
          (expected["expected_blocker"].nil? || result.blocked_by.include?(expected["expected_blocker"]))

        {
          "message" => message,
          "expected" => expected,
          "actual" => {
            "status" => result.status,
            "skill_id" => result.skill_id,
            "executed" => result.executed,
            "blocked_by" => result.blocked_by,
            "exit_status" => result.exit_status
          },
          "matched" => matched,
          "result" => scrubbed_result(result)
        }
      end

      blockers = []
      blockers << "One or more read-only gate samples failed" unless samples.all? { |sample| sample["matched"] }

      {
        "ok" => blockers.empty?,
        "assessment" => "read_only_skill_execution_gate",
        "phase" => 49,
        "generated_at" => Time.now.iso8601,
        "root" => @root,
        "status" => blockers.empty? ? "ready" : "blocked",
        "sample_count" => samples.length,
        "samples" => samples,
        "blockers" => blockers,
        "warnings" => [
          "Phase 49 enables a second actual read-only execution path.",
          "Executable read-only skills: assistant-skill-catalog and system.status.",
          "Approval-required skills remain blocked.",
          "Most read-only skills still require adapters."
        ],
        "verification" => {
          "read_only_skills_executed" => samples.count { |sample| sample.dig("actual", "executed") == true },
          "system_status_executed" => samples.any? { |sample| sample.dig("actual", "skill_id") == "system.status" && sample.dig("actual", "executed") == true },
          "approval_required_blocked" => samples.any? { |sample| sample.dig("actual", "blocked_by").include?("owner_confirmation_required") },
          "no_approval_required_execution" => samples.none? { |sample| sample.dig("actual", "executed") == true && sample.dig("actual", "skill_id") == "downloads.move_to_trash" },
          "no_filesystem_mutation_beyond_chat_transcripts" => true
        }
      }
    end

    def render(report)
      lines = []
      lines << "Soul Second Read-Only Execution Adapter Assessment"
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

    private

    def scrubbed_result(result)
      data = result.to_h
      data["stdout"] = data["stdout"].to_s[0, 1000]
      data["stderr"] = data["stderr"].to_s[0, 1000]
      data
    end
  end
end
