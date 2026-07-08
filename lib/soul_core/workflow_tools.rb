# frozen_string_literal: true

require "json"
require "fileutils"
require "time"

module SoulCore
  class WorkflowTools
    DEFAULT_SESSION_ROOT = "Soul/workflows/sessions"

    ACTIVE_STATUSES = [
      "needs_location",
      "needs_youtube_query",
      "waiting_for_selection",
      "waiting_for_final_confirmation",
      "waiting_for_restore_selection",
      "waiting_for_restore_final_confirmation",
      "waiting_for_weather_location_choice",
      "waiting_for_weather_override_location",
      "waiting_for_weather_detail_decision",
      "waiting_for_youtube_open_confirmation",
      "waiting_for_youtube_search_confirmation"
    ].freeze

    COMPLETE_STATUSES = [
      "complete",
      "complete_no_action",
      "cancelled",
      "failed"
    ].freeze

    def initialize(session_root: DEFAULT_SESSION_ROOT)
      @session_root = session_root
      FileUtils.mkdir_p(@session_root)
    end

    def list(include_all: true)
      rows = session_paths.map { |path| summarize(path) }.compact
      rows = rows.reject { |row| COMPLETE_STATUSES.include?(row.fetch("status")) } unless include_all

      {
        "status" => "ok",
        "outcome" => "complete",
        "session_root" => @session_root,
        "count" => rows.length,
        "sessions" => rows,
        "verification" => {
          "read_only" => true,
          "sessions_listed" => rows.length,
          "complete_statuses" => COMPLETE_STATUSES,
          "active_statuses" => ACTIVE_STATUSES
        }
      }
    end

    def status(target = "latest")
      path = resolve(target)
      state = load(path)
      summary = summarize(path, state)

      {
        "status" => "ok",
        "outcome" => "complete",
        "target" => target,
        "session" => summary,
        "next_action" => next_action_for(state),
        "verification" => {
          "read_only" => true,
          "workflow_path" => path,
          "workflow_status" => state["status"],
          "next_expected" => state["next_expected"]
        }
      }
    end

    def clear_complete(confirm: false)
      candidates = session_paths.filter_map do |path|
        state = safe_load(path)
        next unless state
        next unless COMPLETE_STATUSES.include?(state["status"])

        summarize(path, state)
      end

      unless confirm
        return {
          "status" => "ok",
          "outcome" => "awaiting_confirmation",
          "candidate_count" => candidates.length,
          "candidates" => candidates,
          "recommendation" => "Re-run with `--confirm CLEAR_COMPLETE` to remove completed, cancelled, and failed workflow session files.",
          "verification" => {
            "read_only" => true,
            "deleted_sessions" => 0,
            "requires_confirmation_before_delete" => true
          }
        }
      end

      deleted = []
      candidates.each do |candidate|
        path = candidate.fetch("path")
        File.delete(path)
        deleted << candidate.merge("deleted" => true)
      rescue StandardError => e
        deleted << candidate.merge("deleted" => false, "error" => "#{e.class}: #{e.message}")
      end

      {
        "status" => "ok",
        "outcome" => "complete",
        "deleted_count" => deleted.count { |item| item["deleted"] },
        "deleted_sessions" => deleted,
        "verification" => {
          "read_only" => false,
          "deleted_sessions" => deleted.count { |item| item["deleted"] },
          "requires_confirmation_before_delete" => true,
          "confirmation_token" => "CLEAR_COMPLETE"
        }
      }
    end

    def render_list(payload)
      sessions = payload.fetch("sessions", [])
      return "No workflow sessions found." if sessions.empty?

      lines = ["Workflow sessions:", ""]
      sessions.each_with_index do |session, index|
        lines << "#{index + 1}. #{session.fetch('workflow')} [#{session.fetch('status')}]"
        lines << "   path: #{session.fetch('path')}"
        lines << "   updated: #{session.fetch('updated_at', 'unknown')}"
        lines << "   next: #{session.fetch('next_expected', 'none')}"
        original = session["original_text"].to_s
        lines << "   request: #{original}" unless original.empty?
      end
      lines.join("\n")
    end

    def render_status(payload)
      session = payload.fetch("session")
      lines = [
        "Workflow status:",
        "",
        "- Workflow: #{session.fetch('workflow')}",
        "- Status: #{session.fetch('status')}",
        "- Path: #{session.fetch('path')}",
        "- Updated: #{session.fetch('updated_at', 'unknown')}",
        "- Next expected: #{session.fetch('next_expected', 'none')}"
      ]

      original = session["original_text"].to_s
      lines << "- Request: #{original}" unless original.empty?

      lines << ""
      lines << payload.fetch("next_action")
      lines.join("\n")
    end

    def render_clear_complete(payload)
      if payload["outcome"] == "awaiting_confirmation"
        candidates = payload.fetch("candidates", [])
        lines = [
          "Completed workflow sessions eligible for cleanup: #{candidates.length}",
          ""
        ]

        if candidates.empty?
          lines << "Nothing to clear."
        else
          candidates.each_with_index do |session, index|
            lines << "#{index + 1}. #{session.fetch('workflow')} [#{session.fetch('status')}]"
            lines << "   path: #{session.fetch('path')}"
            lines << "   updated: #{session.fetch('updated_at', 'unknown')}"
          end
          lines << ""
          lines << 'To clear these session files: `ruby bin/soul workflow clear-complete --confirm CLEAR_COMPLETE`'
        end

        return lines.join("\n")
      end

      "Cleared #{payload.fetch('deleted_count')} completed workflow session file(s)."
    end

    private

    def session_paths
      Dir.glob(File.join(@session_root, "*.json")).sort
    end

    def latest_path
      session_paths.last
    end

    def resolve(target)
      value = target.to_s.strip
      value = "latest" if value.empty?

      if value == "latest" || value == "last"
        path = latest_path
        raise "no workflow sessions found" unless path

        return path
      end

      return value if File.exist?(value)

      matches = session_paths.select { |path| File.basename(path).include?(value) }
      raise "no workflow matched: #{value}" if matches.empty?
      raise "multiple workflows matched #{value}: #{matches.join(', ')}" if matches.length > 1

      matches.first
    end

    def load(path)
      JSON.parse(File.read(path))
    end

    def safe_load(path)
      load(path)
    rescue StandardError
      nil
    end

    def summarize(path, state = nil)
      state ||= safe_load(path)
      return nil unless state

      {
        "path" => path,
        "basename" => File.basename(path),
        "workflow" => state["workflow"] || "unknown",
        "status" => state["status"] || "unknown",
        "generated_at" => state["generated_at"],
        "updated_at" => state["updated_at"],
        "next_expected" => state["next_expected"] || "none",
        "original_text" => state["original_text"],
        "skill_run_count" => Array(state["skill_runs"]).length,
        "complete" => state.dig("verification", "complete")
      }
    end

    def next_action_for(state)
      status = state["status"].to_s
      next_expected = state["next_expected"].to_s

      case status
      when "complete", "complete_no_action"
        "This workflow is complete. Start a new workflow with `ruby bin/soul do \"...\"`, or clear completed sessions with `ruby bin/soul workflow clear-complete`."
      when "cancelled"
        "This workflow was cancelled. Start a new workflow with `ruby bin/soul do \"...\"`, or clear completed sessions with `ruby bin/soul workflow clear-complete`."
      when "failed"
        "This workflow failed. Inspect it with `ruby bin/soul workflow show latest`, then start a new workflow after fixing the issue."
      when *ACTIVE_STATUSES
        "This workflow is waiting for #{next_expected.empty? ? 'a response' : next_expected}. Continue with `ruby bin/soul respond \"...\"`."
      else
        "This workflow has an unrecognized status. Inspect it with `ruby bin/soul workflow show latest`."
      end
    end
  end
end
