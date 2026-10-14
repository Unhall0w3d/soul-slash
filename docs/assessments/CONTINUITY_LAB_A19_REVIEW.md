# Continuity Lab A19: chronological direct-evidence chat

Date: 2026-10-12. Status: approved implementation and single foreground comparison
complete; modest correction-handling improvement, **not everyday reliability or
release**. Authority: [A19 brief](../soul/CONTINUITY_LAB_A19_BRIEF.md).

## Outcome

The chronological presentation correctly retained the previously missed projector
correction. It did not repair constrained selection: both presentations made the
same three wrong initial choices with complete evidence available. Keep chat as
the preferred opt-in experimental presentation, without changing production
defaults or adding more memory machinery to explain those selection failures.

| Measure | Fresh direct envelope | Chronological chat |
| --- | --- | --- |
| Correct factual tasks / 20 scheduled | 16 | 17 |
| Correct callbacks / 7 scheduled, included above | 6 | 7 |
| Source-grounded unknown-fact answers / 4 | 4 | 4 |
| Replies / 28 scheduled | 28 | 28 |
| Model calls | 28 | 28 |
| Frozen mechanical eligibility / 28 | 22 | 23 |

Three social turns and one uppercase control are also outside the factual
denominator. Both controls passed. Casual replies were relevant but generic,
with unsupported positive assumptions; no broad conversational-quality claim.
All fourteen batches finished in **445.209 seconds / 56 generations**. No
infrastructure failure, skipped prerequisite or unstarted request. Exit 1 records
behavioral screen failures, not a crashed or incomplete harness.

## Exact change and comparison limits

The opt-in `direct_evidence_chat_v1` projection presents selected prior user and
assistant utterances in journal order, with the current request last. Utterance
text is preserved apart from existing template-control escaping. The complete
corpus and ordered source metadata remain explicitly labeled user-role reference
data, never system instructions. Transcript text occurs once in its role message;
IDs, revisions, digests and spans remain in metadata and the original envelope.
No synthetic acknowledgement, inferred summary or corrected answer is inserted.

Both conditions use unchanged A18 v9 config, system/protocol, source selection,
maximum three recent exchanges, full-corpus limits, replay, reply-only grammar,
one-call/zero-tool limits, actual-token preparation and overflow refusal. Exact
fixed worker modes distinguish the profiles and reject cross-binding before
spawn. Existing modes and defaults remain available unchanged.

Same Qwen3-8B-Q4_K_M, GTX 1070 8 GiB, llama.cpp b9851-0eca4d490, sampler,
thinking disabled, 4096 context / 3072 input / 768 output reserve. No model-server
restart; PID 3065 was freshly observed before freezing, then pinned throughout.
Seven independent stores per condition, fresh isolated worker per request,
alternating condition order by batch. Twenty-four inherited cases plus four new
Tarnvale cases were frozen before inference; no retries or post-outcome tuning.

Presentation is the intervention, not evidence-selection policy. Prompt tokens
differ, and histories diverge through generated replies. The correction gain is
a single observation, not proof that role order alone caused it. This small,
partly familiar pilot is not a general accuracy estimate or a process-continuity
comparison. It does not establish subjective continuity or personhood.

## Primary semantic assessment

Full per-case assessments are in the separate `primary-assessment.json` beside
the immutable suite summary. Recorded replies, exact inputs and original scores
are retained; the semantic assessment does not rewrite the scorer.

| Case or sequence | Envelope | Chat |
| --- | --- | --- |
| `m-plan`, `m-change` | Correct Birch/42, then two Cedar/110 | Same |
| `m-recall` | Wrong: reverted to one Birch/42 | Correct: two Cedar/110 |
| `c-plan`, `c-change`, `c-recall` | Correct Meadow 3/36/27, then Birch 4/32/24 | Same |
| `chat-recall` | Correct hot chocolate, walk to clear mind | Same |
| `t-plan`, `t-change`, `t-callback` | Correct Nova/24, then two Orbit/20/50 | Same |
| `a17-plan` | Wrong Lark/41 | Same |
| `a17-change`, `a17-callback` | Correct three Lark, 27 aggregate hours/123 | Same |
| `a18-plan` | Wrong Cedar/37 | Same |
| `a18-change`, `a18-callback` | Correct four Maple, 56 seals/132 | Same |
| `a19-plan` | Wrong Merith/101 | Same |
| `a19-first-correction` | Correct fifteen Merith packs, 480 sensors/1515 | Same |
| `a19-second-correction`, `a19-callback` | Correct twenty Tavren packs, 520 sensors/1420 | Same |

Selection failures are distinct from recall:

- Eastmere: Lark's nine hours qualify, but Harbor offers ten hours for 38 rather
  than 41 credits. Eligible-but-not-cheapest error.
- Silverfen: Cedar has thirteen seals, below the fifteen-seal minimum. Birch has
  seventeen for 43 credits and is the only eligible crate. Constraint violation.
- New Tarnvale case: Merith's 32 sensors qualify, but Uldara has 34 for 89 rather
  than 101 crowns. Eligible-but-not-cheapest error.

All three are first events with empty recent dialogue under both conditions.
The full catalogs were present; there were no context omissions or output
truncations anywhere in the suite. More retained dialogue cannot explain or
repair these particular first-event mistakes. Both conditions then followed two
successive explicit corrections in the new sequence and recalled the final one.

Four frozen-screen false negatives are accepted separately: envelope `m-unknown`
says delivery time is not specified; chat `t-absent` says the catalog does not
record warranty terms; both `chat-recall` answers use the supported paraphrase
"clear your mind" instead of "clear your head". All four unknown-fact requests
in each condition had complete sources with explicit absence statements.

Social replies acknowledge the drink correction without claiming a physical
action, but presume the walk was pleasant or brought relief and unnecessarily
judge hot chocolate as better. Chat asks one natural follow-up; four short turns
do not establish a material overall conversational-quality improvement.

## Cost and lifecycle evidence

| Measure | Envelope | Chat |
| --- | --- | --- |
| Input tokens summed over generations | 22,689 | 22,811 |
| Output tokens reported by server | 1,094 | 973 |
| Peak input tokens | 1,341 | 1,333 |
| Generation transport seconds | 95.465 | 102.403 |
| Sum of batch seconds, including checks | 218.516 | 224.994 |

These are local observed totals, not subscription usage or an isolated speed
benchmark. No meaningful efficiency gain is established. Every worker exited,
all terminal receipts matched durable events, and every batch verified idle
inference. Zero tool actions, invalid actions, note changes or admission-contention
events. No ordinary Soul memory, service, model/default, dashboard or release
promotion occurred. The foreground lifecycle is complete; no retry, watcher or
worker remains running from this qualification.

## Implementation, checks and preservation

Changed integration paths: `lib/soul_core/continuity_lab/qwen_message_projection.rb`,
`qwen_broker_session.rb`, `sandbox_runner.rb`, and
`scripts/continuity-lab-worker.rb`. New pure cases/verifier were delegated to Luna;
primary owned context, broker/worker boundaries, live use and assessment.
New files: `qualification_cases_a19.rb`, `scripts/verify-continuity-lab-cases-a19.rb`,
`verify-continuity-lab-chat-a19.rb`, `qualify-continuity-lab-qwen-a19.rb`, brief and
this review. No new config or persistence policy.

Pinned Ruby 4.0.7: **259 distinct grouped checks passed** (22 new, 237 targeted
historical). The new 15-check projection/isolation verifier covers chronological
roles, exact text/provenance, escaping, unchanged v9 config/old projection,
whole-dialogue eviction, essential overflow refusal, prepared-prompt binding,
one-call/reply-only guards, actual isolated run/resume, wrong-profile refusals
before spawn and forged-tool denial. Seven case checks independently validate
catalog operands, minimum-price selection, correction arithmetic and final-order
callbacks. All 41 Ruby files passed syntax; scoped whitespace checks passed.
Commands, counts and outputs are retained in the development validation receipt.
Local model answers are behavioral evidence, not safety/permission tests.

Before inference, the new case clarified packs versus sensors and gained an
independent catalog oracle; copied runner work-budget metadata was corrected to
880 seconds. No live outcome informed those changes. Read-only source review's
possible stale-PID concern was resolved against fresh service observation; a
replacement process still fails closed. Actual isolation tests used supported
host escalation, without weakening containment. No source edits during inference.

All **111 prior plus 14 new stores** replay at closeout. All **3,215 pre-live
evidence files and 127 frozen source files** were unchanged through execution
and the post-run replay check. The predevelopment count was 3,211; four retained
development receipts account for the difference. Closeout documentation is a
separate, subsequent edit; earlier reviews/failures and unrelated dirty work stay.

Evidence roots, relative to repository:

- `Soul/runtime/qualification/continuity-lab-a19-development-20261012/`:
  prechange copies/digests, regular and isolated test output, `validation.txt`.
- `Soul/runtime/qualification/continuity-lab-a19-20261012T174539Z/`:
  frozen baselines, summaries, exact inputs, replies, calls, journals, separate
  `primary-assessment.json` and `closeout.json`.

## Next proposal, not executed

Retain chronological chat as the experimental baseline. The next narrow question
is constrained selection, not memory: would a general filter-then-compare answer
check help the model reject ineligible options and compare prices across all
eligible ones? Test against the unchanged chat baseline with fresh held-out
catalogs before adoption; no case-specific hints, expected answers in prompts,
host-selected winners or additional autonomous loops. Retain the one-call,
reply-only boundary. Do not silently enable thinking: the current template and
reply grammar explicitly enforce non-thinking output; that would be a separate
transport/output-budget experiment, not a free configuration toggle.

If the bounded comparison does not help, record the limitation rather than layer
on prompts indefinitely. Deterministic calculation/selection support for practical
work would be a separate substrate design and must be reported as such, not a
model capability gain. Dashboard/ordinary-memory integration, owner conversation
acceptance, actual resident-versus-restarted model comparison and release remain
separate gates. A19's authorized live window is closed.
