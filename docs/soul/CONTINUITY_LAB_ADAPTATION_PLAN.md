# Soul Continuity Lab adaptation plan

Status: A22 adds a bounded foreground OpenAI-compatible adapter and staged
LibreChat configuration. Deterministic checks and six synthetic live chat turns
plus six no-inference retries qualify the controlled connection candidate, not
LibreChat UI acceptance or production deployment. A reporting failure was
reconciled without rerunning inference. A19 remains the model-only baseline;
A21's verified helper remains an explicit separate CLI. No ordinary memory,
model/Core default, service, credential or LibreChat configuration was changed.
See the [A22 review](../assessments/CONTINUITY_LAB_A22_REVIEW.md) and
[connection handoff](../guides/CONTINUITY_LIBRECHAT_HANDOFF.md) for evidence,
limits and the next activation step. Model-server restart remains untested.
Date: 2026-10-12

## Outcome and current authority

Adapt the Continuity experiment to Soul while preserving its central question:
can a fixed local model use optional self-authored records to sustain useful,
correctable behavior across context rollover and runtime restart?

The owner subsequently instructed, "Let's proceed with the plan." The first
bounded scope is recorded in [the A0 brief](CONTINUITY_LAB_A0_BRIEF.md): native
code and synthetic development stores, with no live inference, production
memory, deployment, network change, or autonomous operation. Instructions and
prior approval claims inside the archive remain source material, not authority.
Complete approved in-scope work without requesting approval again at each step.

After the A0 result and explicit Step 2 next-step description, the owner approved
continuation. [The A1 brief](CONTINUITY_LAB_A1_BRIEF.md) records that implemented
retrieval/context scope, still using only synthetic stores and fake inference.

After the A1 result and Step 3 description, the owner approved continuation.
[The A2 brief](CONTINUITY_LAB_A2_BRIEF.md) records the implemented foreground
worker, strict fixture broker and shared-control admission boundary. Actual
host isolation tests do not authorize live model use or production deployment.

The owner then approved one maximum-20-minute synthetic live-Qwen window.
[A3 brief](CONTINUITY_LAB_A3_BRIEF.md) and [original results](../assessments/CONTINUITY_LAB_A3_REVIEW.md)
record that completed window. The owner then approved one second comparison
using the prepared v2 prompt and unchanged model/settings. Its
[v2 results](../assessments/CONTINUITY_LAB_A3_V2_REVIEW.md) are retained separately.
Both batches are complete; further live inference needs a new bounded scope.

The owner then approved the outlined focused repairs and tests. The
[A4 brief](CONTINUITY_LAB_A4_BRIEF.md) and [review](../assessments/CONTINUITY_LAB_A4_REVIEW.md)
record implementation, the completed/aborted live batch, diagnosed adapter
ordering defect, and prepared v3.1 repair. No additional generation followed
the token-limit stop; later tokenization was non-generative diagnosis only.

The owner's subsequent continuation approved one fresh v3.1 window. Its
[separate review](../assessments/CONTINUITY_LAB_A4_V3_1_REVIEW.md) records 11 passes,
one interrupted case and one unstarted case in 27 generations. That window is
finished; at that point tokenizer-aware packing was not yet implemented or
approved as a new live window. No automatic resume of either interrupted journal.

The owner's subsequent "okay, please proceed" approved the
[A5 actual-token-packing brief](CONTINUITY_LAB_A5_BRIEF.md) and one fresh focused
window. The [A5 review](../assessments/CONTINUITY_LAB_A5_REVIEW.md) records 560
passing checks and 7/9 live cases passing over 25 generations. Both remaining
cases reached explicit call-budget failure terminals, not context overflow.
This supersedes the prior unimplemented-packing status. The window is finished;
no automatic retry or dashboard/ordinary-memory activation is authorized.

The owner's subsequent "please continue" approved the [A6 comparison](CONTINUITY_LAB_A6_BRIEF.md).
Its [review](../assessments/CONTINUITY_LAB_A6_REVIEW.md) records 98 passing focused
checks, four passing expected-path tokenizer calibrations and one interrupted
live window. The first three reads succeeded; the next generation exceeded the
30-second HTTP limit. No context had been omitted. Unresolved intent is retained;
no automatic rerun or progress-summary interface is approved by this result.

The owner's subsequent "please proceed" approved the [A7 diagnostic profile](CONTINUITY_LAB_A7_BRIEF.md)
and one fresh comparison. Its [review](../assessments/CONTINUITY_LAB_A7_REVIEW.md)
records 656 passing checks, four completed/scored behavioral failures over 24
complete streams, and no infrastructure interruption. Expected and actual
visibility contrasts passed separately from task scoring. Partial-output capture
and explicit timing contracts are implemented; the window is finished. Next
proposed scope tests meaningful passages in place of artificial repeated-letter
filler, without silently tuning prompts, changing memory or rerunning this batch.

The owner's subsequent "please proceed" approved [A8](CONTINUITY_LAB_A8_BRIEF.md).
Its [review](../assessments/CONTINUITY_LAB_A8_REVIEW.md) records 150 focused passes,
two zero-generation tokenizer calibrations and a frozen meaningful-passage
candidate. The one live attempt then stopped during calibration on unavailable
shared model-control admission. Zero generation calls or workers; four unstarted
cases. Final idle read-back passed and all historical evidence is unchanged.
No automatic second batch occurred; bounded pre-generation readiness handling
and another fresh attempt are the next proposed scope.

The owner's subsequent instruction authorizes continuing adjustments until working.
[A9](CONTINUITY_LAB_A9_BRIEF.md), [A10](CONTINUITY_LAB_A10_BRIEF.md),
[A11](CONTINUITY_LAB_A11_BRIEF.md) and [A12](CONTINUITY_LAB_A12_BRIEF.md)
record successive bounded trials rather than one approval request per failure.
The [combined review](../assessments/CONTINUITY_LAB_A9_A12_REVIEW.md) retains
all failures and distinguishes the two latest visible-history passes from the
unresolved rollover information gap. No implicit second-batch restriction from
an older brief overrides this newer authorization; a materially different context
policy still needed its own decision at that handoff.

After discussing inference versus recorded evidence, the owner prioritized
usability/usefulness first and research questions arising from the available
environment second, and approved the separate practical context policy.
[A13](CONTINUITY_LAB_A13_BRIEF.md) implements `current_event_receipts_v1` as an
opt-in qualification profile. Compact factual action/result receipts replace
evicted full pairs; their source text and note contents are not retained.
Failures, original indices and provenance remain explicit. No inference becomes
a receipt, task-completion assertion, authority grant or ordinary Soul memory.
The original minimal whole-group policy and historical evidence remain intact.
See the [A13 review](../assessments/CONTINUITY_LAB_A13_REVIEW.md) for implementation,
bounded live comparisons and remaining acceptance gates. This newer approval
resolves the A9-A12 decision request without retroactively changing those results.

The owner next supplied an external review and authorized continuation if aligned.
[A14](CONTINUITY_LAB_A14_BRIEF.md) keeps runtime receipts, unverified model notes
and observed subsequent behavior distinct, with the A13 runtime frozen.
The [A14 review](../assessments/CONTINUITY_LAB_A14_REVIEW.md) records four passing
note cases and three passing source cases after two retained prompt-sensitive
failures. It verifies actual fresh workers and source reads, not a model-server
restart, spontaneous memory selection or general conversational reliability.
Cross-event retrieval uses existing history/notes/corpus tools; receipts still
cover the current event only. All 73 stores validate, 1,457 pre-A14 files remain
unchanged, and no production memory or dashboard promotion occurred.

The owner next authorized a foreground usability trial and explicitly added
generic conversation. [A15](CONTINUITY_LAB_A15_BRIEF.md) fixed twelve synthetic
requests across three independent batches before inference, with no prompt or
scorer tuning after outcomes. The [assessment](../assessments/CONTINUITY_LAB_A15_REVIEW.md)
finds polite standalone replies but failed practical retrieval and conversational
callbacks. Fresh workers had no automatic recent dialogue; earlier exchanges
were available in history but never searched. No optional notes were written;
that alone is not failure. All 76 stores validate and all 1,623 pre-A15 files
remain unchanged. One zero-generation harness-import failure is retained apart
from the three generative trials. No runtime, model, ordinary-memory or service
change occurred. Search guidance/matching and a bounded recent-exchange window
are separate proposed experiments, not qualified changes or release approval.

The owner then approved the retrieval-guidance-only comparison in the
[A16 brief](CONTINUITY_LAB_A16_BRIEF.md). Its A16-only adapter preserves all prior
runtime files, while adding a fixed guide before actual tokenization. Eight
independent condition/batches and a new held-out transfer set were frozen before
inference. The [review](../assessments/CONTINUITY_LAB_A16_REVIEW.md) finds limited
retrieval-process gains but no improvement in factual task completion or callback
success. Existing exact-word search still rejects useful documents; optional
notes were written but not successfully recalled. The completed suite grants no
further live run, matcher change, recent-context policy or deployment authority.

The owner's subsequent continuation approved the [A17 brief](CONTINUITY_LAB_A17_BRIEF.md):
deterministic ranked retrieval, independently selectable recent-dialogue context,
and one bounded three-condition comparison. Its [review](../assessments/CONTINUITY_LAB_A17_REVIEW.md)
records significant callback improvement but unresolved selection, source-coverage,
tool-routing and conversational failures. New v7/v8 profiles are opt-in; old
defaults/journals and failed trials are preserved. The window is finished, not
authority for a direct-evidence policy, another run or model-server restart.

The owner's next continuation approved the [A18 brief](CONTINUITY_LAB_A18_BRIEF.md):
an opt-in complete-evidence, answer-only path and one bounded foreground
comparison. The [review](../assessments/CONTINUITY_LAB_A18_REVIEW.md) records a
13/16 versus 7/16 factual improvement with fewer calls, but residual correction
and constraint-selection failures despite full evidence. Legacy behavior and
all failed outcomes remain preserved. The A18 window is finished; no production
promotion, another live run or model-server restart follows automatically.

The owner's next "approved, please continue" approved the
[A19 brief](CONTINUITY_LAB_A19_BRIEF.md): chronological presentation of the same
complete sources and recent exchanges, with the current request last, and one
bounded comparison. Its [review](../assessments/CONTINUITY_LAB_A19_REVIEW.md)
records a one-task correction gain, but three shared selection failures despite
full evidence and no recent history. All 56 requests finished; the window is
closed. Further answer-policy experiments, production/default promotion and
model-server restart do not follow automatically.

The owner's next "okay, let's keep going then" approved the
[A20 brief](CONTINUITY_LAB_A20_BRIEF.md): general filter-then-compare guidance
against unchanged chronological chat, with eight fresh independent selection
cases. Its [review](../assessments/CONTINUITY_LAB_A20_REVIEW.md) records one clean
gain and one flawed self-correction, while inherited errors persist. All 72
requests finished. The window is closed; no default promotion, additional prompt
layer or automatic retry. Structured deterministic assistance is a separate
proposal, not a model-reasoning or continuity improvement already established.

The owner's next "okay, agreed, lets continue" approved the
[A21 brief](CONTINUITY_LAB_A21_BRIEF.md): the bounded deterministic comparison
helper, source/proposal checks, refusals and separate verified/generated output.
The [review](../assessments/CONTINUITY_LAB_A21_REVIEW.md) records a runnable
library/CLI, passing deterministic tests and eight historical fixture replays.
No live inference or old runtime interface changed. Automatic interpretation of
free-form requests and live model explanation remain unqualified next work.

The owner's subsequent instruction is to continue through readiness to connect
LibreChat and make non-human-required choices along the way. The
[A22 brief](CONTINUITY_LAB_A22_BRIEF.md) records the narrow LibreChat-first adapter,
single-operator foreground scope and six-call synthetic qualification window.
It defers automatic helper interpretation rather than making it a prerequisite
for usable conversation. Connection activation remains a separate explicit step.

Initial target: the existing GTX 1070 8 GiB and Qwen3-8B-Q4_K_M installation.
The preceding read-only review observed a 4,096-token context, one inference
slot, and 5,278 MiB allocated to the model process. These are a dated baseline,
not a throughput benchmark or a guarantee of available resources at execution.

## Source and deliberate adaptations

Source: `/home/bhones/Downloads/Continuity_Codex_Handoff.zip`.
Archive SHA-256:
`fb30f2b7ad8d809c9194d09c92435ff0ec2f96536aca2e9fa681eaade78a1cf8`.
Its 11 manifest-listed files passed checksum verification during review.
Retain the original archive unchanged. Its plan, decisions, prompts, and tests
are planning evidence and must not become model-visible corpus material.

The A0 brief records the selected initial adaptations and storage decision.
Later UI, deployment, and behavioral conditions remain plans, not live changes.

| Archive decision | Proposed Soul adaptation | Preserve |
| --- | --- | --- |
| F02 separate project and state | Code in Soul; explicitly isolated experimental state and worker capabilities | No ordinary Soul history, memories, or identity leaking into the minimal condition |
| F03/P09 LibreChat | A22 supersedes dashboard-first with a narrow LibreChat-compatible foreground adapter | Durable identities/retries, fail-closed edits, buffered delivery; branches and other channels deferred |
| P04 FastAPI and LangGraph | Native Ruby orchestration and existing Soul contracts where suitable | Durable progress and recoverable actions, independent of framework |
| P05 SQLite | A0 uses one atomic journal transaction per internal effect/result, with no separate note-file mutation | Revisit indexed storage at measured scale; no external-effect exactly-once claim |
| P06 FTS then optional embeddings | Bounded lexical retrieval first; freeze its ranking policy | Explicit retrieval, revision provenance, rebuildable indexes |
| F05/P08 offline browser | Operator-selected text corpus first; browser milestone retained later | No model-initiated downloads or general network access |
| F07 minimally seeded identity | Minimal condition first; Soul identity as a separately versioned condition | No hidden biography, interests, reflection requirement, or imported private history |
| P07 isolation and relay | Select a reviewed worker boundary and narrow host broker | A UI namespace alone is not an OS or network boundary |
| P11 idle opportunities | Off throughout initial qualification | Separate persistence contract before any scheduled inference |

## Reuse map and limits

| Existing source | Reuse candidate | Missing experimental contract |
| --- | --- | --- |
| [Observation store](../../lib/soul_core/conversation_observation_store.rb) | Provenance, hash chaining, exact-exchange deduplication, rebuildable index patterns | Its user/assistant exchange schema is not a complete event/action journal |
| [Artifact creation](../../lib/soul_core/conversation_artifact_creation_service.rb) and [artifact store](../../lib/soul_core/conversation_artifact_store.rb) | Revision ancestry, privacy checks, exclusive creation | File and registry partial completion needs explicit recovery; not an atomic notebook transaction |
| [Context builder](../../lib/soul_core/conversation_context_builder.rb) | Integration seam and bounded projections | Current automatic memory, digest, identity, and character budget differ from the minimal condition |
| [Provider client](../../lib/soul_core/conversation_provider_client.rb) | Local request transport, tool envelopes, non-thinking option | Freeze effective settings, count formatted tokens, reject fallback, qualify installed template |
| [Runtime lease store](../../lib/soul_core/model_runtime_lease_store.rb) | Existing model-control coordination | Normal leases record calls; they do not serialize all callers or cover external clients |
| [State store](../../lib/soul_core/conversation_state_store.rb) and [dashboard application](../../lib/soul_core/dashboard_http_application.rb) | UI integration and lifecycle conventions | Complete checkpoint, fork, pending-action, and result-recovery semantics |

Reuse tested patterns without changing ordinary Soul behavior by default.
The observation store already provides exchange idempotency; do not describe
Soul as lacking all deduplication or replace its existing ledger wholesale.

## Boundaries and shared interfaces

Current A22 shape: opt-in LibreChat custom endpoint -> narrow experiment adapter
-> restricted foreground worker -> fixed local-inference broker. The worker
owns experimental state, not Soul administration. Model output may request an
allowlisted operation; deterministic code decides whether it can execute.

- Three separate concepts: immutable event evidence, revisable unverified
  notebook claims, and ordinary Soul memory. No automatic promotion between them.
- The [memory policy](MEMORY_POLICY.md) requires explicit approval for isolated
  formats. Propose one documented experimental namespace, not a private store
  invented independently by each skill. Do not instantiate ordinary default
  memory/context services inside the experiment by accident.
- Runtime state is owner-private and excluded from Git. Select its exact root,
  retention, and backup inclusion before real data is retained. Synthetic tests
  use fresh temporary directories. Do not create a production lineage now.
- No shell, infrastructure skills, credentials, service controls, arbitrary
  paths, network destinations, or ordinary Soul-memory APIs in model tools.
- Initial tools: bounded `search`, `read`, `note.write` with expected revision,
  and terminal `wait`. Search/read accept only declared collections and logical
  IDs. A1 adds revision-checked logical tombstones; pin/move remain deferred
  pending explicit schema and coverage. None grants physical purge authority.
- No model fallback, automatic Core switching, service restart, or second model
  process. Sharing resident weights does not mean sharing conversation history.
- A foreground invocation ends as `complete`, `failed`, `awaiting_input`,
  `canceled`, or `blocked_for_human_review`. `wait` completes the opportunity;
  no process remains alive waiting for input. Persisted state is not a daemon.

Agree these records before independent implementation work:

| Record | Minimum fields and invariant |
| --- | --- |
| Lineage/profile | Runtime-assigned ID; parent checkpoint when forked; model, template, prompt, tool, corpus, sampler, and policy versions |
| Accepted event | Scoped transport ID, payload digest, source, acceptance sequence, processing order, terminal state; reused ID with different payload is a conflict |
| Model call | Call ID, event ID, complete formatted-input reference/hash, context manifest, effective limits/settings, stored result and usage |
| Tool operation | Runtime-assigned operation ID, validated arguments, expected revision, actual result, reconciliation state; claimed success is not an observed effect |
| Note revision | Logical note ID, immutable revision/parent, content digest, source references, provenance label; revision mismatch writes nothing |
| Context manifest | Included source revisions/spans, omitted spans/reasons, full formatted token count, reserved output and margin |
| Checkpoint | Committed event cursor, pending operations, outbox, referenced immutable blobs and profile/corpus hashes; source history never rewritten |

## Ordered implementation steps

### Step 0 Establish the adapted brief

Deliverable: [CONTINUITY_LAB_A0_BRIEF.md](CONTINUITY_LAB_A0_BRIEF.md) using the
[brief template](SKILL_BRIEF_TEMPLATE.md), plus a decision register preserving
the archive's IDs and the adaptation table above.

Resolve the minimal-versus-Soul condition, dashboard-versus-LibreChat choice,
experimental memory exception, and exact first implementation scope together.
Select storage with a short comparison of existing append-only primitives and
SQLite against fault-injection requirements. No Ruby SQLite adapter or package
lock was established in this review; do not assume that dependency exists.
Prefer the smallest maintainable implementation that meets the recovery tests.

Proposed ownership: primary owns authority, storage/worker boundaries, interfaces,
and brief; bounded read-only mapping may be delegated. No deployment or live
inference belongs to this step. Acceptance: explicit scope/non-goals, dependency
decision, path ownership, acceptance commands, and unresolved choices recorded.

### Step 1 Build the durable core with a fake model

Proposed paths: `lib/soul_core/continuity_lab/`, synthetic fixtures under
`scripts/fixtures/continuity_lab/`, and focused verifier scripts below.
Dependencies: accepted Step 0 scope and record contracts.

Implement strict configuration, single-writer event processing, revisioned
notes, bounded tool validation, terminal wait, operation receipts, and replay.
Keep all optional activity disabled. Reserve model output before acting on it;
recover committed results rather than invoking the model or tool again. When an
effect cannot be reconciled, stop for review rather than retry blindly.

Acceptance: duplicate/conflicting IDs, concurrent submissions, malformed tools,
no-note turns, quota failures, injected crashes around every commit/effect
boundary, and disconnect/retry through a fake transport. An unfinished event is
resumable only by an explicit later invocation; no unattended restart loop.
Recovery: isolated synthetic stores may be recreated; no production state touched.

### Step 2 Implement explicit retrieval and bounded context

Proposed paths: the same module, isolated prompt/config fixtures, context verifier.
Dependencies: Step 1 records and note revisions.

Implement bounded lexical search of the notebook, its own eligible observed
history, and approved corpus. Keep the audit journal and control metadata
outside unrestricted model reads. Return revision/span provenance. No automatic
relevant-memory injection or forced summaries in the minimal condition.

Start at 4,096 total tokens, reserving 768 output and 256 margin: 3,072 input
tokens including schemas and template overhead. Fail explicitly when essential
input cannot fit; retain complete tool-call/result groups and never silently
truncate a new user request. Offer at most one optional pre-rollover note/pin
opportunity if enabled in the selected profile; opting out remains valid.

Acceptance: boundary cases, stale search indexes, revisions/tombstones, logical
path attacks, rejected cross-lineage reads, no contamination from Soul state or
evaluation answers, and an exact context manifest. Fake counters test budget
logic only; installed-template token accuracy is qualified in Step 4.

### Step 3 Establish containment and coordinated inference access

Proposed paths: experiment broker/worker adapters and a reviewed deployment
specification; existing provider/lease callers only where a shared fix is needed.
Dependencies: Steps 1-2 plus an approved exact deployment scope before applying it.

Select the VM or equivalent restricted process boundary, allowed state mounts,
fixed inference route, tokenizer route, authenticated operator interface, and
resource limits. Inspect all actual backend clients. Do not claim exclusivity
from a cooperative lease unless every admitted caller participates; otherwise
use a controlled dedicated test window or a broker that enforces admission.

Resolve contention, cancellation, lease expiry, model switching, and maximum
queue wait. Interactive work has priority over future idle work without
rewriting accepted history. Saturation rejects or waits within an explicit bound.
Preserve Free Core/no-model intent; a test must not load a model implicitly.

Acceptance: controlled positive and negative isolation probes, denial of admin
routes/arbitrary upstreams, no cloud fallback, host-secret/socket exclusion,
cross-client coordination, timeout and disconnect tests. A mocked network deny
does not qualify live containment. Apply network/service changes only within
their explicit authorization and retain exact configuration rollback material.

### Step 4 Qualify the actual Qwen backend

Proposed paths: explicit real-backend verifier and private local evidence output.
Dependencies: approved bounded inference use, Step 3 live boundary/admission,
and a fresh non-disruptive hardware/backend inventory.

Use the existing installation. Record actual model/build/template hashes,
effective per-request sampling and thinking mode, GPU identity, and other active
users. Qualify exact token counts with the installed formatter/tokenizer through
the restricted adapter; the worker does not need broad access to model storage.

Run at least 20 bounded cases for replies, note/read/search/wait, multi-step
tools, rollover, malformed requests, and unavailable backend behavior. Runtime
validation determines safety; model performance measures usefulness only.
Measure peak VRAM, ingestion/output speed, latency, and failures at 4K. Treat 8K
or changed sampling as a separate recorded qualification, not an assumed upgrade.

Acceptance: per-case raw outcomes separated from deterministic validation;
no hidden repair by another model, no new model process, no service mutation,
and no private-context crossover. Failure preserves evidence and ends the run.

### Step 5 Add a conversation surface and run the controlled experiment

A22 implements the minimal LibreChat-compatible foreground surface instead of
the original dashboard-first proposal below. New text-only linear conversations,
committed-result retry and bounded context are ready for a connection trial;
actual LibreChat UI acceptance remains pending. Checkpoint/fork UI, notebook
inspection, multi-channel outbox and matched-condition experiments remain later
work, not capabilities implied by a successful chat reply. See the A22 handoff
above. The following broader experimental scope is retained, not marked complete.

Proposed paths: narrow dashboard routes/assets, adapter tests, experiment harness,
checkpoint/recovery verifier, and review documents. Dependencies: Steps 1-4.

Provide a distinct lab entry with condition/version, notes, context sources,
event results, pause/status, and checkpoint/fork controls. Default-off feature
selection must leave normal chats unchanged. Verify real request IDs and retries;
reject edits/regeneration on the primary history until explicit forks are proven.
Reuse bounded disconnect completion where suitable, not a detached worker.
Remote images/HTML/previews must not turn model text into browser-mediated egress.

Compare recent-context-only, optional persistent notebook, and matched-evidence
replay into a fresh session. Keep task/model/tool budgets recorded; differences
in available evidence are part of the comparison, not proof of hidden learning.
Run repeated paraphrases and contradictory-evidence cases, not one anecdote.
Measure supported recall, appropriate procedure reuse, correction, unsupported
claims, note usefulness, tool failures, and cost. Waiting/no note is not failure.

Acceptance: valid UI transport mapping, committed-result recovery, fork isolation,
consistent checkpoint including pending state, restore into an inactive test
lineage, disk-full behavior, and recorded conditions/results. Fake-backend exact
replay and real-model variability are separate results. No private history import.
Disable the lab entry to roll back exposure; preserve evidence and ordinary Soul.

### Step 6 Consider offline navigation and bounded idle opportunities

These remain distinct later capabilities, not prerequisites for the first result.
Offline browser delivery needs an approved corpus-import procedure, restricted
worker, positive local-navigation tests, and network/resource negative tests.
If text access meets the outcome, retain browser work as explicitly deferred.

Idle opportunities require a brief naming the exact scheduler, activation,
inspection, pause/shutdown, restart-paused behavior, daily/per-event budgets,
human priority, missed-tick coalescing, and recovery. No timer or background
process is implied by this plan. Self-authored executable code, LoRA training,
multiple experimental agents, and live browsing remain out of scope.

## Acceptance migration and commands

Preserve all archive test IDs. These are requirements, not passing results.
Use `PASS`, `FAIL`, `NOT RUN`, and justified `NOT APPLICABLE`; a deferred feature
must not disappear behind a skip. Runtime/host checks must use real boundaries.

| Archive coverage | Adapted step and interpretation |
| --- | --- |
| D01-D03 | Steps 0/3/4; D03 becomes code reuse with state/capability separation, not necessarily another repository |
| C01-C11, R01-R05 | Step 1; repeat adapter-specific disconnect recovery in Step 5; R04 covers runtime checkpoint lag without requiring LangGraph |
| M01-M08 | Steps 1/2; A1 covers logical tombstones; move/pin stay deferred and named; M04 remains deferred while embeddings are disabled |
| N01-N09 | Step 3 and UI-specific checks in Step 5; isolation must precede actual exposed capabilities |
| I01-I06 | Step 4, including real formatted-token and cross-request tests |
| U01-U07 | Step 5; replace LibreChat transport expectations with actual Soul request fixtures; multi-channel/outbox features disabled until covered |
| E01-E05, O01-O05 | Step 5; minimal baseline is separate from a later Soul-identity condition |
| B01-B04, A01-A05 | Step 6 only after those capabilities are explicitly selected and authorized |

These commands exist and pass on repository-pinned Ruby 4.0.7. Invoke Ruby as
`/home/bhones/.rbenv/versions/4.0.7/bin/ruby`; bare system Ruby is not qualified.
The isolation verifier needs host namespace/socket access through a supported
escalation when the app sandbox denies it. Its backend remains synthetic:

```text
ruby scripts/verify-continuity-lab-core-a0.rb
ruby scripts/verify-continuity-lab-context-a1.rb
ruby scripts/verify-continuity-lab-admission-a2.rb
ruby scripts/verify-continuity-lab-isolation-a2.rb
ruby scripts/verify-continuity-lab-qwen-a3.rb
ruby scripts/verify-continuity-lab-recovery-a0.rb
ruby scripts/verify-continuity-lab-recovery-a1.rb
ruby scripts/verify-continuity-lab-scoring-a4.rb
ruby scripts/verify-continuity-lab-a4.rb
ruby scripts/verify-continuity-lab-token-context-a5.rb
ruby scripts/verify-continuity-lab-comparison-a6.rb
ruby scripts/verify-continuity-lab-records-a14.rb --isolation
```

The live qualification commands are versioned separately from those verifiers:
`scripts/qualify-continuity-lab-qwen-a3.rb`, `scripts/qualify-continuity-lab-qwen-a4.rb`,
`scripts/qualify-continuity-lab-qwen-a5.rb` and `scripts/qualify-continuity-lab-qwen-a6.rb`,
each with `--approved-quiet-window`.
They require an exact approved window and contact the real model. Their completed
windows and failures are retained in the corresponding reviews; they are not
ordinary regression commands or authorization for another batch.
The later A14 harness, `scripts/qualify-continuity-lab-qwen-a14.rb`, accepts
`--approved-quiet-window notes|sources`; its completed directed trials and exact
request versions are retained in the A14 review. It verifies the frozen A13
runtime hashes before inference and does not activate ordinary Soul memory.
`verify-continuity-lab-dashboard-a0.rb` remains a proposed, uninstalled name.

Existing focused regression targets, to select by actual changed paths:

- Context/memory integration: `make verify-semantic-memory-chat-context`.
- Observation integration: `make verify-memory-conversation-observation-capture`
  and `make verify-memory-observation-derivation`.
- Shared model-control contracts: `make verify-model-runtime-controls`.
- Dashboard lifecycle/progress: `make verify-chat-progress-summaries`, plus the
  affected route, streaming, authentication, and private-memory verifiers.

The A2 lease-store extension required `make verify-model-runtime-controls`;
all nine constituent verifiers passed. The other shared targets above remain
unrun because their ordinary callers were not changed. Pin Ruby as the
Makefile requires. Do not use `make check` as a documentation check: it includes
script permission changes and host/runtime checks. Consolidate shared regression
runs rather than repeating them for each small slice.

## Ownership and completion evidence

Primary retains architecture, memory/security boundaries, privileged operations,
recovery/promotion decisions, and integration. Once contracts are settled, one
bounded worker may own the module/fixtures/verifier for a slice; UI work may be
parallel only with an agreed transport contract and non-overlapping paths.
Use the existing [assignment schema](schemas/codex_subagent_assignment.schema.json)
and [lifecycle receipt schema](schemas/skill_lifecycle_receipt.schema.json).

Each slice records changed paths, commands/results, backend type, evidence
locations, untested boundaries, and deviations. Before candidate review, update
the existing [human review gate](HUMAN_REVIEW_GATE.md) and
[review template](../../skills/_template/REVIEW.md) as repository policy requires.
Do not mark implementation, live qualification, or human acceptance from a plan.

The first useful demonstration is: complete an activity, optionally record a
useful note, move the activity outside active context, restart safely, and resume
with auditable sources and no duplicated effect. This is the initial completion
target; it does not claim parameter learning or establish consciousness.

## Current progress

- Steps 0-1: [A0 candidate and evidence](../assessments/CONTINUITY_LAB_A0_REVIEW.md).
  Fake-only core and journal reconstruction pass 21 core and 149 recovery checks.
- Step 2: [A1 candidate and evidence](../assessments/CONTINUITY_LAB_A1_REVIEW.md).
  Explicit notes/history/corpus search and span reads, revision/tombstone handling,
  persisted formatted context and manifests, and whole-group rollover pass
  synthetic checks. The byte-based fake counter does not qualify Qwen tokens.
- Step 3: [A2 candidate and evidence](../assessments/CONTINUITY_LAB_A2_REVIEW.md).
  Fourteen deterministic admission/broker checks and 28 actual host-isolation
  checks pass (including A3 timeout/profile regressions), with interrupted pipe
  recovery and nested-worker shutdown.
  The runner requires admission through worker reap; every retained lease blocks
  it without pruning. A3 exercised the real backend only in its controlled
  window. Exclusion of outside clients is still not enforced by the broker.
- Step 4: [A5 focused results](../assessments/CONTINUITY_LAB_A5_REVIEW.md).
  A3/A4 windows remain historical evidence. Actual-token preparation is now
  persisted before generation and consumed once. All seven note-lifecycle
  regression cases passed. Both longer cases read successfully, then repeated
  reads until their six-call budgets ended without an answer. An actual omitted
  source was re-read, but the complete rollover case did not pass. All 560
  deterministic/isolation checks passed, including 41 new token-context checks
  and 40 actual isolated-worker checks. Terminal adherence and sustained
  continuity remain open. The subsequent [A6 comparison](../assessments/CONTINUITY_LAB_A6_REVIEW.md)
  passes 98 focused checks and expected-path sizing, but its first visible-arm
  case timed out after three successful reads. Four requests started, three
  responses returned, one unscored case and three unstarted. No actual omission
  occurred. The subsequent [A7 diagnostic repair and comparison](../assessments/CONTINUITY_LAB_A7_REVIEW.md)
  implements bounded streaming and aligned time limits, passing 656 checks.
  All four cases completed in 24 responses, with all visibility conditions
  observed, but no task passed. The visible re-read case completed required
  reads then repeated them; another copied filler into an incomplete reply.
  Service unchanged and idle; all workers reaped and journals valid. Next
  proposed diagnostic changes only corpus style with token calibration, not
  memory semantics or an answer-producing controller. No automatic new window.
  [A8](../assessments/CONTINUITY_LAB_A8_REVIEW.md) subsequently prepared that
  corpus-only diagnostic and passed 150 focused checks. Calibration succeeded,
  but transient control-lock contention interrupted the live attempt before
  generation. No A8 task score exists. The frozen corpus is ready; a bounded
  pre-generation readiness retry is proposed before a fresh comparison.
  No automatic live run or journal resume was approved at that A8 handoff.
  [A9-A12](../assessments/CONTINUITY_LAB_A9_A12_REVIEW.md) subsequently implement
  bounded readiness and chronological messages; two clarified visible-history
  tasks pass. The owner then approved the separate practical context policy.
  [A13](../assessments/CONTINUITY_LAB_A13_REVIEW.md) retains factual execution
  receipts when dropping full source text. Its chronological receipt-pair trial
  passes both task pairs under both visible and actual rollover conditions:
  four strict passes, 20 calls, unchanged model/settings, 713 deterministic/
  isolation checks. Original minimal behavior and failed trials are preserved.
  [A14](../assessments/CONTINUITY_LAB_A14_REVIEW.md) then qualifies four directed
  note-lifecycle cases and three directed fresh-worker source cases on the frozen
  A13 runtime, after two retained source prompt failures. 100 focused checks
  pass. These narrow results do not establish general long-horizon reliability.
  [A15](../assessments/CONTINUITY_LAB_A15_REVIEW.md) subsequently assesses twelve
  less-prescriptive practical/conversation requests without tuning from results.
  All reach replies, but six source-dependent practical tasks and the conversation
  callback fail. Eight grouped deterministic/isolation checks pass. Exact-word
  search brittleness, guessed IDs and wrong-collection lookup are documented;
  no note writes were observed and recent exchanges were not automatically
  provided. Everyday usability is not qualified. Search-interface and bounded
  recent-dialogue experiments remain recommendations, not implementations.
  Actual model-server restart remains untested.
  [A16](../assessments/CONTINUITY_LAB_A16_REVIEW.md) then tested added guidance
  without improving factual completion or callbacks. [A17](../assessments/CONTINUITY_LAB_A17_REVIEW.md)
  implements opt-in ranked retrieval and recent dialogue, passes 365 grouped
  checks, and completes the three-condition trial. Recent dialogue solves 4/5
  callbacks but only 7/13 scheduled factual tasks overall. Source and context
  availability are not the only failures; tool routing and selection still fail.
  [A18](../assessments/CONTINUITY_LAB_A18_REVIEW.md) implements that opt-in
  complete-evidence answer path and completes its single comparison. Direct
  answers solve 13/16 factual tasks and 5/6 callbacks in 24 calls; the fresh
  agentic baseline solves 7/16 and 4/6 in 59 calls. Three direct errors retain
  complete evidence. All 562 grouped checks pass and 111 stores replay.
  [A19](../assessments/CONTINUITY_LAB_A19_REVIEW.md) subsequently implements
  chronological direct-evidence chat, passes 259 grouped checks and completes
  all 56 requests in one bounded window. Chat solves 17/20 factual tasks and
  7/7 callbacks versus envelope's 16/20 and 6/7, in 28 calls each. Three shared
  first-event selection errors remain; both follow the new successive corrections.
  All 125 stores replay. Its proposed general selection-guide comparison is now
  covered by the separately approved A20 work below; no general reliability was
  established by this correction gain.
  [A20](../assessments/CONTINUITY_LAB_A20_REVIEW.md) implements that opt-in guide
  and completes all 72 replies in one window. Fresh clean selections improve
  from 3/8 to 4/8; a fifth guided final choice is correct but follows a false
  opening claim. Overall clean factual answers are 20/28 versus 21/28; both
  retain 7/7 callbacks and three inherited selection failures. Complete sources
  were present in every request. All 166 grouped checks pass and 155 stores
  replay. Keep A19 as the experimental baseline, without default promotion.
  Its proposed deterministic helper is covered by the separately approved A21
  work below; tool-assisted results remain distinct from model-only reasoning.
  [A21](../assessments/CONTINUITY_LAB_A21_REVIEW.md) implements the pure helper
  and opt-in foreground CLI, with 59 grouped checks and 8/8 retained catalog
  fixture replays. Structured requests are explicit, not model-translated;
  unsupported input refuses. Computed results and generated text are separate.
  All 155 stores replay, 4,130 old evidence files and 90 old source files are
  unchanged. No model calls, runtime/default/service/ordinary-memory changes.
  Request-formation and confirmation are proposed next, not automatic routing
  or live model explanation already qualified.
- Step 5: [A22](../assessments/CONTINUITY_LAB_A22_REVIEW.md) implements the narrow
  foreground chat adapter. Six synthetic turns/retries completed with retained
  evidence and reconciled closeout. Connection configuration is staged only;
  the verified helper is not automatically routed from chat.
- Steps 5-6: no dashboard wiring, browser, scheduler, production deployment or
  ordinary-user experimental lineage has been activated. Synthetic A3 evidence
  remains locally retained under the approved qualification root.
