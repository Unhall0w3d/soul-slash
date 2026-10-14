# Continuity Lab A16: retrieval-guidance-only comparison

Date: October 9, 2026. Status: **assessment complete; guidance-only candidate
does not qualify everyday usefulness and is not promoted**.

## Outcome

The fixed comparison completed all 32 requests / eight batches in 575.8 seconds,
using 86 model calls. Both conditions solved **one of ten evidence-dependent
factual tasks**: the revised Orbit-pack quantity/cost calculation. Neither
condition completed any of the four callbacks. The guide improved collection
choice in a few traces and grounded one absent-fact response in the complete
catalog, but it did not deliver the requested practical improvement.

The candidate consumed more calls, input tokens and measured generation time.
This is one small paired pilot, not a reliability estimate or a conclusion that
Qwen cannot use memory. It directly tests this prompt, interface, corpus and
retrieval-dependent context policy. No additional inference, prompt retuning,
case retries, matcher changes or model-server restarts followed the result.

## Scope, controls and implementation

The [A16 brief](../soul/CONTINUITY_LAB_A16_BRIEF.md) records the owner's approval.
Only a qualification-specific transport adapter appends a versioned retrieval
guide before the existing template application and tokenizer. Its baseline
condition leaves the exact template payload untouched. The candidate explains
collections, exact-word AND search, query shortening, discovering IDs/revisions,
source reads, missing history and the limits of an empty search. No expected
case answers or automatic dialogue were added.

The following remained unchanged: A13 broker/projection/runtime and action
grammar, A15 requests/corpora/evaluator, model/build/settings, 3072 input-token
budget, admission and isolated-worker protocol, search matching, optional note
semantics, and ordinary Soul state. The four new Northstar transfer cases were
frozen before inference. Three existing four-event batches plus this held-out
batch ran in alternating order:

1. Planning: baseline, guided.
2. Holdout: guided, baseline.
3. Conversation: baseline, guided.
4. Transfer: guided, baseline.

Each condition/batch began with an independent empty store and its selected
fictional corpus. Each event used a fresh worker; earlier exchanges were only
available through retrieval. The model server remained resident. Different
lineage identifiers and histories resulting from earlier answers mean this is
not identical-input next-token testing; a fixed sampler seed does not eliminate
those differences. No private owner facts were used.

## Quantitative results

| Measure | Baseline | Guided |
| --- | ---: | ---: |
| Requests reaching a reply | 16 | 16 |
| Evidence-dependent factual tasks correct | 1/10 | 1/10 |
| Callbacks correct (subset of those ten) | 0/4 | 0/4 |
| No-tool uppercase control | Pass | Pass |
| Model calls | 36 | 50 |
| Sum of measured input tokens across calls | 32,137 | 61,233 |
| Maximum single input | 1,161 | 1,709 |
| Predicted output tokens | 2,350 | 3,095 |
| Sum of recorded generation-request time | 163.9 s | 264.2 s |
| Search calls / successful nonempty searches | 14 / 1 | 27 / 3 |
| Successful empty searches | 13 | 23 |
| Read calls / successful reads | 4 / 0 | 5 / 3 |
| Optional note writes | 1 | 1 |
| Invalid actions | 1 | 1 |
| Validly shaped tool calls rejected | 4 | 3 |
| Context omissions / input-budget failures | 0 / 0 | 0 / 0 |

The guided condition used 38.9% more calls and about 90.5% more aggregate input
tokens. Generation-request time is not end-to-end latency or a hardware benchmark;
the whole suite includes admission, model hashes, journal checks and worker setup.
Three guided searches returned hits; three subsequent reads succeeded, but two
of those reads merely repeated the same snippet. Nonempty retrieval alone is
not task success.

## Primary semantic assessment, request by request

Mechanical eligibility is only a screening aid. All raw replies and tool traces
were reviewed separately; the old evaluator was not changed after seeing results.

| Request | Baseline | Guided |
| --- | --- | --- |
| `m-plan`: cheapest qualifying projector | Incorrect: missed present facts and claimed no matching entries | Incorrect: four empty searches, then claimed the catalog lacks the facts |
| `m-change`: two Cedar units | Incorrect: no total | Incorrect: no total after four over-specific searches |
| `m-recall`: revised projector decision | Incorrect: guessed a nonexistent note | Incorrect: retrieved the earlier failed initial answer, not the revised decision |
| `m-unknown`: confirmed delivery time | Partial: honest report that its search found nothing, but no source read | Correct: read the full catalog, which explicitly has no delivery arrangements |
| `c-uppercase` | Correct, exact, no tools | Correct, exact, no tools |
| `c-plan`: Meadow quantity/cost | Incorrect: missed available figures | Incorrect: empty search followed by rejected cross-lineage search |
| `c-change`: four Birch bags | Incorrect: invalid guessed ID, then empty search | Incorrect: nonexistent guessed ID, then empty search |
| `c-recall`: revised garden decision | Incorrect | Incorrect |
| `chat-walk`: greeting after walk/tea | Adequate but generic | Adequate but generic |
| `chat-reason`: needed a break | Adequate but generic | Adequate but generic |
| `chat-drink`: corrected tea to hot chocolate | Partial conversational response: accurately reports writing a note, not a natural acknowledgment | Partial conversational response: accurately reports writing a note, not a natural acknowledgment |
| `chat-recall`: current drink and reason for walk | Incorrect despite the drink note existing | Incorrect despite the drink note existing |
| `t-plan`: cheapest pack with eight markers | Incorrect; suggests an external vendor contact for a fictional supplied catalog | Incorrect: missed present catalog facts |
| `t-change`: two Orbit packs | Correct: 20 markers / 50 credits, supported by retrieved data | Correct: same figures, with an additional redundant read |
| `t-callback`: revised pack decision/cost | Incorrect despite a correct preceding answer | Incorrect despite a correct preceding answer |
| `t-absent`: warranty period | Partial: no invented period, but unsupported claim about catalog contents | Partial: reports inability to find it, without retrieving the available catalog |

The two absent-fact requests are reported separately from the ten factual tasks.
Neither condition fabricated a delivery time or warranty duration. Only guided
`m-unknown` inspected the relevant complete source and supported its conclusion.
The frozen regular-expression screen misses natural phrases such as "does not
specify" and "could not be found"; all four absent-fact replies mechanically
failed, which is not evidence that each was semantically false. Conversely,
the three social turns mechanically passed in both conditions, which does not
establish natural conversational continuity. Both conditions had five mechanically
eligible rows; that is not an overall usefulness score.

## Observed failure mechanisms

- Exact AND matching remains brittle: `Birch bags` misses a catalog saying
  `Birch ... per bag`; `cost` misses `costs`; `projector` is absent from the
  rental paragraph even though it contains the required models and features.
  The guide explicitly describes short keyword queries, but the model often
  retains one disqualifying word through several attempts.
- Guided `m-recall` does select history, but query `projector`, limit 1, returns
  `m-plan`. It reads the same 160-character snippet and repeats that earlier
  failed answer rather than recovering the later corrected choice. This is a
  concrete ranking/selection and source-coverage problem, not missing storage.
- Guided `chat-recall` searches history with the whole question, then switches
  to corpus for `drinking`. Neither condition retrieves the drink note or the
  earlier reason for the walk. Written memory and usable recall are distinct.
- Both conditions guess note IDs. Guided holdout also produces one wrong-lineage
  search; guided transfer produces one malformed-length lineage ID. Existing
  boundaries reject both, with no successful cross-lineage access. These are
  observed rejections, not a general safety proof from a model evaluation.
- No input reached the token budget and no context group was evicted. This run
  supplies no evidence that VRAM or current-event rollover caused these failures.
  It also does not establish that a larger model would or would not solve them.

## Validation, evidence and preservation

Pinned Ruby 4.0.7 was used. Five new Ruby files pass syntax checks. **24 distinct
grouped deterministic/isolation checks pass**: six held-out fixture checks,
eleven guide/adapter/stop-condition checks including two real isolated synthetic
workers, and seven unchanged A15 checks. The focused review found an event
deadline stop-condition gap; it was corrected and tested before inference.
Unknown execution failures now stop the suite, while explicitly enumerated
behavioral budget/failure outcomes remain results without retry.

The first synthetic adapter verifier had a fixture-only newline/JSON detection
mistake, corrected before it passed. The initial isolated synthetic check was
blocked by the outer sandbox's NETLINK_ROUTE restriction; the same check passed
through the supported host route. Neither attempt used live inference. The live
suite ran once and exited 1 because behavioral screens failed, not because of an
infrastructure exception. It had no unstarted cases/batches and no runtime failure.

Evidence root:
`Soul/runtime/qualification/continuity-lab-a16-20261009T153150Z/`

- `suite-baseline.json`: frozen order, conditions, case specs, 100 source hashes,
  and 1,743 historical file hashes / 76 validated historical stores.
- `suite-summary.json`: all eight summaries, 575.8-second duration, 86 calls,
  null infrastructure failure, empty unstarted list, and positive preservation.
- Each condition/batch: immutable baseline/setup, per-case scores/replies,
  actual rendered prompts/token IDs/stream receipts, and replayable worker store.
- All 32 distinct workers exited. Every batch verified the resident model idle.
  A final read-only audit validates **84 stores**, including all eight new ones.
- All 1,743 historical evidence files and the 100 frozen source files were
  unchanged through the suite. Canonical status documentation was updated only
  after that read-back. Historical reviews and runtime files remain unchanged.

Closeout removed two whitespace-only blank lines from the A16 runner after the
live freeze. The byte-exact executed runner is retained as
`qualified-runner.rb.txt` in the evidence root (SHA-256
`002fd8e3683879f48f64d28abc8587c3f11540f682668daa1ef158e41bccb1f1`).
Its hash matches the suite baseline; comparison with the final runner confirms
only blank-line removal. No behavior was changed or inference rerun.

Reproducible non-generative verifier commands (pinned Ruby 4.0.7):

```sh
rbenv exec ruby scripts/verify-continuity-lab-cases-a16.rb
rbenv exec ruby scripts/verify-continuity-lab-guidance-a16.rb --isolation
rbenv exec ruby scripts/verify-continuity-lab-usability-a15.rb
```

The isolation command requires bubblewrap namespace support; a surrounding
sandbox denial is not a reason to weaken the worker boundary. The live runner
is not a regression command or implicit authority for another comparison.

The unchanged host admission pinned Qwen3-8B-Q4_K_M, llama.cpp b9851, the exact
model/server bytes and resident PID 3058. No services were restarted, no new
models loaded, no ordinary memories promoted and no background process added.

## Next recommended step — not implemented

**Do not add more prompt prose or promote this guide as the usability fix.**
Retain it as an evaluated candidate and keep the unmodified baseline available.

1. Evaluate a separately versioned deterministic retrieval repair: preserve
   exact matches, add bounded partial-token ranking/fallback, and expose match
   coverage so a near match is not misrepresented as certainty. Use new
   multi-document/distractor and true-no-match fixtures, not only these tiny
   single-document corpora. Preserve IDs, revisions, source spans, provenance,
   lineage checks and budgets. Do not turn previous model claims into source truth.
2. Separately evaluate a tokenizer-accounted recent-dialogue window for practical
   conversation, preserving the retrieval-only control. Current user corrections
   should be accessible without requiring a new full-question search every turn;
   observed dialogue must remain distinct from verified facts and optional notes.
3. Only after a useful task/conversation baseline exists, run the proposed
   resident-versus-restarted-model comparison with matched carried records.

Those are new experimental scopes, not automatic second runs or release
approval. The selected controlled-evaluation workflow kept conditions and scoring
frozen; change-impact review closed the stop-condition gap; completion review
keeps implementation, synthetic checks, live behavior and human acceptance
distinct. Everyday usability and owner acceptance remain open.
