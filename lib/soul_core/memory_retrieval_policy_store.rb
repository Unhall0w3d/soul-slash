# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "pathname"
require "tempfile"
require "time"

module SoulCore
  # Stores only the selected retrieval algorithm and its content-free change
  # history. Canonical memories and projection data remain separate authorities.
  class MemoryRetrievalPolicyStore
    SCHEMA = "soul.memory_retrieval_policy.a26.v1"
    MAX_BYTES = 64 * 1024
    MAX_EVENTS = 64
    PROFILES = {
      "local_hybrid_a4" => nil,
      "projection_gate_local_order_a25" => 0.65,
      "projection_gate_local_order_a29" => 0.55
    }.freeze

    def initialize(private_root:, path:, clock: -> { Time.now.utc })
      @private_root = File.realpath(private_root)
      @path = File.expand_path(path)
      @clock = clock
      raise ArgumentError, "policy path escapes private memory" unless @path.start_with?("#{@private_root}#{File::SEPARATOR}")
    end

    def active
      document = load_document
      document ? document.fetch("active") : default_policy
    rescue StandardError
      default_policy.merge("fallback_reason" => "policy_unavailable")
    end

    def status
      document = load_document
      {
        "schema" => SCHEMA,
        "active" => document ? document.fetch("active") : default_policy,
        "previous" => document&.fetch("previous"),
        "revision" => document&.fetch("revision", 0) || 0,
        "audit" => document&.fetch("audit", []) || [],
        "configured" => !document.nil?,
        "content_included" => false,
        "mutation" => "none"
      }
    end

    def activate(profile:, reason_sha256:)
      desired = policy(profile)
      current = load_document
      from = current ? current.fetch("active") : default_policy
      revision = current ? current.fetch("revision") + 1 : 1
      event = event_for("activate", revision, from, desired, reason_sha256)
      document = {
        "schema" => SCHEMA,
        "revision" => revision,
        "active" => desired,
        "previous" => from,
        "updated_at" => event.fetch("at"),
        "audit" => (Array(current&.fetch("audit", [])) + [event]).last(MAX_EVENTS)
      }
      write_document(document)
      status
    end

    def rollback(reason_sha256:)
      current = load_document
      raise "retrieval policy has no rollback target" unless current && current["previous"]
      desired = validate_policy(current.fetch("previous"))
      from = current.fetch("active")
      revision = current.fetch("revision") + 1
      event = event_for("rollback", revision, from, desired, reason_sha256)
      document = {
        "schema" => SCHEMA,
        "revision" => revision,
        "active" => desired,
        "previous" => from,
        "updated_at" => event.fetch("at"),
        "audit" => (current.fetch("audit") + [event]).last(MAX_EVENTS)
      }
      write_document(document)
      status
    end

    private

    def default_policy = {"profile" => "local_hybrid_a4", "projection_threshold" => nil}

    def policy(profile)
      name = profile.to_s
      raise ArgumentError, "retrieval policy profile is unsupported" unless PROFILES.key?(name)
      {"profile" => name, "projection_threshold" => PROFILES.fetch(name)}
    end

    def validate_policy(value)
      raise "retrieval policy is invalid" unless value.is_a?(Hash) && value.keys.sort == %w[profile projection_threshold]
      expected = policy(value.fetch("profile"))
      raise "retrieval policy threshold is invalid" unless value["projection_threshold"] == expected["projection_threshold"]
      expected
    end

    def event_for(action, revision, from, to, reason_sha256)
      digest = reason_sha256.to_s
      raise ArgumentError, "retrieval policy reason digest is invalid" unless digest.match?(/\A[0-9a-f]{64}\z/)
      body = {"action" => action, "revision" => revision, "from" => from.fetch("profile"), "to" => to.fetch("profile"), "reason_sha256" => digest, "at" => @clock.call.utc.iso8601(6)}
      body.merge("event_id" => "policy_#{Digest::SHA256.hexdigest(JSON.generate(body))[0, 20]}")
    end

    def load_document
      validate_path!
      return nil unless File.exist?(@path)
      File.open(@path, File::RDONLY | File::NOFOLLOW) do |file|
        before = file.stat
        raise "retrieval policy must be owner private" unless before.file? && before.uid == Process.uid && (before.mode & 0o077).zero?
        raise "retrieval policy exceeds byte bound" if before.size > MAX_BYTES
        payload = file.read(MAX_BYTES + 1)
        after = file.stat
        raise "retrieval policy changed while being read" unless before.dev == after.dev && before.ino == after.ino && before.size == after.size && before.mtime == after.mtime
        validate_document(JSON.parse(payload))
      end
    rescue JSON::ParserError
      raise "retrieval policy JSON is malformed"
    end

    def validate_document(value)
      raise "retrieval policy document is invalid" unless value.is_a?(Hash) && value.keys.sort == %w[active audit previous revision schema updated_at]
      raise "retrieval policy schema is invalid" unless value["schema"] == SCHEMA
      revision = Integer(value["revision"])
      raise "retrieval policy revision is invalid" unless revision.between?(1, 1_000_000)
      validate_policy(value.fetch("active"))
      validate_policy(value.fetch("previous")) if value["previous"]
      audit = value.fetch("audit")
      raise "retrieval policy audit is invalid" unless audit.is_a?(Array) && audit.length.between?(1, MAX_EVENTS)
      audit.each { |event| validate_event(event) }
      JSON.parse(JSON.generate(value))
    rescue KeyError, ArgumentError, TypeError
      raise "retrieval policy document is malformed"
    end

    def validate_event(event)
      keys = %w[action at event_id from reason_sha256 revision to]
      raise "retrieval policy audit event is invalid" unless event.is_a?(Hash) && event.keys.sort == keys
      raise "retrieval policy audit action is invalid" unless %w[activate rollback].include?(event["action"])
      raise "retrieval policy audit identifier is invalid" unless event["event_id"].to_s.match?(/\Apolicy_[0-9a-f]{20}\z/)
      raise "retrieval policy audit digest is invalid" unless event["reason_sha256"].to_s.match?(/\A[0-9a-f]{64}\z/)
      Time.iso8601(event.fetch("at").to_s)
      revision = Integer(event.fetch("revision"))
      raise "retrieval policy audit revision is invalid" unless revision.between?(1, 1_000_000)
      policy(event.fetch("from")); policy(event.fetch("to"))
    end

    def write_document(document)
      validate_document(document)
      validate_path!
      FileUtils.mkdir_p(File.dirname(@path), mode: 0o700)
      temporary = Tempfile.new([".retrieval-policy-", ".json"], File.dirname(@path), mode: 0o600)
      begin
        temporary.write(JSON.generate(document) + "\n")
        temporary.flush
        temporary.fsync
        temporary.close
        raise "retrieval policy destination is a symlink" if File.symlink?(@path)
        File.rename(temporary.path, @path)
        File.chmod(0o600, @path)
        File.open(File.dirname(@path), File::RDONLY) { |directory| directory.fsync }
      ensure
        temporary.close unless temporary.closed?
        File.delete(temporary.path) if File.exist?(temporary.path)
      end
    end

    def validate_path!
      current = Pathname.new(@private_root)
      relative = Pathname.new(File.dirname(@path)).relative_path_from(current)
      [current, *relative.each_filename.map { |name| current = current.join(name) }].each do |component|
        raise "retrieval policy path contains a symlink" if File.symlink?(component.to_s)
      end
    rescue ArgumentError
      raise "retrieval policy path escapes private memory"
    end
  end
end
