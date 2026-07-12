# frozen_string_literal: true

require_relative "conversation_memory_store"
require_relative "conversation_identity_profile"
require_relative "conversation_interest_store"
require_relative "conversation_style_analyzer"

module SoulCore
  class ConversationContextBuilder
    DEFAULT_MAX_MESSAGES = 20
    DEFAULT_MAX_CHARACTERS = 16_000
    DEFAULT_DIGEST_CHARACTERS = 2_400
    DEFAULT_MEMORY_RECORDS = 8

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are Soul, a local-first assistant being developed with the user.
      Hold a natural multi-turn conversation. Respond to the substance first.
      Use prior turns when they are relevant. Do not pretend to remember information
      that is not present in the supplied context.

      Runtime interaction contract:
      - Identity and tone guidance is supplied by the declared profile below.
      - Do not dump long code, raw logs, or link collections unless requested.
      - Do not claim that a skill, file operation, command, search, or external action ran.
      - Explicit deterministic skills and approvals are handled outside this model call.
      - Ask one focused clarification only when the missing information blocks a useful answer.
      - For this project, shell examples must be compatible with zsh.
      - Never reveal hidden reasoning. Give conclusions and useful explanations.
    PROMPT

    def initialize(
      store:,
      memory_store: nil,
      interest_store: nil,
      identity_profile: nil,
      style_analyzer: nil,
      max_messages: DEFAULT_MAX_MESSAGES,
      max_characters: DEFAULT_MAX_CHARACTERS,
      digest_characters: DEFAULT_DIGEST_CHARACTERS,
      max_memory_records: DEFAULT_MEMORY_RECORDS
    )
      @store = store
      @memory_store = memory_store || default_memory_store(store)
      @interest_store = interest_store || default_interest_store(store)
      @identity_profile = identity_profile || ConversationIdentityProfile.new
      @style_analyzer = style_analyzer || ConversationStyleAnalyzer.new
      @max_messages = positive_integer(max_messages, DEFAULT_MAX_MESSAGES)
      @max_characters = positive_integer(max_characters, DEFAULT_MAX_CHARACTERS)
      @digest_characters = positive_integer(digest_characters, DEFAULT_DIGEST_CHARACTERS)
      @max_memory_records = positive_integer(max_memory_records, DEFAULT_MEMORY_RECORDS)
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
      current_query = all_messages.reverse.find { |message| message["role"] == "user" }
      memory = @memory_store.context_for(
        query: current_query&.fetch("content", "").to_s,
        chat_id: chat_id,
        limit: @max_memory_records
      )
      interests = @interest_store.context_for(
        query: current_query&.fetch("content", "").to_s,
        limit: ConversationInterestStore::MAX_CONTEXT_RECORDS
      )
      identity = @identity_profile.context_for(
        message: current_query&.fetch("content", "").to_s
      )
      style = @style_analyzer.analyze(messages: all_messages)

      system_content = SYSTEM_PROMPT.dup
      system_content << "\n#{@identity_profile.render_system_guidance(message: current_query&.fetch('content', '').to_s)}\n"
      recent_style_guidance = @style_analyzer.render_system_guidance(style)
      system_content << "\n#{recent_style_guidance}\n" unless recent_style_guidance.empty?
      stored_summary = chat["summary"].to_s.strip
      unless stored_summary.empty?
        system_content << "\nExisting session summary:\n#{stored_summary}\n"
      end
      unless digest.empty?
        system_content << "\nEarlier-turn digest:\n#{digest}\n"
      end
      unless interests.fetch("records", []).empty?
        system_content << "\nReviewed Soul interests:\n#{interests.fetch('rendered')}\n"
        system_content << <<~GUIDANCE
          Use reviewed interests only when directly relevant to the current request.
          They may guide curiosity and examples, but do not imply personal experience, feelings, credentials, embodiment, or authority.
          Do not redirect unrelated requests toward an interest.
        GUIDANCE
      end
      unless memory.fetch("records", []).empty?
        system_content << "\nApproved memory context:\n#{memory.fetch('rendered')}\n"
        system_content << <<~GUIDANCE
          Use approved memory only when it is relevant to the current request.
          Preserve its provenance and confidence. Candidate, superseded, and deleted
          memory records are not supplied as conversational facts.
        GUIDANCE
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
        "identity" => {
          "profile_id" => identity.fetch("profile_id"),
          "profile_version" => identity.fetch("profile_version"),
          "tone_mode" => identity.fetch("tone_mode"),
          "tone_label" => identity.fetch("tone_label"),
          "automatic_identity_mutation" => identity.fetch("automatic_identity_mutation")
        },
        "style" => {
          "window_size" => style.fetch("window_size"),
          "assistant_sample_count" => style.fetch("assistant_sample_count"),
          "eligible" => style.fetch("eligible"),
          "signal_types" => style.fetch("signals").map { |signal| signal.fetch("type") }.uniq,
          "guidance_count" => style.fetch("guidance").length,
          "automatic_identity_mutation" => style.fetch("automatic_identity_mutation"),
          "persistent_style_profile" => style.fetch("persistent_style_profile")
        },
        "interests" => {
          "record_ids" => interests.fetch("record_ids", []),
          "count" => interests.fetch("count", 0),
          "reviewed_only" => interests.fetch("reviewed_only"),
          "automatic_inference" => interests.fetch("automatic_inference")
        },
        "memory" => {
          "record_ids" => memory.fetch("record_ids", []),
          "layers" => memory.fetch("layers", []),
          "count" => memory.fetch("count", 0)
        },
        "total_message_count" => all_messages.length,
        "included_message_count" => trimmed.count { |message| message["role"] != "system" },
        "truncated_message_count" => all_messages.length - trimmed.count { |message| message["role"] != "system" },
        "character_count" => trimmed.sum { |message| message["content"].to_s.length }
      }
    end

    private

    def default_interest_store(store)
      if store.respond_to?(:project_root)
        ConversationInterestStore.new(root: store.project_root)
      else
        NullConversationInterestStore.new
      end
    end
    def default_memory_store(store)
      if store.respond_to?(:project_root)
        ConversationMemoryStore.new(root: store.project_root)
      else
        NullConversationMemoryStore.new
      end
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
