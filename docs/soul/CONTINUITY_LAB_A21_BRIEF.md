# Continuity A21: source-verified deterministic selection helper

Date: 2026-10-12. The owner's "okay, agreed, lets continue" accepts the A20
recommendation: implement a small bounded comparison/calculation helper with
source-checked inputs, refusals and a result separate from generated prose.
This is an opt-in foreground library/CLI, not a runtime/default promotion or
permission to start another live-Qwen window. No service, GPU, ordinary-memory,
worker protocol, journal format, dashboard or autonomous continuation changes.

## Scope and boundaries

Primary owns the parser, request-validation boundary, pure computation and CLI.
A worker may implement pure contract tests and synthetic fixtures in its assigned
new verifier only. Preserve all dirty work, previous profiles and evidence.

`VerifiedSelection.evaluate(source:, request:, proposal: nil)` consumes one
complete, already selected DirectEvidence-style corpus record. Verify exact
metadata fields, ID, lineage, revision, full character span, UTF-8 text, size and
SHA256. A digest binds supplied bytes; it does not authenticate their origin,
truth, freshness or completeness beyond this selected document. The trusted
caller selects source and request. Model proposals may not replace either.

Parse the entire supported catalog, not selected matching substrings. Initial
grammar: an ASCII heading ending in `catalog.`, followed by one or more
`Option label: attribute, attribute.` rows. Labels are unique (case-insensitive),
all rows have identical field/unit sets, and no unparsed text is permitted.
At most 32 options, 12 fields each, 8192 source-text bytes. Recognized attributes:
shelves; crowns or credits; watts; cubic meters per hour; decibels; hours or
minutes (runtime); in/out of stock; kilowatt-hours or watt-hours; height in
centimeters or meters; pages per minute; drive bays; setup in minutes or hours.
Normalize explicit units, never currencies. Nonnegative finite decimal literals
have at most nine whole digits and six decimal digits; counts must be integers.
Use exact Rational arithmetic, not floating-point ranking. Preserve each
attribute's original quote and character span, including normalized units.
Outputs use exact finite decimal strings where possible, otherwise a rational
string such as `1/6` hours for ten minutes; normalized proposals must match them.
Unknown syntax, duplicate fields/labels, incomplete rows, mixed currencies,
oversized input and empty catalogs refuse rather than producing a partial result.

The request is explicitly structured, not claimed to be a verified translation
of free-form conversation. Exact keys: `version: selection_request_v1`,
`source_ref` (lineage_id, id, revision, content_digest), `constraints`,
`objective`; optional `totals`. Up to eight constraints have exact
`field`, `op` (`gte`, `lte`, `eq`), `value` and `unit`. Numeric values are decimal
strings in canonical units; stock is boolean with unit `boolean` and `eq` only.
Fields/units must exist in every source row. Reject contradictory or duplicate
constraints. Objective: exact `field`, `direction` (`min` or `max`), numeric only.
Optional totals: exact `quantity` (integer 1..1000000), `fields` (unique numeric
field list). This is scalar multiplication for each selected option, not bundle
optimization or a claim that physical properties combine usefully.

Canonical fields/units: shelves/count, price/crowns or credits, power/W,
airflow/m3/h, noise/dB, runtime/h, stock/boolean, capacity/kWh, height/cm,
speed/pages/min, bays/count, setup/min. Do not silently infer units or tie-break.
Return every equal optimum as a tie, or an explicit no-eligible result.

If an optional model-proposed table is supplied, it must contain all options and
all fields exactly: array of `option`, `values`, where each field has only `value`
and `unit`. Compare it to deterministic source extraction; reject missing,
invented, reordered-association or changed values. Proposal row/field order is
irrelevant. There is no proposal-provided authority or automatic promotion.

## Output and runnable path

Success is `state: complete`, `reason: selected|tie|none_eligible`, all parsed
options with eligibility, all winners, verified objective, optional totals,
source binding and request digest. Refusal is `state: awaiting_input` plus a
stable reason and no selected options. Verification scope is only computation
over the supplied source and explicit request, not external truth or model thought.

`VerifiedSelection.present(source:, request:, proposal: nil, explanation: nil)`
returns separate `verified_result` and `generated_explanation` fields. The latter
is null or explicitly labeled unverified text; it cannot replace computed fields.
No generated text is executed, treated as an instruction or written to memory.

`scripts/continuity-lab-select.rb` accepts one bounded JSON object on stdin:
source/request, optionally proposal/explanation. Reject unknown/duplicate keys,
non-JSON values, nesting/size excess and stalled input. Print one JSON result to
stdout; exit 0 for complete, 2 for refusal. No file/path/URL discovery or writes,
network, shell/tool execution, inference or process left waiting after return.
No free-form automatic chat routing in A21; that would require a separately
qualified interpretation boundary. Supply an executable synthetic example.

## Required evidence

- Independent synthetic tests for lower/upper/equality and combined constraints,
  min/max, exact decimals, supported unit conversions, ties, no eligible options,
  scalar totals, source spans and metadata, schema/size bounds, contradictory
  requests, malformed rows and verified-versus-generated separation.
- Tampered source/digest/reference and model-proposal cases must refuse.
  Exercise duplicate JSON keys, bounded CLI input, CLI complete/refusal exits,
  and no mutation of caller data. Safety is deterministic, never model-judged.
- Re-evaluate the eight A20 catalogs with explicit operator-authored structured
  contracts and unchanged source bytes. Compare with retained historical A20
  replies, labeled a retrospective fixture replay, not a fresh controlled model
  comparison or proof of natural-language interpretation. Preserve all old files.
- Run pinned Ruby 4.0.7 syntax, new helper/verifier/CLI checks, A20 case checks and
  pure A20 projection regressions; replay old stores and verify historical hashes.
  No broad unchanged isolation/model test suite or live calls needed because
  existing runtime interfaces are unchanged.
- Update A21 review, adaptation plan, human review gate and candidate review.
  Retain test/replay receipts locally under a new qualification directory.

Acceptance: the documented opt-in helper is runnable and correct/refusing on the
declared contract. This does not qualify ordinary conversation integration,
production deployment, live model explanations, restart continuity or personhood.
