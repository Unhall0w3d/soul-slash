# frozen_string_literal: true

require "json"
require "fileutils"
require "time"

require_relative "skill_registry"
require_relative "skill_runner"
require_relative "task_log"
require_relative "response_renderer"

module SoulCore
  class WorkflowRunner
    def initialize(workflow_root: "Soul/workflows/pending", session_root: "Soul/workflows/sessions")
      @workflow_root = workflow_root
      @session_root = session_root
      FileUtils.mkdir_p(@workflow_root)
      FileUtils.mkdir_p(@session_root)
      @task_log = TaskLog.new
      @renderer = ResponseRenderer.new
    end

    def run(intent:, parameters:, original_text:)
      case intent
      when "downloads.cleanup"
        run_downloads_cleanup(parameters: parameters, original_text: original_text)
      when "downloads.restore_last_cleanup"
        run_downloads_restore_last_cleanup(parameters: parameters, original_text: original_text)
      else
        raise ArgumentError, "unsupported workflow intent: #{intent}"
      end
    end

    def list_pending
      Dir.glob(File.join(@session_root, "*.json")).sort
    end

    def latest_session_path
      list_pending.last
    end

    def load_session(target = "latest")
      path = resolve_workflow(target)
      JSON.parse(File.read(path))
    end

    def save_session(state)
      path = state.fetch("workflow_path")
      File.write(path, JSON.pretty_generate(state))
      path
    end

    def show(target = "latest")
      path = resolve_workflow(target)
      JSON.pretty_generate(JSON.parse(File.read(path)))
    end

    private

    def run_downloads_cleanup(parameters:, original_text:)
      older_than_days = parameters.fetch("older_than_days", 30)
      target_path = parameters.fetch("target_path", File.join(Dir.home, "Downloads"))

      registry = SkillRegistry.new
      runner = SkillRunner.new(registry: registry)

      skill_args = [
        "--path", target_path,
        "--older-than-days", older_than_days.to_s
      ]

      plan_result = runner.run("downloads.cleanup_plan", args: skill_args)
      task_log_path = @task_log.write(kind: "skill.downloads.cleanup_plan", payload: plan_result)

      plan = plan_result[:json] || {}
      summary = plan.fetch("summary", {})
      proposed = plan.fetch("proposed_actions", {})
      candidates = assign_candidate_ids(proposed.fetch("would_move_to_trash_after_approval", []))

      state = {
        "workflow" => "downloads.cleanup",
        "status" => candidates.empty? ? "complete_no_action" : "waiting_for_selection",
        "generated_at" => Time.now.iso8601,
        "updated_at" => Time.now.iso8601,
        "original_text" => original_text,
        "parameters" => {
          "target_path" => target_path,
          "older_than_days" => older_than_days,
          "include_directories" => true,
          "recursive" => false
        },
        "skill_runs" => [
          {
            "skill" => "downloads.cleanup_plan",
            "args" => skill_args,
            "ok" => plan_result[:ok],
            "task_log" => task_log_path
          }
        ],
        "summary" => summary,
        "candidate_count" => candidates.length,
        "candidates" => candidates,
        "selected_candidates" => [],
        "excluded_candidates" => [],
        "next_expected" => candidates.empty? ? "none" : "selection",
        "verification" => {
          "plan_generated" => plan_result[:ok],
          "plan_log" => task_log_path,
          "moved_files" => 0,
          "moved_directories" => 0,
          "deleted_files" => 0,
          "stopped_before_execution" => true,
          "requires_confirmation_before_trash" => true
        }
      }

      workflow_path = write_workflow_state(state, suffix: "downloads.cleanup")
      state["workflow_path"] = workflow_path
      save_session(state)

      {
        ok: plan_result[:ok],
        workflow_path: workflow_path,
        task_log_path: task_log_path,
        plan: plan,
        state: state,
        user_message: @renderer.render_plan(state, plan)
      }
    end

    def run_downloads_restore_last_cleanup(parameters:, original_text:)
      registry = SkillRegistry.new
      runner = SkillRunner.new(registry: registry)

      restore_result = runner.run("downloads.restore_last_cleanup", args: [])
      task_log_path = @task_log.write(kind: "skill.downloads.restore_last_cleanup", payload: restore_result)
      payload = restore_result[:json] || {}
      candidates = payload.fetch("candidates", [])

      state = {
        "workflow" => "downloads.restore_last_cleanup",
        "status" => candidates.empty? ? "complete_no_action" : "waiting_for_restore_selection",
        "generated_at" => Time.now.iso8601,
        "updated_at" => Time.now.iso8601,
        "original_text" => original_text,
        "parameters" => {
          "target_path" => parameters.fetch("target_path", File.join(Dir.home, "Downloads"))
        },
        "skill_runs" => [
          {
            "skill" => "downloads.restore_last_cleanup",
            "args" => [],
            "ok" => restore_result[:ok],
            "task_log" => task_log_path
          }
        ],
        "candidate_count" => candidates.length,
        "candidates" => candidates,
        "selected_candidates" => [],
        "excluded_candidates" => [],
        "next_expected" => candidates.empty? ? "none" : "restore_selection",
        "verification" => {
          "restore_dry_run_generated" => restore_result[:ok],
          "restore_dry_run_log" => task_log_path,
          "source_move_log" => payload["source_move_log"],
          "restored_files" => 0,
          "restored_directories" => 0,
          "deleted_files" => 0,
          "stopped_before_execution" => true,
          "requires_confirmation_before_restore" => true
        }
      }

      workflow_path = write_workflow_state(state, suffix: "downloads.restore_last_cleanup")
      state["workflow_path"] = workflow_path
      save_session(state)

      {
        ok: restore_result[:ok],
        workflow_path: workflow_path,
        task_log_path: task_log_path,
        restore_result: payload,
        state: state,
        user_message: @renderer.render_restore_plan(state, payload)
      }
    end

    def assign_candidate_ids(candidates)
      file_index = 0
      dir_index = 0

      candidates.map do |candidate|
        copy = candidate.dup
        case copy["type"]
        when "directory"
          dir_index += 1
          copy["id"] = "D#{dir_index}"
        else
          file_index += 1
          copy["id"] = "F#{file_index}"
        end
        copy
      end
    end

    def write_workflow_state(state, suffix:)
      timestamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
      path = File.join(@session_root, "#{timestamp}-#{suffix}.json")
      state["workflow_path"] = path
      File.write(path, JSON.pretty_generate(state))
      path
    end

    def resolve_workflow(target)
      target ||= "latest"
      if target == "latest" || target == "last"
        path = latest_session_path
        raise "no workflow sessions found" unless path

        return path
      end

      return target if File.exist?(target)

      matches = list_pending.select { |path| File.basename(path).include?(target) }
      raise "no workflow matched: #{target}" if matches.empty?
      raise "multiple workflows matched #{target}: #{matches.join(', ')}" if matches.length > 1

      matches.first
    end
  end
end
