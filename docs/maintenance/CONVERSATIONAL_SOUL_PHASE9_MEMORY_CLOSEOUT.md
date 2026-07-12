# Conversational Soul Phase 9 Memory Closeout

## Status

Phase 9 complete after this overlay.

## Delivered in the closeout slice

- deterministic approved-reflection discovery and preview;
- confirmation-gated import of `candidate_memory_updates`;
- separate reflection and memory approval boundaries;
- stable import provenance and duplicate prevention;
- local JSON memory snapshots;
- canonical SHA-256 verification;
- event replay against materialized records;
- explicit logical-deletion and no-physical-purge policy;
- Phase 9 closeout assessor and regression verifier.

## Invariants

- Pending or rejected reflection files cannot enter the bridge.
- Reflection import never approves durable memory.
- Repeated import does not append duplicate candidate events.
- Snapshot export does not mutate the memory ledger.
- A snapshot is valid only when its digest, counts, and event replay agree.
- Model output is not used to authorize, import, approve, export, or verify memory.

## Acceptance commands

```bash
ruby scripts/verify-phase9-memory-reflection-and-export-closeout.rb
ruby bin/soul assess phase9-memory-closeout
ruby bin/soul assess phase9-memory-closeout --json
```

## Next phase

Phase 10 begins identity, interests, and variation. It should consume approved memory as context, but identity declarations must remain inspectable and must not invent biography, embodiment, preferences, or experiences.
