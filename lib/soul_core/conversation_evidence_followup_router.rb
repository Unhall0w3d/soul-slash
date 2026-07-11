# frozen_string_literal: true

module SoulCore
  class ConversationEvidenceFollowupRouter
    MAX_SELECTED_CLAIMS = 24

    Selection = Struct.new(
      :matched,
      :reason,
      :record,
      :claims,
      :not_collected,
      :focus_terms,
      keyword_init: true
    ) do
      def matched?
        matched == true
      end

      def to_h
        {
          "matched" => matched?,
          "reason" => reason.to_s,
          "evidence_id" => record && record["evidence_id"],
          "tool_id" => record && record["tool_id"],
          "evidence_profile" => record && record["evidence_profile"],
          "focus_terms" => Array(focus_terms),
          "claim_count" => Array(claims).length,
          "not_collected_count" => Array(not_collected).length
        }.reject { |_key, value| value.nil? }
      end
    end

    REFERENTIAL_PATTERNS = [
      /\b(?:that|those|them|it|this result|that result|the result|the check|the assessment|the evidence)\b/i,
      /\b(?:you mentioned|you referred to|you were referring to|you were talking about)\b/i,
      /\bwhich\b.{0,60}\bwere you (?:referring to|talking about)\b/i,
      /\bwhich\b.{0,60}\bdid you mean\b/i,
      /\bwhat about\b/i,
      /\bwhich (?:one|ones|of those)\b/i,
      /\b(?:tell|show|give) me (?:more|the details|more details)\b/i,
      /\b(?:expand|elaborate) on\b/i,
      /\bwhat (?:does|did) (?:that|it|this) mean\b/i
    ].freeze

    RESULT_ACTION_PATTERNS = [
      /\bwhich\b.{0,60}\b(?:did you find|did you check|were found|were listed|were flagged|were reported|were collected|were included)\b/i,
      /\bwhat\b.{0,60}\b(?:did you find|did you check|was found|was listed|was flagged|was reported|was collected|was included)\b/i,
      /\bwhere did (?:that|those|this)\b/i,
      /\bdetails? (?:from|about|on) (?:the|that|those|this)\b/i
    ].freeze

    STOP_WORDS = %w[
      a about after again all also am an and any are as at be because been before being
      between both but by can could did do does doing for from further had has have having
      he her here hers herself him himself his how i if in into is it its itself just me more
      most my myself no nor not now of off on once only or other our ours ourselves out over
      own please same she should so some such than that the their theirs them themselves then
      there these they this those through to too under until up very was we were what when where
      which while who whom why will with would you your yours yourself yourselves mentioned
      referring referred talking tell show give expand elaborate result check assessment evidence
      one ones details detail mean
    ].freeze

    TOPIC_GROUPS = [
      %w[disk disks drive drives block device devices nvme ssd hdd],
      %w[filesystem filesystems volume volumes mount mounts mounted partition partitions btrfs ext4 xfs ntfs vfat],
      %w[storage capacity space usage utilization],
      %w[network networks interface interfaces ethernet wifi wireless link links mtu],
      %w[memory ram swap zram available used],
      %w[service services systemd unit units daemon daemons failed running],
      %w[skill skills capability capabilities tool tools catalog],
      %w[download downloads file files cleanup candidate candidates flagged],
      %w[history execution executions run runs record records],
      %w[error errors failure failures failed warning warnings],
      %w[smart health],
      %w[temperature temperatures thermal],
      %w[raid zfs firewall authentication scheduled jobs]
    ].freeze

    def route(message:, evidence_records:)
      text = message.to_s.strip
      records = Array(evidence_records).select { |record| record.is_a?(Hash) }
      return unmatched("no persisted evidence is available") if text.empty? || records.empty?
      return unmatched("the message does not refer to prior deterministic evidence") unless followup_language?(text)

      terms = expanded_focus_terms(text)
      record = select_record(records, terms)
      return unmatched("no evidence record could be selected") unless record

      claims = select_lines(Array(record["claims"]), terms)
      not_collected = select_not_collected(record, text, terms, claims)

      Selection.new(
        matched: true,
        reason: selection_reason(text, terms),
        record: record,
        claims: claims,
        not_collected: not_collected,
        focus_terms: terms
      )
    end

    def render(selection:, heading: "Details from the most recent deterministic check")
      return "#{heading}\n- No matching persisted evidence is available." unless selection&.matched?

      record = selection.record
      lines = [heading, ""]
      lines << "#{record['label']} (#{record['tool_id']})"
      lines << "Evidence ID: #{record['evidence_id']}"
      lines << "Scope: #{record['scope']}"
      lines << "Status: #{record['status']}"
      lines << "Collected:"

      claims = Array(selection.claims)
      if claims.empty?
        lines << "- No matching collected facts were recorded."
      else
        claims.each { |claim| lines << "- #{claim}" }
      end

      not_collected = Array(selection.not_collected)
      unless not_collected.empty?
        lines << "Not collected by this check:"
        not_collected.each { |item| lines << "- #{item}" }
      end

      lines.join("\n")
    end

    private

    def unmatched(reason)
      Selection.new(
        matched: false,
        reason: reason,
        record: nil,
        claims: [],
        not_collected: [],
        focus_terms: []
      )
    end

    def followup_language?(text)
      REFERENTIAL_PATTERNS.any? { |pattern| text.match?(pattern) } ||
        RESULT_ACTION_PATTERNS.any? { |pattern| text.match?(pattern) }
    end

    def selection_reason(text, terms)
      return "generic referential follow-up selected the most recent relevant evidence" if terms.empty?

      "follow-up focus matched persisted evidence terms: #{terms.first(8).join(', ')}"
    end

    def select_record(records, terms)
      return records.last if terms.empty?

      scored = records.each_with_index.map do |record, index|
        [record_score(record, terms), index, record]
      end

      best = scored.max_by { |score, index, _record| [score, index] }
      return nil unless best && best[0].positive?

      best[2]
    end

    def record_score(record, terms)
      identity = [
        record["label"],
        record["tool_id"],
        record["evidence_profile"],
        record["scope"]
      ].join(" ")

      identity_score = overlap_score(identity, terms) * 4
      claim_score = Array(record["claims"]).map { |line| overlap_score(line, terms) }.max.to_i * 2
      omitted_score = Array(record["not_collected"]).map { |line| overlap_score(line, terms) }.max.to_i
      collected_score = overlap_score(flatten_text(record["collected"]), terms)

      identity_score + claim_score + omitted_score + collected_score
    end

    def select_lines(lines, terms)
      values = lines.map(&:to_s).reject(&:empty?)
      return values.first(MAX_SELECTED_CLAIMS) if terms.empty?

      matching = values.select { |line| overlap_score(line, terms).positive? }
      matching.first(MAX_SELECTED_CLAIMS)
    end

    def select_not_collected(record, text, terms, selected_claims)
      values = Array(record["not_collected"]).map(&:to_s).reject(&:empty?)
      return values if terms.empty?

      matching = values.select { |line| overlap_score(line, terms).positive? }
      asks_about_omission = text.match?(/\b(?:not collected|omitted|missing|unknown|unavailable|what about)\b/i)
      return [] unless asks_about_omission || selected_claims.empty?

      matching
    end

    def expanded_focus_terms(text)
      base = tokenize(text).reject { |token| STOP_WORDS.include?(token) }
      expanded = base.dup

      TOPIC_GROUPS.each do |group|
        expanded.concat(group) unless (base & group).empty?
      end

      expanded.uniq
    end

    def tokenize(text)
      text.to_s.downcase.scan(/[a-z0-9][a-z0-9._\/-]*/).map { |token| singularize(token) }
    end

    def singularize(token)
      return token[0..-4] + "y" if token.end_with?("ies") && token.length > 4
      return token[0..-2] if token.end_with?("s") && token.length > 4 && !token.end_with?("ss") && token != "status"

      token
    end

    def overlap_score(text, terms)
      tokens = tokenize(text)
      (tokens & terms).length
    end

    def flatten_text(value)
      case value
      when Hash
        value.flat_map { |key, nested| [key.to_s, flatten_text(nested)] }.join(" ")
      when Array
        value.map { |nested| flatten_text(nested) }.join(" ")
      else
        value.to_s
      end
    end
  end
end
