# frozen_string_literal: true

require_relative "conversation_workspace_service"

module SoulCore
  class ConversationWorkspaceControls
    ARTIFACT_ID = /art_[a-z0-9_]+/i
    DELIVERY_ID = /del_[a-z0-9_]+/i

    def initialize(root:, service: nil)
      @service = service || ConversationWorkspaceService.new(root: root)
    end

    def match?(message)
      patterns.any? { |pattern| message.to_s.strip.match?(pattern) }
    end

    def respond(message, chat_id: nil)
      text = message.to_s.strip
      return help if text.match?(patterns[0])
      return render_list(@service.list, "Shared workspace") if text.match?(patterns[1])
      return render_list(@service.list(chat_id: chat_id), "Workspace for this chat") if text.match?(patterns[2])
      return render_list(@service.inbox(chat_id: chat_id), "Artifact inbox") if text.match?(patterns[3])
      return render_detail(@service.detail(artifact_id: text[ARTIFACT_ID])) if text.match?(patterns[4])
      return render_delivery(@service.deliver(artifact_id: text[ARTIFACT_ID], chat_id: chat_id)) if text.match?(patterns[5])
      return render_state(@service.change_state(delivery_id: text[DELIVERY_ID], chat_id: chat_id, state: "seen")) if text.match?(patterns[6])
      return render_state(@service.change_state(delivery_id: text[DELIVERY_ID], chat_id: chat_id, state: "dismissed")) if text.match?(patterns[7])
      return terminal("canceled", "Workspace request canceled.") if text.match?(patterns[8])
      return terminal("awaiting_input", "Name exactly one artifact ID: deliver artifact <id> to inbox.") if text.match?(patterns[9])
      return terminal("awaiting_input", "Name the delivery ID to dismiss: dismiss delivery <id>.") if text.match?(patterns[10])
      return terminal("failed", "Background workspace watching is unavailable. Use 'show workspace' for a foreground refresh.") if text.match?(patterns[11])

      terminal("failed", "Workspace control did not match a supported command.")
    rescue ArgumentError, RuntimeError => error
      terminal("failed", error.message)
    end

    private

    def patterns
      @patterns ||= [
        /\A\s*(?:workspace help|help workspace|help inbox)\s*[?.!]*\z/i,
        /\A\s*(?:(?:show|list)\s+(?:shared\s+)?workspace|what\s+is\s+in\s+my\s+workspace)\s*[?.!]*\z/i,
        /\A\s*(?:(?:show|list)\s+workspace\s+for\s+this\s+chat|show\s+me\s+what\s+soul\s+created\s+in\s+this\s+chat)\s*[?.!]*\z/i,
        /\A\s*(?:show|list)\s+(?:artifact\s+)?inbox\s*[?.!]*\z/i,
        /\A\s*show\s+workspace\s+artifact\s+#{ARTIFACT_ID}\s*[?.!]*\z/i,
        /\A\s*deliver\s+artifact\s+#{ARTIFACT_ID}\s+to\s+(?:the\s+)?inbox\s*[?.!]*\z/i,
        /\A\s*mark\s+delivery\s+#{DELIVERY_ID}\s+seen\s*[?.!]*\z/i,
        /\A\s*dismiss\s+delivery\s+#{DELIVERY_ID}\s*[?.!]*\z/i,
        /\A\s*cancel\s+workspace\s+request\s*[?.!]*\z/i,
        /\A\s*(?:send|deliver)\s+that\s+to\s+(?:the\s+)?inbox\s*[?.!]*\z/i,
        /\A\s*dismiss\s+it\s*[?.!]*\z/i,
        /\A.*\b(?:keep watching|watch)\b.*\bworkspace\b.*\z/i
      ].freeze
    end

    def help
      [
        "Workspace controls",
        "- show workspace",
        "- show workspace for this chat",
        "- show inbox",
        "- show workspace artifact <artifact-id>",
        "- deliver artifact <artifact-id> to inbox",
        "- mark delivery <delivery-id> seen",
        "- dismiss delivery <delivery-id>",
        "- cancel workspace request",
        "Lifecycle: complete",
        "Content read: no",
        "Mutation: none"
      ].join("\n")
    end

    def render_list(result, heading)
      return render_terminal_result(result) unless result["ok"]

      lines = [heading, "Lifecycle: complete", "Count: #{result.fetch('count')}", ""]
      if result.fetch("records").empty?
        lines << "- none"
      else
        result.fetch("records").each do |record|
          lines << "- #{record['artifact_id']}: #{record['title']}"
          lines << "  kind: #{record['kind']}"
          lines << "  lifecycle: #{record['lifecycle']}"
          lines << "  privacy: #{record['privacy']}"
          lines << "  revision of: #{record['revision_of_artifact_id']}" if record["revision_of_artifact_id"]
          lines << "  delivery: #{record['delivery_state'] || 'none'}"
          lines << "  updated: #{record['workspace_updated_at']}"
        end
      end
      lines.concat(["Content read: no", "Mutation: none"])
      lines.join("\n")
    end

    def render_detail(result)
      return render_terminal_result(result) unless result["ok"]

      record = result.fetch("record")
      [
        "Workspace artifact",
        "Lifecycle: complete",
        "Artifact ID: #{record['artifact_id']}",
        "Title: #{record['title']}",
        "Kind: #{record['kind']}",
        "Artifact lifecycle: #{record['lifecycle']}",
        "Privacy: #{record['privacy']}",
        "Path: #{record['relative_path']}",
        "Size: #{record['size_bytes']} bytes",
        "SHA-256: #{record['sha256']}",
        "Revision of: #{record['revision_of_artifact_id'] || 'none'}",
        "Delivery ID: #{record['delivery_id'] || 'none'}",
        "Delivery state: #{record['delivery_state'] || 'none'}",
        "Content read: no",
        "Mutation: none"
      ].join("\n")
    end

    def render_delivery(result)
      return render_terminal_result(result) unless result["ok"]

      delivery = result.fetch("delivery")
      [
        "Artifact delivered to inbox.",
        "Lifecycle: complete",
        "Artifact ID: #{delivery['artifact_id']}",
        "Delivery ID: #{delivery['delivery_id']}",
        "Delivery state: #{delivery['latest_delivery_state']}",
        "Idempotent: #{delivery['idempotent']}",
        "File modified: no",
        "Mutation: inbox_delivery_recorded"
      ].join("\n")
    end

    def render_state(result)
      return render_terminal_result(result) unless result["ok"]

      delivery = result.fetch("delivery")
      [
        "Inbox delivery state updated.",
        "Lifecycle: complete",
        "Delivery ID: #{delivery['delivery_id']}",
        "State: #{delivery['latest_delivery_state']}",
        "Artifact lifecycle changed: no",
        "File modified: no",
        "Mutation: inbox_state_appended"
      ].join("\n")
    end

    def render_terminal_result(result)
      terminal(result.fetch("lifecycle_state"), result.fetch("reason", "workspace operation did not complete"))
    end

    def terminal(lifecycle, reason)
      [
        "Workspace operation",
        "Lifecycle: #{lifecycle}",
        "Reason: #{reason}",
        "Content read: no",
        "Mutation: none"
      ].join("\n")
    end
  end
end
