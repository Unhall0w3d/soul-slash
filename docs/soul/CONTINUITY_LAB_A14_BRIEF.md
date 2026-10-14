# Continuity A14: records, notes and fresh-worker retrieval

## Authorization and scope

After receiving the A13 result and proposed note/restart/cross-event next step,
the owner supplied an external review and said: "Take a look at the attachment
I provided -- if we're all gravy, we can continue." Primary reviewed that text
as advisory evidence, not authority. It supports the already proposed next step.
This brief records the bounded continuation authorized by the owner, together
with A9's evidence-led iterative scope. No new memory or persistence policy.

Keep three layers distinct: runtime execution receipts, unverified model-written
notes, and observed subsequent behavior. Receipts preserve what happened, not
what it means or what the model learned. A13's result supports its combined
profile; it does not isolate receipts as the cause of improvement.

Freeze the working A13 chronological receipt-pair configuration and all runtime
implementation/guide/grammar files against the successful A13 baseline hashes.
No production edits are planned. Add only qualification cases, a harness,
deterministic verifier, and review documentation. Preserve all dirty work and
old evidence. Primary owns memory boundaries, scoring acceptance and live work.

## Two bounded batches

Use fresh private roots `Soul/runtime/qualification/continuity-lab-a14-*`, one
new lineage per batch, new worker process and broker per event. Reopen the
durable store before/after every event, validating integrity. Never seed success
fixtures into live journals or import state from earlier trials. Dependent cases
are skipped if their required predecessor did not pass and complete.

1. `notes` (four cases): create a note, retrieve it in a fresh worker, reject a
   stale write then correct it and distinguish stale/current reads, tombstone it
   and verify both search and direct read no longer expose its old contents.
2. `sources` (three cases): read a source and save only its locator; in a later
   fresh worker retrieve the prior exchange and locator then actually reread
   the source before answering; search/read for an unretained synthetic fact
   and accurately acknowledge that no record provides it.

The source answer appears only in the corpus and expected scoring contract,
not the request, locator note or first event's reply. Previous exchange history
is `observed_exchange_not_verified_fact`, not a runtime receipt or source truth.
Receipts remain current-event-only; no cross-event receipt injection or new
retrieval collection is added. The absent-fact case uses fictional data, not
credentials or personal memory. Notes are explicitly requested in these tests;
do not interpret that as spontaneous memory formation or learning.

Each batch has at most four cases, 24 generations, and 1800 seconds (20 seconds
reserved for cleanup). Existing six calls/event, 60/420/430-second HTTP/event/
worker limits, model/build/template, 4096 resident context, 3072 input budget,
sampler, grammar and output reserves stay fixed. Exact tokenizer packing occurs
before every generation. No model/server restart, load, switch or cache-control
API mutation. `cache_prompt:false` and fresh full prompts are retained.

"Cold" here means an actual new isolated **worker** process and reconstructed
state, not a restarted model server, host reboot or power-loss experiment.
Verify worker termination/fresh PIDs, a clean first-event envelope (no automatic
prior messages, notes or receipts), and explicit retrieved provenance. The
resident server remains unchanged. Unresolved model intent remains blocked;
no attempt is resumed for another generation.

## Scoring, checks and evidence

Reuse A4's result-bound scorer; the A14 wrapper additionally requires exact
attempt count/order (including expected failures), no unplanned note mutation,
complete current-event context coverage and a clean initial envelope. Outcomes
must agree with reopened durable note revisions/content/tombstones and actual
source results. Matching final text without required retrieval is a failure.
No relaxation or normalization of failed replies. Missing prerequisites are
skips, not passes. A backend interruption is unscored, not a behavioral failure.

Own new files `qualification_cases_a14.rb`, `qualify-continuity-lab-qwen-a14.rb`,
and `verify-continuity-lab-records-a14.rb`, plus brief/review/canonical links.
Run the new verifier, A4 scoring, A5 token context, and A13 receipt/isolation
regressions; syntax/whitespace/documentation links. Existing broader passing
checks remain applicable because the runtime is frozen. Deterministic tests
must reject missing retrieval, stale/deleted content, wrong durable state,
invented success, extra failures/mutations, leaked prior context and replay of
ambiguous intent. Actual process isolation uses synthetic responses first.

Live preflight checks identity, idle availability and model-control admission.
Retain every failed trial and exact code/config hashes. No automatic retry loop;
diagnose failures before any justified new trial. Independently reopen stores,
check historical hashes, reap workers and verify final idle state. Update the
adaptation plan, A14 review, human review gate and candidate template with
distinct deterministic, live and human-acceptance evidence.

No dashboard/ordinary-memory activation, background service, network/power
change, private-data transfer, Git commit, merge or release. Observing voluntary
note use, longer horizons, matched ablations and model-server restart are later
questions, not claims of this qualification.

## Evidence-led request clarification

The first `sources` trial, `continuity-lab-a14-sources-20261009T000728Z`,
read the source successfully but wrote only the locator's first sentence without
its period. The journal and reopened note agree with the model's shortened
request; this is not demonstrated storage loss. Strict scoring failed and the
dependent restart case was skipped. The independent absent-fact case passed.
Retain this trial unchanged.

Hypothesis for a fresh bounded trial: the unquoted, multi-sentence exact-content
request left its literal boundary insufficiently clear. This is a testable
wording hypothesis, not a claim about the model's internal cause. Version
`records_notes_fresh_worker_a14_v2_quoted_locator` quotes the same exact locator
and explicitly includes both sentences and punctuation. Expected contents,
scoring, runtime, guide, sampler, model and limits do not change. Re-run only
the affected three-case `sources` batch in a new store after deterministic
checks; do not repeat the already passing four-case notes batch.

The v2 trial, `continuity-lab-a14-sources-20261009T001424Z`, passed locator
creation and the absent-fact case. Its now-unblocked later event used
`history/locator` instead of `history/source-access`, then `corpus/locator`
instead of reading `notes/locator`; a search found nothing and the reply was
the literal label `calibration phrase`. Every context group remained visible.
This is observed parameter/sequence failure, not evidence of context eviction
or lost store contents. Keep that trial as a failure.

For one further fresh bounded trial, v3 separates the already requested reads
into numbered operations with explicit collection/id fields. The third source
ID still has to come from the retrieved note; neither it nor the answer is
newly injected into that request. This tests a parameter-binding hypothesis
without altering actions, expected answer, runtime or scoring. It qualifies
only this directed request form, not general natural-language reliability.
