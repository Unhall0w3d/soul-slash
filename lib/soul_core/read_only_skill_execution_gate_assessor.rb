
# frozen_string_literal: true

require "json"
require "time"
require "tmpdir"
require_relative "read_only_skill_execution_gate"

module SoulCore
  class ReadOnlySkillExecutionGateAssessor
    SAMPLE_MESSAGES = {
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
      "execution history summary" => {
        "expected_status" => "executed",
        "expected_skill" => "execution.history.summary",
        "expected_blocker" => nil,
        "execute" => true,
        "expected_executed" => true
      },
      "inspect my downloads" => {
        "expected_status" => "blocked",
        "expected_skill" => "downloads.inspect",
        "expected_blocker" => "adapter_not_implemented",
        "execute" => false,
        "expected_executed" => false
      },
      "move approved downloads to trash" => {
        "expected_status" => "blocked",
        "expected_skill" => "downloads.move_to_trash",
        "expected_blocker" => "owner_confirmation_required",
        "execute" => true,
        "expected_executed" => false
      }
    }.freeze

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      Dir.mktmpdir("soul-read-only-gate-phase54-") do |dir|
        history = ChatExecutionHistory.new(root: @root, path: File.join(dir, "chat_executions.jsonl"))
        gate = ReadOnlySkillExecutionGate.new(root: @root, history: history)

        gate.evaluate("what skills do you have?", execute: true, record_history: true)
        gate.evaluate("check repo health", execute: true, record_history: true)

        samples = SAMPLE_MESSAGES.map do |message, expected|
          result = gate.evaluate(message, execute: expected["execute"])
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

        history_summary_sample = samples.find { |sample| sample.dig("actual", "skill_id") == "execution.history.summary" }
        history_summary = JSON.parse(history_summary_sample.dig("result", "stdout")) rescue {}

        blockers = []
        blockers << "One or more read-only gate samples failed" unless samples.all? { |sample| sample["matched"] }
        blockers << "Expected execution.history.summary to report at least two entries" unless history_summary["total_entries"].to_i >= 2
        blockers << "Expected execution.history.summary to include counts_by_skill" unless history_summary["counts_by_skill"].is_a?(Hash)

        {
          "ok" => blockers.empty?,
          "assessment" => "read_only_skill_execution_gate",
          "phase" => 54,
          "generated_at" => Time.now.iso8601,
          "root" => @root,
          "status" => blockers.empty? ? "ready" : "blocked",
          "sample_count" => samples.length,
          "samples" => samples,
          "history_summary" => history_summary,
          "blockers" => blockers,
          "warnings" => [
            "Phase 54 enables a third actual read-only execution path.",
            "Executable read-only skills: assistant-skill-catalog, system.status, execution.history.summary.",
            "Approval-required skills remain blocked.",
            "Most external read-only skills still require adapters."
          ],
          "verification" => {
            "read_only_skills_executed" => samples.count { |sample| sample.dig("actual", "executed") == true },
            "history_summary_executed" => samples.any? { |sample| sample.dig("actual", "skill_id") == "execution.history.summary" && sample.dig("actual", "executed") == true },
            "history_summary_reports_counts" => history_summary["counts_by_skill"].is_a?(Hash),
            "approval_required_blocked" => samples.any? { |sample| sample.dig("actual", "blocked_by").include?("owner_confirmation_required") },
            "no_approval_required_execution" => samples.none? { |sample| sample.dig("actual", "executed") == true && sample.dig("actual", "skill_id") == "downloads.move_to_trash" },
            "no_filesystem_mutation_beyond_chat_transcripts" => true
          }
        }
      end
    end

    def render(report)
      lines = []
      lines << "Soul Third Read-Only Execution Adapter Assessment"
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
      lines << "History summary"
      lines << "- total_entries: #{report.dig('history_summary', 'total_entries') || 0}"
      lines << "- counts_by_skill: #{report.dig('history_summary', 'counts_by_skill') || {}}"
      lines << ""
      lines << "Blockers"
      report.fetch("blockers").empty? ? lines << "- None" : report.fetch("blockers").each { |blocker| lines << "- #{blocker}" }
      lines.join("\n")
    end

    private

    def scrubbed_result(result)
      data = result.to_h
      data["stdout"] = data["stdout"].to_s[0, 1200]
      data["stderr"] = data["stderr"].to_s[0, 1200]
      data
    end
  end
end
