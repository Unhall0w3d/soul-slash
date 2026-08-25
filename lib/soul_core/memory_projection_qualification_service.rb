# frozen_string_literal: true

require "digest"
require "json"
require "pathname"
require "timeout"

module SoulCore
  # Compares local and remote-derived retrieval over one owner-private corpus.
  # It emits identifiers, digests, and aggregate evidence only; it cannot select
  # or activate a production ranking profile.
  class MemoryProjectionQualificationService
    SCHEMA = "soul.memory_projection_qualification.a24.v1"
    CASE_SCHEMA = "soul.memory_projection_qualification_cases.a24.v1"
    MAX_FILE_BYTES = 64 * 1024
    MAX_CASES = 48
    MAX_QUERY_CHARACTERS = 200
    MAX_IDS = 8
    MAX_LIMIT = 8
    MAX_OPERATION_SECONDS = 300
    THRESHOLDS = [0.50, 0.55, 0.60, 0.65, 0.70, 0.75, 0.80].freeze
    DOCUMENT_KEYS = %w[cases schema_version].freeze
    CASE_KEYS = %w[expected_memory_ids forbidden_memory_ids id query result_limit].freeze

    def initialize(case_path:, allowed_root:, approved_memory_ids:, local_retrieval:, projection_retrieval:,
                   clock: -> { Time.now.utc }, operation_timeout: 120)
      @case_path = File.expand_path(case_path)
      @allowed_root = File.realpath(allowed_root)
      @local_retrieval = local_retrieval
      @projection_retrieval = projection_retrieval
      ids = Array(approved_memory_ids).map { |id| bounded_id(id, "approved memory ID") }
      raise ArgumentError, "approved memory identifiers exceed bound" if ids.length > 10_000
      raise ArgumentError, "approved memory identifiers must be unique" unless ids.uniq.length == ids.length
      @approved_memory_ids = ids.to_h { |id| [id, true] }
      @clock = clock
      @operation_timeout = Float(operation_timeout)
      raise ArgumentError, "qualification timeout is invalid" unless @operation_timeout.between?(1.0, MAX_OPERATION_SECONDS)
    end

    def qualify
      Timeout.timeout(@operation_timeout) do
        document = load_cases
        cases = document.fetch("cases").map { |item| evaluate(item) }
        complete(
          "case_file_digest" => document.fetch("digest"),
          "case_count" => cases.length,
          "positive_case_count" => cases.count { |item| item.fetch("expected_memory_ids").any? },
          "negative_case_count" => cases.count { |item| item.fetch("expected_memory_ids").empty? },
          "thresholds" => THRESHOLDS,
          "local" => aggregate(cases.map { |item| item.fetch("local") }),
          "projection_thresholds" => THRESHOLDS.to_h do |threshold|
            [format("%.2f", threshold), aggregate(cases.map { |item| item.fetch("projection").fetch(format("%.2f", threshold)) })]
          end,
          "cases" => cases,
          "decision" => "human_review_required",
          "production_profile_changed" => false,
          "chat_voice_routing_changed" => false,
          "content_included" => false,
          "authority" => "evaluation_only",
          "mutation" => "none",
          "qualified_at" => @clock.call.utc.iso8601(6)
        )
      end
    rescue StandardError => error
      failed("memory projection qualification failed safely: #{error.class}")
    end

    private

    def evaluate(item)
      local = result_data(@local_retrieval.query(query: item.fetch("query"), limit: item.fetch("result_limit")), projection: false)
      remote = result_data(@projection_retrieval.query(query: item.fetch("query"), limit: item.fetch("result_limit")), projection: true)
      {
        "case_id" => item.fetch("id"),
        "query_sha256" => Digest::SHA256.hexdigest(item.fetch("query")),
        "expected_memory_ids" => item.fetch("expected_memory_ids"),
        "forbidden_memory_ids" => item.fetch("forbidden_memory_ids"),
        "local" => score(item, local.fetch("results")),
        "projection" => THRESHOLDS.to_h do |threshold|
          selected = remote.fetch("results").select { |result| result.fetch("score") >= threshold }
          [format("%.2f", threshold), score(item, selected)]
        end
      }
    end

    def result_data(envelope, projection:)
      raise "retrieval result is invalid" unless envelope.is_a?(Hash) && envelope["lifecycle_state"] == "complete"
      data = envelope.fetch("data")
      raise "retrieval result can mutate" unless data["mutation"] == "none"
      if projection
        valid_projection = envelope["schema"] == "soul.memory_projection_query.a23.v1" &&
          envelope["mutation"] == "none" && data["projection_available"] == true &&
          data["retrieval_mode"] == "remote_projection_local_join" &&
          data["content_source"] == "canonical_local_ledger" &&
          data["authority"] == "approved_memory_context" &&
          data["projection_generation"].to_s.match?(/\Ageneration_[0-9a-f]{20}\z/)
        raise "projection retrieval fell back locally" unless valid_projection
      end
      results = data.fetch("results")
      raise "retrieval results are invalid" unless results.is_a?(Array)
      raise "retrieval result count exceeds bound" if results.length > MAX_LIMIT
      normalized = results.map do |result|
        id = bounded_id(result.fetch("memory_id"), "result memory ID")
        raise "retrieval returned a non-approved memory identifier" unless @approved_memory_ids.key?(id)
        score = Float(result.fetch("score"))
        raise "retrieval score is invalid" unless score.finite? && score.between?(-1.0, 1.0)
        {"memory_id" => id, "score" => score}
      end
      raise "retrieval returned duplicate identifiers" unless normalized.map { |item| item.fetch("memory_id") }.uniq.length == normalized.length
      {"results" => normalized}
    rescue KeyError, ArgumentError, TypeError
      raise "retrieval result is malformed"
    end

    def score(item, results)
      actual = results.map { |result| result.fetch("memory_id") }
      expected = item.fetch("expected_memory_ids")
      forbidden = item.fetch("forbidden_memory_ids")
      position = actual.index { |id| expected.include?(id) }
      {
        "positive_case" => expected.any?,
        "returned_memory_ids" => actual,
        "hit" => !position.nil?,
        "recall" => expected.empty? ? 1.0 : ((actual & expected).length.to_f / expected.length).round(6),
        "precision" => actual.empty? ? (expected.empty? ? 1.0 : 0.0) : ((actual & expected).length.to_f / actual.length).round(6),
        "reciprocal_rank" => position ? (1.0 / (position + 1)).round(6) : 0.0,
        "forbidden_hit" => !(actual & forbidden).empty?,
        "abstained" => actual.empty?,
        "decision_correct" => expected.empty? ? actual.empty? : !position.nil?,
        "abstention_correct" => expected.empty? ? actual.empty? : nil
      }
    end

    def aggregate(items)
      positives = items.select { |item| item.fetch("positive_case") }
      {
        "mean_recall" => mean(items.map { |item| item.fetch("recall") }),
        "mean_precision" => mean(items.map { |item| item.fetch("precision") }),
        "mean_reciprocal_rank" => mean(items.map { |item| item.fetch("reciprocal_rank") }),
        "mean_positive_recall" => mean(positives.map { |item| item.fetch("recall") }),
        "mean_positive_precision" => mean(positives.map { |item| item.fetch("precision") }),
        "mean_positive_reciprocal_rank" => mean(positives.map { |item| item.fetch("reciprocal_rank") }),
        "hit_count" => items.count { |item| item.fetch("hit") },
        "correct_decision_count" => items.count { |item| item.fetch("decision_correct") },
        "negative_abstention_count" => items.count { |item| !item.fetch("positive_case") && item.fetch("abstained") },
        "forbidden_hit_count" => items.count { |item| item.fetch("forbidden_hit") },
        "returned_result_count" => items.sum { |item| item.fetch("returned_memory_ids").length },
        "case_count" => items.length,
        "scored_positive_count" => positives.length
      }
    end

    def load_cases
      validate_path!
      bytes = nil
      File.open(@case_path, File::RDONLY | File::NOFOLLOW) do |file|
        before = file.stat
        raise "qualification corpus must be a private regular file" unless before.file? && before.uid == Process.uid && (before.mode & 0o077).zero?
        raise "qualification corpus exceeds bound" if before.size > MAX_FILE_BYTES
        bytes = file.read(MAX_FILE_BYTES + 1)
        after = file.stat
        raise "qualification corpus changed during read" unless before.dev == after.dev && before.ino == after.ino && before.size == after.size
        raise "qualification corpus exceeds bound" if bytes.bytesize > MAX_FILE_BYTES
      end
      document = JSON.parse(bytes)
      raise "qualification corpus must be an object" unless document.is_a?(Hash)
      raise "qualification corpus contains unsupported fields" unless document.keys.sort == DOCUMENT_KEYS
      raise "qualification corpus schema mismatch" unless document["schema_version"] == CASE_SCHEMA
      cases = document["cases"]
      raise "qualification corpus case count is invalid" unless cases.is_a?(Array) && cases.length.between?(2, MAX_CASES)
      validated = cases.map { |item| validate_case(item) }
      ids = validated.map { |item| item.fetch("id") }
      raise "qualification case IDs must be unique" unless ids.uniq.length == ids.length
      raise "qualification corpus requires positive and negative cases" unless validated.any? { |item| item.fetch("expected_memory_ids").any? } && validated.any? { |item| item.fetch("expected_memory_ids").empty? }
      {"cases" => validated, "digest" => Digest::SHA256.hexdigest(bytes)}
    rescue JSON::ParserError
      raise "qualification corpus JSON is malformed"
    end

    def validate_case(item)
      raise "qualification case must be an object" unless item.is_a?(Hash) && item.keys.sort == CASE_KEYS
      id = bounded_id(item.fetch("id"), "case ID")
      query = item.fetch("query").to_s
      raise "qualification query is invalid" if query.empty? || query.length > MAX_QUERY_CHARACTERS || query.match?(/[\r\n]/)
      expected = validate_ids(item.fetch("expected_memory_ids"), allow_empty: true)
      forbidden = validate_ids(item.fetch("forbidden_memory_ids"), allow_empty: true)
      raise "qualification corpus references a non-approved memory" unless (expected + forbidden).all? { |id| @approved_memory_ids.key?(id) }
      raise "expected and forbidden identifiers overlap" unless (expected & forbidden).empty?
      limit = Integer(item.fetch("result_limit"))
      raise "qualification result limit is invalid" unless limit.between?(1, MAX_LIMIT)
      {"id" => id, "query" => query, "expected_memory_ids" => expected, "forbidden_memory_ids" => forbidden, "result_limit" => limit}
    rescue KeyError, ArgumentError, TypeError
      raise "qualification case is malformed"
    end

    def validate_ids(value, allow_empty:)
      raise "qualification identifiers must be an array" unless value.is_a?(Array)
      raise "qualification identifier count exceeds bound" if value.length > MAX_IDS || (!allow_empty && value.empty?)
      value.map { |id| bounded_id(id, "memory ID") }.tap do |ids|
        raise "qualification identifiers must be unique" unless ids.uniq.length == ids.length
      end
    end

    def bounded_id(value, label)
      text = value.to_s
      raise "#{label} is invalid" unless text.match?(/\A[A-Za-z0-9][A-Za-z0-9_.:-]{0,199}\z/)
      text
    end

    def validate_path!
      prefix = "#{@allowed_root}#{File::SEPARATOR}"
      raise "qualification corpus escapes private root" unless @case_path.start_with?(prefix)
      relative = Pathname.new(@case_path).relative_path_from(Pathname.new(@allowed_root))
      current = Pathname.new(@allowed_root)
      relative.each_filename do |component|
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
