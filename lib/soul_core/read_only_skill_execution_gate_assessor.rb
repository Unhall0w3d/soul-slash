# frozen_string_literal: true

require "json"
require "time"
require "tmpdir"
require_relative "read_only_skill_execution_gate"

module SoulCore
  class ReadOnlySkillExecutionGateAssessor
    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      Dir.mktmpdir("soul-gate-registry-") do |dir|
        history = ChatExecutionHistory.new(root: @root, path: File.join(dir, "history.jsonl"))
        gate = ReadOnlySkillExecutionGate.new(root: @root, history: history)
        gate.evaluate("what skills do you have?", execute: true, record_history: true)
        gate.evaluate("check repo health", execute: true, record_history: true)

        samples = {
          "what skills do you have?" => ["assistant-skill-catalog", true, nil],
          "check repo health" => ["system.status", true, nil],
          "execution history summary" => ["execution.history.summary", true, nil],
          "inspect my downloads" => ["downloads.inspect", false, "adapter_not_enabled"],
          "move approved downloads to trash" => ["downloads.move_to_trash", false, "owner_confirmation_required"]
        }.map do |msg, (skill, executed, blocker)|
          r = gate.evaluate(msg, execute: true)
          matched = r.skill_id == skill && r.executed == executed && (blocker.nil? || r.blocked_by.include?(blocker))
          { "message" => msg, "actual" => { "skill_id" => r.skill_id, "status" => r.status, "executed" => r.executed, "blocked_by" => r.blocked_by }, "matched" => matched }
        end

        blockers = []
        blockers << "One or more registry gate samples failed" unless samples.all? { |s| s["matched"] }
        { "ok" => blockers.empty?, "assessment" => "read_only_skill_execution_gate", "phase" => 55, "generated_at" => Time.now.iso8601, "root" => @root, "status" => blockers.empty? ? "ready" : "blocked", "samples" => samples, "registry" => gate.registry.summary, "blockers" => blockers, "verification" => { "uses_adapter_registry" => gate.registry.summary["enabled_count"] == 3, "enabled_adapters_execute" => samples.count { |s| s.dig("actual","executed") == true } == 3, "disabled_adapter_blocked" => samples.any? { |s| s.dig("actual","blocked_by").include?("adapter_not_enabled") }, "approval_required_blocked" => samples.any? { |s| s.dig("actual","blocked_by").include?("owner_confirmation_required") } } }
      end
    end

    def render(report)
      lines = ["Soul Read-Only Gate Registry Integration Assessment", "Generated: #{report['generated_at']}", "Status: #{report['status']}", "Enabled adapters: #{report.dig('registry','enabled_count')}", "Blocked adapters: #{report.dig('registry','blocked_count')}", "", "Samples"]
      report["samples"].each { |s| lines << "- #{s['message']}: #{s['matched'] ? 'ok' : 'mismatch'}"; lines << "  skill_id: #{s.dig('actual','skill_id')}"; lines << "  executed: #{s.dig('actual','executed')}"; lines << "  blocked_by: #{s.dig('actual','blocked_by').join(', ')}" }
      lines << ""
      lines << "Blockers"
      report["blockers"].empty? ? lines << "- None" : report["blockers"].each { |b| lines << "- #{b}" }
      lines.join("\n")
    end
  end
end
