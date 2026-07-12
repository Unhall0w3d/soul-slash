# Memory Reflection Bridge and Export

## Purpose

This Phase 9 closeout connects two existing reviewed systems without collapsing their approval boundaries:

1. reflection artifacts may be reviewed and approved;
2. approved reflections may contain `candidate_memory_updates`;
3. those updates may be imported into layered memory;
4. imported records remain **candidates** until separately approved through the reviewed memory controls.

Reflection approval means the reflection artifact is acceptable. It does not mean every durable memory update inside it is automatically trusted.

## Approved-reflection import

Only JSON files under:

```text
Soul/reflection/approved/
```

are eligible. The JSON must declare:

```json
{
  "review_status": "approved",
  "candidate_memory_updates": []
}
```

Each memory update may be a string:

```json
"Soul uses focused ZIP overlays."
```

or a structured object:

```json
{
  "layer": "preference",
  "content": "Use exact commands in overlay instructions.",
  "confidence": 0.9,
  "tags": ["overlays", "commands"]
}
```

Unknown layers fall back to `semantic`; invalid confidence values fall back to `0.75`.

Every imported candidate records:

- the approved reflection path;
- reflection review status and review time;
- source task log when present;
- item index;
- a stable SHA-256 import key.

The import key makes repeated imports idempotent. A previously imported item is skipped even when its memory record was later superseded or logically deleted; the audit history is not silently forked.

## Deterministic controls

```text
memory maintenance help
list approved reflections
preview approved reflection latest
import approved reflection latest confirm
```

An import command without `confirm` is only a preview and performs no ledger mutation.

## Portable memory snapshots

A snapshot contains:

- schema identifier;
- generation time;
- source ledger path;
- every append-only memory event;
- every materialized record, including superseded and deleted records;
- event and record counts;
- the explicit no-physical-purge policy;
- a canonical SHA-256 digest.

Commands:

```text
export memory snapshot
export memory snapshot <simple-name>
verify memory snapshot latest
verify memory snapshot <simple-name>
```

Snapshots are written beneath:

```text
Soul/memory/exports/
```

The files are local runtime artifacts and are ignored by Git.

Verification checks:

- schema identity;
- canonical digest;
- declared event count;
- declared record count;
- replay of the exported events into materialized records.

Snapshot export does not mutate the source ledger.

## Deletion and purge boundary

Memory deletion remains logical. Deleted records stop participating in active retrieval, while their events remain available for audit and snapshot export.

This phase does not provide physical purge. A future purge design would need an explicit threat model, backup interaction, audit-retention rules, and an irreversible confirmation contract. “Just delete the line” is not a policy; it is an exciting way to discover why event sourcing has opinions.
