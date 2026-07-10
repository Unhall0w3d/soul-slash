
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
      Dir.mktmpdir("soul-history-filters-assessment-") do |dir|
        history = ChatExecutionHistory.new(root: @root, path: File.join(dir, "chat_executions.jsonl"))
        gate = ReadOnlySkillExecutionGate.new(root: @root, history: history)

        gate.evaluate("what skills do you have?", execute: true, record_history: true)
        gate.evaluate("check repo health", execute: true, record_history: true)
        gate.evaluate("move approved downloads to trash", execute: true, record_history: true)
        gate.evaluate("inspect my downloads", execute: false, record_history: true)

        all = history.entries
        system_status = history.entries(filters: { "skill_id" => "system.status" })
        blocked = history.entries(filters: { "status" => "blocked" })
        executed = history.entries(filters: { "executed" => true })
        parsed = ChatExecutionHistory.filters_from_text("show execution history skill system.status executed only")
        parsed_rows = history.entries(filters: parsed)
        filtered_export = history.export(format: "json", filters: { "status" => "blocked" }, export_dir: File.join(dir, "exports"))

        blockers = []
        blockers << "Expected four history entries" unless all.length == 4
        blockers << "Expected one system.status entry" unless system_status.length == 1
        blockers << "Expected two blocked entries" unless blocked.length == 2
        blockers << "Expected two executed entries" unless executed.length == 2
        blockers << "Expected parsed filters to include skill_id and executed" unless parsed["skill_id"] == "system.status" && parsed["executed"] == true
        blockers << "Expected parsed filter to return one row" unless parsed_rows.length == 1
        blockers << "Expected filtered export to include two rows" unless filtered_export["count"] == 2

        {
          "ok" => blockers.empty?,
          "assessment" => "chat_execution_history",
          "phase" => 52,
          "generated_at" => Time.now.iso8601,
          "root" => @root,
          "status" => blockers.empty? ? "ready" : "blocked",
          "counts" => {
            "all" => all.length,
            "system_status" => system_status.length,
            "blocked" => blocked.length,
            "executed" => executed.length,
            "parsed_rows" => parsed_rows.length
          },
          "parsed_filters" => parsed,
          "filtered_export" => filtered_export,
          "blockers" => blockers,
          "warnings" => [
            "Assessment writes to a temporary directory.",
            "Real chat history is stored locally under Soul/runtime/.",
            "Filters only apply to local execution metadata.",
            "Runtime history and exports must remain gitignored."
          ],
          "verification" => {
            "filters_by_skill_id" => system_status.length == 1,
            "filters_by_status" => blocked.length == 2,
            "filters_by_executed" => executed.length == 2,
            "parses_chat_filters" => parsed_rows.length == 1,
            "exports_filtered_history" => filtered_export["count"] == 2,
            "uses_runtime_path_by_default" => ChatExecutionHistory::DEFAULT_PATH.start_with?(File.join("Soul", "runtime")),
            "assessment_uses_tempdir" => true
          }
        }
      end
    end

    def render(report)
      lines = []
      lines << "Soul Execution History Filters Assessment"
      lines << "Generated: #{report['generated_at']}"
      lines << "Status: #{report['status']}"
      lines << ""
      lines << "Counts"
      report.fetch("counts").each { |key, value| lines << "- #{key}: #{value}" }
      lines << ""
      lines << "Parsed filters"
      report.fetch("parsed_filters").each { |key, value| lines << "- #{key}: #{value}" }
      lines << ""
      lines << "Blockers"
      report.fetch("blockers").empty? ? lines << "- None" : report.fetch("blockers").each { |blocker| lines << "- #{blocker}" }
      lines.join("\n")
    end
  end
end
