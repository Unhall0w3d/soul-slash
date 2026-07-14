# frozen_string_literal: true

require_relative "conversation_artifact_store"

module SoulCore
  class ConversationArtifactControls
    ARTIFACT_ID = /art_[a-z0-9_]+/i

    def initialize(root:, store: nil)
      @store = store || ConversationArtifactStore.new(root: root)
    end

    def match?(message)
      text = message.to_s.strip
      patterns.any? { |pattern| text.match?(pattern) }
    end

    def respond(message, chat_id: nil)
      text = message.to_s.strip

      return help if text.match?(patterns[0])
      return register(text, chat_id) if text.match?(patterns[1])
      return list_all if text.match?(patterns[2])
      return list_chat(chat_id) if text.match?(patterns[3]) || text.match?(patterns[4])
      return show(text) if text.match?(patterns[5])
      return attach(text, chat_id) if text.match?(patterns[6])
      return detach(text, chat_id) if text.match?(patterns[7])
      return archive(text) if text.match?(patterns[8])

      "Artifact control did not match a supported command.\nMutation: none"
    rescue ArgumentError, RuntimeError => error
      ["Artifact control blocked.", "Reason: #{error.message}", "Mutation: none"].join("\n")
    end

    private

    def patterns
      @patterns ||= [
        /\A\s*(?:artifact help|help artifacts?)\s*[?.!]*\z/i,
        /\A\s*register\s+artifact\s*:\s*.+\z/i,
        /\A\s*(?:list|show)\s+all\s+artifacts?\s*[?.!]*\z/i,
        /\A\s*(?:list|show)\s+(?:chat|attached)\s+artifacts?\s*[?.!]*\z/i,
        /\A\s*(?:what artifacts? (?:are|is) attached|what is attached to this chat)\s*[?.!]*\z/i,
        /\A\s*(?:show|inspect)\s+artifact\s+#{ARTIFACT_ID}\s*[?.!]*\z/i,
        /\A\s*attach\s+artifact\s+#{ARTIFACT_ID}\s*[?.!]*\z/i,
        /\A\s*detach\s+artifact\s+#{ARTIFACT_ID}\s*[?.!]*\z/i,
        /\A\s*archive\s+artifact\s+#{ARTIFACT_ID}(?:\s+confirm)?\s*[?.!]*\z/i
      ].freeze
    end

    def help
      <<~TEXT.strip
        Artifact controls
        - register artifact: <project-relative path> | <title> | <kind> | <privacy> confirm
        - list all artifacts
        - list chat artifacts
        - show artifact <id>
        - attach artifact <id>
        - detach artifact <id>
        - archive artifact <id> confirm

        Registration records metadata and attaches the file to the current chat. It does not read or modify file contents.
        Mutation: none
      TEXT
    end

    def register(text, chat_id)
      confirmed = text.match?(/\s+confirm\s*[?.!]*\z/i)
      return confirmation_required("register artifact") unless confirmed

      body = text.sub(/\A\s*register\s+artifact\s*:\s*/i, "")
                 .sub(/\s+confirm\s*[?.!]*\z/i, "")
      parts = body.split("|").map(&:strip)
      path = parts[0]
      title = parts[1]
      kind = parts[2]
      privacy = parts[3] || "project"

      record = @store.register(
        path: path,
        title: title,
        kind: kind,
        privacy: privacy,
        chat_id: chat_id,
        source: { "kind" => "manual_registration" }
      )

      [
        "Artifact registered and attached.",
        "Artifact ID: #{record['artifact_id']}",
        "Title: #{record['title']}",
        "Kind: #{record['kind']}",
        "Path: #{record['relative_path']}",
        "Privacy: #{record['privacy']}",
        "SHA-256: #{record['sha256']}",
        "File content read: no",
        "File modified: no",
        "Mutation: metadata_registered"
      ].join("\n")
    end

    def list_all
      render_list("Artifacts", @store.list)
    end

    def list_chat(chat_id)
      render_list("Artifacts attached to this chat", @store.attached_to_chat(chat_id))
    end

    def show(text)
      artifact_id = text[ARTIFACT_ID]
      record = @store.find(artifact_id)
      raise ArgumentError, "Unknown artifact ID: #{artifact_id}" unless record

      [
        "Artifact #{record['artifact_id']}",
        "Title: #{record['title']}",
        "Kind: #{record['kind']}",
        "Lifecycle: #{record['lifecycle']}",
        "Path: #{record['relative_path']}",
        "Media type: #{record['media_type']}",
        "Size: #{record['size_bytes']} bytes",
        "Privacy: #{record['privacy']}",
        "SHA-256: #{record['sha256']}",
        "Source: #{record.dig('source', 'kind')}",
        "Attached chats: #{Array(record['attached_chat_ids']).length}",
        "Content read by registry: no",
        "Mutation: none"
      ].join("\n")
    end

    def attach(text, chat_id)
      artifact_id = text[ARTIFACT_ID]
      record = @store.attach(artifact_id, chat_id: chat_id)
      [
        "Artifact attached to this chat.",
        "Artifact ID: #{record['artifact_id']}",
        "Mutation: attachment_added"
      ].join("\n")
    end

    def detach(text, chat_id)
      artifact_id = text[ARTIFACT_ID]
      record = @store.detach(artifact_id, chat_id: chat_id)
      [
        "Artifact detached from this chat.",
        "Artifact ID: #{record['artifact_id']}",
        "Mutation: attachment_removed"
      ].join("\n")
    end

    def archive(text)
      artifact_id = text[ARTIFACT_ID]
      confirmed = text.match?(/\s+confirm\s*[?.!]*\z/i)
      return confirmation_required("archive artifact #{artifact_id}") unless confirmed

      record = @store.archive(artifact_id)
      [
        "Artifact metadata archived.",
        "Artifact ID: #{record['artifact_id']}",
        "File deleted: no",
        "Mutation: metadata_archived"
      ].join("\n")
    end

    def render_list(heading, records)
      lines = [heading, "Count: #{records.length}", ""]
      if records.empty?
        lines << "- none"
      else
        records.each do |record|
          lines << "- #{record['artifact_id']}: #{record['title']}"
          lines << "  kind: #{record['kind']}"
          lines << "  lifecycle: #{record['lifecycle']}"
          lines << "  path: #{record['relative_path']}"
        end
      end
      lines << "Mutation: none"
      lines.join("\n")
    end

    def confirmation_required(action)
      [
        "Confirmation required.",
        "Action: #{action}",
        "Repeat the command with the literal confirm keyword.",
        "Mutation: none"
      ].join("\n")
    end
  end
end
