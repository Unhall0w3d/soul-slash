# Continuity Lab A0 fake core brief

Status: implementation scope derived from the owner's instruction, "Let's
proceed with the plan," following the adaptation outline. Candidate review,
live inference, deployment, and unattended use remain separate.

This preserves the original Steps 0-1 contract. The subsequently approved
[A1 extension](CONTINUITY_LAB_A1_BRIEF.md) adds an explicit context profile and
uses store schema A1; `raw_fixture` keeps the A0 action/test behavior. Previous
A0-schema stores are refused, not migrated or overwritten.

## Objective and scope

Implement Steps 0-1 of [the adaptation plan](CONTINUITY_LAB_ADAPTATION_PLAN.md):
a foreground Ruby core using only the installed standard/default libraries and an in-process scripted fake model
and fresh explicitly selected development stores. This is not a registered Soul
skill, dashboard route, production lineage, or a connection to ordinary memory.

The experiment's separate synthetic store is within this approved development
scope; this does not authorize copying or retaining real private conversations.
Proposed risk class: Class 2 local reversible state; human review remains pending.

Owned paths: `lib/soul_core/continuity_lab/`,
`scripts/verify-continuity-lab-core-a0.rb`,
`scripts/verify-continuity-lab-recovery-a0.rb`, this brief, the adaptation plan,
and the A0 review entry/packet. Do not alter ordinary runtime or memory callers.

## Decisions

- Keep the minimally seeded condition, optional notes, Soul-hosted code, and
  later dashboard direction. Do not import Soul identity/history or archive text.
- Use repository-pinned Ruby 4.0.7 and its installed JSON library with strict
  duplicate-key rejection. Fail closed when that parser capability is absent;
  the system Ruby 3.4.10/JSON 2.9.1 silently ignores the required option. No
  package installation is part of this slice.
- Use a bounded immutable transaction journal.
  Each atomic commit contains the full internal effect and its receipt; notes
  are projections of that journal, not separately written files. A derived
  cache is unnecessary at A0. SQLite would add an unestablished adapter/package
  dependency; reconsider when indexed retrieval or scale requires it.
- The journal replaces neither Soul observations nor ordinary artifact storage.
  It is append-only through this API, not tamper-proof against the owner.
- No separate graph checkpoint is needed: reopen reconstructs state from the
  committed journal. Do not call this a production checkpoint/fork facility.
- Fresh store creation is exclusive. Existing stores reopen only through the
  explicit open path with a matching validated configuration.
- Linux directory descriptors anchor file access; model note IDs never become
  paths. Reject symlinks, hardlinked/special journal files, invalid permissions,
  unsafe logical IDs, conflicting revisions, invalid journal chains, and drift.
  This is a local store boundary, not qualification of future OS containment.

## Interface contract

Namespace: `SoulCore::ContinuityLab`.

```ruby
config = Config.new # only backend=fake and all optional features disabled
store = Store.create(path: absolute_new_path, config: config)
store.close
store = Store.open(path: absolute_existing_path, config: config)
backend = FakeBackend.new(responses: [JSON.generate({"action" => "wait"})])
runtime = Runtime.new(store: store, backend: backend)
receipt = runtime.submit(event_id: "request-1", content: "Synthetic task")
receipt = runtime.resume(event_id: "request-1")
snapshot = store.snapshot # explicit local inspection; can contain synthetic text
summary = store.integrity # counts/digests only
store.close
```

Errors: `ValidationError`, `Conflict`, `IntegrityError`, `Busy`, `QuotaExceeded`
under `SoulCore::ContinuityLab::Error`. Invalid configuration/store/input raises
before processing. A valid processed event returns `event_id`, `state`, `reason`,
and `reply` (if present); state uses Soul lifecycle names. Duplicate terminal
requests return their committed receipt. Unknown resume raises `ValidationError`.
Same event ID plus different content raises `Conflict`. A pending different
event or occupied writer lock raises `Busy` without accepting another event.

`FakeBackend#calls` counts this instance's invocations. The backend selects
`responses[call_index]` (zero-based within an event) and never executes responses.
No arbitrary provider callback, network transport, shell, or model endpoint.

Complete JSON responses have exactly one of these shapes:

```json
{"action":"reply","content":"Synthetic reply"}
{"action":"wait"}
{"action":"tool","tool":"note.write","arguments":{"note_id":"example","expected_revision":0,"content":"Synthetic note"}}
```

Only `note.write` is exposed in A0. Search/read/pin/move/tombstone tools belong
to Step 2 and are rejected here. Creating requires expected revision zero;
updates require the current integer revision. IDs are ASCII alphanumerics with
internal `_` or `-`, maximum 64 bytes; no dots, slashes, Unicode path aliases,
or absolute paths. Empty text is allowed, overlarge text is not. Extra fields,
partial JSON, nested surprises, model-supplied operation IDs and lifecycle
assertions never authorize effects. A tool result is recorded by runtime code.

Snapshot fields: `events` keyed by transport ID; `notes` keyed by logical ID
with `revision`, `content`, and ancestry; `operations` with actual results;
`transaction_count`. Receipts expose no unrelated note content.

## Limits and lifecycle

Config accepts only documented keys and exact types. Defaults / hard maxima:

| Key | Default | Allowed range |
| --- | --- | --- |
| backend | fake | fake only |
| max_model_calls | 9 | 1-16 |
| max_tool_calls | 8 | 0-16 |
| max_invalid_actions | 1 | 0-2 |
| max_event_bytes | 16384 | 1-65536 |
| max_response_bytes | 16384 | 64-65536 |
| max_note_bytes | 4096 | 1-16384 |
| max_notes | 64 | 1-128 |
| max_total_note_bytes | 65536 | 1-1048576 |
| max_transactions | 512 | 8-8192 |
| max_journal_bytes | 4194304 | 4096-67108864 |
| max_seconds | 30 | 1-60 |

`autonomy`, `browser`, `code_execution`, `training`, and `fallback` must be
literal false. Bounds and the config digest are part of the store manifest.
Model calls here are bounded in-process fixture reads; the deadline is checked
between actions. No timeout promise is made for arbitrary remote inference.

`invoked -> validated -> accepted -> model intent -> stored model response ->
validated action -> committed effect/result -> next bounded call or terminal`.
Wait completes without a note or follow-up job. Malformed responses get at most
the configured number of additional opportunities, then fail. Budget exhaustion
fails; an ambiguous stored model intent without a response blocks for review.
The blocked lineage does not accept new work automatically.

Hold a nonblocking per-store writer lock for the whole bounded event. Admission
and processing order coincide at A0; there is no scheduler or waiting queue.
The wall-time bound applies per foreground invocation; persisted call/tool/error
counters prevent explicit resumption from resetting event action budgets. Disk-full
or quota failure must not silently lose committed history or trigger pruning.

## Recovery and delivery

Commit by private exclusive staging, file fsync, atomic rename under the writer
lock, and directory fsync. Retained staging files are non-authoritative but count
toward storage bounds. Reject malformed committed records rather than truncating
or repairing them automatically. Immutable sequence/digest checks are mandatory.

Inject test faults at `before_stage`, `after_stage`, and `after_commit`, carrying
the record kind. A crash before a response commit leaves an ambiguous model
intent; a crash after response commit reuses that response. A note/result commit
is one transaction: a crash before it leaves no effect; a crash after it replays
the actual result without a second note revision. Backend calls are not repeated
for already committed responses. No exactly-once claim for external effects.

Optional `submit` receipt delivery block runs only after terminal commit and
outside the writer lock. A failed delivery cannot roll back work; a client retry
recovers the terminal receipt without another backend call. No worker survives
return/disconnect, and no background continuation is added.

## Required acceptance

Activate the repository Ruby first, or invoke its absolute binary. On Atelier
the tested executable is `/home/bhones/.rbenv/versions/4.0.7/bin/ruby`.

- `ruby scripts/verify-continuity-lab-core-a0.rb`: strict types/unknown keys,
  fake-only defaults, provenance, duplicate/conflicting requests, single writer,
  tool allowlist and bounds, invalid-action budget, wait/no-note, actual results,
  note revisions, quota and pending-event behavior (archive C01-C11; relevant M01/M02).
- `ruby scripts/verify-continuity-lab-recovery-a0.rb`: faults around response and
  note commits, ambiguous intent, journal-only reconstruction, failed receipt
  delivery, malformed/tampered records and storage boundaries (R01-R05).
- Ruby syntax checks for added files; changed-file whitespace/link checks.
  All fixture stores must be fresh temporary directories. No broad host checks.

Existing callers are unchanged, so broad chat/GPU/host regression runs are not
required for this isolated slice. Additional regressions follow any unexpected
shared-path edit. Real-model evaluations are NOT RUN, not passed by fake results.

## Non-goals and review

No live input collection, retrieval engine, token qualification, UI wiring,
Qwen inference, embeddings, services, worker deployment, network rule changes,
model switching, package installation, automatic backup inclusion, or memory
promotion. No daemon, watcher, timer, listener, thread left alive, deletion API,
physical purge, credential access, cloud fallback, code execution, or training.

Candidate completion requires the full above checks, evidence and known limits,
and an A0 review packet linked from the canonical review gate/template. This is
not release/merge approval. Later stages retain the adaptation plan's boundaries.
