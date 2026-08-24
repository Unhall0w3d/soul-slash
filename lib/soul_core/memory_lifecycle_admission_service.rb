# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"
require_relative "memory_paths"
require_relative "memory_protection_policy"

module SoulCore
  class MemoryLifecycleAdmissionService
    SCHEMA = "soul.memory_lifecycle_admission.a13.v1"
    POLICY_VERSION = "soul.memory.lifecycle.a13.v1"
    FILE_NAME = "memory_lifecycle_decisions.jsonl"
    MAX_BYTES = 64 * 1024 * 1024
    MAX_DECISIONS = 10_000
    APPROVAL_THRESHOLDS = { "project" => 0.90, "preference" => 0.90,
                            "episodic" => 0.90, "semantic" => 0.95 }.freeze
    CANDIDATE_THRESHOLD = 0.70
    DECISIONS = %w[
      admitted_active admitted_candidate already_active existing_candidate
      blocked_for_human_review rejected_no_user_evidence rejected_low_confidence
    ].freeze
    ENTRY_KEYS = %w[
      created_at decision_id decision_sha256 outcomes policy_version
      previous_decision_sha256 request_id schema source_packet_id source_packet_sha256
    ].freeze
    OUTCOME_REQUIRED_KEYS = %w[
      after_state_sha256 before_state_sha256 decision evidence_sha256 proposal_id rollback_reference
    ].freeze
    HEX_DIGEST = /\A[0-9a-f]{64}\z/

    def initialize(root:, derivation_service:, observation_store:, memory_store:, audit_service:, path: nil, clock: -> { Time.now })
      @root = File.expand_path(root)
      @derivations = derivation_service
      @observations = observation_store
      @memories = memory_store
      @audit = audit_service
      @path = File.expand_path(path || MemoryPaths.new(root: @root).write_path(FILE_NAME), @root)
      @clock = clock
      ensure_safe_path!
    end

    def apply(request_id:)
      request = bounded_id(request_id)
      ensure_safe_path!
      audit = @audit.verify
      raise ArgumentError, "canonical memory audit baseline is unavailable" unless audit["ok"]
      derivation = @derivations.integrity
      raise ArgumentError, "memory derivation evidence is unavailable" unless derivation["ok"]
      FileUtils.mkdir_p(File.dirname(@path))
      File.open(@path, "a+b", 0o600) do |file|
        file.flock(File::LOCK_EX)
        file.rewind
        decisions = parse_and_verify(file.read.to_s)
        replay = decisions.find { |item| item["request_id"] == request }
        return receipt(replay, idempotent: true) if replay
        cursor = decisions.last && decisions.last["source_packet_sha256"]
        source = @derivations.packet_batch(after_packet_sha256: cursor, limit: 1).first
        return no_work(cursor) unless source
        evidence = @observations.find_by_ids(ids: source.fetch("observation_ids"))
        outcomes = source.fetch("proposals").map { |proposal| admit(proposal, source, evidence) }
        decision = build_decision(request, source, outcomes, decisions.last)
        encoded = JSON.generate(decision) + "\n"
        raise ArgumentError, "memory lifecycle decision ledger exceeds size limit" if file.size + encoded.bytesize > MAX_BYTES
        raise ArgumentError, "memory lifecycle decision ledger exceeds entry limit" if decisions.length + 1 > MAX_DECISIONS
        file.seek(0, IO::SEEK_END)
        file.write(encoded)
        file.flush
        file.fsync
        receipt(decision, idempotent: false)
      end
    rescue JSON::ParserError
      failure("memory lifecycle decision data contains malformed JSON")
    rescue ArgumentError, Errno::EACCES, Errno::EISDIR, Errno::ENOENT, IOError => error
      failure(error.message)
    end

    def integrity
      ensure_safe_path!
      decisions = File.file?(@path) ? parse_and_verify(File.binread(@path)) : []
      { "ok" => true, "lifecycle_state" => "complete", "schema" => SCHEMA,
        "decision_count" => decisions.length,
        "chain_head_sha256" => decisions.last && decisions.last["decision_sha256"],
        "content_included" => false }
    rescue JSON::ParserError
      failure("memory lifecycle decision data contains malformed JSON")
    rescue ArgumentError, Errno::EACCES, Errno::EISDIR => error
      failure(error.message)
    end

    # Internal supervised consumers receive verified, content-free decisions.
    def decision_batch(limit: 8)
      requested = Integer(limit)
      raise ArgumentError, "memory lifecycle decision limit is invalid" unless requested.between?(1, 8)
      ensure_safe_path!
      entries = File.file?(@path) ? parse_and_verify(File.binread(@path)) : []
      JSON.parse(JSON.generate(entries.last(requested)))
    end

    private

    def admit(proposal, source, evidence)
      proposal_id = proposal.fetch("proposal_id")
      before = state_digest
      evidence_ids = proposal.fetch("evidence_observation_ids")
      cited = evidence.select { |item| evidence_ids.include?(item["observation_id"]) }
      evidence_digest = Digest::SHA256.hexdigest(JSON.generate(cited.map { |item| item["event_sha256"] }) + "\n")
      transaction = "memory-admit:#{proposal_id}"
      protection = MemoryProtectionPolicy.classify(proposal.fetch("content"))
      outcome = if protection != "ordinary_candidate"
                  result("blocked_for_human_review", proposal_id, before, before, evidence_digest, transaction)
                elsif cited.none? { |item| item["role"] == "user" }
                  result("rejected_no_user_evidence", proposal_id, before, before, evidence_digest, transaction)
                elsif proposal.fetch("confidence").to_f < CANDIDATE_THRESHOLD
                  result("rejected_low_confidence", proposal_id, before, before, evidence_digest, transaction)
                else
                  reconcile_or_create(proposal, source, before, evidence_digest, transaction)
                end
      outcome
    end

    def reconcile_or_create(proposal, source, before, evidence_digest, transaction)
      existing = @memories.records(include_deleted: true).find do |record|
        record.dig("metadata", "derivation_proposal_id") == proposal["proposal_id"]
      end
      unless existing
        duplicate = @memories.records.find do |record|
          record["layer"] == proposal["layer"] && record["content"].to_s.strip == proposal["content"].to_s.strip
        end
        return result(duplicate["status"] == "approved" ? "already_active" : "existing_candidate",
                      proposal["proposal_id"], before, before, evidence_digest, transaction, duplicate["id"]) if duplicate
        existing = @memories.propose(
          layer: proposal["layer"], content: proposal["content"], confidence: proposal["confidence"],
          source: { "kind" => "observation_derivation", "reference" => source["packet_id"] },
          metadata: { "derivation_proposal_id" => proposal["proposal_id"],
                      "derivation_packet_id" => source["packet_id"],
                      "evidence_observation_ids" => proposal["evidence_observation_ids"],
                      "admission_policy_version" => POLICY_VERSION },
          audit_metadata: audit_metadata(transaction, evidence_digest, before, "admit ordinary derived memory")
        )
      end
      threshold = APPROVAL_THRESHOLDS.fetch(proposal.fetch("layer"))
      decision = "admitted_candidate"
      if proposal.fetch("confidence").to_f >= threshold && existing["status"] == "candidate"
        existing = @memories.approve(existing["id"], note: "deterministic lifecycle admission",
          audit_metadata: audit_metadata(transaction, evidence_digest, state_digest, "activate high-confidence ordinary memory"))
        decision = "admitted_active"
      elsif existing["status"] == "approved"
        decision = "admitted_active"
      end
      result(decision, proposal["proposal_id"], before, state_digest, evidence_digest, transaction, existing["id"])
    end

    def audit_metadata(transaction, evidence_digest, before, reason)
      { "transaction_id" => transaction, "actor" => "soul.memory.lifecycle",
        "trigger" => "verified_derivation_packet", "reason" => reason,
        "policy_version" => POLICY_VERSION, "before_state_sha256" => before,
        "evidence_digest" => evidence_digest, "rollback_reference" => transaction }
    end

    def result(decision, proposal_id, before, after, evidence, transaction, memory_id = nil)
      { "proposal_id" => proposal_id, "decision" => decision, "memory_id" => memory_id,
        "evidence_sha256" => evidence, "before_state_sha256" => before,
        "after_state_sha256" => after, "rollback_reference" => transaction }.compact
    end

    def build_decision(request, source, outcomes, prior)
      item = { "schema" => SCHEMA,
        "decision_id" => "mad_#{Digest::SHA256.hexdigest([request, source["packet_sha256"]].join(':'))[0, 24]}",
        "request_id" => request, "created_at" => @clock.call.iso8601(6),
        "policy_version" => POLICY_VERSION, "source_packet_id" => source["packet_id"],
        "source_packet_sha256" => source["packet_sha256"], "outcomes" => outcomes,
        "previous_decision_sha256" => prior && prior["decision_sha256"] }
      item["decision_sha256"] = digest(item)
      item
    end

    def parse_and_verify(raw)
      raise ArgumentError, "memory lifecycle decision ledger exceeds size limit" if raw.bytesize > MAX_BYTES
      raise ArgumentError, "memory lifecycle decision ledger has a partial final write" unless raw.empty? || raw.end_with?("\n")
      entries = raw.lines.filter_map { |line| JSON.parse(line) unless line.strip.empty? }
      raise ArgumentError, "memory lifecycle decision ledger exceeds entry limit" if entries.length > MAX_DECISIONS
      previous = nil
      entries.each do |item|
        raise ArgumentError, "memory lifecycle decision is invalid" unless item.is_a?(Hash) && item.keys.sort == ENTRY_KEYS && item["schema"] == SCHEMA && item["policy_version"] == POLICY_VERSION
        bounded_id(item["decision_id"])
        bounded_id(item["request_id"])
        bounded_id(item["source_packet_id"])
        raise ArgumentError, "memory lifecycle source digest is invalid" unless HEX_DIGEST.match?(item["source_packet_sha256"].to_s)
        outcomes = item["outcomes"]
        raise ArgumentError, "memory lifecycle outcomes are invalid" unless outcomes.is_a?(Array) && outcomes.length <= 8
        outcomes.each do |outcome|
          keys = outcome.keys.sort
          valid_keys = [OUTCOME_REQUIRED_KEYS, (OUTCOME_REQUIRED_KEYS + ["memory_id"]).sort]
          raise ArgumentError, "memory lifecycle outcome is invalid" unless outcome.is_a?(Hash) && valid_keys.include?(keys)
          bounded_id(outcome["proposal_id"])
          bounded_id(outcome["memory_id"]) if outcome["memory_id"]
          raise ArgumentError, "memory lifecycle outcome is invalid" unless DECISIONS.include?(outcome["decision"])
          raise ArgumentError, "memory lifecycle outcome digest is invalid" unless %w[evidence_sha256 before_state_sha256 after_state_sha256].all? { |key| HEX_DIGEST.match?(outcome[key].to_s) }
          raise ArgumentError, "memory lifecycle rollback reference is invalid" unless outcome["rollback_reference"].to_s == "memory-admit:#{outcome["proposal_id"]}"
        end
        raise ArgumentError, "memory lifecycle decision chain is broken" unless item["previous_decision_sha256"] == previous
        raise ArgumentError, "memory lifecycle decision digest is invalid" unless item["decision_sha256"] == digest(item)
        Time.iso8601(item.fetch("created_at"))
        previous = item["decision_sha256"]
      end
      raise ArgumentError, "memory lifecycle decision identity is duplicated" unless entries.map { |item| item["request_id"] }.uniq.length == entries.length
      raise ArgumentError, "memory lifecycle source packet is duplicated" unless entries.map { |item| item["source_packet_sha256"] }.uniq.length == entries.length
      entries
    end

    def state_digest
      rows = @memories.records(include_deleted: true).sort_by { |record| record["id"] }
      Digest::SHA256.hexdigest(JSON.generate(rows) + "\n")
    end

    def digest(item)
      Digest::SHA256.hexdigest(JSON.generate(item.reject { |key, _| key == "decision_sha256" }) + "\n")
    end

    def receipt(item, idempotent:)
      outcomes = item.fetch("outcomes")
      counts = outcomes.group_by { |outcome| outcome["decision"] }.transform_values(&:length)
      { "ok" => true, "lifecycle_state" => "complete", "idempotent" => idempotent,
        "decision_id" => item["decision_id"], "source_packet_id" => item["source_packet_id"],
        "proposal_count" => outcomes.length, "decision_counts" => counts,
        "rollback_references" => outcomes.filter_map do |outcome|
          outcome["rollback_reference"] if %w[admitted_active admitted_candidate].include?(outcome["decision"])
        end.uniq,
        "decision_sha256" => item["decision_sha256"], "content_included" => false }
    end

    def no_work(cursor)
      { "ok" => true, "lifecycle_state" => "complete", "no_work" => true,
        "cursor_sha256" => cursor, "content_included" => false }.compact
    end

    def bounded_id(value)
      text = value.to_s
      raise ArgumentError, "request ID is invalid" unless text.bytesize.between?(1, 160) && text.match?(/\A[A-Za-z0-9_.:\/-]+\z/)
      text
    end

    def failure(reason)
      { "ok" => false, "lifecycle_state" => "failed",
        "reason" => reason.to_s.gsub(@root, "[PROJECT_ROOT]")[0, 300], "content_included" => false }
    end

    def ensure_safe_path!
      prefix = "#{@root}#{File::SEPARATOR}"
      raise ArgumentError, "memory lifecycle decision path escapes project" unless @path.start_with?(prefix)
      current = @path
      while current.start_with?(prefix)
        raise ArgumentError, "memory lifecycle decision path component must not be a symlink" if File.symlink?(current)
        current = File.dirname(current)
      end
    end
  end
end
