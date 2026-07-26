# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "time"

module SoulCore
  class ProjectTrackerService
    SCHEMA_VERSION = "soul.project_tracker.v1"
    ITEM_ID = /\Atrack_[a-z0-9_]{3,64}\z/
    STATUSES = %w[planned in_progress blocked needs_review validated done deferred].freeze
    HORIZONS = %w[now next later backlog archive].freeze
    PRIORITIES = %w[high medium low].freeze
    MAX_ITEMS = 300
    MAX_BYTES = 512 * 1024
    TEXT_LIMITS = {
      "title" => 160, "area" => 80, "summary" => 2_000,
      "acceptance" => 3_000, "notes" => 4_000, "source" => 240,
      "implementation" => 5_000, "technologies" => 2_000,
      "interfaces" => 2_000, "commands" => 4_000, "references" => 3_000
    }.freeze

    def initialize(
      root: Dir.pwd,
      state_path: nil,
      seed_path: nil,
      clock: -> { Time.now.utc },
      id_generator: -> { SecureRandom.hex(5) }
    )
      @root = File.expand_path(root)
      @state_path = File.expand_path(state_path || File.join(@root, "Soul/private/project_tracker/state.json"))
      @seed_path = File.expand_path(seed_path || File.join(@root, "config/project_tracker_seed.json"))
      @clock = clock
      @id_generator = id_generator
      raise ArgumentError, "tracker state must remain inside project root" unless within?(@state_path, @root)
      raise ArgumentError, "tracker seed must remain inside project root" unless within?(@seed_path, @root)
    end

    def snapshot
      state = load_or_initialize
      outcome("complete", true, "Project timeline loaded", state, "none")
    end

    def create(attributes:)
      state = load_or_initialize
      raise ArgumentError, "project tracker item limit exceeded" if state.fetch("items").length >= MAX_ITEMS

      input = normalize_input(attributes, require_all: true)
      item_id = input["item_id"].to_s.empty? ? generated_id(input.fetch("title"), state) : input.fetch("item_id")
      raise ArgumentError, "tracker item ID already exists" if state.fetch("items").any? { |item| item["item_id"] == item_id }

      now = @clock.call.iso8601
      item = input.merge("item_id" => item_id, "revision" => 1, "created_at" => now, "updated_at" => now)
      state.fetch("items") << item
      state["revision"] += 1
      state["updated_at"] = now
      persist(state)
      outcome("complete", true, "Timeline item created", { "tracker" => state, "item" => item }, "project_tracker_item_created")
    end

    def update(item_id:, attributes:, expected_revision:)
      state = load_or_initialize
      item = state.fetch("items").find { |record| record["item_id"] == item_id.to_s }
      return outcome("awaiting_input", false, "Timeline item was not found", { "item_id" => item_id }, "none") unless item
      revision = Integer(expected_revision)
      return outcome("blocked_for_human_review", false, "Timeline item changed; reload before editing", { "item" => item }, "none") unless revision == item.fetch("revision")

      changes = normalize_input(attributes, require_all: false)
      raise ArgumentError, "at least one editable tracker field is required" if changes.empty?
      now = @clock.call.iso8601
      item.merge!(changes)
      item["revision"] += 1
      item["updated_at"] = now
      state["revision"] += 1
      state["updated_at"] = now
      persist(state)
      outcome("complete", true, "Timeline item updated", { "tracker" => state, "item" => item }, "project_tracker_item_updated")
    rescue TypeError
      raise ArgumentError, "expected tracker revision must be an integer"
    end

    def find(reference)
      text = reference.to_s.strip
      state = load_or_initialize
      exact = state.fetch("items").find { |item| item["item_id"].casecmp?(text) || item["title"].casecmp?(text) }
      return { "status" => "found", "item" => exact } if exact

      matches = state.fetch("items").select { |item| item["title"].downcase.include?(text.downcase) }
      return { "status" => "found", "item" => matches.first } if matches.length == 1

      { "status" => matches.empty? ? "missing" : "ambiguous", "items" => matches }
    end

    private

    def load_or_initialize
      return read_state if File.file?(@state_path) && !File.symlink?(@state_path)
      raise RuntimeError, "project tracker state path is unsafe" if File.exist?(@state_path) || File.symlink?(@state_path)

      seed = JSON.parse(File.binread(@seed_path, MAX_BYTES))
      raise RuntimeError, "project tracker seed schema is unsupported" unless seed["schema_version"] == "soul.project_tracker.seed.v1"
      now = @clock.call.iso8601
      items = Array(seed["items"]).map do |record|
        normalized = normalize_input(record, require_all: true)
        normalized.merge(
          "revision" => 1,
          "notes" => record["notes"].to_s,
          "created_at" => now,
          "updated_at" => now
        )
      end
      state = {
        "schema_version" => SCHEMA_VERSION,
        "title" => seed.fetch("title", "Soul / Project Timeline").to_s[0, 160],
        "revision" => 1,
        "created_at" => now,
        "updated_at" => now,
        "items" => items
      }
      validate_state!(state)
      persist(state)
      state
    rescue JSON::ParserError, Errno::ENOENT => error
      raise RuntimeError, "project tracker seed is unavailable: #{error.class}"
    end

    def read_state
      raise RuntimeError, "project tracker state exceeds size limit" if File.size(@state_path) > MAX_BYTES
      state = JSON.parse(File.binread(@state_path, MAX_BYTES))
      validate_state!(state)
      state
    rescue JSON::ParserError, Errno::ENOENT => error
      raise RuntimeError, "project tracker state is invalid: #{error.class}"
    end

    def normalize_input(attributes, require_all:)
      input = attributes.to_h.transform_keys(&:to_s)
      editable = %w[item_id title area horizon status priority summary acceptance notes source implementation technologies interfaces commands references]
      unknown = input.keys - editable
      raise ArgumentError, "unknown tracker fields: #{unknown.join(', ')}" unless unknown.empty?

      required = %w[title area horizon status priority summary acceptance source]
      missing = required.reject { |key| input.key?(key) }
      raise ArgumentError, "missing tracker fields: #{missing.join(', ')}" if require_all && !missing.empty?
      result = {}
      input.each do |key, value|
        next if key == "item_id" && value.to_s.strip.empty?
        if key == "item_id"
          raise ArgumentError, "tracker item ID is invalid" unless value.to_s.match?(ITEM_ID)
          result[key] = value.to_s
        elsif key == "horizon"
          raise ArgumentError, "tracker horizon is invalid" unless HORIZONS.include?(value.to_s)
          result[key] = value.to_s
        elsif key == "status"
          raise ArgumentError, "tracker status is invalid" unless STATUSES.include?(value.to_s)
          result[key] = value.to_s
        elsif key == "priority"
          raise ArgumentError, "tracker priority is invalid" unless PRIORITIES.include?(value.to_s)
          result[key] = value.to_s
        else
          text = value.to_s.strip
          limit = TEXT_LIMITS.fetch(key)
          raise ArgumentError, "#{key} is required" if required.include?(key) && text.empty?
          raise ArgumentError, "#{key} exceeds #{limit} characters" if text.length > limit
          result[key] = text
        end
      end
      result
    end

    def validate_state!(state)
      raise RuntimeError, "project tracker schema is unsupported" unless state["schema_version"] == SCHEMA_VERSION
      raise RuntimeError, "project tracker revision is invalid" unless state["revision"].is_a?(Integer) && state["revision"].positive?
      items = state["items"]
      raise RuntimeError, "project tracker items are invalid" unless items.is_a?(Array) && items.length <= MAX_ITEMS
      ids = items.map { |item| item["item_id"] }
      raise RuntimeError, "project tracker item IDs are invalid" unless ids.uniq.length == ids.length && ids.all? { |id| id.to_s.match?(ITEM_ID) }
      items.each do |item|
        normalize_input(item.slice("item_id", "title", "area", "horizon", "status", "priority", "summary", "acceptance", "notes", "source", "implementation", "technologies", "interfaces", "commands", "references"), require_all: true)
        raise RuntimeError, "project tracker item revision is invalid" unless item["revision"].is_a?(Integer) && item["revision"].positive?
      end
      true
    rescue ArgumentError => error
      raise RuntimeError, "project tracker state failed validation: #{error.message}"
    end

    def generated_id(title, state)
      stem = title.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")[0, 44]
      stem = "item" if stem.empty?
      loop do
        id = "track_#{stem}_#{@id_generator.call}"
        return id if id.match?(ITEM_ID) && state.fetch("items").none? { |item| item["item_id"] == id }
      end
    end

    def persist(state)
      validate_state!(state)
      directory = File.dirname(@state_path)
      FileUtils.mkdir_p(directory, mode: 0o700)
      raise RuntimeError, "project tracker directory is unsafe" if File.symlink?(directory)
      temporary = "#{@state_path}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(JSON.pretty_generate(state))
        file.write("\n")
        file.flush
        file.fsync
      end
      File.rename(temporary, @state_path)
    ensure
      File.unlink(temporary) if defined?(temporary) && temporary && File.file?(temporary)
    end

    def outcome(lifecycle, ok, message, data, mutation)
      { "lifecycle_state" => lifecycle, "ok" => ok, "message" => message, "data" => data, "mutation" => mutation }
    end

    def within?(path, root)
      expanded = File.expand_path(path)
      boundary = File.expand_path(root)
      expanded == boundary || expanded.start_with?("#{boundary}/")
    end
  end
end
