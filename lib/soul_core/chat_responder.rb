# frozen_string_literal: true

require "json"
require_relative "conversation_memory_controls"
require_relative "intent_router"
require_relative "skill_invocation_planner"
require_relative "read_only_skill_execution_gate"
require_relative "chat_execution_history"
require_relative "execution_adapter_registry"
require_relative "approval_token_chat_controls"
require_relative "downloads_move_dry_run_executor"
require_relative "downloads_move_to_trash_executor"

module SoulCore
  class ChatResponder
    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
      @memory_controls = ConversationMemoryControls.new(root: @root)
      @router = IntentRouter.new
      @planner = SkillInvocationPlanner.new(router: @router)
      @history = ChatExecutionHistory.new(root: @root)
      @registry = ExecutionAdapterRegistry.new
      @gate = ReadOnlySkillExecutionGate.new(root: @root, planner: @planner, history: @history, registry: @registry)
      @approval_controls = ApprovalTokenChatControls.new(root: @root, gate: @gate)
      @dry_run_executor = DownloadsMoveDryRunExecutor.new(root: @root, gate: @gate, store: @approval_controls.store)
      @trash_executor = DownloadsMoveToTrashExecutor.new(root: @root, store: @approval_controls.store, history: @history)
    end

    def respond(message, chat_id: nil)
      text = message.to_s.strip
      lower = text.downcase
      intent = @router.route(text)

      return "I am here. Give me a thread to pull." if lower.empty?
      return @memory_controls.respond(text, chat_id: chat_id) if @memory_controls.match?(text)
      return approve_downloads_cleanup if lower.match?(/\b(approve downloads cleanup preview|approve cleanup preview)\b/)
      return list_pending_approvals if lower.match?(/\b(pending approvals|show approvals|list approvals)\b/)
      return revoke_approval(lower) if lower.match?(/\brevoke approval\b/)
      return dry_run_downloads_move(lower) if lower.match?(/\b(dry run downloads move|dry run move approved downloads|preview approved downloads move)\b/)
      return execute_downloads_move(lower) if lower.match?(/\bmove approved downloads to trash\b/)
      return @registry.render if lower.match?(/\b(adapter registry|execution adapters|list adapters|enabled adapters|blocked adapters)\b/)
      return execute_downloads_inspect(intent, text) if intent.id == "downloads_inspect"
      return execute_downloads_cleanup_plan(intent, text) if intent.id == "downloads_cleanup_plan"

      case intent.id
      when "identity"
        "I am Soul: a local assistant shaped around this environment, its owner, and the skills I can safely use."
      when "skill_catalog"
        simple_execute(intent, text, "assistant skill catalog")
      when "repo_status"
        simple_execute(intent, text, "system status")
      else
        [
          "I heard you. This request did not match an executable path.",
          "Intent: #{intent.label}",
          "Reason: #{intent.reason}",
          "Next step: #{intent.next_step}"
        ].join("\n")
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
        "Token: #{token['token_id']}",
        "Status: #{token['status']}",
        "Expires: #{token['expires_at']}",
        "Candidates: #{preview['candidate_count']}",
        "Candidate bytes: #{preview['candidate_bytes']}",
        "Mutation enabled: true, but only with the token and the literal confirm keyword."
      ].join("\n")
    end

    def list_pending_approvals
      result = @approval_controls.pending
      lines = ["Pending approvals", "Count: #{result['count']}", ""]
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
      ["Approval revoke result", "Token: #{token_id}", "Status: #{result['status']}"].join("\n")
    end

    def dry_run_downloads_move(lower)
      token_id = lower[/\b([a-f0-9]{32})\b/, 1]
      return "Provide the approval token: dry run downloads move <token>" unless token_id

      result = @dry_run_executor.execute(token_id: token_id)
      return ["Downloads move dry-run blocked.", "Reason: #{result['reason']}", "Mutation: none"].join("\n") unless result["ok"]

      [
        "Downloads move dry-run complete.",
        "Would move files: #{result['would_move_count']}",
        "Would move bytes: #{result['would_move_bytes']}",
        "Mutation: #{result['mutation']}",
        "Token consumed: #{result['token_consumed']}"
      ].join("\n")
    end

    def execute_downloads_move(lower)
      token_id = lower[/\b([a-f0-9]{32})\b/, 1]
      confirmed = lower.match?(/\bconfirm\b/)

      return "Provide the approval token: move approved downloads to trash <token> confirm" unless token_id

      result = @trash_executor.execute(token_id: token_id, confirm: confirmed)
      unless result.executed
        return [
          "Downloads move-to-trash blocked.",
          "Blocked by: #{result.blocked_by.join(', ')}",
          "Confirmation required: true",
          "Executed: false",
          result.message
        ].join("\n")
      end

      payload = JSON.parse(result.stdout)
      [
        "Downloads move-to-trash completed.",
        "Status: #{payload['status']}",
        "Attempted: #{payload['attempted_count']}",
        "Moved: #{payload['moved_count']}",
        "Failed: #{payload['failed_count']}",
        "Moved bytes: #{payload['moved_bytes']}",
        "Token status: #{payload['token_status']}",
        "Permanent delete: #{payload['permanent_delete']}",
        "Filenames omitted: #{payload['filenames_omitted']}",
        "Executed: true"
      ].join("\n")
    rescue JSON::ParserError
      "Downloads were processed, but the execution report could not be parsed."
    end

    def execute_downloads_inspect(intent, message)
      result = @gate.evaluate(message, execute: true, record_history: true)
      return gate_blocked_message("downloads inspection", result) unless result.executed && result.ok

      data = JSON.parse(result.stdout)
      [
        "I executed the read-only Downloads inspection.",
        "Files: #{data['file_count']}",
        "Directories: #{data['directory_count']}",
        "Total bytes: #{data['total_file_bytes']}",
        "Executed: true",
        "Skill: #{intent.skill_id}",
        "History recorded: true",
        "Privacy: filenames omitted."
      ].join("\n")
    end

    def execute_downloads_cleanup_plan(intent, message)
      result = @gate.evaluate(message, execute: true, record_history: true)
      return gate_blocked_message("downloads cleanup preview", result) unless result.executed && result.ok

      data = JSON.parse(result.stdout)
      [
        "I executed the Downloads cleanup preview.",
        "Action: #{data['action']}",
        "Mutation: #{data['mutation']}",
        "Candidate files: #{data['candidate_count']}",
        "Candidate bytes: #{data['candidate_bytes']}",
        "Executed: true",
        "Skill: #{intent.skill_id}",
        "History recorded: true",
        "Privacy: filenames omitted."
      ].join("\n")
    end

    def simple_execute(intent, message, label)
      result = @gate.evaluate(message, execute: true, record_history: true)
      return gate_blocked_message(label, result) unless result.executed && result.ok

      ["I executed the read-only #{label}.", "Executed: true", "Skill: #{intent.skill_id}", "History recorded: true"].join("\n")
    end

    def gate_blocked_message(label, result)
      [
        "I mapped this to #{label}, but the execution gate did not allow it.",
        "Gate status: #{result.status}",
        "Blocked by: #{result.blocked_by.join(', ')}",
        "Executed: false",
        result.message
      ].join("\n")
    end
  end
end
