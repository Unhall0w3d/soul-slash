# Continuity Lab A18: direct complete-evidence answers

Date: 2026-10-11. Status: approved implementation and single foreground comparison
complete; useful directional improvement, **not everyday reliability or release**.
Authority: [A18 brief](../soul/CONTINUITY_LAB_A18_BRIEF.md).

## Outcome

The smaller answer-only path solved more practical tasks with fewer generations.
Supplying complete evidence removed retrieval/note-routing work, but did not
eliminate selection and correction errors. Keep it as the preferred experimental
baseline, not an autonomous worker or production memory feature.

| Measure | Fresh v8 agentic baseline | v9 direct evidence |
| --- | --- | --- |
| Correct factual tasks / 16 scheduled | 7 | 13 |
| Correct callbacks / 6 scheduled, included above | 4 | 5 |
| Replies / 24 scheduled | 21 | 24 |
| Executed requests | 23 | 24 |
| Model calls | 59 | 24 |
| Frozen mechanical eligibility / 24 | 9 | 20 |

Four unknown-fact requests, three social turns and one uppercase control are
outside the factual denominator. Agentic `c-recall` was skipped after its
predecessor exhausted the call budget: uncompleted scheduled work, not an
independently observed model error. Agentic `chat-walk` returned wait, not a reply.

All twelve batches finished in 627.124 seconds / 83 generations. No infrastructure
failure; every worker exited and every batch verified idle inference. Exit 1
records behavioral screen failures, not an unfinished or crashed harness.

## Intervention and limits

Opt-in `direct_evidence_v1` supplies all documents in an operator-selected small
corpus, including distractors, with full text, IDs, revision, lineage, spans and
digests. Limits: eight documents / 8192 encoded source bytes; refuse oversize
essential context rather than truncate it. A17's maximum three completed recent
exchanges remain observed/unverified data, with whole-exchange eviction under
byte/token pressure. Exact context selection is journal-replay checked.

A separate concise projection and reply-only grammar are enforced alongside
one generation, zero tools, zero invalid retries and exact v9 worker/broker
binding. Existing defaults, tools and v8 behavior remain available unchanged.
Thus this compares a package of complete sources, shorter prompt and simpler
action space; it cannot isolate which constituent caused the improvement.

Same Qwen3-8B-Q4_K_M, GTX 1070 8 GiB, installed llama.cpp b9851-0eca4d490,
sampler, thinking disabled, 4096 context / 3072 input / 768 output reserve.
No model-server restart. Six independent stores per condition, fresh worker per
request, alternating condition order by batch. Twenty inherited A17 cases plus
four separately frozen Silverfen cases per condition. No live retries or tuning.
This small, partly familiar, single-run pilot is not a general reliability rate.

## Primary semantic assessment

P = complete correct answer with traceable source support; F = not established;
S = skipped prerequisite; A = appropriate abstention, with source-coverage limits
below. Social quality is not included in the factual score.

| Request | Agentic | Direct |
| --- | --- | --- |
| `m-plan`, cheapest HDMI+battery projector | F: Alder lacks battery | P: Birch, 42 |
| `m-change`, two Cedar projectors | P: 110 | P: 110 |
| `m-recall`, revised order | P: two Cedar, 110 | F: reverted to Birch, 42 |
| `m-unknown`, confirmed delivery | A, limited context | A, full source |
| `c-uppercase`, no-tool control | P | P |
| `c-plan`, 36 litres Meadow compost | P: three bags, 27 | P: three bags, 27 |
| `c-change`, four Birch bags | F: call budget, no reply | P: 32 litres, 24 |
| `c-recall`, revised compost order | S | P: four Birch, 32 litres, 24 |
| `chat-walk`, greeting | Wait, no reply | Adequate generic reply |
| `chat-reason`, purpose of walk | Adequate acknowledgement | Adequate generic acknowledgement |
| `chat-drink`, tea corrected to hot chocolate | Implied physical replacement | Correct acknowledgement, no physical agency |
| `chat-recall`, drink and purpose | P: hot chocolate, clear head/break | P: same |
| `t-plan`, cheapest pack with at least eight markers | F: incomplete source, no correct choice | P: Nova, 24 |
| `t-change`, two Orbit packs | F: nonexistent note | P: 20 markers, 50 |
| `t-callback`, revised marker order | P: two Orbit, 20, 50 | P: same |
| `t-absent`, warranty | A, limited snippet | A, full source |
| `a17-plan`, cheapest nine-hour lighting | F: Lark, 41 | F: Lark, 41; Harbor, 38 qualifies |
| `a17-change`, three Lark kits | F: claims data unavailable | P: 27 hours, 123 |
| `a17-callback`, revised lighting order | P: three Lark, 123 | P: same |
| `a17-absent`, warranty | A, explicit source absence | A, full source |
| `a18-plan`, cheapest crate with at least fifteen seals | P: Birch, 43 | F: Cedar has only thirteen seals |
| `a18-change`, four Maple crates | F: wrong note lookup | P: 56 seals, 132 |
| `a18-callback`, revised crate order | F: omits requested cost | P: four Maple, 132 |
| `a18-absent`, warranty | A, explicit source absence | A, full source |

All three direct factual failures had the required evidence in their final input.
`m-recall` carried both the original plan and the later two-Cedar correction;
`a17-plan` and `a18-plan` carried the complete qualifying catalogs. No live context
eviction or server output truncation occurred. More context alone is therefore
not an adequate explanation or remedy for these failures.

Direct conversation followed corrections and avoided the tested physical-agency
error, but was generic and repeated polite closings. Four short conversation
turns do not establish rich dialogue quality or long-term continuity.

### Frozen-screen discrepancies and source support

Original scorer outputs remain untouched. Separate primary review accepts:

- Direct `m-unknown`: "does not establish" is a sound abstention against the
  complete source's explicit missing delivery arrangements, but is absent from
  the frozen phrase regex.
- Agentic `t-callback`: prior `t-plan` says Orbit has 10 markers and costs 25;
  the later user requests two. Those operands support 20/50, although the prior
  text does not literally contain the newly calculated 50 demanded by the screen.
  Original operands are traceable to `field-kit-catalog`, SHA-256
  `cecb65ad3d9c0cfaf3f62c8a59e3e6045c29396f05d833ea3cc70b49b4a0ba5f`.
- Agentic `a17-callback`: earlier Lark/41 plus the user's three-kit correction
  supports 123, although 123 first appears in the callback. Earlier Lark figures
  are traceable to `eastmere-lighting`, SHA-256
  `f428cd4d50006d283ad712d5be840fe387f1eff2fdda4832adc9ad929eab4efb`.
  These two callbacks carry operands as prior assistant text, not direct verified
  facts in a promoted memory store; source tracing validates this assessment only.
- Agentic `a17-absent` and `a18-absent` retrieved explicit absence statements.
  Their snippets omit the project name demanded by the screen, but preserve the
  exact document ID/digest/span. Silverfen digest:
  `4ded8db6aabc2909c6becdd6424b1d2bc5077bf4104d2b8608bc2f6811e7d112`.

Agentic `m-unknown` had no direct catalog in its terminal context. `t-absent` had
only the [0,160] excerpt, which omitted the warranty sentence. Both avoided
inventing a value, but do not establish exhaustive catalog absence. All four
direct unknown-fact answers had complete documents including absence statements;
Silverfen correctly did not borrow the distractor's three-month warranty.

## Cost and operational evidence

| Measure | Agentic | Direct |
| --- | --- | --- |
| Input tokens summed over generations | 79,736 | 18,488 |
| Output tokens reported by server | 3,434 | 896 |
| Peak input tokens | 2,079 | 1,345 |
| Generation transport seconds | 331.934 | 78.669 |
| Sum of batch seconds, including checks | 441.651 | 183.961 |
| Invalid actions | 0 | 0 |
| Failed tool actions | 12 | 0 |
| Durable note changes | 0 | 0 |

These are observed local workload totals, not subscription usage or isolated
per-task speed estimates. Executed counts, prompt sizes and histories differ.
No ordinary Soul memory, service, model, dashboard or release promotion occurred.

## Implementation, verification and preservation

New runtime: `direct_evidence.rb`, `qwen_reply_a18.gbnf`,
`qualification_cases_a18.rb`, `usability_assessment_a18.rb` under
`lib/soul_core/continuity_lab/`. Additive integration in `config.rb`, `actions.rb`,
`context_builder.rb`, `token_context.rb`, `qwen_message_projection.rb`,
`qwen_broker_session.rb`, `sandbox_runner.rb` and `scripts/continuity-lab-worker.rb`.
New runner/verifiers: `scripts/qualify-continuity-lab-qwen-a18.rb`,
`verify-continuity-lab-direct-a18.rb`, `verify-continuity-lab-cases-a18.rb`.

Pinned Ruby 4.0.7: **562 distinct grouped checks passed** (27 new, 535 historical),
including actual isolated synthetic workers, strict no-tool/call/profile bounds,
complete-source replay/provenance, control-token escaping, byte/token eviction,
essential overflow rejection, altered/reordered/missing source refusal and legacy
config/digest equality. All 40 Ruby files passed syntax. The development validation
receipt lists verifier counts and execution caveats. Read-only independent review found no
concrete integration defect; primary independently verified authority boundaries.

Pre-live corrections are retained: a synthetic PipeBackend fixture initially used
an unsupported constructor block; the first held-out answer key contradicted
prices. Before any inference, the fixture adopted the established adapter and
the selection threshold changed to fifteen seals/Birch43, with an independent
minimum-price oracle added. No corpus change or post-outcome scorer repair.
Bubblewrap was blocked by the app sandbox; the exact synthetic check passed via
supported host escalation without weakening isolation. No service mutation.

All 99 prior plus 12 new stores replayed at closeout. All 2,790 pre-live evidence
files and 121 frozen source files were unchanged through execution. Earlier
predevelopment aggregate covered 2,785 files; five development receipts account
for the difference. Only after the run were this review, the plan and review
links updated. Existing dirty work and earlier failures are preserved.

Evidence roots, relative to repository:

- `Soul/runtime/qualification/continuity-lab-a18-development-20261011/`:
  prechange source copies/hashes, check outputs and `validation.txt`.
- `Soul/runtime/qualification/continuity-lab-a18-20261011T171726Z/`:
  frozen suite/batch baselines, summaries, case receipts, calls, exact contexts,
  replayable journals and separate `primary-assessment.json`. Original receipts
  and frozen scores are not rewritten by semantic review.

## Recommended next adaptation, not yet executed

Keep the direct-evidence experimental baseline. Test a conventional chronological
chat projection of the same recorded exchanges, with the current request last,
instead of embedding conversation in one serialized envelope. Preserve the
ledger, provenance, complete-source and no-tool boundaries underneath. This is
a bounded representation hypothesis for correction handling, not a promised fix.
Retain fresh constraint-selection cases: ordinary chat formatting may not solve
the observed numeric/comparison errors. Do not add more autonomous memory/tool
machinery to compensate or hard-code answers from these cases.

Production/dashboard integration, owner conversational acceptance and actual
resident-versus-restarted model comparison remain separate future gates. The
approved A18 live window is closed; no job, retry or watcher remains running.
