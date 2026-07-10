# frozen_string_literal: true

require "json"
require "time"
require_relative "execution_adapter_registry"

module SoulCore
  class ExecutionAdapterRegistryAssessor
    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
      @registry = ExecutionAdapterRegistry.new
    end

    def assess
      data = @registry.summary
      blockers = []
      blockers << "Expected at least seven registered adapters" unless data["adapter_count"].to_i >= 7
      blockers << "Expected exactly three enabled adapters" unless data["enabled_count"] == 3
      blockers << "Expected downloads.inspect registered disabled" unless @registry.find("downloads.inspect") && !@registry.enabled?("downloads.inspect")
      blockers << "Expected system.status command metadata" unless @registry.command_for("system.status").is_a?(Array)
      blockers << "Expected history summary handler" unless @registry.internal_handler_for("execution.history.summary") == "execution_history_summary"
      { "ok" => blockers.empty?, "assessment" => "execution_adapter_registry", "phase" => 55, "generated_at" => Time.now.iso8601, "root" => @root, "status" => blockers.empty? ? "ready" : "blocked", "registry" => data, "blockers" => blockers, "verification" => { "has_enabled_adapters" => data["enabled_count"] == 3, "has_blocked_adapters" => data["blocked_count"].to_i >= 1, "downloads_inspect_registered_disabled" => @registry.find("downloads.inspect") && !@registry.enabled?("downloads.inspect"), "system_status_has_command" => @registry.command_for("system.status").is_a?(Array), "history_summary_has_internal_handler" => @registry.internal_handler_for("execution.history.summary") == "execution_history_summary" } }
    end

    def render(report)
      [@registry.render, "", "Assessment status: #{report['status']}", "Blockers:", *(report["blockers"].empty? ? ["- None"] : report["blockers"].map { |b| "- #{b}" })].join("\n")
    end
  end
end
