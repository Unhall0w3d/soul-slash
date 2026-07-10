# frozen_string_literal: true

require "json"
require_relative "intent_router"
require_relative "skill_invocation_planner"
require_relative "read_only_skill_execution_gate"
require_relative "chat_execution_history"
require_relative "execution_adapter_registry"

module SoulCore
  class ChatResponder
    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
      @router = IntentRouter.new
      @planner = SkillInvocationPlanner.new(router: @router)
      @history = ChatExecutionHistory.new(root: @root)
      @registry = ExecutionAdapterRegistry.new
      @gate = ReadOnlySkillExecutionGate.new(root: @root, planner: @planner, history: @history, registry: @registry)
    end

    def respond(message)
      text = message.to_s.strip
      lower = text.downcase
      intent = @router.route(text)

      return "I am here. Give me a thread to pull." if lower.empty?
      return @registry.render if lower.match?(/\b(adapter registry|execution adapters|list adapters|enabled adapters|blocked adapters)\b/)
      return prune_history(lower) if lower.match?(/\b(prune execution history|prune history)\b/)
      return export_history(lower) if lower.match?(/\b(export execution history|export history)\b/)
      return clear_history(lower) if lower.match?(/\b(clear execution history|clear history)\b/)
      return execute_downloads_inspect(intent, text) if intent.id == "downloads_inspect"
      return execute_history_summary(intent, text) if intent.id == "execution_history_summary"
      return render_history(lower) if lower.match?(/\b(execution history|recent executions|show executions)\b/) || lower == "history"
      return route_explanation(text) if lower.match?(/\b(intent|route|classify)\b/) && lower.match?(/\b(this|message|request|utterance)\b/)
      return @planner.explain(text) if lower.match?(/\b(plan|prepare)\b/) && lower.match?(/\b(skill|invocation|execution|run)\b/)
      return @gate.explain(text, execute: false, record_history: false) if lower.match?(/\b(execute|run|invoke)\b/) && lower.match?(/\b(skill|this|it|request)\b/)

      case intent.id
      when "identity"
        identity
      when "skill_catalog"
        execute_skill_catalog(intent, text)
      when "repo_status"
        execute_system_status(intent, text)
      when "pending_work"
        pending_work
      when "downloads_move_to_trash", "downloads_cleanup_plan", "weather_request", "cloud_providers", "youtube_request", "skill_brief"
        gated_skill(intent, text)
      else
        fallback(intent)
      end
    end

    private

    def execute_downloads_inspect(intent, message)
      result = @gate.evaluate(message, execute: true, record_history: true)
      return gate_blocked_message("downloads inspection", result) unless result.executed && result.ok

      data = JSON.parse(result.stdout)
      extensions = data["extensions"] || {}

      [
        "I executed the read-only Downloads inspection.",
        "",
        "Path: #{data['path']}",
        "Exists: #{data['exists']}",
        "Entries: #{data['entry_count']}",
        "Files: #{data['file_count']}",
        "Directories: #{data['directory_count']}",
        "Hidden entries: #{data['hidden_entry_count']}",
        "Total bytes: #{data['total_file_bytes']}",
        "Largest file bytes: #{data['largest_file_bytes']}",
        "Extensions: #{extensions.empty? ? 'none' : extensions.map { |key, value| "#{key}=#{value}" }.join(', ')}",
        "",
        "Executed: true",
        "Skill: #{intent.skill_id}",
        "Risk: #{intent.risk}",
        "History recorded: true",
        "Privacy: filenames omitted, because apparently we are trying not to be a creep."
      ].join("\n")
    rescue JSON::ParserError
      [
        "I executed Downloads inspection, but could not parse the output as JSON.",
        "History recorded: true",
        "",
        result.stdout.to_s[0, 1200]
      ].join("\n")
    end

    def execute_history_summary(intent, message)
      result = @gate.evaluate(message, execute: true, record_history: true)
      return gate_blocked_message("execution history summary", result) unless result.executed && result.ok

      data = JSON.parse(result.stdout)
      counts_by_status = data["counts_by_status"] || {}
      counts_by_skill = data["counts_by_skill"] || {}

      [
        "I executed the read-only execution history summary.",
        "",
        "Total entries: #{data['total_entries'] || 0}",
        "Shown entries: #{data['shown_entries'] || 0}",
        "Counts by status: #{counts_by_status.empty? ? 'none' : counts_by_status.map { |key, value| "#{key}=#{value}" }.join(', ')}",
        "Counts by skill: #{counts_by_skill.empty? ? 'none' : counts_by_skill.map { |key, value| "#{key}=#{value}" }.join(', ')}",
        "",
        "Executed: true",
        "Skill: #{intent.skill_id}",
        "Risk: #{intent.risk}",
        "History recorded: true",
        "Adapter registry: enabled"
      ].join("\n")
    rescue JSON::ParserError
      [
        "I executed the read-only execution history summary, but could not parse the output as JSON.",
        "History recorded: true",
        "",
        result.stdout.to_s[0, 1200]
      ].join("\n")
    end

    def execute_skill_catalog(intent, message)
      result = @gate.evaluate(message, execute: true, record_history: true)
      return gate_blocked_message("assistant skill catalog", result) unless result.executed && result.ok

      [
        "I executed the read-only assistant skill catalog.",
        "",
        "Executed: true",
        "Skill: #{intent.skill_id}",
        "Risk: #{intent.risk}",
        "History recorded: true"
      ].join("\n")
    end

    def execute_system_status(intent, message)
      result = @gate.evaluate(message, execute: true, record_history: true)
      return gate_blocked_message("system status", result) unless result.executed && result.ok

      [
        "I executed the read-only system status check.",
        "",
        "Executed: true",
        "Skill: #{intent.skill_id}",
        "Risk: #{intent.risk}",
        "History recorded: true"
      ].join("\n")
    end

    def prune_history(lower)
      keep = ChatExecutionHistory.keep_count_from_text(lower, default: 10)
      confirmed = lower.include?("confirm") || lower.include?("--confirm")
      result = @history.prune(keep: keep, confirm: confirmed)
      lines = []
      lines << (confirmed ? "Execution history pruned." : "Execution history prune preview.")
      lines << "Status: #{result['status']}"
      lines << "Total before: #{result['total_before']}"
      lines << "Keep: #{result['keep']}"
      lines << "Would remove: #{result['would_remove']}"
      lines << "Would keep: #{result['would_keep']}"
      lines << "Pruned: #{result['pruned']}"
      lines << "Exported removed entries: #{result.dig('export', 'count') || 0}"
      lines << "Export path: #{result.dig('export', 'path') || 'none'}"
      lines << "Add `confirm` to actually prune. This is not negotiable, because logs are cheaper than regret." unless confirmed
      lines.join("\n")
    rescue StandardError => error
      "Execution history prune failed: #{error.class}: #{error.message}"
    end

    def export_history(lower)
      format = lower.include?("jsonl") ? "jsonl" : "json"
      filters = ChatExecutionHistory.filters_from_text(lower)
      result = @history.export(format: format, filters: filters)
      [
        "Execution history exported.",
        "Format: #{result['format']}",
        "Entries: #{result['count']}",
        "Filters: #{result['filters'].empty? ? 'none' : result['filters'].map { |key, value| "#{key}=#{value}" }.join(', ')}",
        "Path: #{result['path']}",
        "This is still runtime/private data. Do not commit it, unless you enjoy turning audit logs into public confetti."
      ].join("\n")
    rescue StandardError => error
      "Execution history export failed: #{error.class}: #{error.message}"
    end

    def clear_history(lower)
      confirmed = lower.include?("confirm") || lower.include?("--confirm")
      result = @history.clear(confirm: confirmed)
      [
        result["message"],
        "Status: #{result['status']}",
        "Deleted: #{result['deleted']}",
        "Path: #{result['path']}"
      ].join("\n")
    end

    def render_history(lower)
      filters = ChatExecutionHistory.filters_from_text(lower)
      @history.render(limit: 10, filters: filters)
    end

    def route_explanation(text)
      "I classified that as:\n#{@router.explain(text)}"
    end

    def gate_blocked_message(label, result)
      [
        "I mapped this to #{label}, but the execution gate did not allow it.",
        "Gate status: #{result.status}",
        "Blocked by: #{result.blocked_by.join(', ')}",
        "History recorded: #{!result.history_entry.nil?}",
        result.message
      ].join("\n")
    end

    def gated_skill(intent, message)
      result = @gate.evaluate(message, execute: false, record_history: true)
      [
        "I can map this request to the read-only execution gate.",
        "",
        "Intent: #{intent.label}",
        "Skill candidate: #{intent.skill_id || 'none'}",
        "Risk: #{intent.risk}",
        "Confirmation required: #{intent.confirmation_required}",
        "Executed: false",
        "Gate status: #{result.status}",
        "Blocked by: #{result.blocked_by.join(', ')}",
        "History recorded: true",
        "",
        result.message
      ].join("\n")
    end

    def identity
      "I am Soul: a local assistant shaped around this environment, its owner, and the skills I can safely use."
    end

    def pending_work
      "The next planned implementation thread is downloads cleanup preview. Inspection can now observe without touching, which is the bare minimum for civilized software."
    end

    def fallback(intent)
      [
        "I heard you. I can route intents and execute registered read-only adapters, but this request did not match an executable path.",
        "",
        "Intent: #{intent.label}",
        "Reason: #{intent.reason}",
        "Next step: #{intent.next_step}"
      ].join("\n")
    end
  end
end
