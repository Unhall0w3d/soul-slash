# frozen_string_literal: true

require_relative "music_reference_library_store"

module SoulCore
  class MusicReferenceLibraryService
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

    private

    def outcome(lifecycle, ok, message, data: {})
      { "ok" => ok, "lifecycle_state" => lifecycle, "message" => message, "data" => data, "mutation" => "none" }
    end
  end
end
