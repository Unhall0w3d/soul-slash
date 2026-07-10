# frozen_string_literal: true

require "json"
require "open3"
require "time"
require_relative "skill_invocation_planner"
require_relative "chat_execution_history"
require_relative "execution_adapter_registry"

module SoulCore
  class ReadOnlySkillExecutionGate
    Execution = Struct.new(:ok, :status, :message, :skill_id, :risk, :confirmation_required, :executed, :stdout, :stderr, :exit_status, :blocked_by, :generated_at, :history_entry, keyword_init: true) do
      def to_h
        { "ok" => ok, "status" => status, "message" => message, "skill_id" => skill_id, "risk" => risk, "confirmation_required" => confirmation_required, "executed" => executed, "stdout" => stdout, "stderr" => stderr, "exit_status" => exit_status, "blocked_by" => blocked_by, "generated_at" => generated_at, "history_entry" => history_entry }
      end
    end

    def initialize(root: Dir.pwd, planner: SkillInvocationPlanner.new, history: nil, registry: ExecutionAdapterRegistry.new)
      @root = File.expand_path(root)
      @planner = planner
      @history = history || ChatExecutionHistory.new(root: @root)
      @registry = registry
    end

    attr_reader :registry

    def evaluate(message, execute: false, record_history: false)
      result = evaluate_plan(@planner.plan(message), execute: execute)
      result.history_entry = @history.record(result, message: message) if record_history
      result
    end

    def evaluate_plan(plan, execute: false)
      skill_id = plan.skill_id
      risk = plan.risk || "unknown"
      return blocked(plan, "No candidate skill was mapped.", ["no_candidate_skill"]) unless skill_id
      return blocked(plan, "This skill requires explicit owner confirmation before execution.", ["owner_confirmation_required"]) if plan.confirmation_required || risk == "approval_required"

      adapter = @registry.find(skill_id)
      return blocked(plan, "This skill is not registered in the execution adapter registry.", ["adapter_not_registered"]) unless adapter
      return blocked(plan, "This skill is not classified as a safe read-only adapter.", ["not_read_only_allowlisted"]) unless @registry.safe_read_only?(skill_id, risk)
      return blocked(plan, "This read-only skill is registered but not enabled for execution.", ["adapter_not_enabled"]) unless adapter.enabled?
      return dry_run(plan, "Read-only execution is allowed for #{skill_id}, but execution was not requested.", ["dry_run_not_execute_requested"]) unless execute

      return history_summary(plan) if adapter.internal_handler == "execution_history_summary"

      stdout, stderr, status = Open3.capture3(*adapter.command, chdir: @root)
      Execution.new(ok: status.success?, status: status.success? ? "executed" : "failed", message: "Executed read-only skill #{skill_id}.", skill_id: skill_id, risk: risk, confirmation_required: false, executed: true, stdout: stdout, stderr: stderr, exit_status: status.exitstatus, blocked_by: [], generated_at: Time.now.iso8601, history_entry: nil)
    end

    def explain(message, execute: false, record_history: false)
      r = evaluate(message, execute: execute, record_history: record_history)
      ["Read-only skill execution gate", "skill_id: #{r.skill_id || 'none'}", "risk: #{r.risk || 'unknown'}", "confirmation_required: #{r.confirmation_required}", "executed: #{r.executed}", "status: #{r.status}", "message: #{r.message}", "history_recorded: #{!r.history_entry.nil?}", "blocked_by:", *(r.blocked_by.empty? ? ["- none"] : r.blocked_by.map { |b| "- #{b}" })].join("\n")
    end

    private

    def history_summary(plan)
      counts_by_status = Hash.new(0)
      counts_by_skill = Hash.new(0)
      rows = @history.entries
      rows.each { |e| counts_by_status[e["status"] || "unknown"] += 1; counts_by_skill[e["skill_id"] || "none"] += 1 }
      payload = { "ok" => true, "skill_id" => plan.skill_id, "total_entries" => rows.length, "shown_entries" => @history.summary(limit: 10)["shown"], "counts_by_status" => counts_by_status.sort.to_h, "counts_by_skill" => counts_by_skill.sort.to_h, "latest" => rows.last }
      Execution.new(ok: true, status: "executed", message: "Executed read-only skill #{plan.skill_id}.", skill_id: plan.skill_id, risk: plan.risk, confirmation_required: false, executed: true, stdout: JSON.pretty_generate(payload) + "\n", stderr: "", exit_status: 0, blocked_by: [], generated_at: Time.now.iso8601, history_entry: nil)
    end

    def dry_run(plan, message, blocked_by)
      Execution.new(ok: true, status: "ready", message: message, skill_id: plan.skill_id, risk: plan.risk, confirmation_required: false, executed: false, stdout: "", stderr: "", exit_status: nil, blocked_by: blocked_by, generated_at: Time.now.iso8601, history_entry: nil)
    end

    def blocked(plan, message, blocked_by)
      Execution.new(ok: false, status: "blocked", message: message, skill_id: plan.skill_id, risk: plan.risk, confirmation_required: plan.confirmation_required, executed: false, stdout: "", stderr: "", exit_status: nil, blocked_by: blocked_by, generated_at: Time.now.iso8601, history_entry: nil)
    end
  end
end
