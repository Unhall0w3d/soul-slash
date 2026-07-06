# frozen_string_literal: true

require "time"
require_relative "workflow_runner"
require_relative "selection_parser"
require_relative "confirmation_parser"
require_relative "skill_registry"
require_relative "skill_runner"
require_relative "task_log"
require_relative "response_renderer"

module SoulCore
  class WorkflowSession
    def initialize
      @runner = WorkflowRunner.new
      @selection_parser = SelectionParser.new
      @confirmation_parser = ConfirmationParser.new
      @registry = SkillRegistry.new
      @skill_runner = SkillRunner.new(registry: @registry)
      @task_log = TaskLog.new
      @renderer = ResponseRenderer.new
    end

    def respond(text)
      state = @runner.load_session("latest")

      case state.fetch("status")
      when "waiting_for_selection"
        handle_cleanup_selection(state, text)
      when "waiting_for_final_confirmation"
        handle_cleanup_final_confirmation(state, text)
      when "waiting_for_restore_selection"
        handle_restore_selection(state, text)
      when "waiting_for_restore_final_confirmation"
        handle_restore_final_confirmation(state, text)
      when "complete_no_action", "complete", "cancelled"
        {
          ok: true,
          message: "Latest workflow is already #{state.fetch('status')}. Start a new workflow with `ruby bin/soul do \"...\"`.",
          state: state
        }
      else
        {
          ok: false,
          message: "Unsupported workflow status: #{state.fetch('status')}",
          state: state
        }
      end
    end

    private

    def handle_cleanup_selection(state, text)
      handle_selection(
        state,
        text,
        next_status: "waiting_for_final_confirmation",
        renderer: :render_selection,
        empty_message: "No items selected. Workflow cancelled. Nothing was moved."
      )
    end

    def handle_restore_selection(state, text)
      handle_selection(
        state,
        text,
        next_status: "waiting_for_restore_final_confirmation",
        renderer: :render_restore_selection,
        empty_message: "No items selected. Restore workflow cancelled. Nothing was restored."
      )
    end

    def handle_selection(state, text, next_status:, renderer:, empty_message:)
      candidates = state.fetch("candidates", [])
      parsed = @selection_parser.parse(text, candidates)

      unless parsed.ok
        return {
          ok: false,
          message: parsed.message,
          state: state
        }
      end

      if parsed.action == "cancel"
        state["status"] = "cancelled"
        state["updated_at"] = Time.now.iso8601
        state["next_expected"] = "none"
        @runner.save_session(state)
        return {
          ok: true,
          message: "Cancelled. Nothing was moved or restored.",
          state: state
        }
      end

      selected = candidates.select { |candidate| parsed.selected_ids.include?(candidate.fetch("id")) }
      excluded = candidates.select { |candidate| parsed.excluded_ids.include?(candidate.fetch("id")) }

      state["selected_candidates"] = selected
      state["excluded_candidates"] = excluded
      state["status"] = selected.empty? ? "cancelled" : next_status
      state["updated_at"] = Time.now.iso8601
      state["next_expected"] = selected.empty? ? "none" : "final_confirmation"
      state["selection_message"] = parsed.message

      @runner.save_session(state)

      if selected.empty?
        {
          ok: true,
          message: empty_message,
          state: state
        }
      else
        {
          ok: true,
          message: @renderer.public_send(renderer, state),
          state: state
        }
      end
    end

    def handle_cleanup_final_confirmation(state, text)
      parsed = @confirmation_parser.parse(text)

      if parsed.cancelled
        state["status"] = "cancelled"
        state["updated_at"] = Time.now.iso8601
        state["next_expected"] = "none"
        @runner.save_session(state)

        return {
          ok: true,
          message: "Cancelled. Nothing was moved.",
          state: state
        }
      end

      unless parsed.confirmed
        return {
          ok: false,
          message: parsed.message,
          state: state
        }
      end

      args = [
        "--workflow-state", state.fetch("workflow_path"),
        "--execute",
        "--confirm", "MOVE_TO_TRASH"
      ]

      result = @skill_runner.run("downloads.move_to_trash", args: args)
      task_log_path = @task_log.write(kind: "skill.downloads.move_to_trash", payload: result)

      state["status"] = result[:ok] ? "complete" : "failed"
      state["updated_at"] = Time.now.iso8601
      state["next_expected"] = "reflection_offer"
      state["skill_runs"] << {
        "skill" => "downloads.move_to_trash",
        "args" => args,
        "ok" => result[:ok],
        "task_log" => task_log_path
      }
      state["verification"]["move_to_trash_log"] = task_log_path
      state["verification"]["moved_files"] = result.dig(:json, "verification", "moved_files") || 0
      state["verification"]["moved_directories"] = result.dig(:json, "verification", "moved_directories") || 0
      state["verification"]["deleted_files"] = result.dig(:json, "verification", "deleted_files") || 0
      state["verification"]["job_complete"] = result.dig(:json, "verification", "job_complete") || false

      @runner.save_session(state)

      {
        ok: result[:ok],
        message: @renderer.render_execution(result),
        state: state
      }
    end

    def handle_restore_final_confirmation(state, text)
      parsed = @confirmation_parser.parse(text)

      if parsed.cancelled
        state["status"] = "cancelled"
        state["updated_at"] = Time.now.iso8601
        state["next_expected"] = "none"
        @runner.save_session(state)

        return {
          ok: true,
          message: "Cancelled. Nothing was restored.",
          state: state
        }
      end

      unless parsed.confirmed
        return {
          ok: false,
          message: parsed.message,
          state: state
        }
      end

      args = [
        "--workflow-state", state.fetch("workflow_path"),
        "--execute",
        "--confirm", "RESTORE_FROM_TRASH"
      ]

      result = @skill_runner.run("downloads.restore_last_cleanup", args: args)
      task_log_path = @task_log.write(kind: "skill.downloads.restore_last_cleanup", payload: result)

      state["status"] = result[:ok] ? "complete" : "failed"
      state["updated_at"] = Time.now.iso8601
      state["next_expected"] = "reflection_offer"
      state["skill_runs"] << {
        "skill" => "downloads.restore_last_cleanup",
        "args" => args,
        "ok" => result[:ok],
        "task_log" => task_log_path
      }
      state["verification"]["restore_log"] = task_log_path
      state["verification"]["restored_files"] = result.dig(:json, "verification", "restored_files") || 0
      state["verification"]["restored_directories"] = result.dig(:json, "verification", "restored_directories") || 0
      state["verification"]["deleted_files"] = result.dig(:json, "verification", "deleted_files") || 0
      state["verification"]["job_complete"] = result.dig(:json, "verification", "job_complete") || false

      @runner.save_session(state)

      {
        ok: result[:ok],
        message: @renderer.render_restore_execution(result),
        state: state
      }
    end
  end
end
