# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"
require_relative "memory_paths"

module SoulCore
  # Owner-private source observations are evidence, not retrieval-active memory.
  class ConversationObservationStore
    SCHEMA = "soul.conversation_observation.v1"
    DIRECTORY_NAME = "conversation_observations"
    SEGMENT_BYTES = 32 * 1024 * 1024
    SEGMENT_EVENTS = 25_000
    MAX_SEGMENTS = 10_000
    MAX_CONTENT_BYTES = 65_536
    ROLES = %w[user assistant].freeze
    IDENTITY_KEYS = %w[message_id chat_id role content created_at request_id interface].freeze
    SEGMENT_PATTERN = /\Asegment_(\d{6})\.jsonl\z/

    attr_reader :path

    def initialize(root: Dir.pwd, path: nil, clock: -> { Time.now })
      @root = File.expand_path(root)
      @path = File.expand_path(path || MemoryPaths.new(root: @root).write_path(DIRECTORY_NAME), @root)
      @clock = clock
      ensure_safe_path!(@path)
    end

    def capture_exchange(user_message:, assistant_message:, request_id:, interface:)
      candidates = [
        normalize_message(user_message, "user", request_id, interface),
        normalize_message(assistant_message, "assistant", request_id, interface)
      ]
      raise ArgumentError, "conversation messages must belong to one chat" unless candidates.map { |item| item["chat_id"] }.uniq.length == 1

      prepare_store!
      File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
        lock.flock(File::LOCK_EX)
        ensure_store_safe!
        segments = segment_paths
        active_path = segments.last || segment_path(1)
        active_events = read_segment(active_path, expected_previous: :embedded)
        existing = indexed_events(candidates, segments, active_events)
        unless existing.empty?
          return idempotent_receipt(existing, candidates) if exact_exchange?(existing, candidates)
          raise ArgumentError, "conversation observation identity conflicts with retained evidence"
        end

        captured_at = @clock.call.iso8601(6)
        previous = active_events.last&.fetch("event_sha256", nil)
        staged = build_events(candidates, captured_at, previous)
        encoded = staged.map { |event| JSON.generate(event) + "\n" }.join
        if rotate?(active_path, active_events, encoded)
          raise ArgumentError, "conversation observation segment limit reached" if segments.length >= MAX_SEGMENTS
          active_path = segment_path(segments.length + 1)
          active_events = []
        end
        append_events(active_path, encoded)
        update_index(staged, File.basename(active_path))
        receipt(staged, false, active_events.length + staged.length, File.basename(active_path))
      end
    rescue JSON::ParserError
      failure("conversation observation ledger contains malformed JSON")
    rescue ArgumentError, Errno::EACCES, Errno::EISDIR, Errno::ENOENT => error
      failure(error.message)
    end

    # Full-history verification is explicit foreground work, never part of chat capture.
    def integrity
      prepare_store!
      File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
        lock.flock(File::LOCK_SH)
        previous = nil
        total = 0
        seen_observations = {}
        seen_messages = {}
        segments = segment_paths
        segments.each do |segment|
          events = read_segment(segment, expected_previous: previous)
          events.each do |event|
            raise ArgumentError, "conversation observation identity is duplicated across segments" if seen_observations[event["observation_id"]] || seen_messages[event["message_id"]]
            seen_observations[event["observation_id"]] = true
            seen_messages[event["message_id"]] = true
          end
          previous = events.last&.fetch("event_sha256", nil) || previous
          total += events.length
        end
        { "ok" => true, "lifecycle_state" => "complete", "schema" => SCHEMA,
          "segment_count" => segments.length, "event_count" => total,
          "chain_head_sha256" => previous, "content_included" => false }
      end
    rescue JSON::ParserError
      failure("conversation observation ledger contains malformed JSON")
    rescue ArgumentError, Errno::EACCES, Errno::EISDIR => error
      failure(error.message)
    end

    # The derived index is rebuildable and never replaces ledger verification.
    def rebuild_index
      prepare_store!
      File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
        lock.flock(File::LOCK_EX)
        rebuilt = Hash.new { |hash, key| hash[key] = {} }
        seen_messages = {}
        previous = nil
        segment_paths.each do |segment|
          events = read_segment(segment, expected_previous: previous)
          events.each do |event|
            raise ArgumentError, "conversation observation identity is duplicated across segments" if seen_messages[event["message_id"]]
            seen_messages[event["message_id"]] = true
            rebuilt[index_shard(event["message_id"])][index_key(event["message_id"])] = index_entry(event, File.basename(segment))
          end
          previous = events.last&.fetch("event_sha256", nil) || previous
        end
        replace_index(rebuilt)
        { "ok" => true, "lifecycle_state" => "complete",
          "indexed_messages" => rebuilt.values.sum(&:length), "content_included" => false }
      end
    rescue JSON::ParserError
      failure("conversation observation ledger contains malformed JSON")
    rescue ArgumentError, Errno::EACCES, Errno::EISDIR => error
      failure(error.message)
    end

    # Internal foreground consumers receive exact observations only after the
    # complete retained chain has been verified.
    def batch(after_event_sha256: nil, limit: 24, max_content_bytes: 48 * 1024)
      requested = Integer(limit)
      raise ArgumentError, "conversation observation batch limit is invalid" unless requested.between?(1, 24)
      byte_limit = Integer(max_content_bytes)
      raise ArgumentError, "conversation observation content limit is invalid" unless byte_limit.between?(1, 48 * 1024)
      prepare_store!
      File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
        lock.flock(File::LOCK_SH)
        events = verified_events
        start = 0
        unless after_event_sha256.to_s.empty?
          index = events.index { |event| event["event_sha256"] == after_event_sha256.to_s }
          raise ArgumentError, "conversation observation cursor is unknown" unless index
          start = index + 1
        end
        selected = []
        bytes = 0
        events.drop(start).first(requested).each_slice(2) do |exchange|
          raise ArgumentError, "conversation observation exchange is incomplete" unless exchange.length == 2 && exchange.map { |event| event["role"] } == %w[user assistant]
          raise ArgumentError, "conversation observation exchange chat identity is inconsistent" unless exchange.map { |event| event["chat_id"] }.uniq.length == 1
          next_bytes = bytes + exchange.sum { |event| event.fetch("content").bytesize }
          raise ArgumentError, "conversation observation exchange exceeds derivation content limit" if selected.empty? && next_bytes > byte_limit
          break if next_bytes > byte_limit
          selected.concat(JSON.parse(JSON.generate(exchange)))
          bytes = next_bytes
        end
        selected
      end
    end

    def find_by_ids(ids:)
      requested = Array(ids).map(&:to_s)
      raise ArgumentError, "conversation observation identity request is invalid" unless requested.length.between?(1, 24) && requested.uniq.length == requested.length
      prepare_store!
      events = File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
        lock.flock(File::LOCK_SH)
        verified_events
      end
      selected = requested.filter_map { |id| events.find { |event| event["observation_id"] == id } }
      raise ArgumentError, "conversation observation evidence is unavailable" unless selected.length == requested.length
      JSON.parse(JSON.generate(selected))
    end

    # Foreground reconciliation may ask which bounded source-message identities
    # are already represented without exposing the corresponding observations.
    def captured_message_ids(ids:)
      requested = Array(ids).map(&:to_s)
      raise ArgumentError, "conversation observation identity request is invalid" unless requested.length.between?(1, 20_000) && requested.uniq.length == requested.length
      prepare_store!
      retained = File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
        lock.flock(File::LOCK_SH)
        verified_events.to_h { |event| [event.fetch("message_id"), true] }
      end
      requested.select { |id| retained[id] }
    rescue JSON::ParserError
      raise ArgumentError, "conversation observation ledger contains malformed JSON"
    end

    private

    def verified_events
      previous = nil
      segment_paths.flat_map do |segment|
        values = read_segment(segment, expected_previous: previous)
        previous = values.last&.fetch("event_sha256", nil) || previous
        values
      end
    end

    def prepare_store!
      ensure_safe_path!(@path)
      raise ArgumentError, "legacy conversation observation ledger requires reviewed migration" if File.file?(@path)
      FileUtils.mkdir_p(index_path, mode: 0o700)
      ensure_store_safe!
      ensure_safe_path!(lock_path)
    end

    def normalize_message(message, expected_role, request_id, interface)
      raise ArgumentError, "conversation message must be an object" unless message.is_a?(Hash)
      value = message.transform_keys(&:to_s)
      role = value["role"].to_s
      raise ArgumentError, "conversation message role is invalid" unless role == expected_role && ROLES.include?(role)
      content = value["content"].to_s
      raise ArgumentError, "conversation message content must not be empty" if content.empty?
      raise ArgumentError, "conversation message content exceeds limit" if content.bytesize > MAX_CONTENT_BYTES
      raise ArgumentError, "conversation message content must be valid UTF-8" unless content.valid_encoding?
      created_at = value["created_at"].to_s
      Time.iso8601(created_at)
      { "message_id" => bounded_identity(value["id"], "message ID"),
        "chat_id" => bounded_identity(value["chat_id"], "chat ID"), "role" => role,
        "content" => content, "created_at" => created_at,
        "request_id" => bounded_identity(request_id, "request ID"),
        "interface" => bounded_identity(interface, "interface") }
    end

    def bounded_identity(value, label)
      text = value.to_s
      raise ArgumentError, "#{label} is required" if text.empty?
      raise ArgumentError, "#{label} exceeds limit" if text.bytesize > 160
      raise ArgumentError, "#{label} contains unsupported characters" unless text.match?(/\A[A-Za-z0-9_.:-]+\z/)
      text
    end

    def build_events(candidates, captured_at, previous)
      candidates.map do |candidate|
        event = { "schema" => SCHEMA, "observation_id" => observation_id(candidate["message_id"]),
                  "message_id" => candidate["message_id"], "chat_id" => candidate["chat_id"],
                  "role" => candidate["role"], "content" => candidate["content"],
                  "created_at" => candidate["created_at"], "captured_at" => captured_at,
                  "request_id" => candidate["request_id"], "interface" => candidate["interface"],
                  "content_sha256" => Digest::SHA256.hexdigest(candidate["content"]),
                  "previous_event_sha256" => previous }
        event["event_sha256"] = event_digest(event)
        previous = event["event_sha256"]
        event
      end
    end

    def read_segment(segment, expected_previous:)
      return [] unless File.exist?(segment)
      ensure_safe_path!(segment)
      raw = File.binread(segment, SEGMENT_BYTES + 1)
      raise ArgumentError, "conversation observation segment exceeds size limit" if raw.bytesize > SEGMENT_BYTES
      raise ArgumentError, "conversation observation segment has a partial final write" unless raw.empty? || raw.end_with?("\n")
      lines = raw.lines
      raise ArgumentError, "conversation observation segment exceeds event limit" if lines.length > SEGMENT_EVENTS
      events = lines.each_with_index.filter_map do |line, index|
        next if line.strip.empty?
        event = JSON.parse(line)
        raise ArgumentError, "conversation observation event #{index + 1} is not an object" unless event.is_a?(Hash)
        event
      end
      expected_previous = events.first&.fetch("previous_event_sha256", nil) if expected_previous == :embedded
      verify_events(events, expected_previous)
      events
    end

    def verify_events(events, previous)
      ids = events.map { |event| event["observation_id"].to_s }
      messages = events.map { |event| event["message_id"].to_s }
      raise ArgumentError, "conversation observation identity is invalid" if ids.any?(&:empty?) || messages.any?(&:empty?) || ids.uniq.length != ids.length || messages.uniq.length != messages.length
      events.each do |event|
        raise ArgumentError, "conversation observation schema is unsupported" unless event["schema"] == SCHEMA
        raise ArgumentError, "conversation observation role is invalid" unless ROLES.include?(event["role"].to_s)
        valid_identity = observation_id(event["message_id"].to_s) == event["observation_id"].to_s &&
                         %w[message_id chat_id request_id interface].all? { |key| !event[key].to_s.empty? && event[key].to_s.bytesize <= 160 }
        raise ArgumentError, "conversation observation identity is invalid" unless valid_identity
        content = event["content"]
        raise ArgumentError, "conversation observation content is invalid" unless content.is_a?(String) && content.valid_encoding? && !content.empty? && content.bytesize <= MAX_CONTENT_BYTES
        Time.iso8601(event["created_at"].to_s)
        Time.iso8601(event["captured_at"].to_s)
        raise ArgumentError, "conversation observation chain is broken" unless event["previous_event_sha256"] == previous
        raise ArgumentError, "conversation observation content digest is invalid" unless event["content_sha256"] == Digest::SHA256.hexdigest(content)
        raise ArgumentError, "conversation observation event digest is invalid" unless event["event_sha256"] == event_digest(event)
        previous = event["event_sha256"]
      end
    end

    def indexed_events(candidates, segments, active_events)
      active = active_events.to_h { |event| [event["message_id"], event] }
      candidates.filter_map { |candidate| active[candidate["message_id"]] || indexed_event(candidate["message_id"], segments) }
    end

    def indexed_event(message_id, segments)
      entry = read_index_shard(index_shard(message_id))[index_key(message_id)]
      return nil unless entry
      segment = File.join(@path, entry.fetch("segment"))
      raise ArgumentError, "conversation observation index references an unknown segment" unless segments.include?(segment)
      event = read_segment(segment, expected_previous: :embedded).find { |candidate| candidate["message_id"] == message_id }
      raise ArgumentError, "conversation observation index entry is invalid" unless event && entry["observation_id"] == event["observation_id"] && entry["identity_sha256"] == identity_digest(event)
      event
    end

    def update_index(events, segment)
      events.group_by { |event| index_shard(event["message_id"]) }.each do |shard_id, values|
        shard = read_index_shard(shard_id)
        values.each { |event| shard[index_key(event["message_id"])] = index_entry(event, segment) }
        atomic_json_write(index_file(shard_id), shard)
      end
    end

    def replace_index(rebuilt)
      Dir.glob(File.join(index_path, "*.json")).each { |file| File.delete(file) }
      rebuilt.each { |shard_id, values| atomic_json_write(index_file(shard_id), values) }
    end

    def read_index_shard(shard_id)
      file = index_file(shard_id)
      return {} unless File.exist?(file)
      ensure_safe_path!(file)
      value = JSON.parse(File.binread(file, 8 * 1024 * 1024))
      raise ArgumentError, "conversation observation index is invalid" unless value.is_a?(Hash)
      value
    end

    def index_entry(event, segment)
      { "identity_sha256" => identity_digest(event), "observation_id" => event["observation_id"], "segment" => segment }
    end

    def append_events(segment, encoded)
      ensure_safe_path!(segment)
      File.open(segment, "a+b", 0o600) { |file| file.write(encoded); file.flush; file.fsync }
    end

    def atomic_json_write(destination, value)
      temporary = "#{destination}.tmp-#{Process.pid}"
      File.open(temporary, File::WRONLY | File::CREAT | File::TRUNC, 0o600) { |file| file.write(JSON.generate(value)); file.flush; file.fsync }
      File.rename(temporary, destination)
    ensure
      File.delete(temporary) if temporary && File.exist?(temporary)
    end

    def exact_exchange?(existing, candidates)
      return false unless existing.length == candidates.length
      by_message = existing.to_h { |event| [event["message_id"], event] }
      candidates.all? { |candidate| (event = by_message[candidate["message_id"]]) && IDENTITY_KEYS.all? { |key| event[key] == candidate[key] } }
    end

    def idempotent_receipt(existing, candidates)
      raise ArgumentError, "conversation observation exchange is only partially retained" unless existing.length == candidates.length
      receipt(existing, true, nil, nil)
    end

    def rotate?(active_path, events, encoded)
      File.size?(active_path).to_i + encoded.bytesize > SEGMENT_BYTES || events.length + 2 > SEGMENT_EVENTS
    end

    def segment_paths
      entries = Dir.children(@path).filter_map { |name| (match = SEGMENT_PATTERN.match(name)) && [match[1].to_i, File.join(@path, name)] }
      raise ArgumentError, "conversation observation segment limit reached" if entries.length > MAX_SEGMENTS
      entries.sort_by!(&:first)
      entries.each_with_index { |(number, _), index| raise ArgumentError, "conversation observation segment sequence is invalid" unless number == index + 1 }
      entries.map(&:last)
    end

    def segment_path(number)
      File.join(@path, format("segment_%06d.jsonl", number))
    end

    def observation_id(message_id) = "obs_#{Digest::SHA256.hexdigest(message_id)[0, 24]}"
    def index_key(message_id) = Digest::SHA256.hexdigest(message_id)
    def index_shard(message_id) = index_key(message_id)[0, 2]
    def identity_digest(event) = Digest::SHA256.hexdigest(JSON.generate(IDENTITY_KEYS.to_h { |key| [key, event[key]] }))
    def event_digest(event) = Digest::SHA256.hexdigest(JSON.generate(event.reject { |key, _| key == "event_sha256" }) + "\n")

    def receipt(events, idempotent, total_events, segment)
      { "ok" => true, "lifecycle_state" => "complete", "idempotent" => idempotent,
        "observation_ids" => events.map { |event| event["observation_id"] },
        "message_ids" => events.map { |event| event["message_id"] }, "event_count" => events.length,
        "active_segment_event_count" => total_events, "segment" => segment,
        "chain_head_sha256" => events.last && events.last["event_sha256"], "content_included" => false }.compact
    end

    def failure(reason)
      { "ok" => false, "lifecycle_state" => "failed", "reason" => reason.to_s.gsub(@root, "[PROJECT_ROOT]")[0, 300], "content_included" => false }
    end

    def lock_path = File.join(@path, ".capture.lock")
    def index_path = File.join(@path, "index")
    def index_file(shard_id) = File.join(index_path, "#{shard_id}.json")

    def ensure_store_safe!
      [@path, index_path].each { |candidate| ensure_safe_path!(candidate) }
    end

    def ensure_safe_path!(candidate)
      expanded = File.expand_path(candidate)
      prefix = "#{@root}#{File::SEPARATOR}"
      raise ArgumentError, "conversation observation path escapes project" unless expanded.start_with?(prefix)
      current = expanded
      while current.start_with?(prefix)
        raise ArgumentError, "conversation observation path component must not be a symlink" if File.symlink?(current)
        current = File.dirname(current)
      end
    end
  end
end
