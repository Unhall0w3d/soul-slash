# Continuity A13: practical receipt-retaining context

Owner authorization: after discussing the context-policy tradeoff, the owner
prioritized usability/usefulness first, research questions arising from the
actual environment second, and instructed: "okay, agreed. let's proceed based
on your recommendation." This approves the separate receipt-retaining profile;
it does not rewrite the A1 minimal condition or authorize production promotion.

## Outcome and contract

Implement opt-in `current_event_receipts_v1` on the existing tokenized streaming
path, exposed by `Config.qwen_v6_qualification`. Preserve every legacy default,
configuration digest, historical journal, and original whole-group policy.
Primary owns memory policy, reconstruction, containment, live work and integration.
A bounded worker may implement the new deterministic verifier after this contract.

- Only completed action/result pairs from the current event are eligible. No
  prior-event journal, ordinary Soul memory, private history, answer keys, new
  collection or cross-lineage retrieval is added.
- Retain newest full result and current request. When removing an oldest full
  group for the existing byte/token budgets, replace it with a factual compact
  receipt. Keep original call indices, recorded action/arguments except note
  content, actual success/failure/reason, note result revisions, and retrieved
  source identity/revision/digest/provenance/spans. Remove source text, search
  snippets and note-write contents; never summarize their meaning. Invalid
  responses retain their recorded rejection and raw-response digest, not an
  invented valid action. Raw complete evidence remains in the original journal.
- Receipts are an ordered prefix; full groups are the remaining ordered suffix.
  No duplicate/renumbered receipts, silent receipt eviction, selected-success
  filtering, inferred completion counter, forced next action or answer insertion.
  Maximum five previous pairs under the existing six-call profile. Receipts use
  the same 12,288-byte input bound and actual 2048/3072 input-token budget, not
  an additional context allowance. Essential overflow fails without generation.
- Record policy and receipt bindings in the context manifest; replay reconstructs
  the exact receipt projection from committed state before accepting model intent.
  Host preparation/generation remain single-use and consume identical token IDs.
  Unresolved model intent still blocks regeneration. Source metadata is not proof
  of understanding, current truth, task completion, or new authority.
- A distinct chronological message profile labels the receipt data and omitted
  contents. Old message profiles must not silently ignore a new-policy envelope.
  The model may make inferences in its reply, but inferred history is never
  converted into a runtime receipt or recorded approval by this feature.

No new service, background work, model/settings change, training, shell/tool
capability, network configuration, dashboard wiring, ordinary-memory promotion,
Git commit/merge/release, or automatic migration of old stores.

## Implementation and validation

Owned implementation: `lib/soul_core/continuity_lab/` context/config/projection/
broker/worker integration, `scripts/continuity-lab-worker.rb`, a new A13 verifier
and qualification harness/cases, this brief, adaptation plan and review links.
Preserve unrelated dirty files. Use pinned Ruby 4.0.7.

Deterministic coverage: default compatibility; exact receipt allowlist and
provenance; failures/repeated attempts/search/note/malformed responses; omitted
bulk content and Unicode/control-token escaping; byte/token packing; newest
result preservation; bounded overflow with no generation; forged/reordered/
cross-event receipt rejection; exact replay, interruption and no repeated
generation; matching worker/broker profiles and actual isolated-worker reap.
Run the A13 verifier plus A0/A1 core/recovery/context, A2 admission/isolation,
A3 transport, A4 action/scoring, A5 token context, A6/A8/A12 comparison, A7 stream/
isolation, A9 admission and A10 message-projection isolation regressions once.
Check syntax, changed-file whitespace and documentation links.

Then qualify in fresh private `Soul/runtime/qualification/continuity-lab-a13-*`
stores, retaining raw results and calibration. Reuse A12's clarified requests
with A8's frozen corpus and strict four-read/re-read contracts; test visible and
rollover cases under the new profile. Actual omission and receipt presence must
be observed separately from task success. Run tokenizer calibration first. Model
identity, grammar, sampler, six calls per case, 24 calls/1800 seconds per trial,
60/420/430-second request/event/worker limits and cleanup reserve remain fixed.
The A9 iterative authorization remains applicable: preserve a failed trial,
diagnose it, test a justified repair, and use new stores rather than resuming
ambiguous intent. No blind retry loop. Preflight must establish resident identity,
idle availability and non-disruptive use; no implicit model load or service fix.

Update the canonical human review gate/template and A13 review with distinct
implementation, deterministic, live and human-acceptance evidence. These narrow
tasks do not establish general long-horizon reliability, calibrated inference,
subjective experience, or production readiness.

## Pre-generation sizing adjustment

The first sizing run (`continuity-lab-a13-sizing-20261008T223400Z`) generated
zero responses: full visible input fit, but the 2048-token reread condition
could not fit essential receipts plus the newest result. Retain that evidence.
For the new profile only, consolidate duplicated v2/receipt guidance while
retaining the six generic JSON shape examples and exact tool contract. Do not
discard receipts, expand budgets, change corpus/tasks/scoring, or alter legacy
guides. Record every subsequent calibration measurement immediately so a
failed boundary also retains its exact measured envelope.

## Evidence-led presentation comparison

The first live trial (`continuity-lab-a13-20261008T223838Z`) passed the first
visible case. In reread-rollover, all four required reads succeeded; decision 4
had receipts 0/1/2 and the complete result 3, but requested an extra read at 768.
The following preparation failed at 2176 tokens with all receipts/newest result
retained. Ten generations, two scored cases, two unstarted, final idle verified.
This disproves "retaining receipts in an opening JSON array is sufficient for
this case," not a claim about the model's internal reason.

Preserve that profile and add `chronological_actions_v4_receipt_pairs` selected
only by `--receipt-pairs`. Render the same prefix records as historical
assistant/tool pairs before the full suffix, labeling compact results with
`execution_receipt: true`. Note-write partial arguments use a `recorded_action`
wrapper explicitly marking omitted content; invalid responses produce only
their recorded rejection/digest, not a fabricated assistant action. Keep all
receipt values, envelope/replay policy, tasks, corpus, budgets and settings.
Adjust the fixed guide only to explain this representation. Qualify sizing
before a fresh four-case trial. No task-specific progress counter or forced
answer is introduced.
