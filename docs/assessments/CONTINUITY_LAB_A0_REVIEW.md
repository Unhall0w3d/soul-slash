# Continuity Lab A0 review

Candidate status: candidate_complete for the fake-model core only.
Human merge/release outcome: pending.

## Scope and implementation

Implements Steps 0-1 of the [adaptation plan](../soul/CONTINUITY_LAB_ADAPTATION_PLAN.md)
under the [A0 brief](../soul/CONTINUITY_LAB_A0_BRIEF.md). The operator authorized
proceeding after the outline. This is an isolated Ruby library and synthetic
verifiers, not a registered Soul skill, live agent, or production deployment.

- Strict, fake-only configuration with fixed hard bounds and optional features
  disabled; unsupported duplicate-key parsing fails before a store is created.
- Explicit fresh store creation, matching-configuration reopen, owner-private
  files, descriptor-anchored paths, a nonblocking writer lock, and bounded scans.
- Atomic journal records bind sequence, prior digest, lineage, and configuration.
  Notes and actual operation results commit together; no separate note-file
  effect or stale derived cache is involved.
- Accepted requests, model-call intent, stored responses, validated effects,
  and terminal outcomes are retained. A stored response is reused on resume;
  ambiguous intent blocks for review instead of regenerating automatically.
- A small closed action protocol supports reply, wait, and note.write. Note
  claims are unverified artifacts; there is no ordinary-memory promotion.
- Revision checks, call/tool/error budgets, note/storage quotas, and strict
  journal transitions reject unsupported effects. Receipt delivery occurs only
  after commit and outside the writer lock; retry recovers the same result.

## Changed paths

```text
lib/soul_core/continuity_lab/config.rb
lib/soul_core/continuity_lab/actions.rb
lib/soul_core/continuity_lab/fake_backend.rb
lib/soul_core/continuity_lab/store.rb
lib/soul_core/continuity_lab/runtime.rb
scripts/verify-continuity-lab-core-a0.rb
scripts/verify-continuity-lab-recovery-a0.rb
docs/soul/CONTINUITY_LAB_A0_BRIEF.md
docs/soul/CONTINUITY_LAB_ADAPTATION_PLAN.md
docs/assessments/CONTINUITY_LAB_A0_REVIEW.md
docs/soul/HUMAN_REVIEW_GATE.md
skills/_template/REVIEW.md
```

Pre-existing unrelated dirty files were left untouched. No commit or merge was
performed. The earlier adaptation-plan file remains part of the uncommitted work.

## Commands and results

```text
/home/bhones/.rbenv/versions/4.0.7/bin/ruby scripts/verify-continuity-lab-core-a0.rb
PASS: 21/21 core checks

/home/bhones/.rbenv/versions/4.0.7/bin/ruby scripts/verify-continuity-lab-recovery-a0.rb
PASS: 149 recovery and adversarial checks

Pinned Ruby -c for five module files and both verifiers
PASS
```

Core coverage includes configuration, revisions, actual tool results, invalid
actions, persisted budgets, same-ID conflict/retry, writer contention, pending
events, quotas, and failed delivery. Recovery coverage includes all three fault
positions around acceptance, intent, response, note/result, and terminal commits;
ambiguous intent; malformed chains; symlinks/hardlinks/FIFOs; changed manifest
and lock; directory-path redirection; cross-lineage journal transplant; encoding;
forged effects/replies; duplicate JSON keys; and no hidden invalid-action retries.

The first preliminary core run used system Ruby 3.4.10. Final acceptance uses
the repository's Ruby 4.0.7 and JSON 2.18.0. A newly added duplicate-key case
exposed that the older JSON parser silently ignored the strict option; the
feature gate now rejects that environment instead of weakening validation.

The initial read-only review found blocking FIFO opens, missing manifest-drift
checks on open handles, insufficient semantic effect validation, and an encoding
exception mismatch. All four were repaired with regression coverage. Focused
re-review confirmed the repairs and found no additional concrete defect.

## Evidence boundaries and known limits

- These are deterministic component tests and simulated interruption/reopen
  tests on temporary stores. They are not a physical power-cut, live-model,
  dashboard, network-isolation, backup, or production-restore qualification.
- The journal is append-only through this API, not owner-tamper-proof. A
  checksum chain is not a cryptographic identity or OS containment boundary.
- No external effects are supported. Exactly-once claims are limited to the
  tested internal journal effects and replay conditions.
- A0 rebuilds bounded state from its journal at each invocation. Search,
  history retrieval, token-budgeted context, corpus ingestion, checkpoints/forks,
  and scheduled opportunities are later work, not hidden features.
- The deadline is checked between bounded in-process fixture actions; kernel
  I/O and future remote model calls are not hard real-time operations. Event
  action counters persist; the wall-time budget is per explicit invocation.
- Retained staging files count toward quotas and never become authoritative
  simply because they exist. No pruning, purge, automatic repair, or janitor
  was added. Capacity/integrity errors preserve known data and fail closed.
- No private conversations were imported. Fixtures are synthetic and temporary;
  production state root, retention, and backup inclusion remain unselected.

## Memory, lifecycle, and operational effects

Ordinary memory keys read/written: none. A0's explicitly scoped synthetic
notebook is separate from all Soul observation and memory defaults. No live
lineage was created. Tested runtime terminal states are complete, failed, and
blocked_for_human_review. Invalid inputs/store failures raise typed errors to
the trusted caller before further model/effect work.

Persistent service, daemon, timer, watcher, listener, scheduler, background
continuation, cloud fallback, package installation, model load/restart, network
change, physical deletion API, and credential access: none.

Local LLM evaluation: NOT RUN; no model was invoked. Proposed Class 2 local
reversible state scope is subject to human review; model output has no authority.

## Human review

- [ ] Accept the bounded fake-core scope and remaining limitations.
- [ ] Approve merge/release of this candidate if desired.
- [ ] Review production memory, containment, and deployment scopes before use.

No approval is inferred from passing tests. Step 2 can build the explicit
retrieval/context components under its repository-only scope; real inference and
deployment retain their separate adaptation-plan gates.
