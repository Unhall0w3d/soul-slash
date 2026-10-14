# Continuity Lab A17: retrieval and recent-dialogue comparison

Date: 2026-10-11. Status: implementation and the approved foreground comparison
are complete; everyday usability **requires repair**, not promotion.
Authority: [A17 brief](../soul/CONTINUITY_LAB_A17_BRIEF.md).

## Outcome

Recent dialogue materially improved this small pilot's callbacks. Ranked search
alone retrieved useful documents more often but did not resolve task completion.
The best condition still made elementary selection errors, misrouted reads,
repeated failed note writes, and sometimes failed to answer. This is useful
diagnostic evidence, not a general reliability estimate or continuity-of-subject
claim. No dashboard, ordinary-memory, service, model, merge or release promotion.

| Condition | Correct factual tasks / 13 scheduled | Correct callbacks / 5 scheduled | Replies / 20 scheduled | Model calls |
| --- | --- | --- | --- | --- |
| Legacy exact retrieval | 1 | 0 | 16 | 43 |
| Ranked retrieval | 2 | 0 | 20 | 52 |
| Ranked + recent dialogue | 7 | 4 | 17 | 49 |

Callbacks are included in the factual denominator, not additional successes.
Three unknown-fact requests, three social turns and one uppercase control are
excluded from that denominator. Three dependent requests were skipped after
predecessor failure (baseline `m-recall`, baseline/recent `c-recall`); they remain
uncompleted scheduled work, not independently observed model failures.

All 15 independent condition/batches finished: 60 scheduled requests, 57 executed,
144 generations, 1,015.504 seconds overall. Infrastructure failure was null;
all workers exited and every batch verified idle inference. Harness exit 1
records behavioral screen failures, not a crashed or unfinished job.

## What changed and what remained fixed

- New optional `ranked_lexical_v2` preserves full exact matches and legacy order.
  Only on no exact hits does a bounded, deterministic term/plural matcher rank
  candidates and report matched/missing terms. It preserves original character
  spans, source identity/revision/digest, lineage and collection boundaries.
- Independently optional `recent_dialogue_v1` supplies up to three completed
  earlier exchanges, with a 4096-byte initial cap and actual-token accounting.
  They are explicitly observed, unverified dialogue, not facts or instructions.
  Eviction removes oldest whole exchanges before old tool pairs; replay verifies
  the selected sequence. Current request/latest tool result remain essential.
- New v7/v8 qualification factories and worker modes opt into those policies.
  Absent settings preserve old configuration digests, defaults and journal
  semantics. Historical runners and their frozen hash gates were not repointed.
- Same Qwen3-8B-Q4_K_M, GTX 1070 8 GiB, llama.cpp b9851-0eca4d490, 4096 context,
  3072 input budget, six-call event ceiling, sampler and action grammar. No A16
  extra guidance. Actual model-server process was not restarted.

The comparison used the sixteen A16 requests and four frozen Eastmere distractor
requests per condition. Batch order alternated; stores were independent and each
event ran in a fresh worker. Source, cases, scorer and order were frozen before
inference. There was no live retry, prompt/scorer tuning or subsequent generation.
Histories and lineage IDs differ; the recent profile also adds explicit context
fields. This is not an identical-token or replicated factorial experiment.

## Primary assessment by request

P = correct complete answer with relevant recorded support; F = not established;
S = skipped prerequisite; A = abstention rather than invented fact, with coverage
limits below. Social quality is assessed separately from factual scoring.

| Request | Legacy | Ranked | Ranked + recent |
| --- | --- | --- | --- |
| `m-plan`, cheapest HDMI+battery projector | F: no hits | F: Alder lacks battery | P: Birch, 42 |
| `m-change`, two Cedar projectors | F: repeated failed reads | F: wrong note lookup | F: unit price only, omitted total |
| `m-recall`, revised plan | S | F | P: two Cedar, 110 |
| `m-unknown`, confirmed delivery | A | A | A |
| `c-uppercase`, no-tool control | P | P | P |
| `c-plan`, 36 litres Meadow compost | F: no hits | P: three bags, 27 | P: three bags, 27 |
| `c-change`, four Birch bags | F: invalid-action budget | F: corpus ID read from notes | F: six revision-conflicted note writes |
| `c-recall`, revised compost order | S | F | S |
| `chat-walk`, greeting | Adequate generic reply | Adequate generic reply | Wait, no reply |
| `chat-reason`, purpose of walk | Adequate acknowledgement | First-person echo of user | Adequate acknowledgement |
| `chat-drink`, beverage correction | Implied physical agency | Implied physical agency | Claimed it would prepare drink |
| `chat-recall`, drink and reason | F | F | P: hot chocolate, clear head/break |
| `t-plan`, cheapest pack with at least eight markers | F: wrong Nova price | F: missed cheaper Nova | F: incomplete source, no correct selection |
| `t-change`, two Orbit packs | P: 20 markers, 50 | P: 20 markers, 50 | F: nonexistent note |
| `t-callback`, revised marker order | F | F | P: two Orbit, 20, 50; derivation below |
| `t-absent`, catalog warranty | A | A | A |
| `a17-plan`, cheapest nine-hour lighting | F: no hits | F: Lark rather than Harbor | F: Lark rather than Harbor |
| `a17-change`, three Lark kits | F | F | P: 27 hours, 123 |
| `a17-callback`, revised lighting order | F | F | P: three Lark, 123 |
| `a17-absent`, lighting warranty | A, direct absence statement | A, direct absence statement | A, direct absence statement |

### Source support and screening limitations

The frozen mechanical screen marked 5/20, 7/20 and 9/20 eligible respectively.
These are not semantic success rates: they include social/control cases, can
miss sound paraphrases and arithmetic, and do not assess conversational agency.
The original outputs and scores remain unchanged.

For recent `t-callback`, the final input contained the earlier assistant's
source-supported Orbit figures (10 markers, 25 credits) and the user's change
to two packs. The answer 20/50 follows from those operands. The earlier `t-plan`
answer was wrong overall, but its Orbit figures are independently traceable to
`field-kit-catalog`, digest
`cecb65ad3d9c0cfaf3f62c8a59e3e6045c29396f05d833ea3cc70b49b4a0ba5f`.
The underlying catalog was retrieved during `t-plan`, not directly during the
callback; the callback's input carried the operands as prior assistant text.
The frozen support pattern demanded literal `50` in earlier text and rejected
the valid derivation. Primary review accepts this one additional factual/callback
success; it does not claim to observe the model's internal reasoning or promote
earlier assistant text into a verified fact store.

All nine unknown-fact answers avoided fabricating a delivery time or warranty.
However, abstention and established source absence differ. Baseline `m-unknown`
and `t-absent` had no retrieved source at reply time. Ranked/recent versions had
partial catalog snippets, not full coverage proving catalog-wide absence.
Their limited-information abstentions are useful; catalog-wide negative wording
must not be treated as exhaustive verification. Only `a17-absent` visibly
retrieved the explicit absence statement in all three conditions. Baseline/recent
snippets omit the word Eastmere but retain the exact `eastmere-lighting` source
ID, revision, lineage and digest
`f428cd4d50006d283ad712d5be840fe387f1eff2fdda4832adc9ad929eab4efb`.
That is a lexical screen false negative, not missing document provenance.

No live tool-group eviction or server output truncation occurred. Maximum input
was 1960 tokens, below 3072. Missing Nova price was a bounded search snippet,
not model context exhaustion; the model could have read the complete document.
Both ranked conditions had Harbor's cheaper qualifying figures but selected
Lark. Thus missing context is not an adequate explanation for every failure.

## Cost, tool behavior and boundaries

| Measure | Legacy | Ranked | Ranked + recent |
| --- | --- | --- | --- |
| Executed requests | 18 | 20 | 19 |
| Input tokens summed over generation calls | 39,555 | 53,030 | 64,628 |
| Output tokens reported by server | 2,954 | 3,571 | 2,846 |
| Peak input tokens | 1,326 | 1,819 | 1,960 |
| Generation transport seconds | 207.529 | 265.938 | 270.863 |
| Sum of batch seconds, including checks | 296.745 | 356.466 | 361.179 |
| Invalid actions | 2 | 0 | 0 |
| Failed tool actions | 6 | 11 | 9 |

Token totals include repeated context, not unique information or subscription
cost. Different executed counts and histories prevent clean per-task efficiency
claims. Recent conversation produced one successful optional note in `chat-drink`;
all six `c-change` writes were revision conflicts and made no durable change.
The guards rejected invalid revisions; the model failed to recover. Optional
note absence itself is not a failure. These are experimental local stores only.

## Implementation, deterministic checks and retained evidence

Shared files changed under `lib/soul_core/continuity_lab/`: `config.rb`,
`retrieval.rb`, `actions.rb`, `context_builder.rb`, `token_context.rb`,
`qwen_message_projection.rb`, `qwen_broker_session.rb`, `sandbox_runner.rb`;
also `scripts/continuity-lab-worker.rb`. New modules: `retrieval_ranked.rb`,
`recent_dialogue.rb`, `qualification_cases_a17.rb`, `usability_assessment_a17.rb`.
New scripts: `qualify-continuity-lab-qwen-a17.rb` and the three A17 verifiers below.
`receipt_context.rb`, older qualification runners and unrelated dirty files
were not changed. Documentation includes the brief, this review, adaptation plan,
human review gate and candidate-review template.

Pinned interpreter: `/home/bhones/.rbenv/versions/4.0.7/bin/ruby`.
All 365 grouped checks passed: 49 new, 316 affected historical checks.

| Verifier under `scripts/` | Checks |
| --- | --- |
| `verify-continuity-lab-retrieval-a17.rb` | 13 |
| `verify-continuity-lab-context-a17.rb --isolation` | 22 |
| `verify-continuity-lab-cases-a17.rb` | 14 |
| `verify-continuity-lab-context-a1.rb` | 30 |
| `verify-continuity-lab-a4.rb` | 38 |
| `verify-continuity-lab-records-a14.rb` | 9 |
| `verify-continuity-lab-cases-a16.rb` | 6 |
| `verify-continuity-lab-usability-a15.rb` | 7 |
| `verify-continuity-lab-receipts-a13.rb` | 25 |
| `verify-continuity-lab-token-context-a5.rb` | 41 |
| `verify-continuity-lab-message-projection-a10.rb` | 13 |
| `verify-continuity-lab-recovery-a1.rb` | 94 |
| `verify-continuity-lab-admission-a2.rb` | 14 |
| `verify-continuity-lab-admission-a9.rb` | 39 |

Coverage includes exact legacy compatibility, ranking/distractors/spans/quotas,
ordered history, source digests, current/incomplete/future-event exclusion,
byte/token eviction, strict profile/worker binding, journal tampering and actual
isolated v7/v8 workers with synthetic inference. 39 Ruby files passed syntax.
Tracked diff and explicit A17 new-file whitespace/link checks passed at closeout.

Pre-live review corrected four evidence issues before any real generation:
preserve journal insertion order rather than canonical-sort events; accept only
source text still visible in the final reply context; allow callback support via
explicit history reads as well as automatic dialogue; include lease-store and
bounded-runner dependencies in the source freeze. A first synthetic negative
fixture mistakenly used `Store.open` without invoking replay; the fixture was
corrected to call integrity. Its original failure remains retained. No failing
live outcome was repaired, retried or rescored in place.

Evidence roots, relative to repository:

- `Soul/runtime/qualification/continuity-lab-a17-development-20261011/`:
  prechange copies/hashes, check outputs and `validation.txt`.
- `Soul/runtime/qualification/continuity-lab-a17-20261011T160036Z/`:
  `suite-baseline.json`, `suite-summary.json`, per-batch summaries, case receipts,
  `calls.jsonl`, exact prepared contexts and replayable journals. The separately
  added `primary-assessment.json` records semantic decisions and closeout counts
  without replacing the frozen scorer's outputs.

All 2,116 predevelopment evidence files remained unchanged before inference
(aggregate SHA256 `0eac018cd80ae44ded2404e6158ed8c96f62607d6ee6c0a6c25852f6c12bef6c`).
All 2,140 pre-live evidence files and 112 frozen source files remained unchanged
through the live suite. Post-suite documentation is a deliberate later change,
not a reason to rewrite the execution snapshot. All 84 historical stores and
15 new stores replay successfully: 99 total. First failures are preserved.

## Recommendation and remaining gates

Keep these policies opt-in. The next useful comparison is a **bounded direct-
evidence answer path**: provide complete selected small source documents plus
recent dialogue, and request an answer without requiring discovery, collection
selection or note orchestration first. Compare against this agentic path on
frozen tasks. This separates source coverage and tool-interface burden from
reasoning/constraint-following limits; it does not assume a larger prompt fixes
them. It also tests whether a simpler practical route better fits this hardware.

That is a proposed new context/action policy and live window, not implemented
here. Preserve the explicit-tool path for later tasks that need it; do not hide
failed actions or turn generated notes into facts. Model-server resident-versus-
restarted testing remains deferred until there is a useful baseline to compare.
Long-horizon usefulness, generic conversation quality and owner acceptance remain
open. No inference or worker continues after this assessment.
