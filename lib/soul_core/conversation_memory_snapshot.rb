# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require "time"
require_relative "conversation_memory_store"

module SoulCore
  class ConversationMemorySnapshot
    SCHEMA = "soul.conversation_memory_snapshot.v1"
    DEFAULT_EXPORT_ROOT = "Soul/memory/exports"

    def initialize(
      root: Dir.pwd,
      store: nil,
      export_root: DEFAULT_EXPORT_ROOT,
      clock: -> { Time.now }
    )
      @root = File.expand_path(root)
      @store = store || ConversationMemoryStore.new(root: @root)
      @export_root = File.expand_path(export_root, @root)
      @clock = clock
      FileUtils.mkdir_p(@export_root)
    end

    def export(name: nil)
      path = export_path(name)
      payload = unsigned_payload
      payload["sha256"] = digest_for(payload)
      File.write(path, JSON.pretty_generate(payload) + "\n", encoding: "UTF-8")

      {
        "ok" => true,
        "path" => relative_path(path),
        "schema" => payload["schema"],
        "sha256" => payload["sha256"],
        "event_count" => payload["event_count"],
        "record_count" => payload["record_count"]
      }
    end

    def verify(target = "latest")
      path = resolve_export_path(target)
      payload = JSON.parse(File.read(path, encoding: "UTF-8"))
      expected = payload["sha256"].to_s
      unsigned = payload.reject { |key, _value| key == "sha256" }
      actual = digest_for(unsigned)
      replay = replay_records(payload.fetch("events", []))
      exported_records = canonicalize(payload.fetch("records", []))

      checks = {
        "schema_matches" => payload["schema"] == SCHEMA,
        "digest_matches" => !expected.empty? && secure_equal?(expected, actual),
        "event_count_matches" => payload["event_count"].to_i == Array(payload["events"]).length,
        "record_count_matches" => payload["record_count"].to_i == Array(payload["records"]).length,
        "replay_matches_records" => canonicalize(replay) == exported_records
      }

      {
        "ok" => checks.values.all?,
        "path" => relative_path(path),
        "expected_sha256" => expected,
        "actual_sha256" => actual,
        "checks" => checks
      }
    rescue JSON::ParserError => error
      {
        "ok" => false,
        "path" => relative_path(path),
        "error" => "invalid_json: #{error.message}",
        "checks" => {}
      }
    end

    def export_paths
      Dir.glob(File.join(@export_root, "*.json")).sort
    end

    private

    def unsigned_payload
      events = @store.events
      records = @store.records(include_deleted: true).sort_by { |record| record["id"].to_s }
      {
        "schema" => SCHEMA,
        "generated_at" => @clock.call.iso8601(6),
        "source_ledger" => relative_path(@store.path),
        "event_count" => events.length,
        "record_count" => records.length,
        "events" => events,
        "records" => records,
        "physical_purge_supported" => false
      }
    end

    def export_path(name)
      filename = name.to_s.strip
      filename = "conversation-memory-#{@clock.call.utc.strftime('%Y%m%dT%H%M%S%6NZ')}.json" if filename.empty?
      validate_filename(filename)
      filename = "#{filename}.json" unless filename.end_with?(".json")
      File.join(@export_root, filename)
    end

    def resolve_export_path(target)
      token = target.to_s.strip
      token = "latest" if token.empty?
      if %w[latest last].include?(token.downcase)
        path = export_paths.last
        raise ArgumentError, "No memory snapshots are available" unless path

        return path
      end

      validate_filename(token)
      token = "#{token}.json" unless token.end_with?(".json")
      path = File.join(@export_root, token)
      raise ArgumentError, "Memory snapshot not found: #{token}" unless File.file?(path)

      path
    end

    def validate_filename(filename)
      if filename.empty? || filename.include?(File::SEPARATOR) || filename.include?("\\") || filename == "." || filename == ".."
        raise ArgumentError, "Snapshot name must be a simple filename"
      end
    end

    def replay_records(events)
      Dir.mktmpdir("soul-memory-snapshot-verify") do |directory|
        path = File.join(directory, ConversationMemoryStore::DEFAULT_PATH)
        FileUtils.mkdir_p(File.dirname(path))
        File.open(path, "w") do |file|
          Array(events).each { |event| file.puts(JSON.generate(event)) }
        end
        store = ConversationMemoryStore.new(root: directory)
        store.records(include_deleted: true).sort_by { |record| record["id"].to_s }
      end
    end

    def digest_for(payload)
      Digest::SHA256.hexdigest(JSON.generate(canonicalize(payload)))
    end

    def canonicalize(value)
      case value
      when Hash
        value.keys.map(&:to_s).sort.each_with_object({}) do |key, result|
          original_key = value.key?(key) ? key : value.keys.find { |candidate| candidate.to_s == key }
          result[key] = canonicalize(value[original_key])
        end
      when Array
        value.map { |item| canonicalize(item) }
      else
        value
      end
    end

    def secure_equal?(left, right)
      return false unless left.bytesize == right.bytesize

      left.bytes.zip(right.bytes).reduce(0) { |difference, pair| difference | (pair[0] ^ pair[1]) }.zero?
    end

    def relative_path(path)
      expanded = File.expand_path(path)
      prefix = "#{@root}#{File::SEPARATOR}"
      expanded.start_with?(prefix) ? expanded.delete_prefix(prefix) : expanded
    end
  end
end
