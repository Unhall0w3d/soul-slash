
# frozen_string_literal: true

require "json"
require "open3"
require "time"
require_relative "skill_invocation_planner"

module SoulCore
  class ReadOnlySkillExecutionGate
    SAFE_SKILL_COMMANDS = {
      "assistant-skill-catalog" => ["ruby", "bin/soul", "assess", "assistant-skill-catalog", "--json"],
      "system.status" => ["ruby", "bin/soul", "assess", "doctor-surface", "--json"],
      "weather.report" => nil,
      "downloads.inspect" => nil,
      "cloud.providers.list" => nil,
      "youtube.song_search" => nil
    }.freeze

    EXECUTION_ENABLED_SKILLS = [
      "assistant-skill-catalog",
      "system.status"
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
          "generated_at" => generated_at
        }
      end
    end

    def initialize(root: Dir.pwd, planner: SkillInvocationPlanner.new)
      @root = File.expand_path(root)
      @planner = planner
    end

    def evaluate(message, execute: false)
      plan = @planner.plan(message)
      evaluate_plan(plan, execute: execute)
    end

    def evaluate_plan(plan, execute: false)
      skill_id = plan.skill_id
      risk = plan.risk || "unknown"
      confirmation_required = plan.confirmation_required || risk == "approval_required"

      unless skill_id
        return blocked(plan, "No candidate skill was mapped.", ["no_candidate_skill"])
      end

      if confirmation_required || risk == "approval_required"
        return blocked(plan, "This skill requires explicit owner confirmation before execution.", ["owner_confirmation_required"])
      end

      unless safe_read_only?(skill_id, risk)
        return blocked(plan, "This skill is not in the read-only allowlist.", ["not_read_only_allowlisted"])
      end

      command = SAFE_SKILL_COMMANDS.fetch(skill_id)
      unless command
        return blocked(plan, "This read-only skill is recognized but does not have a chat execution adapter yet.", ["adapter_not_implemented"])
      end

      unless EXECUTION_ENABLED_SKILLS.include?(skill_id)
        return dry_run(plan, "Read-only execution is allowed for #{skill_id}, but this skill is not enabled for Phase 49 execution yet.", ["phase49_not_enabled_for_actual_execution"])
      end

      return dry_run(plan, "Read-only execution is allowed for #{skill_id}, but execution was not requested.", ["dry_run_not_execute_requested"]) unless execute

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
        generated_at: Time.now.iso8601
      )
    end

    def explain(message, execute: false)
      result = evaluate(message, execute: execute)
      lines = []
      lines << "Read-only skill execution gate"
      lines << "skill_id: #{result.skill_id || 'none'}"
      lines << "risk: #{result.risk || 'unknown'}"
      lines << "confirmation_required: #{result.confirmation_required}"
      lines << "executed: #{result.executed}"
      lines << "status: #{result.status}"
      lines << "message: #{result.message}"
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
        generated_at: Time.now.iso8601
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
        generated_at: Time.now.iso8601
      )
    end
  end
end
