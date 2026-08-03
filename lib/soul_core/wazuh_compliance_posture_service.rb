# frozen_string_literal: true

require "json"
require "time"

module SoulCore
  class WazuhCompliancePostureService
    SCHEMA_VERSION = "soul.security.wazuh-compliance-posture.v1"
    MANIFEST_SCHEMA = "soul.wazuh.compliance-posture.v1"
    MAX_MANIFEST_BYTES = 256 * 1024
    MAX_FINDINGS = 512
    CLASSIFICATIONS = %w[
      verified_effective_control
      accepted_workstation_exception
      policy_or_parser_limitation
      genuine_remaining_decision
    ].freeze
    AGENT_ID_PATTERN = /\A\d{3,8}\z/
    POLICY_ID_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9_.-]{0,127}\z/

    def initialize(root: Dir.pwd, process_env: ENV, clock: -> { Time.now.utc })
      @root = File.expand_path(root)
      @process_env = process_env.to_h.transform_keys(&:to_s)
      @clock = clock
    end

    def status
      path = configured_path
      return success(unavailable_data("Wazuh compliance posture is not configured", configured: false)) unless path

      manifest = read_private_json(path)
      success(normalize(manifest))
    rescue StandardError => error
      success(unavailable_data("Wazuh compliance posture unavailable: #{safe_reason(error)}", configured: true))
    end

    alias snapshot status

    private

    def configured_path
      raw = @process_env.fetch("SOUL_WAZUH_POSTURE_FILE", "").to_s.strip
      return nil if raw.empty?
      raise "Wazuh posture path must be absolute" unless raw.start_with?(File::SEPARATOR)

      File.expand_path(raw)
    end

    def read_private_json(path)
      raise "Wazuh posture manifest is unavailable" unless File.file?(path)
      raise "Wazuh posture manifest path is unsafe" if File.symlink?(path)
      stat = File.stat(path)
      raise "Wazuh posture manifest must be owner-private" unless stat.uid == Process.uid && (stat.mode & 0o077).zero?
      raise "Wazuh posture manifest exceeds its size bound" if stat.size > MAX_MANIFEST_BYTES

      JSON.parse(File.binread(path, MAX_MANIFEST_BYTES + 1))
    end

    def normalize(manifest)
      raise "Wazuh posture manifest schema is unsupported" unless manifest.is_a?(Hash) && manifest["schema_version"] == MANIFEST_SCHEMA
      raise "Wazuh posture manifest is disabled" unless manifest["enabled"] == true

      raw = normalize_raw(manifest.fetch("raw_wazuh_result"))
      review = normalize_review(manifest.fetch("adapted_review"), raw)
      {
        "schema_version" => SCHEMA_VERSION,
        "available" => true,
        "configured" => true,
        "state" => review.fetch("genuine_remaining_decision_count").positive? ? "attention" : "reviewed",
        "loaded_at" => @clock.call.utc.iso8601,
        "source" => "owner_reviewed_wazuh_sca_snapshot",
        "read_only" => true,
        "raw_result_preserved" => true,
        "wazuh_remains_authoritative" => true,
        "remote_query" => false,
        "remote_mutation" => false,
        "raw_wazuh_result" => raw,
        "adapted_review" => review,
        "verification" => {
          "all_raw_failures_classified" => review.fetch("reviewed_failure_count") == raw.fetch("failed"),
          "classification_ids_unique" => true,
          "score_recalculated" => false,
          "wazuh_result_modified" => false
        }
      }
    end

    def normalize_raw(raw)
      raise "raw Wazuh result is invalid" unless raw.is_a?(Hash)

      agent_id = raw["agent_id"].to_s
      policy_id = raw["policy_id"].to_s
      raise "raw Wazuh agent identity is invalid" unless agent_id.match?(AGENT_ID_PATTERN) && agent_id != "000"
      raise "raw Wazuh policy identity is invalid" unless policy_id.match?(POLICY_ID_PATTERN)

      passed = bounded_integer(raw["passed"], 0, MAX_FINDINGS)
      failed = bounded_integer(raw["failed"], 0, MAX_FINDINGS)
      not_applicable = bounded_integer(raw["not_applicable"], 0, MAX_FINDINGS)
      total = bounded_integer(raw["total_checks"], 1, MAX_FINDINGS)
      score = bounded_integer(raw["score"], 0, 100)
      scan_hash = raw["scan_hash"].to_s.downcase
      raise "raw Wazuh scan hash is invalid" unless scan_hash.match?(/\A[0-9a-f]{64}\z/)
      raise "raw Wazuh result totals do not reconcile" unless passed + failed + not_applicable == total

      {
        "agent_id" => agent_id,
        "policy_id" => policy_id,
        "policy_name" => bounded_text(raw["policy_name"], 180),
        "scan_id" => bounded_text(raw["scan_id"], 80),
        "scan_hash" => scan_hash,
        "scanned_at" => normalized_time(raw["scanned_at"]),
        "passed" => passed,
        "failed" => failed,
        "not_applicable" => not_applicable,
        "total_checks" => total,
        "score" => score,
        "unaltered" => true
      }
    end

    def normalize_review(review, raw)
      raise "adapted posture review is invalid" unless review.is_a?(Hash)

      version = bounded_text(review["version"], 64)
      raise "adapted posture version is required" if version.empty?
      groups = review.fetch("classifications")
      raise "adapted posture classifications are invalid" unless groups.is_a?(Array) && groups.length == CLASSIFICATIONS.length

      normalized = groups.map { |group| normalize_group(group) }
      kinds = normalized.map { |group| group.fetch("classification") }
      raise "adapted posture classifications must be complete and unique" unless kinds.sort == CLASSIFICATIONS.sort
      ids = normalized.flat_map { |group| group.fetch("check_ids") }
      raise "adapted posture finding IDs must be unique" unless ids.uniq.length == ids.length
      raise "adapted posture must classify every raw Wazuh failure" unless ids.length == raw.fetch("failed")

      counts = normalized.to_h { |group| [group.fetch("classification"), group.fetch("count")] }
      {
        "version" => version,
        "reviewed_at" => normalized_time(review["reviewed_at"]),
        "reviewed_failure_count" => ids.length,
        "verified_effective_control_count" => counts.fetch("verified_effective_control"),
        "accepted_workstation_exception_count" => counts.fetch("accepted_workstation_exception"),
        "policy_or_parser_limitation_count" => counts.fetch("policy_or_parser_limitation"),
        "genuine_remaining_decision_count" => counts.fetch("genuine_remaining_decision"),
        "classifications" => normalized,
        "boundary" => "Interpretation only; the raw Wazuh score remains unchanged and authoritative."
      }
    end

    def normalize_group(group)
      raise "adapted posture classification is invalid" unless group.is_a?(Hash)
      classification = group["classification"].to_s
      raise "adapted posture classification is unsupported" unless CLASSIFICATIONS.include?(classification)
      ids = group.fetch("check_ids")
      raise "adapted posture check IDs are invalid" unless ids.is_a?(Array) && !ids.empty? && ids.length <= MAX_FINDINGS
      ids = ids.map { |id| bounded_integer(id, 1, 999_999) }.sort
      raise "adapted posture check IDs must be unique" unless ids.uniq.length == ids.length

      {
        "classification" => classification,
        "count" => ids.length,
        "check_ids" => ids,
        "summary" => bounded_text(group["summary"], 320)
      }
    end

    def bounded_integer(value, minimum, maximum)
      integer = Integer(value)
      raise "Wazuh posture numeric value is outside its bound" unless integer.between?(minimum, maximum)

      integer
    rescue ArgumentError, TypeError
      raise "Wazuh posture numeric value is invalid"
    end

    def normalized_time(value)
      Time.iso8601(value.to_s).utc.iso8601
    rescue ArgumentError
      raise "Wazuh posture timestamp is invalid"
    end

    def bounded_text(value, maximum)
      value.to_s.byteslice(0, maximum).to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "�")
    end

    def safe_reason(error)
      bounded_text(error.message.to_s.gsub(%r{/(?:home|run|etc)/[^\s]+}, "[private path]"), 320)
    end

    def unavailable_data(reason, configured:)
      {
        "schema_version" => SCHEMA_VERSION,
        "available" => false,
        "configured" => configured,
        "state" => "unavailable",
        "loaded_at" => @clock.call.utc.iso8601,
        "reason" => bounded_text(reason, 320),
        "source" => "owner_reviewed_wazuh_sca_snapshot",
        "read_only" => true,
        "raw_result_preserved" => true,
        "remote_query" => false,
        "remote_mutation" => false
      }
    end

    def success(data)
      {"ok" => true, "lifecycle_state" => "complete", "data" => data, "mutation" => "none"}
    end
  end
end
