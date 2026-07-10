
# frozen_string_literal: true

require "json"
require "open3"
require "time"
require_relative "skill_invocation_planner"
require_relative "chat_execution_history"

module SoulCore
  class ReadOnlySkillExecutionGate
    SAFE_SKILL_COMMANDS = {
      "assistant-skill-catalog" => ["ruby", "bin/soul", "assess", "assistant-skill-catalog", "--json"],
      "system.status" => ["ruby", "bin/soul", "assess", "doctor-surface", "--json"],
      "execution.history.summary" => :internal_execution_history_summary,
      "weather.report" => nil,
      "downloads.inspect" => nil,
      "cloud.providers.list" => nil,
      "youtube.song_search" => nil
    }.freeze

    EXECUTION_ENABLED_SKILLS = [
      "assistant-skill-catalog",
      "system.status",
      "execution.history.summary"
    ].freeze

    Execution = Struct.new(
      :ok,
      :status,
      :message,
      :skill_id,
      :risk,
      :confirmation_required,
      :executed,
      :stdout,
      :stderr,
      :exit_status,
      :blocked_by,
      :generated_at,
      :history_entry,
      keyword_init: true
    ) do
      def to_h
        {
          "ok" => ok,
          "status" => status,
          "message" => message,
          "skill_id" => skill_id,
          "risk" => risk,
          "confirmation_required" => confirmation_required,
          "executed" => executed,
          "stdout" => stdout,
          "stderr" => stderr,
          "exit_status" => exit_status,
          "blocked_by" => blocked_by,
          "generated_at" => generated_at,
          "history_entry" => history_entry
        }
      end
    end

    def initialize(root: Dir.pwd, planner: SkillInvocationPlanner.new, history: nil)
      @root = File.expand_path(root)
      @planner = planner
      @history = history || ChatExecutionHistory.new(root: @root)
    end

    def evaluate(message, execute: false, record_history: false)
      plan = @planner.plan(message)
      result = evaluate_plan(plan, execute: execute)
      record(message, result) if record_history
      result
    end

    def evaluate_plan(plan, execute: false)
      skill_id = plan.skill_id
      risk = plan.risk || "unknown"
      confirmation_required = plan.confirmation_required || risk == "approval_required"

      return blocked(plan, "No candidate skill was mapped.", ["no_candidate_skill"]) unless skill_id

      if confirmation_required || risk == "approval_required"
        return blocked(plan, "This skill requires explicit owner confirmation before execution.", ["owner_confirmation_required"])
      end

      unless safe_read_only?(skill_id, risk)
        return blocked(plan, "This skill is not in the read-only allowlist.", ["not_read_only_allowlisted"])
      end

      command = SAFE_SKILL_COMMANDS.fetch(skill_id)
      return blocked(plan, "This read-only skill is recognized but does not have a chat execution adapter yet.", ["adapter_not_implemented"]) unless command

      unless EXECUTION_ENABLED_SKILLS.include?(skill_id)
        return dry_run(plan, "Read-only execution is allowed for #{skill_id}, but this skill is not enabled for Phase 54 execution yet.", ["phase54_not_enabled_for_actual_execution"])
      end

      return dry_run(plan, "Read-only execution is allowed for #{skill_id}, but execution was not requested.", ["dry_run_not_execute_requested"]) unless execute

      if command == :internal_execution_history_summary
        return internal_history_summary(plan)
      end

      stdout, stderr, status = Open3.capture3(*command, chdir: @root)
      ok = status.success?

      Execution.new(
        ok: ok,
        status: ok ? "executed" : "failed",
        message: ok ? "Executed read-only skill #{skill_id}." : "Read-only skill #{skill_id} failed.",
        skill_id: skill_id,
        risk: risk,
        confirmation_required: false,
        executed: true,
        stdout: stdout,
        stderr: stderr,
        exit_status: status.exitstatus,
        blocked_by: [],
        generated_at: Time.now.iso8601,
        history_entry: nil
      )
    end

    def explain(message, execute: false, record_history: false)
      result = evaluate(message, execute: execute, record_history: record_history)
      lines = []
      lines << "Read-only skill execution gate"
      lines << "skill_id: #{result.skill_id || 'none'}"
      lines << "risk: #{result.risk || 'unknown'}"
      lines << "confirmation_required: #{result.confirmation_required}"
      lines << "executed: #{result.executed}"
      lines << "status: #{result.status}"
      lines << "message: #{result.message}"
      lines << "history_recorded: #{!result.history_entry.nil?}"
      lines << "blocked_by:"
      if result.blocked_by.empty?
        lines << "- none"
      else
        result.blocked_by.each { |item| lines << "- #{item}" }
      end
      lines << "exit_status: #{result.exit_status}" if result.exit_status
      lines.join("\n")
    end

    private

    def internal_history_summary(plan)
      summary = @history.summary(limit: 10)
      entries = Array(summary["entries"])
      counts_by_status = Hash.new(0)
      counts_by_skill = Hash.new(0)

      @history.entries.each do |entry|
        counts_by_status[entry["status"] || "unknown"] += 1
        counts_by_skill[entry["skill_id"] || "none"] += 1
      end

      payload = {
        "ok" => true,
        "skill_id" => plan.skill_id,
        "path" => summary["path"],
        "total_entries" => summary["count"],
        "shown_entries" => entries.length,
        "counts_by_status" => counts_by_status.sort.to_h,
        "counts_by_skill" => counts_by_skill.sort.to_h,
        "latest" => entries.last
      }

      Execution.new(
        ok: true,
        status: "executed",
        message: "Executed read-only skill #{plan.skill_id}.",
        skill_id: plan.skill_id,
        risk: plan.risk,
        confirmation_required: false,
        executed: true,
        stdout: JSON.pretty_generate(payload) + "\n",
        stderr: "",
        exit_status: 0,
        blocked_by: [],
        generated_at: Time.now.iso8601,
        history_entry: nil
      )
    end

    def record(message, result)
      result.history_entry = @history.record(result, message: message)
    end

    def safe_read_only?(skill_id, risk)
      risk == "read_only" && SAFE_SKILL_COMMANDS.key?(skill_id)
    end

    def dry_run(plan, message, blocked_by)
      Execution.new(
        ok: true,
        status: "ready",
        message: message,
        skill_id: plan.skill_id,
        risk: plan.risk,
        confirmation_required: false,
        executed: false,
        stdout: "",
        stderr: "",
        exit_status: nil,
        blocked_by: blocked_by,
        generated_at: Time.now.iso8601,
        history_entry: nil
      )
    end

    def blocked(plan, message, blocked_by)
      Execution.new(
        ok: false,
        status: "blocked",
        message: message,
        skill_id: plan.skill_id,
        risk: plan.risk,
        confirmation_required: plan.confirmation_required,
        executed: false,
        stdout: "",
        stderr: "",
        exit_status: nil,
        blocked_by: blocked_by,
        generated_at: Time.now.iso8601,
        history_entry: nil
      )
    end
  end
end
