# frozen_string_literal: true

require "json"
require "fileutils"
require "time"

require_relative "skill_registry"
require_relative "skill_runner"
require_relative "task_log"

module SoulCore
  class WorkflowRunner
    def initialize(workflow_root: "Soul/workflows/pending")
      @workflow_root = workflow_root
      FileUtils.mkdir_p(@workflow_root)
      @task_log = TaskLog.new
    end

    def run(intent:, parameters:, original_text:)
      case intent
      when "downloads.cleanup"
        run_downloads_cleanup(parameters: parameters, original_text: original_text)
      else
        raise ArgumentError, "unsupported workflow intent: #{intent}"
      end
    end

    def list_pending
      Dir.glob(File.join(@workflow_root, "*.json")).sort
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

      skill_args = ["--path", target_path, "--older-than-days", older_than_days.to_s]
      plan_result = runner.run("downloads.cleanup_plan", args: skill_args)
      task_log_path = @task_log.write(kind: "skill.downloads.cleanup_plan", payload: plan_result)

      plan = plan_result[:json] || {}
      summary = plan.fetch("summary", {})
      proposed = plan.fetch("proposed_actions", {})
      candidates = proposed.fetch("would_move_to_trash_after_approval", [])

      state = {
        workflow: "downloads.cleanup",
        status: plan_result[:ok] ? "waiting_for_confirmation" : "failed",
        generated_at: Time.now.iso8601,
        original_text: original_text,
        parameters: {
          target_path: target_path,
          older_than_days: older_than_days,
          include_directories: true,
          recursive: false
        },
        skill_runs: [
          {
            skill: "downloads.cleanup_plan",
            args: skill_args,
            ok: plan_result[:ok],
            task_log: task_log_path
          }
        ],
        summary: summary,
        candidate_count: candidates.length,
        candidates: candidates,
        next_options: next_options(candidates),
        verification: {
          plan_generated: plan_result[:ok],
          plan_log: task_log_path,
          moved_files: 0,
          moved_directories: 0,
          deleted_files: 0,
          stopped_before_execution: true,
          requires_confirmation_before_trash: true
        }
      }

      workflow_path = write_workflow_state(state)
      state[:workflow_path] = workflow_path

      {
        ok: plan_result[:ok],
        workflow_path: workflow_path,
        task_log_path: task_log_path,
        plan: plan,
        state: state,
        user_message: render_user_message(plan, state)
      }
    end

    def next_options(candidates)
      if candidates.empty?
        [{ label: "Nothing to move", command: nil, description: "No cleanup candidates were found." }]
      else
        [
          {
            label: "Move all candidates to Trash",
            command: "ruby bin/soul skill downloads.move_to_trash -- --latest-plan --execute --confirm MOVE_TO_TRASH",
            description: "Moves every candidate from the verified latest cleanup plan to Trash."
          },
          { label: "Cancel", command: nil, description: "Do nothing." }
        ]
      end
    end

    def render_user_message(plan, state)
      lines = []
      lines << "Workflow: downloads.cleanup"
      lines << "Status: #{state[:status]}"
      lines << "Plan log: #{state.dig(:verification, :plan_log)}"
      lines << "Workflow state: #{state[:workflow_path]}" if state[:workflow_path]
      lines << ""

      if plan["markdown_report"]
        lines << plan["markdown_report"]
      else
        lines << JSON.pretty_generate(plan)
      end

      lines << ""
      lines << "## Next Options"
      lines << ""
      state[:next_options].each do |option|
        lines << "- #{option[:label]}: #{option[:description]}"
        lines << "  Command: `#{option[:command]}`" if option[:command]
      end
      lines.join("\n")
    end

    def write_workflow_state(state)
      timestamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
      path = File.join(@workflow_root, "#{timestamp}-downloads.cleanup.json")
      File.write(path, JSON.pretty_generate(state.merge(workflow_path: path)))
      path
    end

    def resolve_workflow(target)
      target ||= "latest"
      if target == "latest" || target == "last"
        path = list_pending.last
        raise "no pending workflow states found" unless path
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
