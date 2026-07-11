# frozen_string_literal: true

require "json"

module SoulCore
  class ConversationGroundingPolicy
    FOLLOWUP_PATTERNS = [
      /\A\s*(?:further|more|additional)\s+details\b/i,
      /\bwhat (?:exactly )?did you check\b/i,
      /\bwhat was checked\b/i,
      /\bwhat did that check\b/i,
      /\bwhich (?:disk|disks|drive|drives|volume|volumes|filesystem|filesystems|service|services|interface|interfaces)\b.{0,45}\b(?:refer(?:ring)? to|mention(?:ed)?|mean)\b/i,
      /\bwhat (?:disk|disks|drive|drives|filesystem|filesystems)\b.{0,45}\b(?:were you referring to|did you mention|did that mean)\b/i,
      /\bwhere did (?:that|those|this) (?:number|information|data|result)\b/i,
      /\btell me more about (?:that|the check|the result|those disks|those drives|those filesystems)\b/i,
      /\bexpand on (?:that|the check|the result)\b/i,
      /\bwhat do you mean by (?:that|the result)\b/i
    ].freeze

    STORAGE_FOCUS = /\b(storage|disk|disks|drive|drives|volume|volumes|filesystem|filesystems|mount|mounts|raid|smart)\b/i
    NETWORK_FOCUS = /\b(network|interface|interfaces|ethernet|wifi|wireless)\b/i
    MEMORY_FOCUS = /\b(memory|ram|load|cpu)\b/i
    PLATFORM_FOCUS = /\b(hostname|operating system|os|kernel|uptime)\b/i
    SERVICE_FOCUS = /\b(systemd|service|services|failed units?)\b/i

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

    def render_followup(message:, evidence_records:, heading: "Deterministic evidence")
      records = Array(evidence_records)
      return "#{heading}\n- No persisted evidence is available." if records.empty?

      record = focused_record(message, records)
      claims = focused_claims(message, record)
      not_collected = focused_not_collected(message, record)

      render_record(
        record,
        claims: claims,
        not_collected: not_collected,
        heading: heading
      )
    end

    def render_evidence(evidence_records, heading: "Deterministic evidence")
      records = Array(evidence_records)
      return "#{heading}\n- No persisted evidence is available." if records.empty?

      sections = records.map do |record|
        render_record(record, heading: nil)
      end

      "#{heading}\n\n#{sections.join("\n\n")}"
    end

    private

    def focused_record(message, records)
      focus = focus_type(message)
      if focus
        host = records.reverse.find do |record|
          record["evidence_profile"] == "host_system_status"
        end
        return host if host
      end

      records.last
    end

    def focused_claims(message, record)
      claims = Array(record["claims"])
      focus = focus_type(message)
      return claims unless focus

      selected =
        case focus
        when :storage
          claims.select do |claim|
            claim.match?(/\A(?:Filesystem|Block device|Linux MD RAID|No active Linux MD RAID)/i)
          end
        when :network
          claims.select { |claim| claim.match?(/\ANetwork interface/i) }
        when :memory
          claims.select { |claim| claim.match?(/\A(?:Memory|Load averages)/i) }
        when :platform
          claims.select { |claim| claim.match?(/\A(?:Hostname|Operating system|Kernel|Uptime)/i) }
        when :service
          claims.select { |claim| claim.match?(/\Asystemd/i) }
        else
          []
        end

      selected.empty? ? claims : selected
    end

    def focused_not_collected(message, record)
      items = Array(record["not_collected"])
      focus = focus_type(message)
      return items unless focus

      selected =
        case focus
        when :storage
          items.select { |item| item.match?(/smart|storage|raid|zfs|filesystem|disk|temperature/i) }
        when :network
          items.select { |item| item.match?(/network|firewall|reachability/i) }
        when :memory
          items.select { |item| item.match?(/memory|cpu|load/i) }
        when :service
          items.select { |item| item.match?(/service|authentication|scheduled|process/i) }
        else
          []
        end

      selected
    end

    def focus_type(message)
      text = message.to_s
      return :storage if text.match?(STORAGE_FOCUS)
      return :network if text.match?(NETWORK_FOCUS)
      return :memory if text.match?(MEMORY_FOCUS)
      return :platform if text.match?(PLATFORM_FOCUS)
      return :service if text.match?(SERVICE_FOCUS)

      nil
    end

    def render_record(record, claims: nil, not_collected: nil, heading: nil)
      lines = []
      lines << heading if heading
      lines << "" if heading
      lines << "#{record['label']} (#{record['tool_id']})"
      lines << "Evidence ID: #{record['evidence_id']}"
      lines << "Scope: #{record['scope']}"
      lines << "Status: #{record['status']}"
      lines << "Collected:"

      selected_claims = claims.nil? ? Array(record["claims"]) : Array(claims)
      if selected_claims.empty?
        lines << "- No matching collected facts were recorded."
      else
        selected_claims.each { |claim| lines << "- #{claim}" }
      end

      selected_not_collected =
        not_collected.nil? ? Array(record["not_collected"]) : Array(not_collected)

      unless selected_not_collected.empty?
        lines << "Not collected by this check:"
        selected_not_collected.each { |item| lines << "- #{item}" }
      end

      lines.join("\n")
    end

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
