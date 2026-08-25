# frozen_string_literal: true

module SoulCore
  # Enriches the existing approved-memory context with fresh semantic matches.
  # The derived index contributes record identifiers only; content is always
  # re-read from the canonical append-only memory ledger before prompt use.
  class SemanticConversationMemoryContext
    MAX_CONTEXT_RECORDS = 20

    def initialize(memory_store:, retrieval_service:)
      @memory_store = memory_store
      @retrieval_service = retrieval_service
    end

    def context_for(query:, chat_id: nil, limit: 8)
      wanted = normalize_limit(limit)
      baseline = @memory_store.context_for(query: query, chat_id: chat_id, limit: wanted)
      retrieval = @retrieval_service.query(query: query, limit: wanted)
      return baseline unless retrieval["lifecycle_state"] == "complete"

      data = retrieval.fetch("data", {})
      return baseline unless %w[hybrid projection_gate_local_order].include?(data["retrieval_mode"])

      approved = @memory_store.records(status: "approved").to_h { |record| [record.fetch("id").to_s, record] }
      baseline_records = Array(baseline["records"]).select { |record| approved.key?(record["id"].to_s) }
      protected, remaining = baseline_records.partition do |record|
        record.fetch("metadata", {})["always_include"] == true ||
          (!chat_id.to_s.empty? && record["chat_id"].to_s == chat_id.to_s)
      end
      semantic = Array(data["results"]).filter_map do |result|
        approved[result["memory_id"].to_s]
      end

      chosen = unique_records(protected + semantic + remaining).first(wanted)
      build_context(chosen, semantic, data)
    rescue StandardError
      baseline || @memory_store.context_for(query: query, chat_id: chat_id, limit: wanted)
    end

    private

    def normalize_limit(value)
      limit = value.to_i
      limit = 8 unless limit.positive?
      [limit, MAX_CONTEXT_RECORDS].min
    end

    def unique_records(records)
      seen = {}
      Array(records).select do |record|
        identifier = record.fetch("id").to_s
        !identifier.empty? && !seen.key?(identifier) && (seen[identifier] = true)
      end
    end

    def build_context(chosen, semantic, retrieval_data)
      chosen_ids = chosen.map { |record| record.fetch("id").to_s }
      semantic_ids = semantic.map { |record| record.fetch("id").to_s } & chosen_ids
      {
        "records" => chosen,
        "record_ids" => chosen_ids,
        "layers" => chosen.map { |record| record["layer"] }.compact.uniq,
        "count" => chosen.length,
        "rendered" => @memory_store.render_context(chosen),
        "retrieval_mode" => retrieval_data.fetch("retrieval_mode"),
        "ranking_profile" => retrieval_data["ranking_profile"],
        "projection_available" => retrieval_data["projection_available"] == true,
        "semantic_record_ids" => semantic_ids,
        "index_available" => retrieval_data["index_available"] == true,
        "authority" => "canonical_approved_memory_ledger"
      }
    end
  end
end
