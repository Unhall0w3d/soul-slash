
# frozen_string_literal: true

require "json"
require "time"
require "tmpdir"
require_relative "read_only_skill_execution_gate"
require_relative "chat_execution_history"

module SoulCore
  class ChatExecutionHistoryAssessor
    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      Dir.mktmpdir("soul-history-assessment-") do |dir|
        history = ChatExecutionHistory.new(root: @root, path: File.join(dir, "chat_executions.jsonl"))
        gate = ReadOnlySkillExecutionGate.new(root: @root, history: history)

        executed = gate.evaluate("what skills do you have?", execute: true, record_history: true)
        blocked = gate.evaluate("move approved downloads to trash", execute: true, record_history: true)
        adapter_missing = gate.evaluate("inspect my downloads", execute: false, record_history: true)

        entries = history.entries

        blockers = []
        blockers << "Expected exactly three history entries" unless entries.length == 3
        blockers << "Expected one executed history entry" unless entries.count { |entry| entry["executed"] == true } == 1
        blockers << "Expected owner confirmation block to be recorded" unless entries.any? { |entry| Array(entry["blocked_by"]).include?("owner_confirmation_required") }
        blockers << "Expected adapter-not-implemented block to be recorded" unless entries.any? { |entry| Array(entry["blocked_by"]).include?("adapter_not_implemented") }
        blockers << "Expected executed result to have a history entry" unless executed.history_entry
        blockers << "Expected blocked result to have a history entry" unless blocked.history_entry
        blockers << "Expected adapter-missing result to have a history entry" unless adapter_missing.history_entry

        {
          "ok" => blockers.empty?,
          "assessment" => "chat_execution_history",
          "phase" => 50,
          "generated_at" => Time.now.iso8601,
          "root" => @root,
          "status" => blockers.empty? ? "ready" : "blocked",
          "history_path" => history.path,
          "entries" => entries,
          "blockers" => blockers,
          "warnings" => [
            "Assessment writes to a temporary directory.",
            "Real chat history is stored locally under Soul/runtime/.",
            "Runtime history must remain gitignored."
          ],
          "verification" => {
            "records_executed_results" => entries.any? { |entry| entry["executed"] == true },
            "records_blocked_results" => entries.any? { |entry| entry["status"] == "blocked" },
            "records_exit_status" => entries.any? { |entry| !entry["exit_status"].nil? },
            "uses_runtime_path_by_default" => ChatExecutionHistory::DEFAULT_PATH.start_with?(File.join("Soul", "runtime")),
            "assessment_uses_tempdir" => true
          }
        }
      end
    end

    def render(report)
      lines = []
      lines << "Soul Chat Execution History Assessment"
      lines << "Generated: #{report['generated_at']}"
      lines << "Status: #{report['status']}"
      lines << "Entries: #{report['entries'].length}"
      lines << ""
      lines << "Recorded entries"
      report.fetch("entries").each do |entry|
        lines << "- #{entry['timestamp']} #{entry['skill_id'] || 'none'}"
        lines << "  status: #{entry['status']}"
        lines << "  executed: #{entry['executed']}"
        lines << "  exit_status: #{entry['exit_status'] || 'none'}"
        lines << "  blocked_by: #{Array(entry['blocked_by']).empty? ? 'none' : Array(entry['blocked_by']).join(', ')}"
      end
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
