# frozen_string_literal: true

# Held-out synthetic reviewer cases. The oracle and seeded audits are diagnostic
# controls; they are not evidence that a model can accurately review itself.
module AmdReviewerCasesM3
  VERDICTS = %w[supported contradicted insufficient_evidence mixed].freeze

  CASES = [
    {
      "id" => "archive-current-revision",
      "question" => "Return retention_period as N months and revision as a bare number. What are the current values?",
      "evidence" => [
        { "id" => "policy-r4", "text" => "Archive policy revision 4, dated 2026-04-02: retain records for 18 months." },
        { "id" => "policy-r5", "text" => "Archive policy revision 5, dated 2026-06-19, supersedes revision 4: retain records for 24 months." }
      ],
      "answer_fields" => %w[retention_period revision],
      "oracle" => { "retention_period" => "24 months", "revision" => "5" },
      "seeded_answer" => { "retention_period" => "24 months", "revision" => "5" },
      "seeded_verdict" => "supported"
    },
    {
      "id" => "parcel-custodian-join",
      "question" => "Return the person's name exactly as recorded and room as its bare number. Which custodian is assigned to parcel P-41, and which room is that custodian based in?",
      "evidence" => [
        { "id" => "office-directory", "text" => "Office code OF-7 is Room 118, occupied by Omar Pell. Office code OF-2 is Room 212, occupied by Nia Vale. Office code OF-9 is Room 215, occupied by Toma Reed." },
        { "id" => "custodian-office-links", "text" => "Custodian C-3 has office code OF-7. Custodian C-8 has office code OF-2. Custodian C-5 has office code OF-9." },
        { "id" => "parcel-assignments", "text" => "Parcel P-14 is assigned to custodian C-3. Parcel P-41 is assigned to custodian C-8. Parcel P-44 is assigned to custodian C-5." }
      ],
      "answer_fields" => %w[person room],
      "oracle" => { "person" => "Nia Vale", "room" => "212" },
      "seeded_answer" => { "person" => "Nia Vale", "room" => "212" },
      "seeded_verdict" => "supported"
    },
    {
      "id" => "kiln-batch-total",
      "question" => "Return total_mass as N kg with no trailing fractional zeros. How many kilograms of clay are in the batch?",
      "evidence" => [
        { "id" => "batch-note", "text" => "The batch contains 7 sealed tubs. Each tub contains exactly 2.5 kg of clay." }
      ],
      "answer_fields" => ["total_mass"],
      "oracle" => { "total_mass" => "17.5 kg" },
      "seeded_answer" => { "total_mass" => "17.5 kg" },
      "seeded_verdict" => "supported"
    },
    {
      "id" => "inspection-two-claims",
      "question" => "Return status exactly as recorded and reviewer as the exact name or the literal unknown. What are the recorded values?",
      "evidence" => [
        { "id" => "inspection-log", "text" => "Inspection ticket T-22: status complete. The report does not list a reviewer name." }
      ],
      "answer_fields" => %w[status reviewer],
      "oracle" => { "status" => "complete", "reviewer" => "unknown" },
      "seeded_answer" => { "status" => "complete", "reviewer" => "unknown" },
      "seeded_verdict" => "supported"
    },
    {
      "id" => "earliest-eligible-valid-record",
      "question" => "Select the earliest record that is at site North, has status valid, and is not retracted. Return record_id exactly as listed and date in YYYY-MM-DD format.",
      "evidence" => [
        { "id" => "selection-row-1", "text" => "Record R-17; date 2026-01-11; site South; status valid; retracted no." },
        { "id" => "selection-row-2", "text" => "Record R-21; date 2026-01-19; site North; status invalid; retracted no." },
        { "id" => "selection-row-3", "text" => "Record R-30; date 2026-02-01; site North; status valid; retracted yes." },
        { "id" => "selection-row-4", "text" => "Record R-42; date 2026-03-05; site North; status valid; retracted no." },
        { "id" => "selection-row-5", "text" => "Record R-44; date 2026-02-10; site North; status valid; retracted no." },
        { "id" => "selection-row-6", "text" => "Record R-55; date 2026-01-25; site North; status invalid; retracted yes." }
      ],
      "answer_fields" => %w[record_id date],
      "oracle" => { "record_id" => "R-44", "date" => "2026-02-10" },
      "seeded_answer" => { "record_id" => "R-44", "date" => "2026-02-10" },
      "seeded_verdict" => "supported"
    },
    {
      "id" => "mixing-tank-arithmetic-error",
      "question" => "Return total_volume as N L with no trailing fractional zeros. How many liters were transferred in total?",
      "evidence" => [
        { "id" => "transfer-record", "text" => "Two transfers were recorded: 8 L in the morning and 6 L in the afternoon." }
      ],
      "answer_fields" => ["total_volume"],
      "oracle" => { "total_volume" => "14 L" },
      "seeded_answer" => { "total_volume" => "48 L" },
      "seeded_verdict" => "contradicted"
    },
    {
      "id" => "superseded-fee-schedule",
      "question" => "Return fee as N credits and revision as a bare number. What values apply under the latest schedule?",
      "evidence" => [
        { "id" => "fees-r2", "text" => "Fee schedule revision 2, dated 2026-02-01: standard filing fee is 9 credits." },
        { "id" => "fees-r3", "text" => "Fee schedule revision 3, dated 2026-05-15, supersedes revision 2: standard filing fee is 11 credits." }
      ],
      "answer_fields" => %w[fee revision],
      "oracle" => { "fee" => "11 credits", "revision" => "3" },
      "seeded_answer" => { "fee" => "9 credits", "revision" => "2" },
      "seeded_verdict" => "contradicted"
    },
    {
      "id" => "misjoined-manuscript-custodian",
      "question" => "Return the custodian's name exactly as recorded. Who is listed for manuscript M-27?",
      "evidence" => [
        { "id" => "manuscript-register", "text" => "Manuscript M-27 is assigned to account A-6. Manuscript M-72 is assigned to account A-9." },
        { "id" => "account-list", "text" => "Account A-6 belongs to Rhea Moss. Account A-9 belongs to Leon Venn." }
      ],
      "answer_fields" => ["owner"],
      "oracle" => { "owner" => "Rhea Moss" },
      "seeded_answer" => { "owner" => "Leon Venn" },
      "seeded_verdict" => "contradicted"
    },
    {
      "id" => "unreported-garden-yield",
      "question" => "Return yield as N kg with no trailing fractional zeros, or the literal unknown if the amount is not recorded. How many kilograms did plot G-5 yield?",
      "evidence" => [
        { "id" => "garden-log", "text" => "Plot G-5 was watered on Tuesday. No harvest amount is recorded." }
      ],
      "answer_fields" => ["yield"],
      "oracle" => { "yield" => "unknown" },
      "seeded_answer" => { "yield" => "12 kg" },
      "seeded_verdict" => "insufficient_evidence"
    },
    {
      "id" => "unmeasured-lantern-runtime",
      "question" => "Return runtime as N hours with no trailing fractional zeros, or the literal unknown if no duration is recorded. How many hours did lantern L-3 operate after its last charge?",
      "evidence" => [
        { "id" => "lantern-note", "text" => "Lantern L-3 was fully charged before the evening event. Its runtime was not measured or recorded." }
      ],
      "answer_fields" => ["runtime"],
      "oracle" => { "runtime" => "unknown" },
      "seeded_answer" => { "runtime" => "8 hours" },
      "seeded_verdict" => "insufficient_evidence"
    }
  ].freeze

  def self.cases
    Marshal.load(Marshal.dump(CASES))
  end

  def self.public_case(case_data)
    validate_case!(case_data)
    case_data.reject { |key, _| %w[oracle seeded_answer seeded_verdict].include?(key) }
  end

  def self.score(answer, case_data)
    validate_case!(case_data)
    fields = case_data.fetch("answer_fields")
    raise ArgumentError, "answer must be a hash" unless answer.is_a?(Hash)
    raise ArgumentError, "answer fields mismatch" unless answer.keys.sort == fields.sort
    raise ArgumentError, "answer values must be strings" unless answer.values.all? { |value| value.is_a?(String) }

    correct_fields = fields.count do |field|
      normalize(answer.fetch(field)) == normalize(case_data.fetch("oracle").fetch(field))
    end
    { "correct" => correct_fields == fields.length,
      "correct_fields" => correct_fields,
      "total_fields" => fields.length }
  end

  def self.validate!
    raise ArgumentError, "expected exactly 10 cases" unless CASES.length == 10
    ids = CASES.map { |item| item.fetch("id") }
    raise ArgumentError, "case ids must be unique lowercase hyphenated values" unless ids.uniq == ids && ids.all? { |id| id.match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/) }

    CASES.each { |item| validate_case!(item) }
    counts = CASES.group_by { |item| item.fetch("seeded_verdict") }.transform_values(&:length)
    expected = { "supported" => 5, "contradicted" => 3, "insufficient_evidence" => 2 }
    raise ArgumentError, "seeded verdict coverage mismatch" unless counts == expected
    raise ArgumentError, "supported seeds must match oracle" unless CASES.select { |item| item.fetch("seeded_verdict") == "supported" }.all? { |item| score(item.fetch("seeded_answer"), item)["correct"] }
    raise ArgumentError, "contradicted seeds must differ from oracle" unless CASES.select { |item| item.fetch("seeded_verdict") == "contradicted" }.all? { |item| !score(item.fetch("seeded_answer"), item)["correct"] }
    raise ArgumentError, "insufficient-evidence seeds must assert unsupported values" unless CASES.select { |item| item.fetch("seeded_verdict") == "insufficient_evidence" }.all? do |item|
      item.fetch("oracle").values.all? { |value| value == "unknown" } && item.fetch("seeded_answer").values.none? { |value| value == "unknown" }
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
      fact.is_a?(Hash) && fact.keys.sort == %w[id text] && nonempty_string?(fact["id"]) && nonempty_string?(fact["text"])
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

  def self.normalize(value)
    stripped = value.strip
    stripped.match?(/\A[+-]?(?:\d+(?:\.\d*)?|\.\d+)\z/) ? stripped : stripped.downcase
  end
  private_class_method :normalize

  def self.nonempty_string?(value)
    value.is_a?(String) && !value.strip.empty?
  end
  private_class_method :nonempty_string?
end
