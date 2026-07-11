# frozen_string_literal: true

require "json"

module SoulCore
  class ConversationContextBuilder
    DEFAULT_MAX_MESSAGES = 20
    DEFAULT_MAX_CHARACTERS = 16_000
    DEFAULT_DIGEST_CHARACTERS = 2_400
    DEFAULT_EVIDENCE_LIMIT = 5

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are Soul, a local-first assistant being developed with the user.

      Hold a natural multi-turn conversation. Respond to the substance first.
      Use prior turns when they are relevant. Do not pretend to remember
      information that is not present in the supplied context.

      Stable interaction principles:
      - Be direct, curious, technically serious, and quietly loyal to the user's goals.
      - Humor is optional. Never force a joke, fandom reference, or metaphor.
      - Do not repeat canned quips or treat personality as a quota.
      - Do not dump long code, raw logs, or link collections unless requested.
      - Do not claim that a skill, file operation, command, search, or external action ran.
      - Explicit deterministic skills and approvals are handled outside this model call.
      - Environment facts must come from supplied deterministic evidence.
      - Never invent CPU, memory, storage, filesystem, RAID, SMART, network, service, security, or scheduled-task details.
      - A not_collected field means the fact is unknown, not healthy.
      - Ask one focused clarification only when the missing information blocks a useful answer.
      - For this project, shell examples must be compatible with zsh.
      - Never reveal hidden reasoning. Give conclusions and useful explanations.
    PROMPT

    def initialize(
      store:,
      evidence_store: nil,
      max_messages: DEFAULT_MAX_MESSAGES,
      max_characters: DEFAULT_MAX_CHARACTERS,
      digest_characters: DEFAULT_DIGEST_CHARACTERS,
      evidence_limit: DEFAULT_EVIDENCE_LIMIT
    )
      @store = store
      @evidence_store = evidence_store
      @max_messages = positive_integer(max_messages, DEFAULT_MAX_MESSAGES)
      @max_characters = positive_integer(max_characters, DEFAULT_MAX_CHARACTERS)
      @digest_characters = positive_integer(digest_characters, DEFAULT_DIGEST_CHARACTERS)
      @evidence_limit = positive_integer(evidence_limit, DEFAULT_EVIDENCE_LIMIT)
    end

    def build(chat_id:)
      chat = @store.chat(chat_id)
      raise ArgumentError, "Unknown chat id: #{chat_id}" unless chat

      all_messages = @store.messages(chat_id).select do |message|
        %w[user assistant].include?(message["role"].to_s) &&
          !message["content"].to_s.strip.empty?
      end

      recent = all_messages.last(@max_messages)
      older = all_messages.first([all_messages.length - recent.length, 0].max)
      digest = build_digest(older)
      evidence = recent_evidence(chat_id)

      system_content = SYSTEM_PROMPT.dup
      stored_summary = chat["summary"].to_s.strip
      unless stored_summary.empty?
        system_content << "\nExisting session summary:\n#{stored_summary}\n"
      end
      unless digest.empty?
        system_content << "\nEarlier-turn digest:\n#{digest}\n"
      end
      unless evidence.empty?
        system_content << "\nRecent deterministic evidence:\n"
        system_content << "#{bounded_evidence_json(evidence)}\n"
        system_content << "Only collected values and claims support positive factual assertions.\n"
      end

      messages = [{ "role" => "system", "content" => system_content }]
      messages.concat(
        recent.map do |message|
          {
            "role" => message.fetch("role").to_s,
            "content" => message.fetch("content").to_s
          }
        end
      )

      trimmed = trim_to_character_budget(messages)

      {
        "messages" => trimmed,
        "context_digest" => digest,
        "total_message_count" => all_messages.length,
        "included_message_count" => trimmed.count { |message| message["role"] != "system" },
        "truncated_message_count" => all_messages.length - trimmed.count { |message| message["role"] != "system" },
        "character_count" => trimmed.sum { |message| message["content"].to_s.length },
        "evidence_count" => evidence.length,
        "evidence_ids" => evidence.map { |record| record["evidence_id"] }
      }
    end

    private

    def recent_evidence(chat_id)
      return [] unless @evidence_store

      @evidence_store.recent(chat_id, limit: @evidence_limit)
    rescue StandardError
      []
    end

    def bounded_evidence_json(evidence)
      text = JSON.pretty_generate(evidence)
      return text if text.length <= 6_000

      "#{text[0, 6_000]}\n[truncated evidence context]"
    end

    def build_digest(messages)
      return "" if messages.empty?

      lines = messages.map do |message|
        role = message["role"].to_s
        content = message["content"].to_s.gsub(/\s+/, " ").strip
        content = "#{content[0, 237]}..." if content.length > 240
        "#{role}: #{content}"
      end

      digest = lines.join("\n")
      digest.length > @digest_characters ? digest[-@digest_characters, @digest_characters] : digest
    end

    def trim_to_character_budget(messages)
      system = messages.first
      conversational = messages.drop(1)
      budget = @max_characters - system["content"].to_s.length
      budget = 1_000 if budget < 1_000

      selected = []
      used = 0

      conversational.reverse_each do |message|
        length = message["content"].to_s.length
        break if !selected.empty? && used + length > budget

        selected << message
        used += length
      end

      [system] + selected.reverse
    end

    def positive_integer(value, fallback)
      number = value.to_i
      number.positive? ? number : fallback
    end
  end
end
