# frozen_string_literal: true

# Held-out synthetic reviewer cases for a second AMD comparison batch.
# Oracle and seeded audit fields are diagnostic controls, not public prompts.
module AmdReviewerCasesM3b
  VERDICTS = %w[supported contradicted insufficient_evidence mixed].freeze

  CASES = [
    {
      "id" => "effective-permit-revision",
      "question" => "Return permit_id exactly as listed and capacity as N units. Which permit is active on 2026-08-01, and what is its capacity?",
      "evidence" => [
        { "id" => "permit-p12", "text" => "Permit P-12 revision 2, effective 2026-01-01: capacity 40 units. It remains valid until superseded." },
        { "id" => "permit-p18-r1", "text" => "Permit P-18 revision 1, effective 2026-03-01, supersedes P-12 for the same permit scope: capacity 55 units." },
        { "id" => "permit-p18-r3", "text" => "Permit P-18 revision 3, effective 2026-07-15, supersedes revision 1: capacity 62 units." }
      ],
      "answer_fields" => %w[permit_id capacity],
      "oracle" => { "permit_id" => "P-18", "capacity" => "62 units" },
      "seeded_answer" => { "permit_id" => "P-18", "capacity" => "62 units" },
      "seeded_verdict" => "supported"
    },
    {
      "id" => "crate-route-join",
      "question" => "Return the handler's name exactly as recorded, destination code exactly as listed, and priority as its bare number or the literal unknown. Who handles crate C-73, where is it routed, and what priority is recorded?",
      "evidence" => [
        { "id" => "crate-handlers", "text" => "Crate C-37 is assigned to handler H-2. Crate C-73 is assigned to handler H-9." },
        { "id" => "handler-names", "text" => "Handler H-2 is Elin Dorr. Handler H-9 is Miro Pell." },
        { "id" => "handler-routes", "text" => "Handler H-2 routes to Dock D-4. Handler H-9 routes to Dock D-8. No crate priority is recorded." }
      ],
      "answer_fields" => %w[handler destination priority],
      "oracle" => { "handler" => "Miro Pell", "destination" => "D-8", "priority" => "unknown" },
      "seeded_answer" => { "handler" => "Miro Pell", "destination" => "D-8", "priority" => "unknown" },
      "seeded_verdict" => "supported"
    },
    {
      "id" => "superseded-inspection-window",
      "question" => "Return interval as N days and revision as a bare number. What applies under the latest inspection schedule?",
      "evidence" => [
        { "id" => "schedule-r6", "text" => "Inspection schedule revision 6: inspect every 45 days." },
        { "id" => "schedule-r7", "text" => "Inspection schedule revision 7 supersedes revision 6: inspect every 30 days." }
      ],
      "answer_fields" => %w[interval revision],
      "oracle" => { "interval" => "30 days", "revision" => "7" },
      "seeded_answer" => { "interval" => "45 days", "revision" => "6" },
      "seeded_verdict" => "contradicted"
    },
    {
      "id" => "misjoined-sample-owner",
      "question" => "Return the owner name exactly as recorded. Who is assigned sample S-28?",
      "evidence" => [
        { "id" => "sample-assignments", "text" => "Sample S-28 is assigned to locker L-3. Sample S-82 is assigned to locker L-8." },
        { "id" => "locker-owners", "text" => "Locker L-3 is managed by Ada Noll. Locker L-8 is managed by Bram Venn." }
      ],
      "answer_fields" => ["owner"],
      "oracle" => { "owner" => "Ada Noll" },
      "seeded_answer" => { "owner" => "Bram Venn" },
      "seeded_verdict" => "contradicted"
    },
    {
      "id" => "unrecorded-valve-duration",
      "question" => "Return duration as N minutes, or the literal unknown if no duration is recorded. How long was valve V-6 open?",
      "evidence" => [
        { "id" => "valve-log", "text" => "Valve V-6 was opened for the flush cycle. The log contains no opening or closing time and no duration measurement." }
      ],
      "answer_fields" => ["duration"],
      "oracle" => { "duration" => "unknown" },
      "seeded_answer" => { "duration" => "18 minutes" },
      "seeded_verdict" => "insufficient_evidence"
    },
    {
      "id" => "unlisted-shelf-location",
      "question" => "Return shelf_code exactly as listed, or the literal unknown if it is not recorded. Which shelf stores folder F-19?",
      "evidence" => [
        { "id" => "folder-index", "text" => "Folder F-91 is stored on shelf S-4. Folder F-19 was checked out for indexing; its storage shelf is not stated." }
      ],
      "answer_fields" => ["shelf_code"],
      "oracle" => { "shelf_code" => "unknown" },
      "seeded_answer" => { "shelf_code" => "S-4" },
      "seeded_verdict" => "insufficient_evidence"
    },
    {
      "id" => "audited-transfer-claims",
      "question" => "Return the applicable transfer limit as N units and the recorded close date as YYYY-MM-DD or the literal unknown. What are the current values?",
      "evidence" => [
        { "id" => "transfer-r1", "text" => "Transfer rule revision 1: limit 20 units. This revision is superseded." },
        { "id" => "transfer-r2", "text" => "Transfer rule revision 2 supersedes revision 1: limit 16 units." },
        { "id" => "transfer-audit", "text" => "Audit A-14 found that the transfer limit was exceeded. The transfer close date is absent from the audit and register." }
      ],
      "answer_fields" => %w[limit close_date],
      "oracle" => { "limit" => "16 units", "close_date" => "unknown" },
      "seeded_answer" => { "limit" => "20 units", "close_date" => "2026-05-10" },
      "seeded_verdict" => "mixed"
    },
    {
      "id" => "revision-and-missing-approver",
      "question" => "Return form_code in the format 'F-N revision N' and approver as the exact name or literal unknown. Which values apply to request Q-14?",
      "evidence" => [
        { "id" => "request-form-links", "text" => "Request Q-14 uses form F-2. Request Q-41 uses form F-7." },
        { "id" => "form-revisions", "text" => "Form F-2 revision 1 was withdrawn. Form F-2 revision 3 supersedes revision 1 and is current." },
        { "id" => "request-approval-log", "text" => "The approval log for Q-14 has no approver entry. No other approver record is supplied." }
      ],
      "answer_fields" => %w[form_code approver],
      "oracle" => { "form_code" => "F-2 revision 3", "approver" => "unknown" },
      "seeded_answer" => { "form_code" => "F-2 revision 1", "approver" => "Jessa Ward" },
      "seeded_verdict" => "mixed"
    }
  ].freeze

  def self.cases
    Marshal.load(Marshal.dump(CASES))
  end

  def self.public_case(case_data)
    validate_case!(case_data)
    case_data.reject { |key, _| %w[oracle seeded_answer seeded_verdict].include?(key) }
  end

  def self.validate!
    raise ArgumentError, "expected exactly 8 cases" unless CASES.length == 8
    ids = CASES.map { |item| item.fetch("id") }
    raise ArgumentError, "case ids must be unique lowercase hyphenated values" unless ids.uniq == ids && ids.all? { |id| id.match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/) }

    CASES.each { |item| validate_case!(item) }
    counts = CASES.group_by { |item| item.fetch("seeded_verdict") }.transform_values(&:length)
    expected = { "supported" => 2, "contradicted" => 2, "insufficient_evidence" => 2, "mixed" => 2 }
    raise ArgumentError, "seeded verdict coverage mismatch" unless counts == expected
    raise ArgumentError, "supported seeds must match oracle" unless CASES.select { |item| item.fetch("seeded_verdict") == "supported" }.all? { |item| item.fetch("seeded_answer") == item.fetch("oracle") }
    raise ArgumentError, "contradicted seeds must differ from oracle" unless CASES.select { |item| item.fetch("seeded_verdict") == "contradicted" }.all? { |item| item.fetch("seeded_answer") != item.fetch("oracle") }
    raise ArgumentError, "insufficient-evidence cases must encode explicit unknown and unsupported certainty" unless CASES.select { |item| item.fetch("seeded_verdict") == "insufficient_evidence" }.all? do |item|
      item.fetch("oracle").values.all? { |value| value == "unknown" } && item.fetch("seeded_answer").values.none? { |value| value == "unknown" }
    end
    mixed = CASES.select { |item| item.fetch("seeded_verdict") == "mixed" }
    raise ArgumentError, "mixed cases must combine contradicted and unsupported claims" unless mixed.all? do |item|
      item.fetch("answer_fields").any? { |field| item.fetch("oracle").fetch(field) == "unknown" && item.fetch("seeded_answer").fetch(field) != "unknown" } &&
        item.fetch("answer_fields").any? { |field| item.fetch("oracle").fetch(field) != "unknown" && item.fetch("seeded_answer").fetch(field) != item.fetch("oracle").fetch(field) }
    end
    true
  end

  def self.validate_case!(item)
    raise ArgumentError, "case must be a hash" unless item.is_a?(Hash)
    required = %w[id question evidence answer_fields oracle seeded_answer seeded_verdict]
    raise ArgumentError, "case shape mismatch" unless item.keys.sort == required.sort
    raise ArgumentError, "invalid verdict" unless VERDICTS.include?(item.fetch("seeded_verdict"))
    raise ArgumentError, "question must be nonempty" unless nonempty_string?(item.fetch("question"))
    evidence = item.fetch("evidence")
    raise ArgumentError, "evidence must be a nonempty array" unless evidence.is_a?(Array) && !evidence.empty?
    raise ArgumentError, "invalid evidence entry" unless evidence.all? do |fact|
      fact.is_a?(Hash) && fact.keys.sort == %w[id text] && nonempty_string?(fact["id"]) && nonempty_string?(fact["text"]) && fact.fetch("text").length < 1400
    end
    raise ArgumentError, "evidence ids must be unique within a case" unless evidence.map { |fact| fact.fetch("id") }.uniq.length == evidence.length
    fields = item.fetch("answer_fields")
    raise ArgumentError, "invalid answer fields" unless fields.is_a?(Array) && (1..3).cover?(fields.length) && fields.uniq == fields && fields.all? { |field| field.match?(/\A[a-z][a-z0-9_]*\z/) }
    %w[oracle seeded_answer].each do |key|
      values = item.fetch(key)
      raise ArgumentError, "#{key} keys mismatch" unless values.is_a?(Hash) && values.keys.sort == fields.sort
      raise ArgumentError, "#{key} values must be nonempty strings" unless values.values.all? { |value| nonempty_string?(value) }
    end
    raise ArgumentError, "invalid case id" unless item.fetch("id").match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/)
    true
  end
  private_class_method :validate_case!

  def self.nonempty_string?(value)
    value.is_a?(String) && !value.strip.empty?
  end
  private_class_method :nonempty_string?
end
