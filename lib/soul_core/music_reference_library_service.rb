# frozen_string_literal: true

require "digest"
require "json"
require_relative "music_reference_library_store"

module SoulCore
  class MusicReferenceLibraryService
    DELETE_CONFIRMATION = "DELETE_MUSIC_REFERENCE"
    def initialize(root: Dir.pwd, store: nil)
      @store = store || MusicReferenceLibraryStore.new(root: root)
    end

    def inventory(limit: 200)
      value = @store.list(limit: limit)
      outcome("complete", true, "music reference library inspected", data: value)
    rescue MusicReferenceLibraryStore::ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue MusicReferenceLibraryStore::IntegrityError, SystemCallError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    def inspect(identifier:)
      outcome("complete", true, "music reference inspected", data: { "reference" => @store.read(identifier) })
    rescue MusicReferenceLibraryStore::ValidationError => error
      outcome("awaiting_input", false, error.message)
    rescue MusicReferenceLibraryStore::IntegrityError, SystemCallError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    def deletion_preview(identifier:)
      reference = @store.read(identifier)
      return awaiting("only track reference profiles can be deleted") unless reference["record_type"] == "track"
      scope = deletion_scope(reference)
      return blocked("music reference is used by fusion profiles: #{scope.fetch('dependent_fusion_ids').join(', ')}", data: { "dependent_fusion_ids" => scope.fetch("dependent_fusion_ids") }) unless scope.fetch("dependent_fusion_ids").empty?
      outcome("blocked_for_human_review", true, "exact music reference deletion confirmation required", data: {
        "confirmation_phrase" => DELETE_CONFIRMATION, "expected_digest" => digest(scope), "preview_scope" => scope
      })
    rescue MusicReferenceLibraryStore::ValidationError => error
      awaiting(error.message)
    rescue MusicReferenceLibraryStore::IntegrityError, SystemCallError => error
      blocked(error.message)
    end

    def delete(identifier:, confirmation:, expected_digest:)
      return awaiting("confirmation and expected_digest are required") if confirmation.to_s.empty? || expected_digest.to_s.empty?
      reference = @store.read(identifier)
      scope = deletion_scope(reference)
      return blocked("exact music reference deletion confirmation did not match") unless confirmation == DELETE_CONFIRMATION
      return blocked("music reference state changed; preview deletion again") unless secure_compare(expected_digest, digest(scope))
      deleted = @store.delete_track(identifier, expected_state: scope.slice("record_digest", "dependent_fusion_ids"))
      outcome("complete", true, "music reference profile permanently deleted", data: {
        "reference_id" => identifier, "title" => deleted.dig("provenance", "title"),
        "artists" => deleted.dig("provenance", "artists")
      }, mutation: "music_reference_deleted")
    rescue MusicReferenceLibraryStore::ValidationError => error
      awaiting(error.message)
    rescue MusicReferenceLibraryStore::IntegrityError, SystemCallError => error
      blocked(error.message)
    end

    private

    def deletion_scope(reference)
      dependencies = @store.list(limit: 500).fetch("fusions").select { |fusion| fusion.fetch("source_reference_ids").include?(reference.fetch("reference_id")) }.map { |fusion| fusion.fetch("fusion_id") }.sort
      {
        "operation" => "delete_music_reference", "reference_id" => reference.fetch("reference_id"),
        "title" => reference.dig("provenance", "title"), "artists" => reference.dig("provenance", "artists"),
        "record_digest" => Digest::SHA256.hexdigest(JSON.generate(reference)),
        "dependent_fusion_ids" => dependencies,
        "deletes" => %w[provenance observed_evidence synthesis_revisions approval_state],
        "source_media_deleted" => false, "source_media_retained" => false
      }
    end

    def digest(value) = Digest::SHA256.hexdigest(JSON.generate(value))
    def secure_compare(left, right) = left.to_s.bytesize == right.bytesize && left.to_s.bytes.zip(right.bytes).all? { |a, b| a == b }
    def awaiting(reason) = outcome("awaiting_input", false, reason)
    def blocked(reason, data: {}) = outcome("blocked_for_human_review", false, reason, data: data)
    def outcome(lifecycle, ok, message, data: {}, mutation: "none") = { "ok" => ok, "lifecycle_state" => lifecycle, "message" => message, "data" => data, "mutation" => mutation }
  end
end
