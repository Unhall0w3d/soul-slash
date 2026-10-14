# frozen_string_literal: true

# Synthetic source answers for a review-protocol comparison. Each field is one
# claim; source labels and expected audit results stay outside public prompts.
module AmdReviewerCasesM3c
  CLAIMS = %w[supported contradicted insufficient_evidence].freeze
  VERDICTS = %w[supported contradicted insufficient_evidence mixed].freeze
  PUBLIC_FIELDS = %w[question evidence answer_fields format_rules].freeze

  CASES = [
    {
      "id" => "seedling-tray-inventory",
      "question" => "Return tray_count as a bare number and cultivar exactly as written. How many trays are listed for this cultivar?",
      "evidence" => [{ "id" => "tray-ledger-61", "text" => "Inventory row TR-61: cultivar Amber-6; tray_count 12." }],
      "answer_fields" => %w[tray_count cultivar],
      "source_answer" => { "tray_count" => "12", "cultivar" => "Amber-6" },
      "oracle" => { "tray_count" => "12", "cultivar" => "Amber-6" },
      "expected_claims" => { "tray_count" => "supported", "cultivar" => "supported" },
      "expected_verdict" => "supported", "category" => "semantic", "format_rules" => {}
    },
    {
      "id" => "ferry-slip-current-dock",
      "question" => "Return dock_code exactly as listed and boarding_state exactly as recorded. What appears on slip FS-28?",
      "evidence" => [{ "id" => "ferry-slip-fs28", "text" => "Ferry slip FS-28 lists dock_code D-4 and boarding_state queued." }],
      "answer_fields" => %w[dock_code boarding_state],
      "source_answer" => { "dock_code" => "D-4", "boarding_state" => "queued" },
      "oracle" => { "dock_code" => "D-4", "boarding_state" => "queued" },
      "expected_claims" => { "dock_code" => "supported", "boarding_state" => "supported" },
      "expected_verdict" => "supported", "category" => "semantic", "format_rules" => {}
    },
    {
      "id" => "microscope-filter-record",
      "question" => "Return filter_grade exactly as listed and replacement_date as YYYY-MM-DD or the literal unknown. What is recorded for microscope MX-5?",
      "evidence" => [{ "id" => "microscope-maintenance-mx5", "text" => "Microscope MX-5 has filter_grade B. The maintenance card has no replacement date entered." }],
      "answer_fields" => %w[filter_grade replacement_date],
      "source_answer" => { "filter_grade" => "B", "replacement_date" => "unknown" },
      "oracle" => { "filter_grade" => "B", "replacement_date" => "unknown" },
      "expected_claims" => { "filter_grade" => "supported", "replacement_date" => "supported" },
      "expected_verdict" => "supported", "category" => "semantic", "format_rules" => {}
    },
    {
      "id" => "kilometer-marker-location",
      "question" => "Return marker_id exactly as listed and distance_km as a bare number. Which marker is at kilometer 18?",
      "evidence" => [
        { "id" => "road-marker-r18", "text" => "Road marker R-18 is at kilometer 18. Road marker R-81 is at kilometer 81." },
        { "id" => "marker-inventory", "text" => "The inventory identifies the kilometer-18 marker as R-18." }
      ],
      "answer_fields" => %w[marker_id distance_km],
      "source_answer" => { "marker_id" => "R-81", "distance_km" => "81" },
      "oracle" => { "marker_id" => "R-18", "distance_km" => "18" },
      "expected_claims" => { "marker_id" => "contradicted", "distance_km" => "contradicted" },
      "expected_verdict" => "contradicted", "category" => "semantic", "format_rules" => {}
    },
    {
      "id" => "stage-light-color",
      "question" => "Return gel_color exactly as recorded. What gel is fitted to light L-12?",
      "evidence" => [{ "id" => "light-check-l12", "text" => "The inspection sheet for light L-12 records gel_color amber." }],
      "answer_fields" => ["gel_color"],
      "source_answer" => { "gel_color" => "blue" },
      "oracle" => { "gel_color" => "amber" },
      "expected_claims" => { "gel_color" => "contradicted" },
      "expected_verdict" => "contradicted", "category" => "semantic", "format_rules" => {}
    },
    {
      "id" => "sealed-cassette-state",
      "question" => "Return cassette_state exactly as recorded. What is the state of cassette C-44?",
      "evidence" => [{ "id" => "cassette-check-c44", "text" => "Cassette C-44 is listed as sealed, not open." }],
      "answer_fields" => ["cassette_state"],
      "source_answer" => { "cassette_state" => "open" },
      "oracle" => { "cassette_state" => "sealed" },
      "expected_claims" => { "cassette_state" => "contradicted" },
      "expected_verdict" => "contradicted", "category" => "semantic", "format_rules" => {}
    },
    {
      "id" => "unlogged-sample-acidity",
      "question" => "Return acidity as a pH value or the literal unknown if no reading is recorded. What is the acidity of sample SA-9?",
      "evidence" => [{ "id" => "sample-sa9-note", "text" => "Sample SA-9 was collected and sealed. No pH reading appears on its record." }],
      "answer_fields" => ["acidity"],
      "source_answer" => { "acidity" => "6.8" },
      "oracle" => { "acidity" => "unknown" },
      "expected_claims" => { "acidity" => "insufficient_evidence" },
      "expected_verdict" => "insufficient_evidence", "category" => "semantic", "format_rules" => {}
    },
    {
      "id" => "unrecorded-ballot-total",
      "question" => "Return ballot_total as a bare number or the literal unknown if the count is absent. How many ballots were deposited in box BX-3?",
      "evidence" => [{ "id" => "box-bx3-seal-log", "text" => "Box BX-3 was sealed at closing. Its seal log does not include a ballot count." }],
      "answer_fields" => ["ballot_total"],
      "source_answer" => { "ballot_total" => "47" },
      "oracle" => { "ballot_total" => "unknown" },
      "expected_claims" => { "ballot_total" => "insufficient_evidence" },
      "expected_verdict" => "insufficient_evidence", "category" => "semantic", "format_rules" => {}
    },
    {
      "id" => "absent-workshop-facilitator",
      "question" => "Return facilitator exactly as named or the literal unknown if no name is recorded. Who facilitated workshop W-16?",
      "evidence" => [{ "id" => "workshop-w16-attendance", "text" => "Workshop W-16 attendance is recorded for 14 participants. The attendance sheet has no facilitator field." }],
      "answer_fields" => ["facilitator"],
      "source_answer" => { "facilitator" => "Ira Moss" },
      "oracle" => { "facilitator" => "unknown" },
      "expected_claims" => { "facilitator" => "insufficient_evidence" },
      "expected_verdict" => "insufficient_evidence", "category" => "semantic", "format_rules" => {}
    },
    {
      "id" => "invoice-payment-and-approver",
      "question" => "What is invoice IV-33's payment_state, and who was its approver? Return the state and person's name, using the literal unknown for any value not established by evidence.",
      "evidence" => [
        { "id" => "invoice-iv33-ledger", "text" => "Invoice IV-33 has payment_state unpaid." },
        { "id" => "invoice-iv33-approval", "text" => "The approval panel for invoice IV-33 is blank; no approver is named." }
      ],
      "answer_fields" => %w[payment_state approver],
      "source_answer" => { "payment_state" => "paid", "approver" => "Mara Venn" },
      "oracle" => { "payment_state" => "unpaid", "approver" => "unknown" },
      "expected_claims" => { "payment_state" => "contradicted", "approver" => "insufficient_evidence" },
      "expected_verdict" => "mixed", "category" => "semantic", "format_rules" => {}
    },
    {
      "id" => "pump-port-and-service-date",
      "question" => "What is pump PU-7's outlet_code, and on what service_date was it serviced? Return the code and YYYY-MM-DD, using the literal unknown for any value not established by evidence.",
      "evidence" => [
        { "id" => "pump-pu7-plate", "text" => "Pump PU-7 outlet_code is OUT-B." },
        { "id" => "pump-pu7-service-card", "text" => "Pump PU-7 has a service card, but its service_date box is empty." }
      ],
      "answer_fields" => %w[outlet_code service_date],
      "source_answer" => { "outlet_code" => "OUT-A", "service_date" => "2026-08-14" },
      "oracle" => { "outlet_code" => "OUT-B", "service_date" => "unknown" },
      "expected_claims" => { "outlet_code" => "contradicted", "service_date" => "insufficient_evidence" },
      "expected_verdict" => "mixed", "category" => "semantic", "format_rules" => {}
    },
    {
      "id" => "delivery-condition-and-recipient",
      "question" => "What was parcel PK-52's package_condition on arrival, and who was its recipient? Return the condition and person's name, using the literal unknown for any value not established by evidence.",
      "evidence" => [
        { "id" => "parcel-pk52-condition", "text" => "Parcel PK-52 was logged as damp on arrival." },
        { "id" => "parcel-pk52-signoff", "text" => "The recipient signature line for parcel PK-52 is blank." }
      ],
      "answer_fields" => %w[package_condition recipient],
      "source_answer" => { "package_condition" => "dry", "recipient" => "Tomas Reed" },
      "oracle" => { "package_condition" => "damp", "recipient" => "unknown" },
      "expected_claims" => { "package_condition" => "contradicted", "recipient" => "insufficient_evidence" },
      "expected_verdict" => "mixed", "category" => "semantic", "format_rules" => {}
    },
    {
      "id" => "compost-bin-mass-format",
      "question" => "Return mass as a number followed by 'kg'. How many kilograms of compost are in bin CB-2?",
      "evidence" => [{ "id" => "compost-bin-cb2-scale", "text" => "Scale record for bin CB-2: net compost mass is 4.25 kg." }],
      "answer_fields" => ["mass"],
      "source_answer" => { "mass" => "4.25" },
      "oracle" => { "mass" => "4.25 kg" },
      "expected_claims" => { "mass" => "supported" },
      "expected_verdict" => "supported", "category" => "format_only", "format_rules" => { "mass" => { "unit" => "kg" } }
    },
    {
      "id" => "cistern-volume-format",
      "question" => "Return volume as a number followed by 'L'. How many liters were measured in cistern CT-8?",
      "evidence" => [{ "id" => "cistern-ct8-meter", "text" => "Meter record for cistern CT-8: collected volume is 16 L." }],
      "answer_fields" => ["volume"],
      "source_answer" => { "volume" => "16" },
      "oracle" => { "volume" => "16 L" },
      "expected_claims" => { "volume" => "supported" },
      "expected_verdict" => "supported", "category" => "format_only", "format_rules" => { "volume" => { "unit" => "L" } }
    }
  ].freeze

  def self.cases
    Marshal.load(Marshal.dump(CASES))
  end

  def self.public_case(item)
    validate_case!(item)
    PUBLIC_FIELDS.to_h { |field| [field, Marshal.load(Marshal.dump(item.fetch(field)))] }
  end

  def self.score(answer, item)
    validate_case!(item)
    fields = item.fetch("answer_fields")
    raise ArgumentError, "answer must be a hash" unless answer.is_a?(Hash)
    raise ArgumentError, "answer fields mismatch" unless answer.keys.sort == fields.sort
    raise ArgumentError, "answer values must be nonempty strings" unless answer.values.all? { |value| nonempty_string?(value) }

    correct_fields = fields.count { |field| normalize(answer.fetch(field)) == normalize(item.fetch("oracle").fetch(field)) }
    { "correct" => correct_fields == fields.length,
      "correct_fields" => correct_fields,
      "total_fields" => fields.length }
  end

  def self.validate!
    raise ArgumentError, "expected exactly 14 cases" unless CASES.length == 14
    ids = CASES.map { |item| item.fetch("id") }
    raise ArgumentError, "case ids must be unique lowercase hyphenated values" unless ids.uniq == ids && ids.all? { |id| id.match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/) }

    CASES.each { |item| validate_case!(item) }
    semantic = CASES.select { |item| item.fetch("category") == "semantic" }
    counts = semantic.group_by { |item| item.fetch("expected_verdict") }.transform_values(&:length)
    raise ArgumentError, "semantic verdict coverage mismatch" unless counts == { "supported" => 3, "contradicted" => 3, "insufficient_evidence" => 3, "mixed" => 3 }
    raise ArgumentError, "expected two format-only cases" unless CASES.count { |item| item.fetch("category") == "format_only" } == 2
    raise ArgumentError, "all oracle answers must score exactly" unless CASES.all? { |item| score(item.fetch("oracle"), item).fetch("correct") }
    true
  end

  def self.validate_case!(item)
    raise ArgumentError, "case must be a hash" unless item.is_a?(Hash)
    required = %w[id question evidence answer_fields source_answer oracle expected_claims expected_verdict category format_rules]
    raise ArgumentError, "case shape mismatch" unless item.keys.sort == required.sort
    raise ArgumentError, "invalid case id" unless nonempty_string?(item["id"]) && item.fetch("id").match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/)
    raise ArgumentError, "question must be nonempty" unless nonempty_string?(item["question"])
    raise ArgumentError, "invalid expected verdict" unless VERDICTS.include?(item["expected_verdict"])
    raise ArgumentError, "invalid category" unless %w[semantic format_only].include?(item["category"])

    evidence = item.fetch("evidence")
    raise ArgumentError, "evidence must be a nonempty array" unless evidence.is_a?(Array) && !evidence.empty?
    raise ArgumentError, "invalid evidence entry" unless evidence.all? do |fact|
      fact.is_a?(Hash) && fact.keys.sort == %w[id text] && nonempty_string?(fact["id"]) && nonempty_string?(fact["text"]) && fact.fetch("text").length < 1400
    end
    raise ArgumentError, "evidence ids must be unique within a case" unless evidence.map { |fact| fact.fetch("id") }.uniq.length == evidence.length

    fields = item.fetch("answer_fields")
    raise ArgumentError, "invalid answer fields" unless fields.is_a?(Array) && (1..3).cover?(fields.length) && fields.uniq == fields &&
      fields.all? { |field| field.is_a?(String) && field.match?(/\A[a-z][a-z0-9_]*\z/) }
    %w[source_answer oracle expected_claims].each do |key|
      values = item.fetch(key)
      raise ArgumentError, "#{key} keys mismatch" unless values.is_a?(Hash) && values.keys.sort == fields.sort
    end
    %w[source_answer oracle].each do |key|
      raise ArgumentError, "#{key} values must be nonempty strings" unless item.fetch(key).values.all? { |value| nonempty_string?(value) }
    end
    raise ArgumentError, "invalid expected claim" unless item.fetch("expected_claims").values.all? { |claim| CLAIMS.include?(claim) }

    rules = item.fetch("format_rules")
    raise ArgumentError, "format_rules must be a hash" unless rules.is_a?(Hash)
    raise ArgumentError, "invalid format rule fields" unless (rules.keys - fields).empty?
    raise ArgumentError, "invalid format rule" unless rules.all? do |field, rule|
      rule.is_a?(Hash) && rule.keys == ["unit"] && %w[kg L].include?(rule["unit"])
    end
    validate_claim_consistency!(item)
    true
  end
  private_class_method :validate_case!

  def self.validate_claim_consistency!(item)
    claims = item.fetch("expected_claims")
    source = item.fetch("source_answer")
    oracle = item.fetch("oracle")
    if item.fetch("category") == "format_only"
      raise ArgumentError, "format-only claims must be supported" unless claims.values.all? { |claim| claim == "supported" } && item.fetch("expected_verdict") == "supported"
      raise ArgumentError, "format-only rules must cover every field" unless item.fetch("format_rules").keys.sort == item.fetch("answer_fields").sort
      item.fetch("answer_fields").each do |field|
        value = source.fetch(field)
        unit = item.fetch("format_rules").fetch(field).fetch("unit")
        raise ArgumentError, "format-only source must omit its required unit" unless value.match?(/\A\d+(?:\.\d+)?\z/) && normalize(oracle.fetch(field)) == normalize("#{value} #{unit}")
      end
    else
      raise ArgumentError, "semantic cases cannot declare format rules" unless item.fetch("format_rules").empty?
      item.fetch("answer_fields").each do |field|
        claim = claims.fetch(field)
        source_value = normalize(source.fetch(field))
        oracle_value = normalize(oracle.fetch(field))
        valid = case claim
                when "supported" then source_value == oracle_value
                when "contradicted" then oracle_value != "unknown" && source_value != oracle_value
                when "insufficient_evidence" then oracle_value == "unknown" && source_value != "unknown"
                end
        raise ArgumentError, "claim/oracle consistency mismatch" unless valid
      end
    end
    raise ArgumentError, "aggregate verdict mismatch" unless aggregate(claims.values) == item.fetch("expected_verdict")
    true
  end
  private_class_method :validate_claim_consistency!

  def self.aggregate(claims)
    has_contradicted = claims.include?("contradicted")
    has_insufficient = claims.include?("insufficient_evidence")
    return "mixed" if has_contradicted && has_insufficient
    return "contradicted" if has_contradicted
    return "insufficient_evidence" if has_insufficient

    "supported"
  end
  private_class_method :aggregate

  def self.normalize(value)
    value.strip.downcase
  end
  private_class_method :normalize

  def self.nonempty_string?(value)
    value.is_a?(String) && !value.strip.empty?
  end
  private_class_method :nonempty_string?
end
