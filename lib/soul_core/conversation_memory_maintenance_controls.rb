# frozen_string_literal: true

require_relative "conversation_memory_reflection_bridge"
require_relative "conversation_memory_snapshot"

module SoulCore
  class ConversationMemoryMaintenanceControls
    CONTROL_PATTERNS = [
      /\A\s*(?:memory maintenance help|help memory maintenance)\s*[?.!]*\z/i,
      /\A\s*list\s+approved\s+reflections?\s*[?.!]*\z/i,
      /\A\s*(?:show|inspect|preview)\s+approved\s+reflection(?:\s+.+)?\z/i,
      /\A\s*import\s+approved\s+reflection(?:\s+.+)?\z/i,
      /\A\s*export\s+memory\s+snapshot(?:\s+.+)?\z/i,
      /\A\s*verify\s+memory\s+snapshot(?:\s+.+)?\z/i
    ].freeze

    def initialize(root: Dir.pwd, store: nil, bridge: nil, snapshot: nil)
      @root = File.expand_path(root)
      shared_store = store || ConversationMemoryStore.new(root: @root)
      @bridge = bridge || ConversationMemoryReflectionBridge.new(root: @root, store: shared_store)
      @snapshot = snapshot || ConversationMemorySnapshot.new(root: @root, store: shared_store)
    end

    def match?(message)
      text = message.to_s.strip
      CONTROL_PATTERNS.any? { |pattern| text.match?(pattern) }
    end

    def respond(message, chat_id: nil)
      _chat_id = chat_id
      text = message.to_s.strip
      return help if text.match?(/\A\s*(?:memory maintenance help|help memory maintenance)\s*[?.!]*\z/i)
      return list_reflections if text.match?(/\A\s*list\s+approved\s+reflections?\s*[?.!]*\z/i)
      return inspect_reflection(reflection_target(text)) if text.match?(/\A\s*(?:show|inspect|preview)\s+approved\s+reflection/i)
      return import_reflection(text) if text.match?(/\A\s*import\s+approved\s+reflection/i)
      return export_snapshot(snapshot_target(text, command: "export")) if text.match?(/\A\s*export\s+memory\s+snapshot/i)
      return verify_snapshot(snapshot_target(text, command: "verify")) if text.match?(/\A\s*verify\s+memory\s+snapshot/i)

      "This did not match a bounded memory-maintenance control. Use: memory maintenance help"
    rescue ArgumentError => error
      [
        "Memory maintenance blocked.",
        "Reason: #{error.message}",
        "Mutation: none"
      ].join("\n")
    end

    private

    def list_reflections
      paths = @bridge.approved_paths
      lines = [
        "Approved reflection candidates",
        "Count: #{paths.length}",
        ""
      ]
      if paths.empty?
        lines << "- none"
      else
        paths.last(20).reverse_each { |path| lines << "- #{relative_path(path)}" }
      end
      lines << ""
      lines << "Use: preview approved reflection latest"
      lines.join("\n")
    end

    def inspect_reflection(target)
      preview = @bridge.preview(target)
      lines = [
        "Approved reflection memory preview",
        "Path: #{preview['path']}",
        "Task kind: #{preview['task_kind']}",
        "Reviewed at: #{preview['reviewed_at']}",
        "Memory update count: #{preview['item_count']}",
        "Mutation: none",
        ""
      ]
      if preview["items"].empty?
        lines << "- no candidate_memory_updates"
      else
        preview["items"].each do |item|
          state = item["already_imported"] ? "already imported" : "new candidate"
          lines << "- [#{item['layer']}; confidence #{format('%.2f', item['confidence'])}; #{state}] #{item['content']}"
        end
      end
      lines << ""
      lines << "Confirm with: import approved reflection #{target} confirm"
      lines.join("\n")
    end

    def import_reflection(text)
      target = reflection_target(text.sub(/\s+confirm\s*[?.!]*\z/i, ""))
      unless text.match?(/\bconfirm\s*[?.!]*\z/i)
        return inspect_reflection(target)
      end

      result = @bridge.import_candidates(target)
      lines = [
        "Approved reflection imported as reviewed memory candidates.",
        "Path: #{result['path']}",
        "Created: #{result['created_count']}",
        "Skipped as duplicates: #{result['skipped_count']}",
        "Automatically approved: no"
      ]
      result["created"].each do |record|
        lines << "- #{record['id']} [#{record['layer']}; candidate] #{record['content']}"
      end
      lines << "Next step: inspect and approve candidates individually."
      lines.join("\n")
    end

    def export_snapshot(name)
      result = @snapshot.export(name: name == "latest" ? nil : name)
      [
        "Conversation memory snapshot exported.",
        "Path: #{result['path']}",
        "Schema: #{result['schema']}",
        "SHA-256: #{result['sha256']}",
        "Events: #{result['event_count']}",
        "Records: #{result['record_count']}",
        "Ledger mutation: none"
      ].join("\n")
    end

    def verify_snapshot(target)
      result = @snapshot.verify(target)
      lines = [
        "Conversation memory snapshot verification",
        "Path: #{result['path']}",
        "Status: #{result['ok'] ? 'valid' : 'invalid'}"
      ]
      result.fetch("checks", {}).each do |name, passed|
        lines << "- #{name}: #{passed}"
      end
      lines << "Mutation: none"
      lines.join("\n")
    end

    def reflection_target(text)
      value = text.sub(/\A\s*(?:(?:show|inspect|preview|import)\s+approved\s+reflection)\s*/i, "")
      value = value.sub(/\s+confirm\s*[?.!]*\z/i, "").strip
      value = value.sub(/[?.!]+\z/, "").strip
      value.empty? ? "latest" : value
    end

    def snapshot_target(text, command:)
      prefix = command == "export" ? /\A\s*export\s+memory\s+snapshot\s*/i : /\A\s*verify\s+memory\s+snapshot\s*/i
      value = text.sub(prefix, "").sub(/[?.!]+\z/, "").strip
      value.empty? ? "latest" : value
    end

    def relative_path(path)
      expanded = File.expand_path(path)
      prefix = "#{@root}#{File::SEPARATOR}"
      expanded.start_with?(prefix) ? expanded.delete_prefix(prefix) : expanded
    end

    def help
      <<~TEXT.rstrip
        Conversation memory maintenance controls

        Reviewed reflection bridge:
        - list approved reflections
        - preview approved reflection latest
        - import approved reflection latest confirm

        Portable audit snapshots:
        - export memory snapshot
        - export memory snapshot <simple-name>
        - verify memory snapshot latest
        - verify memory snapshot <simple-name>

        Safety boundary:
        - only approved reflection JSON files may be imported;
        - imported updates remain candidates until separately approved;
        - repeated imports are idempotent;
        - snapshots contain the append-only event ledger and materialized records;
        - snapshot export does not mutate the ledger;
        - physical purge remains unsupported.
      TEXT
    end
  end
end
