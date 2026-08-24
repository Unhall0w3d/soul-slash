# Memory Autonomous Lifecycle A16 Review

## Candidate

One explicit foreground operation now joins the reviewed A12 local proposal
stage and A13 deterministic admission stage. It drains an older derived packet
first or derives and admits exactly one new packet, then terminates.

## Files

- `lib/soul_core/memory_autonomous_lifecycle_service.rb`
- `scripts/soul-memory-lifecycle-cycle`
- `scripts/verify-memory-autonomous-lifecycle-a16.rb`
- A16 brief and Make targets

## Deterministic evidence

The synthetic verifier covers ordinary derive-and-admit, pending-packet-first
ordering, explicit no-work completion, protected-memory blocking, content-free
receipts, cycle-journal integrity, canonical audit integrity, completed replay,
and recovery after interruption between admission and the combined journal
append.

```text
make verify-memory-autonomous-lifecycle
make verify-memory-observation-derivation
make verify-memory-lifecycle-admission
make verify-memory-live-qualification
make verify-memory-historical-chat-backfill
git diff --check
```

## Boundaries

- Risk: medium; audited owner-private ordinary-memory mutation.
- Model authority: proposal only.
- Protected memory: blocked for human review.
- Background or persistent execution: none.
- Per invocation: at most one derivation packet and one admission decision.
- Memory content in public receipts and the cycle journal: none.

## Known weakness and next gate

A16 must be invoked explicitly. It does not yet provide scheduled batching,
Core-aware deferred execution, consolidation, supersession, demotion, or
speculative recall. Those behaviors require separately reviewed policy and the
explicit A17 persistence authority before implementation.

The first owner-private live invocation on 2026-08-24 failed safely before
derivation or canonical-memory mutation because the selected Core did not
permit development work. The existing runtime requested Soul Core, Soul-Lite
Core, or Dev Core. A16 intentionally did not switch Cores on its own. Live
qualification therefore remains a human test after selecting an eligible Core;
the failed request created no completed cycle-journal entry and is safe to
retry with the same request identifier.
