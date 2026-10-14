# Continuity Lab A20: general filter-then-compare guidance

Date: 2026-10-12. Status: approved implementation and single foreground comparison
complete; small observed gain, **not everyday reliability or release**. Authority:
[A20 brief](../soul/CONTINUITY_LAB_A20_BRIEF.md).

## Outcome and decision

The added general instruction produced one clean new success and one answer with
a correct final choice after a false opening claim. None of the three inherited
selection failures was repaired. Keep A19 chronological chat as the opt-in
experimental baseline; retain the A20 candidate and evidence without promotion.
Do not keep adding prompt layers or silently rerun the completed comparison.

| Measure | Unchanged chat | Chat plus selection guidance |
| --- | --- | --- |
| Clean factual answers / 28 | 20 | 21 |
| Correct final conclusions / 28 | 20 | 22, including one flawed explanation |
| Inherited factual answers / 20 | 17 | 17 |
| Fresh clean selections / 8 | 3 | 4 |
| Fresh correct final selections / 8 | 3 | 5, including that same flawed answer |
| Correct callbacks / 7, included in factual count | 7 | 7 |
| Appropriate unknown-fact answers / 4 | 4 | 4 |
| Replies / 36 scheduled | 36 | 36 |
| Frozen mechanical screen passes / 36 | 27 | 29 |

Each condition also had three adequate but generic social turns and one passing
uppercase control, outside the factual denominator. Social replies assume
positive feelings and judge hot chocolate as better; they do not establish a
general conversational-quality gain. No physical-action claim was observed.

All thirty batches completed in **805.094 seconds / 72 generations**. No
infrastructure failure, skipped prerequisite, unstarted case or second attempt.
Exit 1 reports behavioral screen failures, not an incomplete execution.

## Exact intervention and limits

The new opt-in `direct_evidence_checked_chat_v1` profile appends the fixed general
selection instruction in the brief to A19's system guidance. It asks for eligible
options to be identified before optimizing and for a check against requirements
and alternatives. It contains no case names, thresholds or expected answers.
The original `direct_evidence_chat_v1` remains unchanged. Both use the same v9
configuration, chronological roles, complete source data, recent-dialogue policy,
escaping, actual-token preparation, grammar, one-call/zero-tool limits and strict
reply validation. Fixed run/resume modes reject cross-profile binding before
worker launch. No new configuration schema, persistence policy or default.

Same installed Qwen3-8B-Q4_K_M, GTX 1070 8 GiB, llama.cpp b9851-0eca4d490,
sampler, thinking disabled, 4096 context / 3072 input / 768 output reserve.
The existing model-service PID 3065 was freshly observed and pinned; it was not
restarted. Fifteen independent stores per condition, fresh isolated worker per
request, alternating condition order by batch. All 28 A19 cases were retained;
eight fresh independent catalogs cover bounds, combined constraints, availability,
maximization and no eligible option. Each fresh case starts with empty history.
Code, prompts, cases, scoring and order were frozen before inference.

One request per condition is not a reliability estimate. This does not establish
that prompt guidance generally helps, that the model internally performed its
stated checks, or that every larger/reasoning model would solve these cases.
Histories may diverge through generated replies. This is not a persistent versus
restarted model-server comparison and says nothing about subjective continuity.

## Semantic findings

The separate `primary-assessment.json` retains all 36 paired case assessments,
actual replies and original mechanical scores. It does not rewrite the scorer.

| Fresh selection | Correct answer | Chat | With guidance |
| --- | --- | --- | --- |
| Minimum shelves | Borlen, 28 shelves / 69 crowns | Correct | Correct |
| Maximum power | Corda, 18 watts / 68 crowns | Deyra / 82, not cheapest | Same error |
| Airflow and noise | Neris, 248 cubic metres/hour / 36 dB / 96 crowns | Pavor / 109, not cheapest | Correct |
| Stock and runtime | Tovin, in stock / 9 hours / 57 crowns | Correct | Correct |
| Maximum capacity within budget | Brel, 8 kWh / 638 crowns | Cevra / 704, exceeds budget | Same error |
| Inclusive height range | Falen, 145 cm / 61 crowns | Halen / 188 cm, outside range | Correct final answer, contradictory opening |
| No eligible printer | None reaches 85 pages/minute | Correct | Correct |
| Shortest setup within limits | Quorin, 5 bays / 28 minutes / 482 crowns | Orin / 32 minutes, not quickest | Same error |

The guided height answer first states that Halen is the cheapest within 140-180
cm, immediately acknowledges its 188 cm height is outside the range, then
correctly selects Falen. Count its final conclusion, but do not count the whole
answer as clean. An expected-name/price regex passed this flawed explanation.
Conversely, both printer answers correctly say none reach the threshold, but
their lack of the literal word "qualify" fails the frozen mechanical check.
These are two separate scoring limitations, not reasons to edit the frozen run.

The three inherited errors remain: Lark instead of cheaper qualifying Harbor;
Cedar (chat) or Maple (guided), both below the required fifteen seals, instead of
Birch; Merith instead of cheaper qualifying Uldara. All explicit corrections and
seven callbacks succeed, including the two successive Tarnvale corrections.
The guidance did not interfere with those corrections in this pilot.

All **72 submitted envelopes contain their complete expected source corpus**,
verified by exact ID/text comparison. There were no context omissions or output
truncations. These fresh first-event selection failures are not missing-history
or retrieval failures. Another memory mechanism would not supply absent operands:
the operands were already present.

## Cost and lifecycle

| Measure | Chat | With guidance |
| --- | --- | --- |
| Model calls | 36 | 36 |
| Input tokens, summed | 26,522 | 29,893 |
| Output tokens reported by server | 1,311 | 1,421 |
| Peak input tokens | 1,322 | 1,430 |
| Generation transport seconds | 132.040 | 142.252 |
| Batch seconds, including checks | 396.614 | 406.158 |

The guide costs 3,371 more input tokens and 110 more output tokens in this run.
These local observed totals are not subscription usage or a controlled speed
benchmark. All 72 worker PIDs were absent at closeout; terminal receipts matched
durable events and all thirty batches verified idle inference. Zero tool actions,
invalid actions, tool failures, note changes or admission-contention events.
No ordinary Soul memory, service, model/default, dashboard or release promotion.
No worker, retry, scheduler or watcher remains active from this qualification.

## Implementation and validation

Integration edits: `lib/soul_core/continuity_lab/qwen_message_projection.rb`,
`sandbox_runner.rb`, and `scripts/continuity-lab-worker.rb`. New files:
`lib/soul_core/continuity_lab/qualification_cases_a20.rb`,
`scripts/verify-continuity-lab-cases-a20.rb`,
`scripts/verify-continuity-lab-selection-a20.rb`,
`scripts/qualify-continuity-lab-qwen-a20.rb`, brief and review. Broker code is
unchanged; existing direct-profile guards cover the new named profile.
Luna owned only pure cases/their verifier and read-only review. Primary owned
context, runtime boundaries, live execution, preservation and interpretation.

Pinned Ruby 4.0.7: **166 distinct grouped checks passed**: 46 new and 120 targeted
historical. Twelve new projection/isolation checks establish the guide-only
difference, provenance/escaping, unchanged v9 bounds, exact prepared binding,
one-call reply-only behavior, overflow refusal, actual isolated run/resume,
cross-profile refusal and forged-tool denial. Thirty-four case checks use
independent numeric/source oracles and preserve inherited cases. Historical
checks: A19 chat/isolation 15, A18 direct/isolation 17, token-context 41, stream
40, A19 cases 7. All **42 unique Ruby files** passed syntax; scoped whitespace
checks passed. Local model outputs do not qualify safety or authority.

Before inference, four new prompts were clarified to request fields already
required by their frozen scoring contract, and a verifier stopped depending on
a dated local fixture file. Affected checks re-passed before live use. No outcome
informed those changes; no post-outcome prompt, runtime or scorer repair occurred.
Read-only source review found no concrete regression. An independent read-only
review agreed on the height defect and printer false negatives; primary retains
responsibility for the final assessment.

All **125 prior plus 30 new stores** replay. All **3,586 pre-live evidence files
and 133 frozen source files** remained unchanged through execution and post-run
replay. The 3,583 predevelopment files plus three retained development receipts
explain the pre-live count. Subsequent closeout documentation is separate from
the frozen experiment; prior results and unrelated dirty work are preserved.

Evidence roots, relative to repository:

- `Soul/runtime/qualification/continuity-lab-a20-development-20261012/`:
  prechange source copies/digests, regular test output and validation receipt.
- `Soul/runtime/qualification/continuity-lab-a20-20261012T193510Z/`:
  frozen baseline, summaries, exact inputs/replies/calls, journals, separate
  `primary-assessment.json` and `closeout.json`.

## Next proposal, not executed

For usability, stop relying on prompt wording alone for exact catalog selection.
Design a narrow deterministic comparison/calculation helper over explicit,
validated structured values and constraints. Preserve source spans and units;
reject ambiguous or unsupported extraction rather than silently choosing an
interpretation. Any model-proposed input must be checked against its source.
Test boundaries, units, ties, empty sets and unsupported requests. Do not add a
general command tool, autonomous loop or inference-as-memory promotion.

The helper's verified result should be displayed separately from generated
explanation, so the latter cannot quietly override it. Keep the current model-only
baseline for comparison: tool-assisted system success is not improved intrinsic
model reasoning or evidence about continuity. This is a separate design and
authority decision, not part of the completed A20 window. Thinking-mode changes,
model-server restart, production integration and owner acceptance remain open.
