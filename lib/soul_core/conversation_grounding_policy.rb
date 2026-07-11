# frozen_string_literal: true

require "json"

module SoulCore
  class ConversationGroundingPolicy
    FOLLOWUP_PATTERNS = [
      /\A\s*(?:further|more|additional)\s+details\b/i,
      /\bwhat (?:exactly )?did you check\b/i,
      /\bwhat was checked\b/i,
      /\bwhat did that check\b/i,
      /\bwhich (?:disk|drive|volume|filesystem|service|interface)\b/i,
      /\bwhere did (?:that|those|this) (?:number|information|data|result)\b/i,
      /\btell me more about (?:that|the check|the result)\b/i,
      /\bexpand on (?:that|the check|the result)\b/i,
      /\bwhat do you mean by (?:that|the result)\b/i
    ].freeze

    ENVIRONMENT_MARKERS = [
      "raid",
      "zfs",
      "ext4",
      "xfs",
      "btrfs",
      "smart",
      "/dev/",
      "/data",
      "/backup",
      "cpu",
      "memory",
      "ram",
      "disk",
      "filesystem",
      "temperature",
      "latency",
      "packet loss",
      "firewall",
      "cron",
      "systemd timer",
      "reallocated sector",
      "pending sector",
      "read speed",
      "write speed"
    ].freeze

    METRIC_PATTERN = /
      \b\d+(?:\.\d+)?\s*
      (?:%|tb|gb|mb|kb|mb\/s|gb\/s|ms|°c|celsius|fahrenheit)
      \b
    /ix

    NEGATION_PATTERN = /
      \b(
        not|didn't|did\ not|wasn't|were\ not|unknown|unavailable|
        uncollected|not\ collected|no\ data|cannot|can't|doesn't\ include
      )\b
    /ix

    def followup?(message)
      text = message.to_s
      FOLLOWUP_PATTERNS.any? { |pattern| text.match?(pattern) }
    end

    def validate(response:, evidence_records:)
      text = response.to_s.strip
      evidence = Array(evidence_records)
      return result(false, ["empty response"]) if text.empty?
      return result(true, []) if evidence.empty?

      collected_text = evidence.flat_map do |record|
        Array(record["claims"]) +
          record.fetch("collected", {}).values.map(&:to_s)
      end.join("\n").downcase

      errors = []
      sentences(text).each do |sentence|
        next if sentence.match?(NEGATION_PATTERN)

        lower = sentence.downcase
        ENVIRONMENT_MARKERS.each do |marker|
          next unless lower.include?(marker)
          next if collected_text.include?(marker)

          errors << "unsupported environmental claim: #{marker}"
        end

        sentence.scan(METRIC_PATTERN).each do |metric|
          normalized = metric.to_s.downcase.gsub(/\s+/, "")
          source_normalized = collected_text.gsub(/\s+/, "")
          next if source_normalized.include?(normalized)

          errors << "unsupported metric: #{metric.to_s.strip}"
        end
      end

      result(errors.empty?, errors.uniq)
    end

    def render_evidence(evidence_records, heading: "Deterministic evidence")
      records = Array(evidence_records)
      return "#{heading}\n- No persisted evidence is available." if records.empty?

      sections = records.map do |record|
        lines = []
        lines << "#{record['label']} (#{record['tool_id']})"
        lines << "Evidence ID: #{record['evidence_id']}"
        lines << "Scope: #{record['scope']}"
        lines << "Status: #{record['status']}"
        lines << "Collected:"

        claims = Array(record["claims"])
        if claims.empty?
          lines << "- No successful claims were recorded."
        else
          claims.each { |claim| lines << "- #{claim}" }
        end

        not_collected = Array(record["not_collected"])
        unless not_collected.empty?
          lines << "Not collected by this check:"
          not_collected.each { |item| lines << "- #{item}" }
        end

        lines.join("\n")
      end

      "#{heading}\n\n#{sections.join("\n\n")}"
    end

    private

    def sentences(text)
      text.split(/(?<=[.!?])\s+|\n+/).map(&:strip).reject(&:empty?)
    end

    def result(valid, errors)
      {
        "valid" => valid,
        "errors" => errors
      }
    end
  end
end
