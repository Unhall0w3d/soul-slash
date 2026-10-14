# frozen_string_literal: true
require "json"

# Fresh A25 task fixtures. Oracle recomputation uses only the supplied fictional
# evidence and question; free-text semantic review remains primary-side work.
module ContinuityCasesA25
  CASE_DATA = [
    {
      "id" => "a25-filter-easy", "family" => "filter_min_cost", "difficulty" => "easy",
      "question" => "Order 44 filter cartridges. Eligibility: stock >= 44 cartridges; delivery <= 4 days; rating >= 8 bar. Choose the eligible vendor with the lowest total price (unit price times 44). Return vendor and total_price in credits.",
      "evidence" => [{ "id" => "quote-fc-81", "text" => "Fictional cartridge quotes: Quote FC-81: vendor=Hearthline Supply; stock=50 cartridges; delivery=3 days; rating=10 bar; unit_price=8 credits/cartridge; setup_fee=0 credits. Quote FC-82: vendor=Orrick Works; stock=42 cartridges; delivery=2 days; rating=9 bar; unit_price=6 credits/cartridge; setup_fee=0 credits. Quote FC-83: vendor=Veylan Depot; stock=70 cartridges; delivery=5 days; rating=12 bar; unit_price=5 credits/cartridge; setup_fee=0 credits." }],
      "answer_fields" => %w[vendor total_price],
      "expected" => { "vendor" => "Hearthline Supply", "total_price" => "352 credits" },
      "oracle" => { "vendor" => "Hearthline Supply", "total_price" => "352 credits" }
    },
    {
      "id" => "a25-filter-hard", "family" => "filter_min_cost", "difficulty" => "hard",
      "question" => "Order 46 equipment tags. Eligibility: stock >= 46 tags; delivery <= 5 days; thermal rating >= 120 C. Choose the eligible vendor with the lowest total cost, including unit price times 46 plus setup_fee. Return vendor and total_cost in credits.",
      "evidence" => [{ "id" => "quote-et-27", "text" => "Fictional equipment-tag quotes: Quote ET-27: vendor=Pave Industrial; stock=60 tags; delivery=4 days; rating=125 C; unit_price=9 credits/tag; setup_fee=35 credits. Quote ET-28: vendor=Ulwen Supply; stock=80 tags; delivery=6 days; rating=180 C; unit_price=7 credits/tag; setup_fee=0 credits. Quote ET-29: vendor=Teral Goods; stock=50 tags; delivery=2 days; rating=110 C; unit_price=6 credits/tag; setup_fee=0 credits. Quote ET-30: vendor=Jasp Fabrication; stock=75 tags; delivery=5 days; rating=120 C; unit_price=10 credits/tag; setup_fee=0 credits." }],
      "answer_fields" => %w[vendor total_cost],
      "expected" => { "vendor" => "Pave Industrial", "total_cost" => "449 credits" },
      "oracle" => { "vendor" => "Pave Industrial", "total_cost" => "449 credits" }
    },
    {
      "id" => "a25-arithmetic-easy", "family" => "multi_step_arithmetic", "difficulty" => "easy",
      "question" => "Use the batch sheet to find the combined volume in all sealed drums and the volume remaining after the listed transfer. Return total_volume and remaining_volume in litres.",
      "evidence" => [{ "id" => "batch-vn-14", "text" => "Fictional wash-line batch sheet: sealed_drums=7; litres_per_drum=24; transfer_fraction=3/8." }],
      "answer_fields" => %w[total_volume remaining_volume],
      "expected" => { "total_volume" => "168 litres", "remaining_volume" => "105 litres" },
      "oracle" => { "total_volume" => "168 litres", "remaining_volume" => "105 litres" }
    },
    {
      "id" => "a25-arithmetic-hard", "family" => "multi_step_arithmetic", "difficulty" => "hard",
      "question" => "A crew processes every tray in the listed crates at the recorded rate, after the setup time. Work starts at the recorded clock time, runs continuously without breaks, and finishes the same day. Return work_duration in minutes and finish_time in 24-hour HH:MM.",
      "evidence" => [{ "id" => "workcard-qp-6", "text" => "Fictional packing work card: crates=26; trays_per_crate=4; minutes_per_tray=3; setup_minutes=18; start=07:45." }],
      "answer_fields" => %w[work_duration finish_time],
      "expected" => { "work_duration" => "330 minutes", "finish_time" => "13:15" },
      "oracle" => { "work_duration" => "330 minutes", "finish_time" => "13:15" }
    },
    {
      "id" => "a25-join-easy", "family" => "revision_join_unknown", "difficulty" => "easy",
      "question" => "Follow asset AX-417's linked job to its source register, then use only that register's current revision for lubricant_code and inspection_status. Return warranty_expiry as not stated in supplied records if no record gives a date; do not infer that coverage is false or expired.",
      "evidence" => [
        { "id" => "asset-ax-417", "text" => "Fictional asset card: asset_id=AX-417; link_id=JOB-62." },
        { "id" => "job-62", "text" => "Fictional job record: link_id=JOB-62; source_id=REG-8; subject_asset=AX-417; current_revision=REV-3." },
        { "id" => "reg-8-rev-2", "text" => "Fictional source record: source_id=REG-8; revision=REV-2; subject_asset=AX-417; lubricant_code=L-9; inspection_status=accepted." },
        { "id" => "reg-8-rev-3", "text" => "Fictional source record: source_id=REG-8; revision=REV-3; subject_asset=AX-417; lubricant_code=Vela-4; inspection_status=conditional." }
      ],
      "answer_fields" => %w[lubricant_code inspection_status warranty_expiry],
      "expected" => { "lubricant_code" => "Vela-4", "inspection_status" => "conditional", "warranty_expiry" => "not stated in supplied records" },
      "oracle" => { "lubricant_code" => "Vela-4", "inspection_status" => "conditional", "warranty_expiry" => "not stated in supplied records" }
    },
    {
      "id" => "a25-join-hard", "family" => "revision_join_unknown", "difficulty" => "hard",
      "question" => "Follow NR-531's active plan to its packet and current revision. Report the current service_interval_days as a number of days and disposition. Return warranty_end as not stated in supplied records if no record gives a date; absence is not evidence that a warranty does not exist.",
      "evidence" => [
        { "id" => "asset-nr-531", "text" => "Fictional asset card: asset_id=NR-531; link_id=PLAN-74." },
        { "id" => "plan-74", "text" => "Fictional plan record: link_id=PLAN-74; source_id=PKT-19; subject_asset=NR-531; current_revision=REV-C." },
        { "id" => "pkt-19-rev-b", "text" => "Fictional packet row: source_id=PKT-19; revision=REV-B; subject_asset=NR-531; service_interval_days=45; disposition=pass." },
        { "id" => "pkt-19-rev-c", "text" => "Fictional packet row: source_id=PKT-19; revision=REV-C; subject_asset=NR-531; service_interval_days=60; disposition=review required." },
        { "id" => "pkt-19-rev-d", "text" => "Fictional packet row: source_id=PKT-19; revision=REV-D; subject_asset=NR-531; service_interval_days=30; disposition=closed." }
      ],
      "answer_fields" => %w[service_interval_days disposition warranty_end],
      "expected" => { "service_interval_days" => "60 days", "disposition" => "review required", "warranty_end" => "not stated in supplied records" },
      "oracle" => { "service_interval_days" => "60 days", "disposition" => "review required", "warranty_end" => "not stated in supplied records" }
    }
  ].freeze

  FAMILY_COUNTS = { "filter_min_cost" => 2, "multi_step_arithmetic" => 2, "revision_join_unknown" => 2 }.freeze
  DIFFICULTY_COUNTS = { "easy" => 3, "hard" => 3 }.freeze
  UNKNOWN_ANSWER = "not stated in supplied records".freeze
  UNIT_POLICY = "Units are required literal answer content; score ignores only case and harmless whitespace, not unit/value substitutions.".freeze

  def self.cases
    deep_copy(CASE_DATA)
  end

  # Model-facing data contains no fixture labels, expected answers, or oracle.
  def self.public_case(item)
    validate_item_shape!(item)
    deep_copy("question" => item.fetch("question"), "evidence" => item.fetch("evidence"),
      "answer_fields" => item.fetch("answer_fields"))
  end

  # Validator-ready JSON Schema: all and only declared fields, each a string.
  def self.schema(item)
    validate_item_shape!(item)
    fields = item.fetch("answer_fields")
    { "type" => "object", "properties" => fields.to_h { |field| [field, { "type" => "string" }] },
      "required" => fields.dup, "additionalProperties" => false }
  end

  # Shape validity and exact correctness are separate. Harmless normalization
  # trims/collapses whitespace and ignores case; it does not alter values/units.
  def self.score(answer, item)
    validate_item_shape!(item)
    fields = item.fetch("answer_fields")
    expected = item.fetch("expected")
    hash = answer.is_a?(Hash)
    keys = hash ? answer.keys : []
    missing = fields - keys
    additional = keys - fields
    valid = hash && missing.empty? && additional.empty? && fields.all? { |field| answer[field].is_a?(String) }
    correct_fields = fields.select do |field|
      hash && answer[field].is_a?(String) && normalize(answer[field]) == normalize(expected.fetch(field))
    end
    { "valid" => valid, "correct" => valid && correct_fields.length == fields.length,
      "correct_fields" => correct_fields, "missing_fields" => missing, "additional_fields" => additional }
  end

  def self.validate!
    rows = CASE_DATA
    raise ArgumentError, "expected six A25 cases" unless rows.length == 6
    raise ArgumentError, "fixture IDs must be unique" unless rows.map { |item| item.fetch("id") }.uniq.length == rows.length
    raise ArgumentError, "unexpected family balance" unless rows.map { |item| item.fetch("family") }.tally == FAMILY_COUNTS
    raise ArgumentError, "unexpected difficulty balance" unless rows.map { |item| item.fetch("difficulty") }.tally == DIFFICULTY_COUNTS
    rows.each do |item|
      validate_item_shape!(item)
      evidence_ids = item.fetch("evidence").map { |entry| entry.fetch("id") }
      raise ArgumentError, "evidence IDs must be unique within each case" unless evidence_ids.uniq.length == evidence_ids.length
      words = ([item.fetch("question")] + item.fetch("evidence").map { |entry| entry.fetch("text") }).join(" ").split.length
      raise ArgumentError, "question/evidence exceeds 350 words" if words > 350
      computed = recompute(item)
      raise ArgumentError, "oracle mismatch for #{item.fetch('id')}" unless computed == item.fetch("expected") && computed == item.fetch("oracle")
    end
    true
  end

  def self.recompute(item)
    case item.fetch("family")
    when "filter_min_cost" then recompute_filter(item)
    when "multi_step_arithmetic" then recompute_arithmetic(item)
    when "revision_join_unknown" then recompute_join(item)
    else raise ArgumentError, "unknown family"
    end
  end
  private_class_method :recompute

  def self.recompute_filter(item)
    question = item.fetch("question")
    order = question.match(/Order (\d+) [\w-]+ ([\w-]+)\./) or raise ArgumentError, "missing order quantity"
    deadline = question.match(/delivery <= (\d+) days/) or raise ArgumentError, "missing delivery bound"
    rating_min = question.match(/rating >= (\d+) ([\w-]+)/) or raise ArgumentError, "missing rating bound"
    quantity = Integer(order[1], 10)
    unit = order[2]
    offers = item.fetch("evidence").flat_map do |entry|
      entry.fetch("text").scan(/Quote [^:]+: vendor=([^;]+); stock=(\d+) ([\w-]+); delivery=(\d+) days; rating=(\d+) ([\w-]+); unit_price=(\d+) credits\/([\w-]+); setup_fee=(\d+) credits\./)
    end
    eligible = offers.filter_map do |vendor, stock, stock_unit, days, rating, rating_unit, price, price_unit, setup|
      next unless stock_unit == unit && price_unit == unit.sub(/s\z/, "")
      next unless Integer(stock, 10) >= quantity && Integer(days, 10) <= Integer(deadline[1], 10)
      next unless rating_unit == rating_min[2] && Integer(rating, 10) >= Integer(rating_min[1], 10)
      { "vendor" => vendor, "total" => Integer(price, 10) * quantity + Integer(setup, 10) }
    end
    winner = eligible.min_by { |offer| [offer.fetch("total"), offer.fetch("vendor")] }
    raise ArgumentError, "no eligible offer" unless winner
    total_field = item.fetch("answer_fields").find { |field| field.start_with?("total_") } or raise ArgumentError, "missing total field"
    { "vendor" => winner.fetch("vendor"), total_field => "#{winner.fetch('total')} credits" }
  end
  private_class_method :recompute_filter

  def self.recompute_arithmetic(item)
    text = item.fetch("evidence").map { |entry| entry.fetch("text") }.join("\n")
    if (batch = text.match(/sealed_drums=(\d+); litres_per_drum=(\d+); transfer_fraction=(\d+)\/(\d+)/))
      drums, litres, numerator, denominator = batch.captures.map { |value| Integer(value, 10) }
      total = drums * litres
      transfer_numerator = total * numerator
      raise ArgumentError, "fractional litre result" unless (transfer_numerator % denominator).zero?
      remaining = total - transfer_numerator / denominator
      { "total_volume" => "#{total} litres", "remaining_volume" => "#{remaining} litres" }
    elsif (work = text.match(/crates=(\d+); trays_per_crate=(\d+); minutes_per_tray=(\d+); setup_minutes=(\d+); start=(\d{2}):(\d{2})/))
      crates, trays, per_tray, setup, hour, minute = work.captures.map { |value| Integer(value, 10) }
      duration = crates * trays * per_tray + setup
      finish = hour * 60 + minute + duration
      raise ArgumentError, "finish exceeds same-day bound" unless finish < 24 * 60 && hour < 24 && minute < 60
      { "work_duration" => "#{duration} minutes", "finish_time" => "%02d:%02d" % [finish / 60, finish % 60] }
    else
      raise ArgumentError, "unrecognized arithmetic evidence"
    end
  end
  private_class_method :recompute_arithmetic

  def self.recompute_join(item)
    lines = item.fetch("evidence").map { |entry| entry.fetch("text") }
    asset_line = lines.find { |line| line.start_with?("Fictional asset card:") } or raise ArgumentError, "missing asset card"
    bridge_line = lines.find { |line| line.start_with?("Fictional job record:") || line.start_with?("Fictional plan record:") } or raise ArgumentError, "missing bridge record"
    asset = parse_record(asset_line)
    bridge = parse_record(bridge_line)
    unless asset.fetch("asset_id") == bridge.fetch("subject_asset") && asset.fetch("link_id") == bridge.fetch("link_id")
      raise ArgumentError, "asset-to-bridge join mismatch"
    end
    source_lines = lines.select do |line|
      line.start_with?("Fictional source record:") || line.start_with?("Fictional packet row:")
    end
    source_rows = source_lines.map { |line| parse_record(line) }
    matching = source_rows.select do |row|
      row.fetch("source_id") == bridge.fetch("source_id") && row.fetch("subject_asset") == asset.fetch("asset_id") &&
        row.fetch("revision") == bridge.fetch("current_revision")
    end
    raise ArgumentError, "current revision must join exactly once" unless matching.length == 1
    current = matching.first
    item.fetch("answer_fields").to_h do |field|
      value = case field
              when "lubricant_code", "inspection_status", "disposition" then current.fetch(field)
              when "service_interval_days" then "#{current.fetch(field)} days"
              when "warranty_expiry", "warranty_end"
                source_rows.any? { |row| row.key?(field) } ? current.fetch(field) : UNKNOWN_ANSWER
              else raise ArgumentError, "unsupported joined field #{field}"
              end
      [field, value]
    end
  end
  private_class_method :recompute_join

  def self.parse_record(line)
    line.split(": ", 2).fetch(1).split("; ").to_h do |pair|
      key, value = pair.split("=", 2)
      raise ArgumentError, "malformed record" unless key && value
      [key, value.sub(/\.\z/, "")]
    end
  end
  private_class_method :parse_record

  def self.validate_item_shape!(item)
    keys = %w[id family difficulty question evidence answer_fields expected oracle]
    raise ArgumentError, "invalid A25 fixture shape" unless item.is_a?(Hash) && item.keys.sort == keys.sort
    fields = item.fetch("answer_fields")
    raise ArgumentError, "invalid answer fields" unless fields.is_a?(Array) && !fields.empty? &&
      fields.length <= 3 && fields.uniq == fields && fields.all? { |field| field.is_a?(String) }
    %w[expected oracle].each do |key|
      value = item.fetch(key)
      raise ArgumentError, "#{key} must exactly cover answer fields" unless value.is_a?(Hash) &&
        value.keys.sort == fields.sort && value.values.all? { |entry| entry.is_a?(String) }
    end
    evidence = item.fetch("evidence")
    raise ArgumentError, "invalid evidence" unless evidence.is_a?(Array) && !evidence.empty? &&
      evidence.all? { |entry| entry.is_a?(Hash) && entry.keys.sort == %w[id text] && entry.values.all? { |value| value.is_a?(String) } }
    raise ArgumentError, "invalid question" unless item.fetch("question").is_a?(String) && !item.fetch("question").empty?
    raise ArgumentError, "invalid fixture identity" unless %w[id family difficulty].all? { |field| item.fetch(field).is_a?(String) }
    true
  end
  private_class_method :validate_item_shape!

  def self.normalize(value)
    value.strip.split(/\s+/).join(" ").downcase
  end
  private_class_method :normalize

  def self.deep_copy(value)
    JSON.parse(JSON.generate(value))
  end
  private_class_method :deep_copy
end
