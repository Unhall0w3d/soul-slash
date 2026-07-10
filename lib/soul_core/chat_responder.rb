# frozen_string_literal: true

require "json"
require_relative "intent_router"
require_relative "skill_invocation_planner"
require_relative "read_only_skill_execution_gate"
require_relative "chat_execution_history"
require_relative "execution_adapter_registry"
require_relative "approval_token_chat_controls"

module SoulCore
  class ChatResponder
    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
      @router = IntentRouter.new
      @planner = SkillInvocationPlanner.new(router: @router)
      @history = ChatExecutionHistory.new(root: @root)
      @registry = ExecutionAdapterRegistry.new
      @gate = ReadOnlySkillExecutionGate.new(
        root: @root,
        planner: @planner,
        history: @history,
        registry: @registry
      )
      @approval_controls = ApprovalTokenChatControls.new(
        root: @root,
        gate: @gate
      )
    end

    def respond(message)
      text = message.to_s.strip
      lower = text.downcase
      intent = @router.route(text)

      return "I am here. Give me a thread to pull." if lower.empty?
      return approve_downloads_cleanup if lower.match?(/\b(approve downloads cleanup preview|approve cleanup preview)\b/)
      return list_pending_approvals if lower.match?(/\b(pending approvals|show approvals|list approvals)\b/)
      return revoke_approval(lower) if lower.match?(/\brevoke approval\b/)
      return @registry.render if lower.match?(/\b(adapter registry|execution adapters|list adapters|enabled adapters|blocked adapters)\b/)
      return prune_history(lower) if lower.match?(/\b(prune execution history|prune history)\b/)
      return export_history(lower) if lower.match?(/\b(export execution history|export history)\b/)
      return clear_history(lower) if lower.match?(/\b(clear execution history|clear history)\b/)
      return execute_downloads_inspect(intent, text) if intent.id == "downloads_inspect"
      return execute_downloads_cleanup_plan(intent, text) if intent.id == "downloads_cleanup_plan"
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
      when "downloads_move_to_trash", "weather_request", "cloud_providers", "youtube_request", "skill_brief"
        gated_skill(intent, text)
      else
        fallback(intent)
      end
    end

    private

    def approve_downloads_cleanup
      result = @approval_controls.approve_downloads_cleanup_preview
      return "Approval failed: #{result['reason']}: #{result['message']}" unless result["ok"]

      token = result.fetch("token")
      preview = result.fetch("preview")

      [
        "Downloads cleanup preview approved.",
        "",
        "Token: #{token['token_id']}",
        "Status: #{token['status']}",
        "Expires: #{token['expires_at']}",
        "Candidates: #{preview['candidate_count']}",
        "Candidate bytes: #{preview['candidate_bytes']}",
        "Rule: #{preview['candidate_rule']}",
        "Mutation enabled: false",
        "",
        "This token authorizes no action yet. Phase 60 builds the keyring, not the door."
      ].join("\n")
    end

    def list_pending_approvals
      result = @approval_controls.pending
      lines = [
        "Pending approvals",
        "Count: #{result['count']}",
        "Mutation enabled: false",
        ""
      ]

      if result["tokens"].empty?
        lines << "- none"
      else
        result["tokens"].each do |token|
          lines << "- #{token['token_id']}"
          lines << "  skill: #{token['skill_id']}"
          lines << "  expires: #{token['expires_at']}"
          lines << "  status: #{token['status']}"
        end
      end

      lines.join("\n")
    end

    def revoke_approval(lower)
      token_id = lower[/\brevoke approval\s+([a-f0-9]{32})\b/, 1]
      return "Provide the full approval token ID: revoke approval <token>" unless token_id

      result = @approval_controls.revoke(token_id)
      [
        "Approval revoke result",
        "Token: #{token_id}",
        "Status: #{result['status']}",
        "Mutation enabled: false"
      ].join("\n")
    end

    def execute_downloads_cleanup_plan(intent, message)
      result = @gate.evaluate(message, execute: true, record_history: true)
      return gate_blocked_message("downloads cleanup preview", result) unless result.executed && result.ok

      data = JSON.parse(result.stdout)
      extensions = data["candidate_extensions"] || {}
      ages = data["candidate_age_buckets"] || {}
      sizes = data["candidate_size_buckets"] || {}

      [
        "I executed the Downloads cleanup preview.",
        "",
        "Action: #{data['action']}",
        "Mutation: #{data['mutation']}",
        "Rule: #{data['candidate_rule']}",
        "Path: #{data['path']}",
        "Files scanned: #{data['file_count']}",
        "Candidate files: #{data['candidate_count']}",
        "Candidate bytes: #{data['candidate_bytes']}",
        "Candidate extensions: #{extensions.empty? ? 'none' : extensions.map { |key, value| "#{key}=#{value}" }.join(', ')}",
        "Candidate age buckets: #{ages.empty? ? 'none' : ages.map { |key, value| "#{key}=#{value}" }.join(', ')}",
        "Candidate size buckets: #{sizes.empty? ? 'none' : sizes.map { |key, value| "#{key}=#{value}" }.join(', ')}",
        "",
        "Executed: true",
        "Skill: #{intent.skill_id}",
        "Risk: #{intent.risk}",
        "History recorded: true",
        "Privacy: filenames omitted. Nothing was moved or deleted."
      ].join("\n")
    rescue JSON::ParserError
      [
        "I executed the Downloads cleanup preview, but could not parse the output as JSON.",
        "History recorded: true",
        "",
        result.stdout.to_s[0, 1200]
      ].join("\n")
    end

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
        "Privacy: filenames omitted."
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

      [
        "I executed the read-only execution history summary.",
        "",
        "Executed: true",
        "Skill: #{intent.skill_id}",
        "Risk: #{intent.risk}",
        "History recorded: true"
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
      lines << "Add `confirm` to actually prune." unless confirmed
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
        "Path: #{result['path']}"
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
        "I can map this request to the execution gate.",
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
      "The next planned implementation thread is the approval-gated Downloads dry-run executor. Tokens exist now, but still authorize no mutation."
    end

    def fallback(intent)
      [
        "I heard you. I can route intents and execute registered non-mutating adapters, but this request did not match an executable path.",
        "",
        "Intent: #{intent.label}",
        "Reason: #{intent.reason}",
        "Next step: #{intent.next_step}"
      ].join("\n")
    end
  end
end
