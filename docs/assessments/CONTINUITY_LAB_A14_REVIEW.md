# Continuity Lab A14: records versus knowledge

Date: October 8, 2026. Qualification results are recorded below. No dashboard,
ordinary-memory, model-server restart, merge or release promotion.

## External review and adopted interpretation

The owner supplied an advisory review attributed to ChatGPT GPT-6 Pro and
authorized continuation if consistent with the plan. Primary read the complete
attachment and reconciled it with A13 and the repository safeguards. The review
was not treated as authority, inserted into model context or used to approve
itself. [A14's brief](../soul/CONTINUITY_LAB_A14_BRIEF.md) records the resulting
bounded qualification; no cloud request/private-data transfer was made.

The adopted distinction is between:

1. Runtime receipts: recorded operations, results and source identities.
2. Model-written notes: unverified retained content, not privileged knowledge.
3. Later behavior: separately observed retrieval, interpretation and action.

Retaining history does not require deriving a lesson from it. Nor does a record
of accessing a source imply that its text is currently available or understood.
A13 supports its combined configuration, not an isolated causal claim about
receipts. We freeze that working configuration rather than perform an elaborate
ablation before usefulness qualification.

Two scope qualifications remain explicit: receipts are **current-event-only**;
later requests must retrieve notes/source/history through existing tools.
Retrieved history is a recorded user/assistant exchange, not an action audit or
verified truth. "Cold" means a new isolated worker and reconstructed state,
not a model-server restart, erased hardware cache or power-loss test.

## Changes and frozen boundary

Only new qualification code and documentation are added:

- `lib/soul_core/continuity_lab/qualification_cases_a14.rb`: two small directed
  batches and a strict wrapper around the existing result-bound scorer.
- `scripts/qualify-continuity-lab-qwen-a14.rb`: fresh owner-private batch stores,
  separate workers/brokers per event, dependency gates and replay/read-back.
- `scripts/verify-continuity-lab-records-a14.rb`: synthetic Runtime/Store and
  actual isolated-worker tests, malformed evidence and interrupted intent.
- A14 brief/review, adaptation plan and canonical review links.

The harness verifies the successful A13 baseline file SHA-256
`b24c56cbde8222b1040e354439b9403e3f07d8d567f60f0c79cf31f072513668`,
all 28 captured code hashes, config, message guide/profile and sampler before
live inference. Runtime, context policy, grammar, source retrieval, admission,
model/build and all old qualification implementations are unchanged.

Each batch is limited to four cases, 24 generations and 1800 seconds, with a
20-second cleanup reserve. Existing six calls/event, 60/420/430-second HTTP/
event/worker limits remain. It uses A13's non-rollover 3072-input-token budget,
4096 resident context and 768 output reserve. Actual tokenizer preparation is
still required before each call. Old A13 rollover results remain a separate
qualification, not re-run or newly attributed to A14.

## Deterministic and isolation evidence

Pinned Ruby: `/home/bhones/.rbenv/versions/4.0.7/bin/ruby`.

| Command (under `scripts/`) | Passing checks |
| --- | ---: |
| `verify-continuity-lab-records-a14.rb --isolation` | 10 grouped checks, including all seven fresh-worker scenarios |
| `verify-continuity-lab-scoring-a4.rb` | 18 |
| `verify-continuity-lab-token-context-a5.rb` | 41 |
| `verify-continuity-lab-receipts-a13.rb --isolation` | 31 |

**100 focused checks passed.** Other previously passing runtime checks remain
applicable to frozen files; they were not needlessly re-run or represented as
new live results. Synthetic actions pass through actual Runtime/Store effects,
then close/reopen and integrity comparison, not direct success injection.

The new wrapper requires exact attempts (including expected negative results),
ordered retrieval, precise replies, no unplanned note mutation, exact durable
note ancestry/content/digests, and a clean initial context with current-event
coverage. Correct final text without the required source read fails. Explicit
tests reject fabricated stale/deleted success, wrong ancestry, extra failures,
unexpected notes and prior-event context injection. Interrupted committed intent
reopens as blocked without another generation. Seven synthetic isolated workers
used distinct PIDs and were reaped.

Luna performed a read-only reuse map and implemented only the new verifier.
Primary retained policy, cases/scoring wrapper, harness, live work and acceptance
responsibility. The verifier exposed an initial wrapper mistake: expected note
effects omitted Store's `ancestry` field. Primary confirmed the reducer contract
and fixed the new wrapper before live use; runtime semantics were not changed.
A reported `.config(spec)` mismatch was retracted after checking the actual file.

The separate CLI readiness probe reported sandbox provider-reachability failure
and warnings; it is not the app's active permissions or evidence of an app
outage. Direct authorized host preflight confirmed resident PID 3058, unchanged
Qwen3-8B-Q4_K_M/build/template, amd-free core, nvidia-fallback and an idle slot.
An attempted isolation rerun inside the app sandbox could not create bubblewrap's
network namespace. The exact synthetic check then passed through the supported
host escalation; no isolation setting or runtime protection was weakened.

## Live results

Evidence roots below are under `Soul/runtime/qualification/` (timestamps UTC).
Each trial is separate; failed trials were not overwritten or reclassified.

| Trial | Scored result | Generations | Elapsed |
| --- | --- | ---: | ---: |
| `continuity-lab-a14-notes-20261008T235729Z`, v1 | 4/4 pass | 13 | 74.516 s |
| `continuity-lab-a14-sources-20261009T000728Z`, v1 | 1/2 pass; dependent third case skipped | 6 | 42.911 s |
| `continuity-lab-a14-sources-20261009T001424Z`, v2 | 2/3 pass | 10 | 62.922 s |
| `continuity-lab-a14-sources-20261009T001717Z`, v3 | 3/3 pass | 10 | 68.936 s |

The successful notes batch and final sources batch establish all **seven
directed cases**, using 23 generations across those two batches. All trials
together used 39 generations. This is not a seven-case first-attempt success
rate, a reliability estimate or a receipt-only causal comparison.

### Note lifecycle

Qwen wrote `beacon` revision 1, then retrieved it in a separate worker. The next
worker exercised the deliberately stale write (rejected), corrected revision 1
to revision 2, distinguished a stale read from the current one and replied with
the corrected text. The final worker tombstoned revision 2 to revision 3,
observed empty search and `not_found` from direct read, and replied `NOT FOUND`.
All notes, ancestry and receipts matched reopened durable state exactly. The
negative tool outcomes were expected tests, not unexpected execution errors.

### Source retrieval and retained failures

The first source-access event actually read the source but shortened the requested
two-sentence note to its first sentence without the period. That shortened value
was in the model's write request and durable note alike. Thus the strict failure
was not demonstrated storage loss. Its dependent case was correctly skipped;
the independent absent-fact case passed.

V2 quoted the same locator and explicitly requested both sentences/punctuation.
Locator creation passed. The later event then confused `history/source-access`
with `history/locator`, tried `corpus/locator`, searched unsuccessfully, and
answered with the literal label `calibration phrase`. No context was evicted.
This is a substantive parameter/sequence and answer failure, not merely reply
formatting. It remains a failed trial.

V3 separately numbered the existing three read operations and spelled out the
collection/id fields. The third corpus ID still had to be retrieved from the
note; the request did not supply `survey` or the expected answer. Both hypotheses
and exact deltas were recorded in the brief before their respective fresh trials.
Expected actions, source text, note content, scoring and runtime did not change.
No adaptive controller supplied additional next-action instructions between
calls or repaired model output; the initial requests were explicitly directed.

In v3, a clean new worker explicitly retrieved, in order:

1. `history/source-access`, provenance `observed_exchange_not_verified_fact`.
2. `notes/locator`, provenance `unverified_model_note`.
3. `corpus/survey`, provenance `operator_selected_source_not_authority`.

Primary independently reopened the journal and verified that neither the initial
context nor the first two retrieved texts contained the answer. The third result
did contain it, and Qwen replied `copper heron 58`. No note changed. The absent
synthetic fact separately produced empty search, a `not_found` read and `UNKNOWN`
without creating a speculative note. The wording changes are consistent with
improved literal/parameter binding in these runs, not a proven general cure.

### Final evidence and cleanup

All 12 workers across the four trials used distinct PIDs and had exited at
independent read-back. Every batch finished with verified idle resident inference;
no model-server restart or switch occurred. All **73 stores** passed journal
integrity without resuming events. All 28 frozen A13 code hashes and the final
trial's captured code hashes still match the current files.

The 20 pre-A14 evidence roots contain 1,457 files, unchanged before/after by
sorted relative-path/content-hash aggregate:
`fe5f31594091a1533c21d56fef67ffd2d64f3cab3b8faab4115ce6747a7e0460`.
No historical evidence or failed trial was deleted. The final source case version
is `records_notes_fresh_worker_a14_v3_structured_reads`; the notes requests are
unchanged from their successful v1 trial.

## Limits and next gate

These tasks explicitly prescribe note operations and retrieval, including exact
abstention when no record supplies an answer. Passing them establishes directed
execution/retrieval under the tested conditions, not voluntary memory selection,
causal learning, calibrated free-form uncertainty or an emerging personality.
The two prompt-sensitive failures particularly preclude calling this robust
free-form conversational behavior. The runtime preserves evidence; it does not
guarantee that the model will use that evidence correctly.
Tombstones hide old contents from current-note search/read; they do not purge
immutable journals or historical exchanges. No physical deletion was performed.

No cross-event receipt injection, automatic private-memory import, ordinary Soul
state promotion, service, background inference, network or power change, Git
commit, merge or release. Broader conversational usability and optional-note
behavior remain distinct from directed qualification and from user acceptance.
The next proposed usability step is a small foreground task set with less
prescriptive requests and optional, not commanded, note use. Keep retrieval
evidence and unsupported claims visible; no dashboard or ordinary-memory
promotion is implied by this candidate-complete qualification.
