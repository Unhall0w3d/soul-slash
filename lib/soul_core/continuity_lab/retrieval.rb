# frozen_string_literal: true

require_relative "config"
require_relative "retrieval_ranked"

module SoulCore
  module ContinuityLab
    module Retrieval
      COLLECTIONS = %w[notes history corpus].freeze
      RESULT_BYTES = 8192
      VERSION = "unicode_word_and_fold_v1"

      # The caller supplies already-selected text. This API never opens a path,
      # follows a URL, or discovers content from ordinary Soul state.
      def self.validate_corpus!(documents)
        unless documents.is_a?(Array) && documents.length <= 32 && documents.all? do |doc|
          doc.is_a?(Hash) && doc.keys.sort == %w[content id] && Actions.valid_id?(doc["id"]) &&
            doc["content"].is_a?(String) && doc["content"].encoding == Encoding::UTF_8 &&
            doc["content"].valid_encoding? && doc["content"].bytesize <= 8192
        end
          raise ValidationError, "invalid explicit corpus"
        end
        unless documents.map { |doc| doc["id"] }.uniq.length == documents.length &&
               documents.sum { |doc| doc["content"].bytesize } <= 65_536
          raise ValidationError, "corpus duplicate IDs or quota exceeded"
        end
        documents
      end

      def self.valid_arguments?(tool, args)
        return false unless args.is_a?(Hash) && COLLECTIONS.include?(args["collection"]) &&
                            args["lineage_id"].is_a?(String) && args["lineage_id"].match?(/\A[a-f0-9]{32}\z/)
        case tool
        when "search"
          args.keys.sort == %w[collection limit lineage_id query] &&
            args["query"].is_a?(String) && args["query"].bytesize.between?(1, 128) &&
            !terms(args["query"]).empty? && args["limit"].is_a?(Integer) && args["limit"].between?(1, 8)
        when "read"
          args.keys.sort == %w[collection id length lineage_id revision start] && Actions.valid_id?(args["id"]) &&
            args["revision"].is_a?(Integer) && args["revision"] > 0 &&
            args["start"].is_a?(Integer) && args["start"].between?(0, 131_072) &&
            args["length"].is_a?(Integer) && args["length"].between?(1, 1024)
        else false
        end
      end

      def self.terms(text) = text.downcase(:fold).scan(/[\p{L}\p{N}]+/).uniq

      def self.documents(state, collection, event_id)
        case collection
        when "notes"
          state.fetch("notes").values.reject { |note| note["tombstone"] }.map do |note|
            { "id" => note["note_id"], "revision" => note["revision"], "content" => note["content"],
              "provenance" => "unverified_model_note" }
          end
        when "history"
          state.fetch("events").values.filter_map do |event|
            next unless event["event_id"] != event_id && event["state"] == "complete" && event["reason"] == "reply"
            { "id" => event["event_id"], "revision" => 1,
              "content" => ContinuityLab.encode({ "user" => event["content"], "assistant" => event["reply"] }),
              "provenance" => "observed_exchange_not_verified_fact" }
          end
        when "corpus"
          state.fetch("corpus").map { |doc| doc.merge("revision" => 1, "provenance" => "operator_selected_source_not_authority") }
        else
          raise ValidationError, "unknown collection"
        end
      end

      def self.source(state, collection, doc, start, length)
        text = doc.fetch("content")
        excerpt = text[start, length] || ""
        { "lineage_id" => state.fetch("lineage_id"), "collection" => collection,
          "id" => doc.fetch("id"), "revision" => doc.fetch("revision"),
          "content_digest" => Digest::SHA256.hexdigest(text), "provenance" => doc.fetch("provenance"),
          "span" => [start, start + excerpt.length], "text" => excerpt }
      end

      def self.result(state, tool, args, event_id, config: nil)
        return { "ok" => false, "reason" => "cross_lineage_read" } unless args["lineage_id"] == state["lineage_id"]
        docs = documents(state, args.fetch("collection"), event_id)
        if tool == "read"
          doc = docs.find { |entry| entry["id"] == args["id"] }
          return { "ok" => false, "reason" => "not_found" } unless doc
          return { "ok" => false, "reason" => "revision_conflict" } unless doc["revision"] == args["revision"]
          return { "ok" => false, "reason" => "invalid_span" } if args["start"] > doc["content"].length
          value = { "ok" => true, "source" => source(state, args["collection"], doc, args["start"], args["length"]) }
          return value if ContinuityLab.encode(value).bytesize <= RESULT_BYTES
          return { "ok" => false, "reason" => "result_bytes_quota" }
        end
        return RankedRetrieval.search(state, args, event_id, docs) if config&.ranked_retrieval?
        query = terms(args.fetch("query"))
        matches = docs.filter_map do |doc|
          words = doc["content"].downcase(:fold).scan(/[\p{L}\p{N}]+/)
          counts = words.tally
          next unless query.all? { |word| counts.fetch(word, 0) > 0 }
          [doc, query.sum { |word| counts.fetch(word) }]
        end.sort_by { |doc, score| [-score, doc["id"]] }
        value = { "ok" => true, "hits" => [], "truncated" => false }
        matches.first(args.fetch("limit")).each do |doc, _score|
          # Match in original text so case-fold expansion cannot corrupt offsets.
          position = doc["content"].index(/#{Regexp.escape(query.first)}/i) || 0
          hit = source(state, args["collection"], doc, [position - 32, 0].max, 160)
          candidate = value.merge("hits" => value["hits"] + [hit])
          break if ContinuityLab.encode(candidate).bytesize > RESULT_BYTES
          value = candidate
        end
        value["truncated"] = matches.length > value["hits"].length
        value
      end
    end
  end
end
