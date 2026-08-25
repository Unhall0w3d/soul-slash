# frozen_string_literal: true

require "digest"
require "json"
require "pathname"
require "timeout"
require "time"

module SoulCore
  # Qualifies the active retrieval policy against the reviewed private corpus
  # without returning query text or memory content.
  class MemoryProductionQualificationService
    SCHEMA = "soul.memory_production_qualification.a29.v1"
    CASE_SCHEMA = "soul.memory_projection_qualification_cases.a24.v1"
    MAX_FILE_BYTES = 64 * 1024
    MAX_CASES = 48
    MAX_IDS = 8
    MAX_QUERY_CHARACTERS = 200
    MAX_OPERATION_SECONDS = 300
    CASE_KEYS = %w[expected_memory_ids forbidden_memory_ids id query result_limit].freeze

    def initialize(case_path:, allowed_root:, approved_memory_ids:, retrieval:, policy_store:,
                   clock: -> { Time.now.utc }, operation_timeout: 180)
      @case_path = File.expand_path(case_path)
      @allowed_root = File.realpath(allowed_root)
      @approved_ids = Array(approved_memory_ids).map { |id| bounded_id(id) }.to_h { |id| [id, true] }
      raise ArgumentError, "approved memory identifiers exceed bound" if @approved_ids.length > 10_000
      @retrieval = retrieval
      @policy_store = policy_store
      @clock = clock
      @operation_timeout = Float(operation_timeout)
      raise ArgumentError, "qualification timeout is invalid" unless @operation_timeout.between?(1, MAX_OPERATION_SECONDS)
    end

    def qualify
      Timeout.timeout(@operation_timeout) do
        policy = @policy_store.active
        raise "production retrieval policy is not qualified" unless policy["profile"] == MemoryFusionRetrievalService::PROFILE && policy["projection_threshold"] == 0.55
        document = load_cases
        cases = document.fetch("cases").map { |item| evaluate(item) }
        positives = cases.select { |item| item.fetch("positive_case") }
        negatives = cases.reject { |item| item.fetch("positive_case") }
        complete(
          "policy_profile" => policy.fetch("profile"),
          "projection_threshold" => policy.fetch("projection_threshold"),
          "case_file_digest" => document.fetch("digest"),
          "case_count" => cases.length,
          "positive_case_count" => positives.length,
          "negative_case_count" => negatives.length,
          "positive_hit_count" => positives.count { |item| item.fetch("hit") },
          "negative_abstention_count" => negatives.count { |item| item.fetch("abstained") },
          "forbidden_hit_count" => cases.count { |item| item.fetch("forbidden_hit") },
          "mean_positive_reciprocal_rank" => mean(positives.map { |item| item.fetch("reciprocal_rank") }),
          "all_routes_used_active_policy" => cases.all? { |item| item.fetch("ranking_profile") == policy.fetch("profile") },
          "projection_available_for_all_cases" => cases.all? { |item| item.fetch("projection_available") },
          "case_receipts" => cases.map { |item| item.reject { |key| key == "query" } },
          "content_included" => false,
          "authority" => "production_qualification_only",
          "mutation" => "none",
          "qualified_at" => @clock.call.utc.iso8601(6)
        )
      end
    rescue StandardError => error
      failed("memory production qualification failed safely: #{error.class}")
    end

    private

    def evaluate(item)
      envelope = @retrieval.query(query: item.fetch("query"), limit: item.fetch("result_limit"))
      raise "production retrieval envelope is invalid" unless envelope.is_a?(Hash) && envelope["lifecycle_state"] == "complete" && envelope["schema"] == MemoryFusionRetrievalService::SCHEMA && envelope["mutation"] == "none"
      data = envelope.fetch("data")
      valid = data["retrieval_mode"] == "projection_gate_local_order" && data["ranking_profile"] == MemoryFusionRetrievalService::PROFILE &&
        data["projection_available"] == true && data["content_source"] == "canonical_local_ledger" && data["authority"] == "approved_memory_context" && data["mutation"] == "none"
      raise "production retrieval did not use the active projection policy" unless valid
      ids = Array(data.fetch("results")).map do |result|
        id = bounded_id(result.fetch("memory_id"))
        raise "production retrieval returned a non-approved memory" unless @approved_ids.key?(id)
        id
      end
      raise "production retrieval returned duplicate identifiers" unless ids.uniq.length == ids.length
      expected = item.fetch("expected_memory_ids")
      position = ids.index { |id| expected.include?(id) }
      {
        "case_id" => item.fetch("id"),
        "query_sha256" => Digest::SHA256.hexdigest(item.fetch("query")),
        "positive_case" => expected.any?,
        "hit" => !position.nil?,
        "abstained" => ids.empty?,
        "forbidden_hit" => !(ids & item.fetch("forbidden_memory_ids")).empty?,
        "reciprocal_rank" => position ? (1.0 / (position + 1)).round(6) : 0.0,
        "returned_count" => ids.length,
        "ranking_profile" => data.fetch("ranking_profile"),
        "projection_available" => data.fetch("projection_available")
      }
    end

    def load_cases
      validate_path!
      bytes = File.open(@case_path, File::RDONLY | File::NOFOLLOW) do |file|
        before = file.stat
        raise "qualification corpus must be an owner-private regular file" unless before.file? && before.uid == Process.uid && (before.mode & 0o077).zero?
        raise "qualification corpus exceeds bound" if before.size > MAX_FILE_BYTES
        value = file.read(MAX_FILE_BYTES + 1)
        after = file.stat
        raise "qualification corpus changed during read" unless before.dev == after.dev && before.ino == after.ino && before.size == after.size && before.mtime == after.mtime
        value
      end
      document = JSON.parse(bytes)
      raise "qualification corpus is invalid" unless document.is_a?(Hash) && document.keys.sort == %w[cases schema_version] && document["schema_version"] == CASE_SCHEMA
      cases = document.fetch("cases")
      raise "qualification corpus case count is invalid" unless cases.is_a?(Array) && cases.length.between?(2, MAX_CASES)
      validated = cases.map { |item| validate_case(item) }
      raise "qualification case identifiers repeat" unless validated.map { |item| item.fetch("id") }.uniq.length == validated.length
      raise "qualification corpus requires positive and negative cases" unless validated.any? { |item| item.fetch("expected_memory_ids").any? } && validated.any? { |item| item.fetch("expected_memory_ids").empty? }
      {"cases" => validated, "digest" => Digest::SHA256.hexdigest(bytes)}
    rescue JSON::ParserError
      raise "qualification corpus JSON is malformed"
    end

    def validate_case(item)
      raise "qualification case is invalid" unless item.is_a?(Hash) && item.keys.sort == CASE_KEYS
      query = item.fetch("query").to_s
      raise "qualification query is invalid" if query.empty? || query.length > MAX_QUERY_CHARACTERS || query.match?(/[\r\n]/)
      expected = bounded_ids(item.fetch("expected_memory_ids"))
      forbidden = bounded_ids(item.fetch("forbidden_memory_ids"))
      raise "qualification identifiers overlap" unless (expected & forbidden).empty?
      raise "qualification references non-approved memory" unless (expected + forbidden).all? { |id| @approved_ids.key?(id) }
      limit = Integer(item.fetch("result_limit"))
      raise "qualification result limit is invalid" unless limit.between?(1, 8)
      {"id" => bounded_id(item.fetch("id")), "query" => query, "expected_memory_ids" => expected, "forbidden_memory_ids" => forbidden, "result_limit" => limit}
    rescue KeyError, ArgumentError, TypeError
      raise "qualification case is malformed"
    end

    def bounded_ids(value)
      raise "qualification identifiers are invalid" unless value.is_a?(Array) && value.length <= MAX_IDS
      value.map { |id| bounded_id(id) }.tap { |ids| raise "qualification identifiers repeat" unless ids.uniq.length == ids.length }
    end

    def bounded_id(value)
      text = value.to_s
      raise ArgumentError, "identifier is invalid" unless text.match?(/\A[A-Za-z0-9][A-Za-z0-9_.:-]{0,199}\z/)
      text
    end

    def validate_path!
      raise "qualification corpus escapes private root" unless @case_path.start_with?("#{@allowed_root}#{File::SEPARATOR}")
      current = Pathname.new(@allowed_root)
      Pathname.new(@case_path).relative_path_from(current).each_filename do |component|
        current = current.join(component)
        raise "qualification corpus path contains a symlink" if File.symlink?(current.to_s)
      end
    rescue ArgumentError
      raise "qualification corpus escapes private root"
    end

    def mean(values) = values.empty? ? 0.0 : (values.sum.to_f / values.length).round(6)
    def complete(data) = {"lifecycle_state" => "complete", "schema" => SCHEMA, "data" => data, "mutation" => "none"}
    def failed(message) = {"lifecycle_state" => "failed", "schema" => SCHEMA, "message" => message, "mutation" => "none"}
  end
end
