
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
      Dir.mktmpdir("soul-history-controls-assessment-") do |dir|
        history = ChatExecutionHistory.new(root: @root, path: File.join(dir, "chat_executions.jsonl"))
        gate = ReadOnlySkillExecutionGate.new(root: @root, history: history)

        gate.evaluate("what skills do you have?", execute: true, record_history: true)
        gate.evaluate("move approved downloads to trash", execute: true, record_history: true)
        gate.evaluate("inspect my downloads", execute: false, record_history: true)

        before = history.entries
        json_export = history.export(format: "json", export_dir: File.join(dir, "exports"))
        jsonl_export = history.export(format: "jsonl", export_dir: File.join(dir, "exports"))
        blocked_clear = history.clear(confirm: false)
        clear = history.clear(confirm: true)
        after = history.entries

        blockers = []
        blockers << "Expected exactly three history entries before clear" unless before.length == 3
        blockers << "Expected JSON export to include three entries" unless json_export["count"] == 3
        blockers << "Expected JSONL export to include three entries" unless jsonl_export["count"] == 3
        blockers << "Expected unconfirmed clear to be blocked" unless blocked_clear["ok"] == false && blocked_clear["deleted"] == false
        blockers << "Expected confirmed clear to succeed" unless clear["ok"] == true
        blockers << "Expected no entries after confirmed clear" unless after.empty?

        {
          "ok" => blockers.empty?,
          "assessment" => "chat_execution_history",
          "phase" => 51,
          "generated_at" => Time.now.iso8601,
          "root" => @root,
          "status" => blockers.empty? ? "ready" : "blocked",
          "entries_before_clear" => before,
          "entries_after_clear" => after,
          "exports" => [json_export, jsonl_export],
          "blocked_clear" => blocked_clear,
          "confirmed_clear" => clear,
          "blockers" => blockers,
          "warnings" => [
            "Assessment writes to a temporary directory.",
            "Real chat history is stored locally under Soul/runtime/.",
            "Clear and export are explicit controls.",
            "Runtime history and exports must remain gitignored."
          ],
          "verification" => {
            "records_executed_results" => before.any? { |entry| entry["executed"] == true },
            "records_blocked_results" => before.any? { |entry| entry["status"] == "blocked" },
            "exports_json" => json_export["ok"] == true,
            "exports_jsonl" => jsonl_export["ok"] == true,
            "blocks_unconfirmed_clear" => blocked_clear["ok"] == false,
            "clears_with_confirmation" => clear["ok"] == true,
            "uses_runtime_path_by_default" => ChatExecutionHistory::DEFAULT_PATH.start_with?(File.join("Soul", "runtime")),
            "assessment_uses_tempdir" => true
          }
        }
      end
    end

    def render(report)
      lines = []
      lines << "Soul Chat Execution History Controls Assessment"
      lines << "Generated: #{report['generated_at']}"
      lines << "Status: #{report['status']}"
      lines << "Entries before clear: #{report['entries_before_clear'].length}"
      lines << "Entries after clear: #{report['entries_after_clear'].length}"
      lines << ""
      lines << "Exports"
      report.fetch("exports").each { |export| lines << "- #{export['format']}: #{export['path']} (#{export['count']} entries)" }
      lines << ""
      lines << "Clear controls"
      lines << "- unconfirmed clear: #{report.dig('blocked_clear', 'status')}"
      lines << "- confirmed clear: #{report.dig('confirmed_clear', 'status')}"
      lines << ""
      lines << "Blockers"
      report.fetch("blockers").empty? ? lines << "- None" : report.fetch("blockers").each { |blocker| lines << "- #{blocker}" }
      lines.join("\n")
    end
  end
end
