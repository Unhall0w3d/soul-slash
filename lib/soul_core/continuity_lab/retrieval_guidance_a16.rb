# frozen_string_literal: true

require_relative "qwen_message_projection"

module SoulCore
  module ContinuityLab
    # Qualification-only template adapter. Keeping this outside the frozen
    # broker/projection preserves earlier profiles and their source hashes.
    module RetrievalGuidanceA16
      VERSION = "retrieval_interface_guidance_a16_v1"
      CONDITIONS = %w[baseline guided].freeze
      GUIDE = <<~TEXT.freeze
        Retrieval interface:
        history contains completed earlier user/assistant exchanges in this lineage; use it for prior conversation, decisions and corrections.
        corpus contains supplied reference documents; use it for catalog facts and other source material. notes contains optional saved model claims, not automatic conversation memory.
        search matches every query word exactly, ignoring case. It does not stem plurals or understand a whole question semantically.
        Start with one or two distinctive keywords likely to occur in the source. Extra words can exclude relevant documents.
        If search returns no hits, try fewer or different keywords or the appropriate collection; an empty search does not prove the information was never provided.
        Search hits provide the collection, logical id, revision and a text snippet. Copy those identifiers for read; never guess a note or document ID.
        If a snippet is incomplete, read the document at the returned revision with an appropriate start and length.
        For a callback, retrieve earlier exchanges rather than assuming the current request contains the answer. Use the user's later correction when it supersedes an earlier choice.
        Ground calculations in retrieved values. If relevant evidence remains unavailable, explain that limitation without inventing a fact or claiming exhaustive absence.
        Tools and note writes are not mandatory when the current request can already be answered. Notes remain optional unverified claims.
      TEXT

      def self.metadata(condition)
        raise ValidationError, "unsupported A16 condition" unless CONDITIONS.include?(condition)
        text = condition == "guided" ? GUIDE : ""
        { "condition" => condition, "guidance_version" => VERSION,
          "guidance_sha256" => Digest::SHA256.hexdigest(text), "guidance_text" => text }
      end

      class Transport
        attr_reader :metadata

        def initialize(client:, condition:)
          @metadata = RetrievalGuidanceA16.metadata(condition).freeze
          @client = client
        end

        def request(method, path, payload = nil, deadline:)
          if method == "POST" && path == "/apply-template"
            expected = QwenMessageProjection::GUIDE_RECEIPT_PAIRS + "\n" + ContextBuilder::SYSTEM + "\n" + ContextBuilder::PROTOCOL
            unless payload.is_a?(Hash) && payload.keys.sort == %w[add_generation_prompt chat_template_kwargs messages] &&
                   payload["add_generation_prompt"] == true && payload["chat_template_kwargs"] == { "enable_thinking" => false } &&
                   payload["messages"].is_a?(Array) && payload["messages"].length >= 2 &&
                   payload["messages"].first == { "role" => "system", "content" => expected } &&
                   payload["messages"].drop(1).all? { |row| row.is_a?(Hash) && %w[user assistant tool].include?(row["role"]) }
              raise ValidationError, "A16 requires unchanged receipt-pairs template input"
            end
            if @metadata.fetch("condition") == "guided"
              # Copy only the changed message; never mutate a caller-owned input.
              messages = payload.fetch("messages").dup
              messages[0] = messages[0].merge("content" => expected + "\n" + GUIDE)
              payload = payload.merge("messages" => messages)
            end
          end
          @client.request(method, path, payload, deadline: deadline)
        end

        def stream_completion(payload, deadline:, on_progress:)
          @client.stream_completion(payload, deadline: deadline, on_progress: on_progress)
        end
      end
    end
  end
end
