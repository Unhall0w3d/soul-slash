
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
      Dir.mktmpdir("soul-history-pruning-assessment-") do |dir|
        history = ChatExecutionHistory.new(root: @root, path: File.join(dir, "chat_executions.jsonl"))
        gate = ReadOnlySkillExecutionGate.new(root: @root, history: history)

        2.times { gate.evaluate("what skills do you have?", execute: true, record_history: true) }
        2.times { gate.evaluate("check repo health", execute: true, record_history: true) }
        gate.evaluate("move approved downloads to trash", execute: true, record_history: true)

        before = history.entries
        preview = history.prune(keep: 2, confirm: false, export_dir: File.join(dir, "exports"))
        after_preview = history.entries
        pruned = history.prune(keep: 2, confirm: true, export_dir: File.join(dir, "exports"))
        after_prune = history.entries

        blockers = []
        blockers << "Expected five entries before prune" unless before.length == 5
        blockers << "Expected preview to remove three entries" unless preview["status"] == "preview" && preview["would_remove"] == 3
        blockers << "Expected preview not to change entries" unless after_preview.length == 5
        blockers << "Expected confirmed prune to keep two entries" unless pruned["status"] == "pruned" && pruned["total_after"] == 2
        blockers << "Expected prune export to preserve removed entries" unless pruned.dig("export", "count") == 3
        blockers << "Expected two entries after prune" unless after_prune.length == 2
        blockers << "Expected keep parser to find 7" unless ChatExecutionHistory.keep_count_from_text("prune execution history keep 7") == 7

        {
          "ok" => blockers.empty?,
          "assessment" => "chat_execution_history",
          "phase" => 53,
          "generated_at" => Time.now.iso8601,
          "root" => @root,
          "status" => blockers.empty? ? "ready" : "blocked",
          "counts" => {
            "before" => before.length,
            "after_preview" => after_preview.length,
            "after_prune" => after_prune.length
          },
          "preview" => preview,
          "pruned" => pruned,
          "blockers" => blockers,
          "warnings" => [
            "Assessment writes to a temporary directory.",
            "Real chat history is stored locally under Soul/runtime/.",
            "Prune requires explicit confirmation.",
            "Confirmed prune exports removed entries by default."
          ],
          "verification" => {
            "previews_without_mutation" => after_preview.length == before.length,
            "requires_confirmation" => preview["status"] == "preview",
            "prunes_with_confirmation" => pruned["status"] == "pruned",
            "exports_before_delete" => pruned.dig("export", "count") == 3,
            "keeps_requested_count" => after_prune.length == 2,
            "parses_keep_count" => ChatExecutionHistory.keep_count_from_text("prune execution history keep 7") == 7,
            "uses_runtime_path_by_default" => ChatExecutionHistory::DEFAULT_PATH.start_with?(File.join("Soul", "runtime")),
            "assessment_uses_tempdir" => true
          }
        }
      end
    end

    def render(report)
      lines = []
      lines << "Soul Execution History Pruning Assessment"
      lines << "Generated: #{report['generated_at']}"
      lines << "Status: #{report['status']}"
      lines << ""
      lines << "Counts"
      report.fetch("counts").each { |key, value| lines << "- #{key}: #{value}" }
      lines << ""
      lines << "Preview"
      lines << "- would_remove: #{report.dig('preview', 'would_remove')}"
      lines << "- would_keep: #{report.dig('preview', 'would_keep')}"
      lines << ""
      lines << "Confirmed prune"
      lines << "- total_after: #{report.dig('pruned', 'total_after')}"
      lines << "- exported_removed: #{report.dig('pruned', 'export', 'count') || 0}"
      lines << ""
      lines << "Blockers"
      report.fetch("blockers").empty? ? lines << "- None" : report.fetch("blockers").each { |blocker| lines << "- #{blocker}" }
      lines.join("\n")
    end
  end
end
