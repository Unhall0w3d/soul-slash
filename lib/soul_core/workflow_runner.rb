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
      when "weather.report"
        run_weather_report(parameters: parameters, original_text: original_text)
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

    def run_weather_report(parameters:, original_text:)
      location = parameters["location"].to_s.strip
      units = parameters.fetch("units", ENV.fetch("SOUL_WEATHER_UNITS", "fahrenheit"))
      location_source = parameters.fetch("location_source", location.empty? ? "missing" : "explicit")
      home_location = parameters["home_location"].to_s.strip
      home_location = ENV.fetch("SOUL_WEATHER_LOCATION", "").to_s.strip if home_location.empty?

      if location_source == "default_home" && !home_location.empty?
        state = {
          "workflow" => "weather.report",
          "status" => "waiting_for_weather_location_choice",
          "generated_at" => Time.now.iso8601,
          "updated_at" => Time.now.iso8601,
          "original_text" => original_text,
          "parameters" => {
            "location" => home_location,
            "location_source" => "default_home",
            "home_location" => home_location,
            "units" => units
          },
          "skill_runs" => [],
          "next_expected" => "weather_location_choice",
          "verification" => {
            "home_location_present" => true,
            "brief_report_generated" => false,
            "complete" => false
          }
        }

        workflow_path = write_workflow_state(state, suffix: "weather.report")
        state["workflow_path"] = workflow_path
        save_session(state)

        return {
          ok: true,
          workflow_path: workflow_path,
          state: state,
          user_message: @renderer.render_weather_location_choice(state)
        }
      end

      if location.empty?
        state = {
          "workflow" => "weather.report",
          "status" => "needs_location",
          "generated_at" => Time.now.iso8601,
          "updated_at" => Time.now.iso8601,
          "original_text" => original_text,
          "parameters" => {
            "location" => nil,
            "location_source" => "missing",
            "home_location" => home_location.empty? ? nil : home_location,
            "units" => units
          },
          "skill_runs" => [],
          "next_expected" => "new_request_with_location",
          "verification" => {
            "location_present" => false,
            "weather_fetch_ok" => false,
            "air_quality_fetch_ok" => false,
            "complete" => false
          }
        }

        workflow_path = write_workflow_state(state, suffix: "weather.report")
        state["workflow_path"] = workflow_path
        save_session(state)

        return {
          ok: false,
          workflow_path: workflow_path,
          state: state,
          user_message: @renderer.render_weather_needs_location(state)
        }
      end

      run_weather_report_now(
        location: location,
        units: units,
        original_text: original_text,
        location_source: location_source,
        home_location: home_location
      )
    end

    def run_weather_report_now(location:, units:, original_text:, location_source:, home_location:)
      registry = SkillRegistry.new
      runner = SkillRunner.new(registry: registry)
      args = ["--location", location, "--units", units]

      result = runner.run("weather.report", args: args)
      task_log_path = @task_log.write(kind: "skill.weather.report", payload: result)
      report = result[:json] || {}

      state = {
        "workflow" => "weather.report",
        "status" => result[:ok] ? "waiting_for_weather_detail_decision" : "failed",
        "generated_at" => Time.now.iso8601,
        "updated_at" => Time.now.iso8601,
        "original_text" => original_text,
        "parameters" => {
          "location" => location,
          "location_source" => location_source,
          "home_location" => home_location.empty? ? nil : home_location,
          "units" => units
        },
        "skill_runs" => [
          {
            "skill" => "weather.report",
            "args" => args,
            "ok" => result[:ok],
            "task_log" => task_log_path
          }
        ],
        "brief_report" => report,
        "next_expected" => result[:ok] ? "weather_detail_decision" : "none",
        "verification" => {
          "brief_report_generated" => result[:ok],
          "brief_report_log" => task_log_path,
          "location_present" => !location.empty?,
          "location_source" => location_source,
          "weather_fetch_ok" => report.dig("verification", "weather_fetch_ok"),
          "air_quality_fetch_ok" => report.dig("verification", "air_quality_fetch_ok"),
          "complete" => false
        }
      }

      workflow_path = write_workflow_state(state, suffix: "weather.report")
      state["workflow_path"] = workflow_path
      save_session(state)

      {
        ok: result[:ok],
        workflow_path: workflow_path,
        task_log_path: task_log_path,
        report: report,
        state: state,
        user_message: @renderer.render_weather_brief(state, report)
      }
    end

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
