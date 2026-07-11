# frozen_string_literal: true

require_relative "conversation_memory_store"

module SoulCore
  class ConversationMemoryControls
    MEMORY_ID_PATTERN = /mem_[a-zA-Z0-9_-]+/.freeze
    LAYER_PATTERN = /(project|preference|episodic|semantic)/i.freeze

    CONTROL_PATTERNS = [
      /\A\s*(?:memory help|help memory)\s*[?.!]*\z/i,
      /\A\s*(?:what do you remember|show memories|show memory|list memories|list memory)(?:\s|\z)/i,
      /\A\s*(?:show|inspect)\s+memory\s+#{MEMORY_ID_PATTERN.source}\s*[?.!]*\z/i,
      /\A\s*approve\s+(?:latest\s+)?memory(?:\s+#{MEMORY_ID_PATTERN.source}|\s+latest)\s*[?.!]*\z/i,
      /\A\s*(?:forget|delete)\s+memory\s+#{MEMORY_ID_PATTERN.source}(?:\s+confirm)?\s*[?.!]*\z/i,
      /\A\s*supersede\s+memory\s+#{MEMORY_ID_PATTERN.source}\s+with\s+#{MEMORY_ID_PATTERN.source}(?:\s+confirm)?\s*[?.!]*\z/i,
      /\A\s*(?:please\s+)?remember\s+(?:this|that)\b/i,
      /\A\s*(?:please\s+)?remember\s+(?:as\s+)?#{LAYER_PATTERN.source}\s*[:\-]/i,
      /\A\s*propose\s+memory(?:\s+as)?\s+#{LAYER_PATTERN.source}\s*[:\-]/i
    ].freeze

    def initialize(root: Dir.pwd, store: nil)
      @root = File.expand_path(root)
      @store = store || ConversationMemoryStore.new(root: @root)
    end

    def match?(message)
      text = message.to_s.strip
      CONTROL_PATTERNS.any? { |pattern| text.match?(pattern) }
    end

    def respond(message, chat_id: nil)
      text = message.to_s.strip
      return help if text.match?(/\A\s*(?:memory help|help memory)\s*[?.!]*\z/i)
      return inspect_record(text) if text.match?(/\A\s*(?:show|inspect)\s+memory\s+#{MEMORY_ID_PATTERN.source}\s*[?.!]*\z/i)
      return approve_record(text, chat_id: chat_id) if text.match?(/\A\s*approve\s+(?:latest\s+)?memory(?:\s+#{MEMORY_ID_PATTERN.source}|\s+latest)\s*[?.!]*\z/i)
      return delete_record(text) if text.match?(/\A\s*(?:forget|delete)\s+memory\s+#{MEMORY_ID_PATTERN.source}(?:\s+confirm)?\s*[?.!]*\z/i)
      return supersede_record(text) if text.match?(/\A\s*supersede\s+memory\s+#{MEMORY_ID_PATTERN.source}\s+with\s+#{MEMORY_ID_PATTERN.source}(?:\s+confirm)?\s*[?.!]*\z/i)
      return list_records(text) if list_request?(text)

      proposal = proposal_from(text)
      return propose_record(proposal, chat_id: chat_id) if proposal

      "This did not match a bounded memory control. Use: memory help"
    rescue ArgumentError => error
      [
        "Memory control blocked.",
        "Reason: #{error.message}",
        "Mutation: none"
      ].join("\n")
    end

    private

    def proposal_from(text)
      patterns = [
        /\A\s*(?:please\s+)?remember\s+(?:this|that)(?:\s+as\s+#{LAYER_PATTERN.source})?\s*[:\-]?\s+(.+)\z/im,
        /\A\s*(?:please\s+)?remember\s+(?:as\s+)?#{LAYER_PATTERN.source}\s*[:\-]\s*(.+)\z/im,
        /\A\s*propose\s+memory(?:\s+as)?\s+#{LAYER_PATTERN.source}\s*[:\-]\s*(.+)\z/im
      ]

      patterns.each_with_index do |pattern, index|
        match = text.match(pattern)
        next unless match

        if index.zero?
          layer = match[1].to_s.downcase
          content = match[2].to_s.strip
          layer = inferred_layer(content) if layer.empty?
        else
          layer = match[1].to_s.downcase
          content = match[2].to_s.strip
        end

        return { "layer" => layer, "content" => content }
      end

      nil
    end

    def inferred_layer(content)
      text = content.to_s.downcase
      return "preference" if text.match?(/\b(i prefer|my preference|from now on|always use|never use)\b/)
      return "episodic" if text.match?(/\b(completed|committed|pushed|finished|happened|today|yesterday)\b/)
      return "semantic" if text.match?(/\b(rule|lesson|means|definition|principle)\b/)

      "project"
    end

    def propose_record(proposal, chat_id:)
      content = proposal.fetch("content").to_s.strip
      raise ArgumentError, "Memory content must not be empty" if content.empty?

      reference = chat_id.to_s.strip
      reference = "unspecified-chat" if reference.empty?
      record = @store.propose(
        layer: proposal.fetch("layer"),
        content: content,
        source: {
          "kind" => "conversation_request",
          "reference" => reference
        },
        confidence: 1.0,
        chat_id: chat_id,
        tags: [proposal.fetch("layer"), "explicit-user-request"],
        metadata: {
          "control" => "reviewed_conversation_memory",
          "requested_by" => "user"
        }
      )

      [
        "Memory candidate created.",
        "ID: #{record['id']}",
        "Layer: #{record['layer']}",
        "Status: #{record['status']}",
        "Content: #{record['content']}",
        "Approved context: no",
        "Next step: approve memory #{record['id']}"
      ].join("\n")
    end

    def approve_record(text, chat_id:)
      id = memory_id(text)
      if id.nil? && text.match?(/\blatest\b/i)
        candidates = @store.records(status: "candidate")
        unless chat_id.to_s.strip.empty?
          candidates = candidates.select { |record| record["chat_id"].to_s == chat_id.to_s }
        end
        latest = candidates.first
        raise ArgumentError, "No candidate memory is available for this chat" unless latest

        id = latest.fetch("id")
      end
      raise ArgumentError, "Provide a memory ID or use: approve memory latest" unless id

      record = @store.approve(id, note: "Approved through reviewed conversation memory control")
      [
        "Memory approved.",
        "ID: #{record['id']}",
        "Layer: #{record['layer']}",
        "Status: #{record['status']}",
        "Content: #{record['content']}",
        "Eligible for relevant context: yes"
      ].join("\n")
    end

    def delete_record(text)
      id = memory_id(text)
      raise ArgumentError, "Provide the exact memory ID" unless id

      record = @store.find(id)
      raise ArgumentError, "Unknown memory id: #{id}" unless record

      unless text.match?(/\bconfirm\s*[?.!]*\z/i)
        return [
          "Memory deletion requires confirmation.",
          "ID: #{record['id']}",
          "Current status: #{record['status']}",
          "Content: #{record['content']}",
          "Mutation: none",
          "Confirm with: forget memory #{record['id']} confirm"
        ].join("\n")
      end

      deleted = @store.delete(id, reason: "Explicit conversation memory forget command")
      [
        "Memory logically deleted.",
        "ID: #{deleted['id']}",
        "Status: #{deleted['status']}",
        "Active retrieval: no",
        "Audit history preserved: yes",
        "Physical purge: not performed"
      ].join("\n")
    end

    def supersede_record(text)
      ids = text.scan(MEMORY_ID_PATTERN)
      raise ArgumentError, "Provide the old and replacement memory IDs" unless ids.length == 2

      old_record = @store.find(ids[0])
      new_record = @store.find(ids[1])
      raise ArgumentError, "Unknown memory id: #{ids[0]}" unless old_record
      raise ArgumentError, "Unknown memory id: #{ids[1]}" unless new_record
      raise ArgumentError, "Replacement memory must be approved first" unless new_record["status"] == "approved"
      raise ArgumentError, "Only active approved memory may be superseded" unless old_record["status"] == "approved"

      unless text.match?(/\bconfirm\s*[?.!]*\z/i)
        return [
          "Memory supersession requires confirmation.",
          "Old ID: #{old_record['id']}",
          "Replacement ID: #{new_record['id']}",
          "Mutation: none",
          "Confirm with: supersede memory #{old_record['id']} with #{new_record['id']} confirm"
        ].join("\n")
      end

      superseded = @store.supersede(
        old_record.fetch("id"),
        by: new_record.fetch("id"),
        reason: "Explicit reviewed conversation memory supersession"
      )
      [
        "Memory superseded.",
        "Old ID: #{superseded['id']}",
        "Old status: #{superseded['status']}",
        "Replacement ID: #{superseded['superseded_by']}",
        "Replacement status: #{new_record['status']}",
        "Audit history preserved: yes"
      ].join("\n")
    end

    def inspect_record(text)
      id = memory_id(text)
      raise ArgumentError, "Provide the exact memory ID" unless id

      record = @store.find(id)
      raise ArgumentError, "Unknown memory id: #{id}" unless record

      render_record(record)
    end

    def list_request?(text)
      text.match?(/\A\s*(?:what do you remember|show memories|show memory|list memories|list memory)(?:\s|\z)/i)
    end

    def list_records(text)
      status = text[/\b(candidates?|approved|superseded|deleted)\b/i, 1]&.downcase
      status = "candidate" if status == "candidates"
      status = "approved" if text.match?(/\A\s*what do you remember\s*[?.!]*\z/i)
      layer = text[/\b(project|preference|episodic|semantic)\b/i, 1]&.downcase
      include_deleted = status == "deleted"
      records = @store.records(layer: layer, status: status, include_deleted: include_deleted)

      lines = [
        "Conversation memory records",
        "Status filter: #{status || 'active'}",
        "Layer filter: #{layer || 'all'}",
        "Count: #{records.length}",
        ""
      ]
      if records.empty?
        lines << "- none"
      else
        records.first(20).each do |record|
          content = record.fetch("content").gsub(/\s+/, " ")
          content = "#{content[0, 157]}..." if content.length > 160
          lines << "- #{record['id']} [#{record['status']}; #{record['layer']}; confidence #{format('%.2f', record['confidence'].to_f)}]"
          lines << "  #{content}"
        end
      end
      lines << ""
      lines << "Use: show memory <id>"
      lines.join("\n")
    end

    def render_record(record)
      source = record.fetch("source", {})
      lines = [
        "Conversation memory record",
        "ID: #{record['id']}",
        "Status: #{record['status']}",
        "Layer: #{record['layer']}",
        "Confidence: #{format('%.2f', record['confidence'].to_f)}",
        "Source: #{source['kind']}:#{source['reference']}",
        "Created: #{record['created_at']}",
        "Updated: #{record['updated_at']}",
        "Content: #{record['content']}"
      ]
      lines << "Superseded by: #{record['superseded_by']}" if record["superseded_by"]
      lines << "Deletion reason: #{record['deletion_reason']}" if record["deletion_reason"]
      lines << "Tags: #{Array(record['tags']).join(', ')}" unless Array(record["tags"]).empty?
      lines.join("\n")
    end

    def memory_id(text)
      text.to_s[MEMORY_ID_PATTERN]
    end

    def help
      <<~TEXT.rstrip
        Reviewed conversation memory controls

        Propose a candidate:
        - remember that <content>
        - remember this as preference: <content>
        - remember project: <content>

        Review and approve:
        - list memory candidates
        - show memory <id>
        - approve memory <id>
        - approve memory latest

        Maintain approved memory:
        - list approved memory
        - supersede memory <old-id> with <new-id> confirm
        - forget memory <id> confirm

        Safety boundary:
        - proposals start as candidates and do not enter model context;
        - approval is explicit;
        - supersession and deletion preserve the append-only audit history;
        - physical purge is not provided by this control surface.
      TEXT
    end
  end
end
