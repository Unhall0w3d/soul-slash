# frozen_string_literal: true

require "digest"
require "json"
require "pathname"

module SoulCore
  # Qualifies closed ranking profiles from the content-free A24 envelope.
  # This service only emits candidate evidence; it cannot select or activate a
  # profile and never receives the underlying query or memory content.
  class MemoryProjectionHybridFusionQualificationService
    SCHEMA = "soul.memory_projection_hybrid_qualification.a25.v1"
    A24_SCHEMA = "soul.memory_projection_qualification.a24.v1"
    THRESHOLD = 0.65
    THRESHOLD_KEY = "0.65"
    # A24 expands each bounded corpus case across seven threshold result sets;
    # its content-free evidence envelope is larger than the 64 KiB input corpus.
    MAX_FILE_BYTES = 512 * 1024
    MAX_CASES = 48
    MAX_IDS = 8
    MAX_ID_CHARACTERS = 200
    MAX_OPERATION_CASES = 48
    RRF_K = 60.0
    LOCAL_WEIGHT = 0.70
    PROJECTION_WEIGHT = 0.30

    TOP_KEYS = %w[lifecycle_state schema data mutation].freeze
    DATA_KEYS = %w[case_file_digest case_count positive_case_count negative_case_count
                   thresholds local projection_thresholds cases decision
                   production_profile_changed chat_voice_routing_changed
                   content_included authority mutation qualified_at].freeze
    CASE_KEYS = %w[case_id query_sha256 expected_memory_ids forbidden_memory_ids local projection].freeze
    SCORE_KEYS = %w[positive_case returned_memory_ids hit recall precision reciprocal_rank
                    forbidden_hit abstained decision_correct abstention_correct].freeze
    AGGREGATE_KEYS = %w[mean_recall mean_precision mean_reciprocal_rank mean_positive_recall
                        mean_positive_precision mean_positive_reciprocal_rank hit_count
                        correct_decision_count negative_abstention_count forbidden_hit_count
                        returned_result_count case_count scored_positive_count].freeze
    PROFILE_KEYS = %w[profile_id cases aggregate].freeze

    def initialize(envelope: nil, envelope_path: nil, allowed_root: nil, clock: -> { Time.now.utc })
      raise ArgumentError, "provide an A24 envelope or envelope path" if envelope.nil? && envelope_path.nil?
      raise ArgumentError, "provide only one A24 envelope source" unless envelope.nil? || envelope_path.nil?

      @envelope = envelope
      @envelope_path = envelope_path && File.expand_path(envelope_path)
      @allowed_root = allowed_root && File.realpath(allowed_root)
      raise ArgumentError, "allowed root is required for an envelope path" if @envelope_path && @allowed_root.nil?
      @clock = clock
    end

    def qualify
      source = load_envelope
      data = validate_envelope(source)
      cases = data.fetch("cases")
      profiles = PROFILE_DEFINITIONS.to_h do |profile_id, label|
        scored = cases.map { |item| evaluate_case(item, profile_id) }
        [profile_id, {
          "profile_id" => profile_id,
          "label" => label,
          "cases" => scored,
          "aggregate" => aggregate(scored)
        }]
      end
      complete(
        "source_case_file_digest" => data.fetch("case_file_digest"),
        "source_case_count" => cases.length,
        "projection_threshold" => THRESHOLD,
        "profiles" => profiles,
        "profile_order" => PROFILE_DEFINITIONS.keys,
        "constants" => {
          "rrf_k" => RRF_K,
          "local_weight" => LOCAL_WEIGHT,
          "projection_weight" => PROJECTION_WEIGHT
        },
        "decision" => "human_review_required",
        "winner_selected" => false,
        "production_profile_changed" => false,
        "chat_voice_routing_changed" => false,
        "content_included" => false,
        "authority" => "evaluation_only",
        "mutation" => "none",
        "qualified_at" => @clock.call.utc.iso8601(6)
      )
    rescue StandardError => error
      failed("memory projection hybrid qualification failed safely: #{error.class}")
    end

    private

    PROFILE_DEFINITIONS = {
      "projection_baseline_a25" => "A24 projection candidates at the fixed 0.65 gate, preserving projection order",
      "projection_gate_local_order_a25" => "0.65 projection candidates ordered by local retrieval rank",
      "projection_gate_weighted_rrf_a25" => "0.65 projection candidates ordered by local-dominant weighted reciprocal rank"
    }.freeze

    def evaluate_case(item, profile_id)
      projection = item.fetch("projection").fetch(THRESHOLD_KEY).fetch("returned_memory_ids")
      local = item.fetch("local").fetch("returned_memory_ids")
      returned, fusion_scores = case profile_id
                               when "projection_baseline_a25"
                                 [projection, {}]
                               when "projection_gate_local_order_a25"
                                 [local_order(local, projection), {}]
                               when "projection_gate_weighted_rrf_a25"
                                 weighted_rrf(local, projection)
                               else
                                 raise "unsupported A25 profile"
                               end
      score = score_case(item, returned)
      score.merge(
        "case_id" => item.fetch("case_id"),
        "query_sha256" => item.fetch("query_sha256"),
        "fusion_scores" => fusion_scores
      )
    end

    def local_order(local, projection)
      projection_set = projection.to_h { |id| [id, true] }
      local.select { |id| projection_set.key?(id) } + projection.reject { |id| local.include?(id) }
    end

    def weighted_rrf(local, projection)
      local_rank = local.each_with_index.to_h { |id, index| [id, index + 1] }
      projection_rank = projection.each_with_index.to_h { |id, index| [id, index + 1] }
      scores = projection.to_h do |id|
        value = PROJECTION_WEIGHT / (RRF_K + projection_rank.fetch(id))
        value += LOCAL_WEIGHT / (RRF_K + local_rank.fetch(id)) if local_rank.key?(id)
        [id, value.round(12)]
      end
      ordered = projection.sort_by { |id| [-scores.fetch(id), projection_rank.fetch(id), id] }
      [ordered, scores]
    end

    def score_case(item, returned)
      expected = item.fetch("expected_memory_ids")
      forbidden = item.fetch("forbidden_memory_ids")
      position = returned.index { |id| expected.include?(id) }
      {
        "positive_case" => expected.any?,
        "returned_memory_ids" => returned,
        "hit" => !position.nil?,
        "recall" => expected.empty? ? 1.0 : ((returned & expected).length.to_f / expected.length).round(6),
        "precision" => returned.empty? ? (expected.empty? ? 1.0 : 0.0) : ((returned & expected).length.to_f / returned.length).round(6),
        "reciprocal_rank" => position ? (1.0 / (position + 1)).round(6) : 0.0,
        "forbidden_hit" => !(returned & forbidden).empty?,
        "abstained" => returned.empty?,
        "decision_correct" => expected.empty? ? returned.empty? : !position.nil?,
        "abstention_correct" => expected.empty? ? returned.empty? : nil
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

    def load_envelope
      return @envelope unless @envelope_path

      validate_path!
      bytes = nil
      File.open(@envelope_path, File::RDONLY | File::NOFOLLOW) do |file|
        before = file.stat
        raise "A24 envelope must be an owner-private regular file" unless before.file? && before.uid == Process.uid && (before.mode & 0o077).zero?
        raise "A24 envelope exceeds bound" if before.size > MAX_FILE_BYTES
        bytes = file.read(MAX_FILE_BYTES + 1)
        after = file.stat
        raise "A24 envelope changed during read" unless before.dev == after.dev && before.ino == after.ino && before.size == after.size
        raise "A24 envelope exceeds bound" if bytes.bytesize > MAX_FILE_BYTES
      end
      JSON.parse(bytes)
    rescue JSON::ParserError
      raise "A24 envelope JSON is malformed"
    end

    def validate_envelope(envelope)
      raise "A24 envelope must be an object" unless envelope.is_a?(Hash) && envelope.keys.sort == TOP_KEYS.sort
      raise "A24 envelope is incomplete" unless envelope["lifecycle_state"] == "complete" && envelope["schema"] == A24_SCHEMA && envelope["mutation"] == "none"
      data = envelope["data"]
      raise "A24 envelope data is malformed" unless data.is_a?(Hash) && data.keys.sort == DATA_KEYS.sort
      raise "A24 envelope data can mutate or select" unless data["mutation"] == "none" && data["decision"] == "human_review_required" && data["production_profile_changed"] == false && data["chat_voice_routing_changed"] == false && data["content_included"] == false && data["authority"] == "evaluation_only"
      validate_data_bounds(data)
      data
    end

    def validate_data_bounds(data)
      digest = data.fetch("case_file_digest").to_s
      raise "A24 case digest is invalid" unless digest.match?(/\A[a-f0-9]{64}\z/)
      cases = data.fetch("cases")
      raise "A24 cases are invalid" unless cases.is_a?(Array) && cases.length.between?(2, MAX_CASES)
      raise "A24 case count is inconsistent" unless data.fetch("case_count") == cases.length
      raise "A24 cases exceed operation bound" if cases.length > MAX_OPERATION_CASES
      ids = cases.map { |item| validate_case(item).fetch("case_id") }
      raise "A24 case IDs must be unique" unless ids.uniq.length == ids.length
      raise "A24 corpus requires positive and negative cases" unless cases.any? { |item| item.fetch("expected_memory_ids").any? } && cases.any? { |item| item.fetch("expected_memory_ids").empty? }
      thresholds = data.fetch("thresholds")
      raise "A24 thresholds are invalid" unless thresholds == [0.50, 0.55, 0.60, 0.65, 0.70, 0.75, 0.80]
      validate_aggregate(data.fetch("local"), cases.length)
      projection_thresholds = data.fetch("projection_thresholds")
      raise "A24 projection thresholds are invalid" unless projection_thresholds.is_a?(Hash) && projection_thresholds.keys.sort == %w[0.50 0.55 0.60 0.65 0.70 0.75 0.80]
      projection_thresholds.each_value { |aggregate| validate_aggregate(aggregate, cases.length) }
      raise "A24 positive/negative counts are inconsistent" unless data.fetch("positive_case_count") == cases.count { |item| item.fetch("expected_memory_ids").any? } && data.fetch("negative_case_count") == cases.count { |item| item.fetch("expected_memory_ids").empty? }
    rescue KeyError, ArgumentError, TypeError
      raise "A24 envelope data is malformed"
    end

    def validate_case(item)
      raise "A24 case is malformed" unless item.is_a?(Hash) && item.keys.sort == CASE_KEYS.sort
      id = bounded_id(item.fetch("case_id"), "case ID")
      query_sha256 = item.fetch("query_sha256").to_s
      raise "A24 query digest is invalid" unless query_sha256.match?(/\A[a-f0-9]{64}\z/)
      expected = validate_ids(item.fetch("expected_memory_ids"))
      forbidden = validate_ids(item.fetch("forbidden_memory_ids"))
      raise "expected and forbidden identifiers overlap" unless (expected & forbidden).empty?
      validate_score(item.fetch("local"), expected, forbidden)
      projection = item.fetch("projection")
      raise "A24 projection score map is malformed" unless projection.is_a?(Hash) && projection.keys.sort == %w[0.50 0.55 0.60 0.65 0.70 0.75 0.80]
      projection.each_value { |score| validate_score(score, expected, forbidden) }
      {"case_id" => id, "query_sha256" => query_sha256, "expected_memory_ids" => expected, "forbidden_memory_ids" => forbidden}
    rescue KeyError, ArgumentError, TypeError
      raise "A24 case is malformed"
    end

    def validate_score(score, expected, forbidden)
      raise "A24 score is malformed" unless score.is_a?(Hash) && score.keys.sort == SCORE_KEYS.sort
      returned = validate_ids(score.fetch("returned_memory_ids"))
      raise "A24 score identifiers are inconsistent" unless score.fetch("positive_case") == expected.any? && score.fetch("forbidden_hit") == !(returned & forbidden).empty? && score.fetch("abstained") == returned.empty?
      raise "A24 score contains invalid numeric evidence" unless %w[recall precision reciprocal_rank].all? { |key| Float(score.fetch(key)).finite? }
      returned
    end

    def validate_aggregate(aggregate, case_count)
      raise "A24 aggregate is malformed" unless aggregate.is_a?(Hash) && aggregate.keys.sort == AGGREGATE_KEYS.sort
      raise "A24 aggregate case count is inconsistent" unless aggregate.fetch("case_count") == case_count
      raise "A24 aggregate numeric evidence is invalid" unless AGGREGATE_KEYS.all? do |key|
        value = aggregate.fetch(key)
        key.start_with?("mean_") ? Float(value).finite? : value.is_a?(Integer) && value >= 0
      end
    end

    def validate_ids(value)
      raise "A24 identifiers are malformed" unless value.is_a?(Array) && value.length <= MAX_IDS
      ids = value.map { |id| bounded_id(id, "memory ID") }
      raise "A24 identifiers must be unique" unless ids.uniq.length == ids.length
      ids
    end

    def bounded_id(value, label)
      text = value.to_s
      raise "#{label} is invalid" unless text.match?(/\A[A-Za-z0-9][A-Za-z0-9_.:-]{0,#{MAX_ID_CHARACTERS - 1}}\z/)
      text
    end

    def validate_path!
      prefix = "#{@allowed_root}#{File::SEPARATOR}"
      raise "A25 envelope escapes private root" unless @envelope_path.start_with?(prefix)
      relative = Pathname.new(@envelope_path).relative_path_from(Pathname.new(@allowed_root))
      current = Pathname.new(@allowed_root)
      relative.each_filename do |component|
        current = current.join(component)
        raise "A25 envelope path contains a symlink" if File.symlink?(current.to_s)
      end
    rescue ArgumentError
      raise "A25 envelope escapes private root"
    end

    def mean(values) = values.empty? ? 0.0 : (values.sum.to_f / values.length).round(6)
    def complete(data) = {"lifecycle_state" => "complete", "schema" => SCHEMA, "data" => data, "mutation" => "none"}
    def failed(message) = {"lifecycle_state" => "failed", "schema" => SCHEMA, "message" => message, "mutation" => "none"}
  end
end
