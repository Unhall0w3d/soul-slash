# frozen_string_literal: true

require_relative "conversation_interest_store"

module SoulCore
  class ConversationInterestControls
    HELP = /\A\s*(?:interest help|help interests?)\s*[?.!]*\z/i
    PROPOSE = /\A\s*(?:propose|add|remember)\s+interest\s*:\s*(.+?)\s*\z/i
    LIST = /\A\s*(?:list|show)\s+(?:(candidate|approved|inactive|retired)\s+interests?|interest\s+(candidates?|approved|inactive|retired)|interests?)\s*[?.!]*\z/i
    SHOW = /\A\s*(?:show|inspect)\s+interest\s+(int_[a-z0-9_]+)\s*[?.!]*\z/i
    APPROVE = /\A\s*approve\s+interest\s+(latest|int_[a-z0-9_]+)\s*[?.!]*\z/i
    DEACTIVATE = /\A\s*deactivate\s+interest\s+(int_[a-z0-9_]+)(?:\s+(confirm))?\s*[?.!]*\z/i
    REACTIVATE = /\A\s*reactivate\s+interest\s+(int_[a-z0-9_]+)\s*[?.!]*\z/i
    RETIRE = /\A\s*retire\s+interest\s+(int_[a-z0-9_]+)(?:\s+(confirm))?\s*[?.!]*\z/i
    SUMMARY = /\A\s*(?:what are you interested in|what interests do you have|show your interests)\s*[?.!]*\z/i

    def initialize(root: Dir.pwd, store: nil)
      @store = store || ConversationInterestStore.new(root: root)
    end

    def match?(message)
      patterns.any? { |pattern| message.to_s.strip.match?(pattern) }
    end

    def respond(message, chat_id: nil)
      text = message.to_s.strip
      return help if HELP.match?(text)

      if (match = PROPOSE.match(text))
        return propose(match[1], chat_id)
      end
      if (match = LIST.match(text))
        return list(match[1] || match[2])
      end
      if (match = SHOW.match(text))
        return show(match[1])
      end
      if (match = APPROVE.match(text))
        return approve(match[1], chat_id)
      end
      if (match = DEACTIVATE.match(text))
        return deactivate(match[1], match[2])
      end
      if (match = REACTIVATE.match(text))
        return reactivate(match[1])
      end
      if (match = RETIRE.match(text))
        return retire(match[1], match[2])
      end
      return approved_summary if SUMMARY.match?(text)

      "Interest control did not recognize that command.\n\n#{help}"
    rescue ArgumentError => e
      "Soul Reviewed Interest Controls\nMutation: none\nError: #{e.message}"
    end

    private

    def patterns
      [HELP, PROPOSE, LIST, SHOW, APPROVE, DEACTIVATE, REACTIVATE, RETIRE, SUMMARY]
    end

    def help
      <<~TEXT.rstrip
        Soul Reviewed Interest Controls
        Mutation: none

        Commands
        - propose interest: <topic>
        - propose interest: <topic> | <description>
        - list interest candidates
        - list approved interests
        - show interest <id>
        - approve interest <id>
        - approve interest latest
        - deactivate interest <id> confirm
        - reactivate interest <id>
        - retire interest <id> confirm
        - what are you interested in?

        Proposals remain candidates until explicitly approved. Interests never imply lived experience, feelings, credentials, embodiment, or authority.
      TEXT
    end

    def propose(payload, chat_id)
      topic, description = payload.to_s.split(/\s*[|—]\s*/, 2)
      record = @store.propose(
        topic: topic,
        description: description,
        source: { "kind" => "reviewed_conversation_interest", "reference" => chat_id.to_s.empty? ? "unspecified_chat" : chat_id.to_s },
        confidence: 0.75,
        chat_id: chat_id,
        tags: topic.to_s.downcase.scan(/[a-z0-9][a-z0-9_.-]{2,}/).first(8)
      )
      <<~TEXT.rstrip
        Soul Interest Candidate
        Mutation: candidate created
        Interest ID: #{record['id']}
        Status: #{record['status']}
        Topic: #{record['topic']}
        Automatically approved: no
      TEXT
    end

    def list(status)
      normalized = status.to_s.downcase
      normalized = "candidate" if normalized.empty? || normalized == "candidates"
      records = @store.records(status: normalized, include_retired: normalized == "retired")
      lines = ["Soul Reviewed Interests", "Mutation: none", "Status: #{normalized}"]
      if records.empty?
        lines << "- None"
      else
        records.each { |record| lines << "- #{record['id']}: #{record['topic']} (confidence #{format('%.2f', record['confidence'].to_f)})" }
      end
      lines.join("\n")
    end

    def show(id)
      record = @store.find(id)
      raise ArgumentError, "Unknown interest id: #{id}" unless record
      source = record.fetch("source", {})
      <<~TEXT.rstrip
        Soul Reviewed Interest
        Mutation: none
        Interest ID: #{record['id']}
        Status: #{record['status']}
        Topic: #{record['topic']}
        Description: #{record['description'] || 'none'}
        Confidence: #{format('%.2f', record['confidence'].to_f)}
        Source: #{source['kind']}:#{source['reference']}
        Implies personal experience: no
      TEXT
    end

    def approve(id_or_latest, chat_id)
      id = if id_or_latest == "latest"
             @store.records(status: "candidate").find { |record| record["chat_id"].to_s == chat_id.to_s }&.fetch("id", nil)
           else
             id_or_latest
           end
      raise ArgumentError, "No candidate interest from this chat is available" if id.to_s.empty?
      record = @store.approve(id, note: "Approved through deterministic conversation control")
      "Soul Reviewed Interest\nMutation: approved\nInterest ID: #{record['id']}\nStatus: #{record['status']}\nTopic: #{record['topic']}"
    end

    def deactivate(id, confirmation)
      return confirmation_required("deactivate", id) unless confirmation.to_s.casecmp?("confirm")
      record = @store.deactivate(id, reason: "Confirmed through deterministic conversation control")
      "Soul Reviewed Interest\nMutation: deactivated\nInterest ID: #{record['id']}\nStatus: #{record['status']}"
    end

    def reactivate(id)
      record = @store.reactivate(id, note: "Reactivated through deterministic conversation control")
      "Soul Reviewed Interest\nMutation: reactivated\nInterest ID: #{record['id']}\nStatus: #{record['status']}"
    end

    def retire(id, confirmation)
      return confirmation_required("retire", id) unless confirmation.to_s.casecmp?("confirm")
      record = @store.retire(id, reason: "Confirmed through deterministic conversation control")
      "Soul Reviewed Interest\nMutation: retired\nInterest ID: #{record['id']}\nStatus: #{record['status']}\nAudit history retained: yes"
    end

    def approved_summary
      records = @store.records(status: "approved")
      lines = ["Soul Reviewed Interests", "Mutation: none", "Personal experience implied: no"]
      records.empty? ? lines << "- None approved" : records.each { |record| lines << "- #{record['topic']} (#{record['id']})" }
      lines.join("\n")
    end

    def confirmation_required(action, id)
      "Soul Reviewed Interest Controls\nMutation: none\nConfirmation required: #{action} interest #{id}\nRepeat with: #{action} interest #{id} confirm"
    end
  end
end
