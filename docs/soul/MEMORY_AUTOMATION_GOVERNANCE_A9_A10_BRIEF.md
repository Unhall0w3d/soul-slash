# Memory Automation Governance and Audit A9-A10 Brief

Status: Operator-approved implementation scope, 2026-08-23

## Objective

Give Soul standing authority to manage ordinary owner-private memory at machine
speed while preserving an attributable, reversible, and recoverable source of
truth. The existing canonical conversation-memory ledger and Soul Vault remain
authoritative. This slice adopts the current ledger in place, adds verifiable
audit history and point-in-time reconstruction, and does not deploy a remote
database or change ordinary retrieval.

## Standing authority

After later lifecycle automation is implemented, Soul may autonomously capture,
classify, consolidate, promote, demote, supersede, reactivate, and logically
tombstone ordinary memory. Those operations do not require an item-by-item
human gate when they remain local, attributable, reversible, recoverable, and
inside the approved policy.

The following remain protected and require a separate explicit human decision:

- credentials, secrets, and authentication material;
- permission or authority grants;
- destructive-operation authorization;
- safety and security policy;
- operator identity and protected persona rules;
- physical purge of irreplaceable source observations;
- export outside the approved local or private-infrastructure boundary;
- broad retention-policy changes and irreversible bulk operations.

Ambiguous ordinary claims may coexist as conflicting candidates. Uncertainty
does not silently become fact, but it also does not create a routine approval
queue. Agreement among models is evidence, not authority.

## A9 governance deliverable

The policy contract distinguishes immutable observations from derived memory
and uses lifecycle state rather than destructive rewriting:

- `observation`: captured source evidence;
- `candidate`: derived or newly proposed memory not yet admitted to retrieval;
- `active`: ordinary memory admitted by reviewed deterministic policy;
- `protected`: human-controlled authority or identity memory;
- `superseded`: replaced by better evidence while history remains;
- `tombstoned`: logically excluded while history remains recoverable.

Existing `candidate`, `approved`, `superseded`, and `deleted` ledger states
remain compatible. Later slices may add richer policy metadata without
rewriting old events. `approved` is the current retrieval-active representation
of ordinary `active` memory; `deleted` remains a logical tombstone, not physical
purge.

## A10 canonical audit adoption

The current JSONL ledger is adopted in place. No existing event is modified,
moved, or re-encoded. One baseline event records:

- exact pre-baseline byte count and SHA-256;
- exact pre-baseline event count;
- adoption time, actor, trigger, reason, and policy version;
- the audit schema and chain genesis.

The operation is idempotent. A malformed, symlinked, escaped, or concurrently
drifted ledger fails closed. The baseline response contains counts and digests,
never private memory content.

Every later event records a digest of the preceding chained event and its own
canonical digest. Audit metadata may include a bounded transaction ID, actor,
trigger, reason, policy version, and model/Core identity. Missing optional model
metadata never prevents deterministic operations from being audited.

## Reconstruction and rollback

Point-in-time reconstruction replays only the immutable prefix ending at an
exact event ID or inclusive timestamp. It never edits the ledger and returns a
content-free receipt unless an owner-private export is explicitly requested by
a later interface.

Rollback is compensating, not destructive. It appends restoration or logical
tombstone events in one auditable transaction so the current materialized state
matches the selected prior point. Original observations and intervening history
remain present. Invalid, protected, malformed, stale, or ambiguous rollback
plans fail closed. A later policy/interface slice decides which rollback classes
may execute autonomously and which require an operator gesture.

## Failure and recovery

- Integrity verification must detect prefix mutation, chained-event mutation,
  partial or non-newline-terminated writes, malformed JSON, broken links,
  duplicate baseline adoption, and unsupported audit schema. A clean deletion
  of a complete chained suffix cannot be proven from the ledger alone until a
  later independently retained checkpoint is introduced; restic snapshots and
  exports remain the recovery evidence for that case.
- Appends are bounded, locked, flushed, and do not continue in the background.
- A failed append never authorizes repair by rewriting earlier bytes.
- Recovery uses the canonical ledger, its audit evidence, Git-tracked policy,
  and restic-protected owner-private state.
- Qdrant and FalkorDB remain future rebuildable projections on Foundry. Redis is
  not required by this slice.

## Explicit non-goals

- No automatic conversation capture or autonomous lifecycle engine yet.
- No model invocation, embeddings, speculative recall, or cross-agent synthesis.
- No service, timer, watcher, daemon, or Core switching.
- No Qdrant, FalkorDB, Redis, container, network listener, or remote mutation.
- No Dashboard mutation surface and no change to approved-only retrieval.
- No physical deletion, Git automation, restic invocation, merge, or release.

## Acceptance

- Existing unchained ledgers remain readable before adoption.
- Adoption does not alter any pre-existing byte.
- Empty and populated ledgers adopt deterministically and only once.
- Every post-baseline event is hash chained and carries normalized audit
  metadata.
- Strict verification detects tampering, partial writes, malformed input,
  symlinks, and path escape without revealing content, and documents the clean
  suffix-removal limitation honestly.
- Point-in-time replay returns the exact historical materialized state.
- Compensating rollback preserves the complete event history.
- Existing Phase 9 memory controls, snapshots, retrieval, and Observatory
  behavior remain compatible.
