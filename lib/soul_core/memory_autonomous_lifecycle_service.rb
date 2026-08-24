# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"
require_relative "memory_paths"

module SoulCore
  class MemoryAutonomousLifecycleService
    SCHEMA = "soul.memory_autonomous_lifecycle.a16.v1"
    POLICY_VERSION = "soul.memory.lifecycle.a16.v1"
    FILE_NAME = "memory_autonomous_lifecycle_cycles.jsonl"
    MAX_BYTES = 32 * 1024 * 1024
    MAX_CYCLES = 10_000
    ENTRY_KEYS = %w[
      admission created_at cycle_id cycle_sha256 derivation mode policy_version
      previous_cycle_sha256 request_id schema
    ].freeze
    MODES = %w[admit_pending derive_and_admit no_work].freeze

    def initialize(root:, derivation_service:, admission_service:, path: nil, clock: -> { Time.now })
      @root = File.expand_path(root)
      @derivations = derivation_service
      @admissions = admission_service
      @path = File.expand_path(path || MemoryPaths.new(root: @root).write_path(FILE_NAME), @root)
      @clock = clock
      ensure_safe_path!
    end

    def run(request_id:)
      request = bounded_id(request_id)
      ensure_safe_path!
      FileUtils.mkdir_p(File.dirname(@path))
      File.open(@path, "a+b", 0o600) do |file|
        file.flock(File::LOCK_EX)
        ensure_safe_path!
        file.rewind
        cycles = parse_and_verify(file.read.to_s)
        replay = cycles.find { |cycle| cycle["request_id"] == request }
        return receipt(replay, idempotent: true) if replay

        verify_sources!
        entry = execute_cycle(request, cycles.last)
        encoded = JSON.generate(entry) + "\n"
        raise ArgumentError, "memory lifecycle cycle journal exceeds size limit" if file.size + encoded.bytesize > MAX_BYTES
        raise ArgumentError, "memory lifecycle cycle journal exceeds entry limit" if cycles.length + 1 > MAX_CYCLES
        file.seek(0, IO::SEEK_END)
        file.write(encoded)
        file.flush
        file.fsync
        receipt(entry, idempotent: false)
      end
    rescue JSON::ParserError
      failure("memory lifecycle cycle data contains malformed JSON")
    rescue ArgumentError, Errno::EACCES, Errno::EISDIR, Errno::ENOENT, IOError => error
      failure(error.message)
    end

    def integrity
      ensure_safe_path!
      cycles = File.file?(@path) ? parse_and_verify(File.binread(@path)) : []
      { "ok" => true, "lifecycle_state" => "complete", "schema" => SCHEMA,
        "cycle_count" => cycles.length,
        "chain_head_sha256" => cycles.last && cycles.last["cycle_sha256"],
        "content_included" => false }
    rescue JSON::ParserError
      failure("memory lifecycle cycle data contains malformed JSON")
    rescue ArgumentError, Errno::EACCES, Errno::EISDIR => error
      failure(error.message)
    end

    private

    def execute_cycle(request, prior)
      pending = pending_packet?
      if pending
        admission = checked(@admissions.apply(request_id: "#{request}:admit-pending"), "memory admission")
        return build_entry(request, "admit_pending", nil, admission, prior)
      end

      derivation = checked(@derivations.derive(request_id: "#{request}:derive"), "memory derivation")
      return build_entry(request, "no_work", derivation, nil, prior) if derivation["no_work"]

      admission = checked(@admissions.apply(request_id: "#{request}:admit-derived"), "memory admission")
      raise ArgumentError, "derived memory packet was not admitted" if admission["no_work"]
      unless admission["source_packet_id"] == derivation["packet_id"]
        raise ArgumentError, "memory lifecycle source packet changed during cycle"
      end
      build_entry(request, "derive_and_admit", derivation, admission, prior)
    end

    def pending_packet?
      latest = @admissions.decision_batch(limit: 1).last
      cursor = latest && latest["source_packet_sha256"]
      !@derivations.packet_batch(after_packet_sha256: cursor, limit: 1).empty?
    end

    def verify_sources!
      derivation = @derivations.integrity
      admission = @admissions.integrity
      raise ArgumentError, "memory derivation evidence is unavailable" unless derivation["ok"]
      raise ArgumentError, "memory admission evidence is unavailable" unless admission["ok"]
    end

    def checked(result, label)
      raise ArgumentError, "#{label} failed: #{result['reason']}" unless result.is_a?(Hash) && result["ok"]
      content_free(result)
    end

    def build_entry(request, mode, derivation, admission, prior)
      entry = {
        "schema" => SCHEMA,
        "cycle_id" => "mac_#{Digest::SHA256.hexdigest([request, mode].join(':'))[0, 24]}",
        "request_id" => request,
        "created_at" => @clock.call.iso8601(6),
        "policy_version" => POLICY_VERSION,
        "mode" => mode,
        "derivation" => derivation,
        "admission" => admission,
        "previous_cycle_sha256" => prior && prior["cycle_sha256"]
      }
      entry["cycle_sha256"] = digest(entry)
      entry
    end

    def parse_and_verify(raw)
      raise ArgumentError, "memory lifecycle cycle journal exceeds size limit" if raw.bytesize > MAX_BYTES
      raise ArgumentError, "memory lifecycle cycle journal has a partial final write" unless raw.empty? || raw.end_with?("\n")
      entries = raw.lines.filter_map { |line| JSON.parse(line) unless line.strip.empty? }
      raise ArgumentError, "memory lifecycle cycle journal exceeds entry limit" if entries.length > MAX_CYCLES
      previous = nil
      entries.each do |entry|
        unless entry.is_a?(Hash) && entry.keys.sort == ENTRY_KEYS
          raise ArgumentError, "memory lifecycle cycle is invalid"
        end
        raise ArgumentError, "memory lifecycle cycle schema is unsupported" unless entry["schema"] == SCHEMA && entry["policy_version"] == POLICY_VERSION
        bounded_id(entry["cycle_id"])
        bounded_id(entry["request_id"])
        raise ArgumentError, "memory lifecycle cycle mode is invalid" unless MODES.include?(entry["mode"])
        raise ArgumentError, "memory lifecycle cycle shape is invalid" unless valid_stage_shape?(entry)
        raise ArgumentError, "memory lifecycle cycle chain is broken" unless entry["previous_cycle_sha256"] == previous
        raise ArgumentError, "memory lifecycle cycle digest is invalid" unless entry["cycle_sha256"] == digest(entry)
        Time.iso8601(entry.fetch("created_at"))
        previous = entry["cycle_sha256"]
      end
      raise ArgumentError, "memory lifecycle cycle identity is duplicated" unless entries.map { |entry| entry["request_id"] }.uniq.length == entries.length
      entries
    end

    def valid_stage_shape?(entry)
      case entry["mode"]
      when "admit_pending" then entry["derivation"].nil? && stage_receipt?(entry["admission"])
      when "derive_and_admit" then stage_receipt?(entry["derivation"]) && stage_receipt?(entry["admission"])
      when "no_work" then stage_receipt?(entry["derivation"]) && entry["derivation"]["no_work"] == true && entry["admission"].nil?
      else false
      end
    end

    def stage_receipt?(value)
      value.is_a?(Hash) && value["ok"] == true && value["lifecycle_state"] == "complete" && value["content_included"] == false
    end

    def receipt(entry, idempotent:)
      admission = entry["admission"]
      { "ok" => true, "lifecycle_state" => "complete", "schema" => SCHEMA,
        "idempotent" => idempotent, "cycle_id" => entry["cycle_id"],
        "mode" => entry["mode"], "no_work" => entry["mode"] == "no_work",
        "packet_id" => (entry["derivation"] && entry["derivation"]["packet_id"]) || (admission && admission["source_packet_id"]),
        "proposal_count" => entry["derivation"] && entry["derivation"]["proposal_count"],
        "decision_counts" => admission && admission["decision_counts"],
        "rollback_references" => admission && admission["rollback_references"],
        "cycle_sha256" => entry["cycle_sha256"], "content_included" => false }.compact
    end

    def content_free(value)
      copy = JSON.parse(JSON.generate(value))
      redact(copy)
    end

    def redact(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, child), output|
          next if %w[text content excerpt query messages candidate structured].include?(key.to_s)
          output[key] = redact(child)
        end
      when Array then value.map { |child| redact(child) }
      else value
      end
    end

    def bounded_id(value)
      text = value.to_s
      raise ArgumentError, "memory lifecycle cycle ID is invalid" unless text.bytesize.between?(1, 128) && text.match?(/\A[A-Za-z0-9_.:\/-]+\z/)
      text
    end

    def digest(entry)
      Digest::SHA256.hexdigest(JSON.generate(entry.reject { |key, _| key == "cycle_sha256" }) + "\n")
    end

    def failure(reason)
      { "ok" => false, "lifecycle_state" => "failed", "schema" => SCHEMA,
        "reason" => reason.to_s.gsub(@root, "[PROJECT_ROOT]")[0, 400], "content_included" => false }
    end

    def ensure_safe_path!
      prefix = "#{@root}#{File::SEPARATOR}"
      raise ArgumentError, "memory lifecycle cycle path escapes project" unless @path.start_with?(prefix)
      current = @path
      while current.start_with?(prefix)
        raise ArgumentError, "memory lifecycle cycle path component must not be a symlink" if File.symlink?(current)
        current = File.dirname(current)
      end
    end
  end
end
