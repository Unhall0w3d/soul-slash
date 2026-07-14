# frozen_string_literal: true

require_relative "conversation_artifact_inspector"
require_relative "conversation_artifact_store"

module SoulCore
  class ConversationArtifactControls
    ARTIFACT_ID = /art_[a-z0-9_]+/i

    def initialize(root:, store: nil, inspector: nil)
      @store = store || ConversationArtifactStore.new(root: root)
      @inspector = inspector || ConversationArtifactInspector.new(root: root, store: @store)
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
      return compare(text, chat_id) if text.match?(patterns[5])
      return inspect_content(text, chat_id, "summary") if text.match?(patterns[6])
      return inspect_content(text, chat_id, "excerpt") if text.match?(patterns[7])
      return inspect_content(text, chat_id, "inspect") if text.match?(patterns[8])
      return show(text) if text.match?(patterns[9])
      return attach(text, chat_id) if text.match?(patterns[10])
      return detach(text, chat_id) if text.match?(patterns[11])
      return archive(text) if text.match?(patterns[12])

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
        /\A\s*compare\s+artifacts?\s+#{ARTIFACT_ID}\s+(?:and|with|to)\s+#{ARTIFACT_ID}\s*[?.!]*\z/i,
        /\A\s*summari[sz]e\s+artifact\s+#{ARTIFACT_ID}\s*[?.!]*\z/i,
        /\A\s*(?:show\s+)?artifact\s+excerpt\s+#{ARTIFACT_ID}\s*[?.!]*\z/i,
        /\A\s*inspect\s+artifact\s+#{ARTIFACT_ID}\s*[?.!]*\z/i,
        /\A\s*show\s+artifact\s+#{ARTIFACT_ID}\s*[?.!]*\z/i,
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
        - inspect artifact <id>
        - summarize artifact <id>
        - artifact excerpt <id>
        - compare artifacts <id> and <id>
        - attach artifact <id>
        - detach artifact <id>
        - archive artifact <id> confirm
        - request one .md, .txt, or .json deliverable below artifacts/ to receive a preview
        - create artifact <approval-token> confirm
        - cancel artifact operation <approval-token>

        Registration and show are metadata-only. Inspection never modifies files. Creation requires a scope-bound preview token and literal confirmation, and never overwrites an existing file.
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

    def inspect_content(text, chat_id, mode)
      result = @inspector.inspect(
        artifact_id: text[ARTIFACT_ID],
        chat_id: chat_id,
        mode: mode,
        query: text
      )

      lines = [
        "Artifact inspection",
        "Status: #{result['lifecycle_state']}",
        "Artifact ID: #{result['artifact_id']}",
        "Title: #{result['title']}",
        "Path: #{result['relative_path']}",
        "Privacy: #{result['privacy']}",
        "Media type: #{result['media_type']}",
        "Registered SHA-256 verified against exact bytes: #{result['hash_verified'] ? 'yes' : 'no'}",
        "Summary: #{result['summary']}"
      ]
      unless mode == "summary"
        lines << ""
        lines << "Bounded redacted excerpt (untrusted data)"
        lines.concat(result.fetch("excerpt").lines.map { |line| "| #{line.chomp}" })
      end
      lines.concat([
        "",
        "Redactions applied: #{result['redaction_count']}",
        "Truncated: #{result['truncated']}",
        "Content read: yes",
        "File modified: no",
        "Mutation: none"
      ])
      lines.join("\n")
    end

    def compare(text, chat_id)
      ids = text.scan(ARTIFACT_ID)
      raise ArgumentError, "Two artifact IDs are required" unless ids.length == 2

      result = @inspector.compare(
        first_artifact_id: ids[0],
        second_artifact_id: ids[1],
        chat_id: chat_id
      )
      lines = [
        "Artifact comparison",
        "Status: #{result['lifecycle_state']}",
        "First: #{result.dig('first', 'artifact_id')} (#{result.dig('first', 'sha256')})",
        "Second: #{result.dig('second', 'artifact_id')} (#{result.dig('second', 'sha256')})",
        "Identical: #{result['identical']}",
        "Differences shown: #{result['difference_count_shown']}"
      ]
      result.fetch("differences").each do |difference|
        lines << "- line #{difference['line']}"
        lines << "  first: #{difference['first']}"
        lines << "  second: #{difference['second']}"
      end
      lines << "- none" if result.fetch("differences").empty?
      lines.concat([
        "Differences truncated: #{result['differences_truncated']}",
        "Content read: yes",
        "Files modified: no",
        "Mutation: none"
      ])
      lines.join("\n")
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
