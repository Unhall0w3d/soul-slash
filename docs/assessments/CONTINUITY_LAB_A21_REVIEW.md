# Continuity Lab A21: source-verified deterministic selection

Date: 2026-10-12. Status: opt-in foreground helper/CLI implemented and
deterministically qualified; **not automatic chat integration or release**.
Authority: [A21 brief](../soul/CONTINUITY_LAB_A21_BRIEF.md), accepted by the
owner's "okay, agreed, lets continue" following the A20 recommendation.

## Outcome

The helper solves **8/8 retained A20 catalog fixtures** using explicit structured
requests and the original source bytes. It adds no model calls, instructions,
tools, memory or autonomy to the existing model runtime. The A19 chat and A20
guided-chat baselines are unchanged.

This is a retrospective fixture replay, not a fresh model comparison. Historical
clean selection counts remain chat 3/8 and guided chat 4/8; the guided height
answer still has a correct conclusion after a false opening. The helper's 8/8
result establishes deterministic computation for the supplied contracts, **not**
successful natural-language interpretation or improved model intelligence.

| Retained fixture | Verified result |
| --- | --- |
| At least 28 shelves, lowest price | Borlen rack, 69 crowns |
| At most 18 watts, lowest price | Corda router, 68 crowns |
| Airflow at least 240 and noise at most 38, lowest price | Neris purifier, 96 crowns |
| In stock, runtime at least 9 hours, lowest price | Tovin lantern, 57 crowns |
| At most 650 crowns, greatest capacity | Brel battery, 8 kWh |
| Height 140-180 cm inclusive, lowest price | Falen shelf, 61 crowns |
| At least 85 pages/minute | No eligible option |
| At least 4 bays and at most 500 crowns, shortest setup | Quorin NAS, 28 minutes |

## What the helper guarantees, and what it does not

`VerifiedSelection.evaluate` consumes one explicitly selected complete source
record and a structured request bound to its ID, lineage, revision and SHA256.
It parses every row in a small documented catalog grammar, preserving each
attribute's original quote and character span. All rows must have the same
field/unit schema. Unsupported or partial extraction refuses; it cannot silently
drop a cheaper option. This covers the supplied document, not unseen catalogs.

Numeric comparisons and requested quantity products use exact Rational
arithmetic. Supported units are normalized, currencies are never converted,
ties return all equal optima, and an empty eligible set is a successful explicit
answer. An empty/malformed source, contradictory request, unsupported field or
unit, duplicate metadata/fields or a mismatched source binding refuses.
Totals are explicit scalar products, not bundle optimization or a claim that
independent devices' capacities combine physically.

An optional proposed table must match every extracted option/field/value/unit;
missing rows, changed values and swapped associations fail verification. A model
proposal never supplies source authority. The caller must select the genuine
source and explicit request: self-consistent hashes alone do not authenticate
origin, freshness, truth or intended meaning. A free-form model translation of
the user's request is **not** automatically verified by this helper.

`VerifiedSelection.present` exposes separate `verified_result` and
`generated_explanation` fields. Text in the latter is explicitly marked
`unverified_model_text`; it cannot overwrite the selected option, objective,
source or computation. The replay deliberately pairs computed results with old
incorrect model replies to demonstrate this separation. It does not demonstrate
that a live model can faithfully explain a computed result.

## Runnable example

From any directory, using the repository-pinned interpreter:

```bash
/home/bhones/.rbenv/versions/4.0.7/bin/ruby \
  /home/bhones/Projects/soul/scripts/continuity-lab-select.rb \
  < /home/bhones/Projects/soul/docs/examples/continuity-lab-selection-a21.json
```

Expected: `verified_result.state` is `complete`, winner `Corda router`, minimum
price `68` crowns, and `generated_explanation` is null. This example was executed
successfully with exit 0. Its input is synthetic, not real purchasing advice.

The CLI accepts only source/request and optional proposal/explanation in JSON
on stdin. See the [brief](../soul/CONTINUITY_LAB_A21_BRIEF.md) and
[example](../examples/continuity-lab-selection-a21.json) for the exact contract.
Exit 0 covers selected/tie/none-eligible outcomes; exit 2 means awaiting corrected
input. Input is limited to 32 KiB, depth 24, and a five-second read timeout.
Duplicate JSON keys, invalid UTF-8, unknown keys and excess sizes refuse. The
pure library and CLI do not discover paths, open URLs, use inference, execute
commands, write files or memory, or leave a process waiting after return.

Initial source support is deliberately narrow: ASCII catalog headings and
`Label: attribute, attribute.` rows with recognized numeric units/stock values.
It is not a general document parser. Requests must state constraints and the
objective explicitly. General prose, automatic chat routing, arbitrary math,
subjective preferences and unknown units are not supported by this candidate.

## Validation and findings

Pinned Ruby 4.0.7: **59 grouped checks pass**: 17 new helper/CLI groups, 34 A20
fixture checks and eight pure A20 projection regressions. Four new Ruby files
pass syntax. Eight retrospective fixtures and the example CLI smoke also pass;
they are not counted again in the 59. No live-Qwen generation or model restart.

New tests cover bound/equality/combined constraints, min/max, ties and no eligible
option, exact decimals and fractions, supported unit conversions, scalar totals,
source spans and metadata, full table validation, mixed units/currencies,
malformed input, size/schema limits, contradictory constraints, model-proposal
tampering, caller nonmutation, separate explanation output, CLI exits and a
five-second stalled-input termination test. Safety is checked deterministically.

Primary review found three concrete gaps in the initial helper: Ruby accepted
integer-equivalent float spans and reference revisions through equality, and
invalid UTF-8 lineage text raised during regex matching. All three were repaired
with explicit type/encoding validation and deterministic regression checks.
These were input-validation defects, not failures in the eight fixture winners.
Several initial delegated test fixtures also contradicted the declared grammar
or contract; they were corrected without weakening valid requirements. Failure
and correction notes are retained in the development receipt and chat tool log.

The read-only mapper traced existing source/result seams; primary implemented
all parsing, validation, computation, presentation and CLI boundaries. Luna
implemented the owned synthetic verifier; primary reviewed and extended it.
No worker received runtime, privilege, persistence or promotion authority.

All **4,130 pre-A21 evidence files** and **90 existing Continuity source/script
files** are unchanged. All **155 existing stores** replay; no store was created
or modified by the helper. New receipts live under:
`Soul/runtime/qualification/continuity-lab-a21-development-20261012/`.
They include the prechange inventory digest, replay, validation and closeout.
Unrelated dirty work, original baselines, historical failures and model settings
remain intact. No deployment, ordinary-memory, service or default promotion.

## Next recommendation

The computation boundary is now usable. Next evaluate the **request-formation
boundary**: can Qwen propose a faithful structured request for a supported
question, and can unsupported/ambiguous questions be reliably withheld from
automatic use? A model-written request must remain a proposal until its meaning
is established; the helper cannot prove that a changed budget matches the user.
Begin with an explicit review/confirmation of the proposed constraints, showing
the verified result separately. Preserve the model-only baseline and separately
score request fidelity, computation and explanation fidelity.

That integration and any fresh bounded model trial remain separate next work.
No automatic routing, live model explanation or production acceptance is claimed
here. Actual model-server restart continuity and owner acceptance remain open.
