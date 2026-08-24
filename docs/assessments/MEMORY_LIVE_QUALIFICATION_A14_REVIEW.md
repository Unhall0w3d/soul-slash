# Memory Live Qualification A14 Review

## Candidate

Supervised, foreground end-to-end qualification of the accepted A10-A13 memory
chain using the existing local Dev Core runtime.

## Files

- `lib/soul_core/memory_local_proposal_synthesizer.rb`
- `lib/soul_core/memory_live_qualification_service.rb`
- `scripts/soul-memory-live-qualification`
- `scripts/verify-memory-live-qualification-a14.rb`
- A14 brief, Make targets, and current-state documentation

## Deterministic evidence

- The verifier captures one exact exchange, establishes an audit baseline,
  runs strict local synthesis, admits one high-confidence ordinary project
  memory, recalls it through approved-memory retrieval, compensates the exact
  transaction, and proves retrieval abstention afterward.
- It checks the closed proposal schema, reviewed low-reasoning/zero-temperature
  model settings, idempotent replay, content-free receipts, and post-rollback
  audit integrity. Unrelated transaction references are rejected before audit
  mutation.

Commands run:

```text
make verify-memory-live-qualification
make verify-memory-observation-derivation
make verify-memory-lifecycle-admission
make verify-memory-audit-reconstruction
make verify-memory-conversation-observation-capture
make verify-memory-retrieval-observatory
make verify-semantic-memory-chat-context
make verify-codex-soul-dev-worker
ruby scripts/verify-core-orchestration.rb
git diff --check
```

All listed deterministic checks pass. The A14 verifier reports 16 checks; A12
reports 20, A13 reports 26, A10 reports 38, and A11 reports 26.

## Local-model evidence

The real supervised qualification completed on 2026-08-24:

- An actual unlocked Dashboard transmission captured the harmless project
  convention as one ordered user/assistant observation pair.
- One host-side GPT-OSS 20B Dev-lane request created one strict proposal packet.
- A13 admitted its single proposal as `admitted_active` and returned the exact
  content-free rollback reference
  `memory-admit:mpr_379f8694a00d28d6865d92c5`.
- The approved-memory adapter returned one matching memory through lexical
  fallback. A separate new Dashboard transmission recalled `Cobalt Lantern`,
  proving cross-chat ordinary-context integration rather than same-chat replay.
- Exact compensation appended one reversal event. Retrieval then abstained,
  and another new Dashboard transmission correctly reported that it did not
  know the project label.
- The host user service restarted successfully and returned `active`; the
  post-restart content-free status repeated the valid audit, observation,
  derivation, and admission chain evidence.
- The post-compensation canonical audit contains 68 valid events with a valid
  baseline and chain; the observation, derivation, and admission ledgers also
  validate. All command receipts remained content-free.

## Risk and boundaries

- Risk: medium; supervised canonical memory append and compensation.
- Model authority: proposal only.
- Persistence: existing owner-private append-only ledgers only.
- Background work, scheduler, remote database, cloud model, physical deletion,
  external publication, and autonomous conflict resolution: none.

Memory stores used: the shared canonical conversation-memory ledger, A11
conversation-observation segments, A12 derivation packets, and A13 lifecycle
decisions. No skill-private memory key or alternate authority store is added.

Lifecycle states touched: `complete` and `failed`; A13 outcomes may additionally
record `blocked_for_human_review` without creating canonical memory.

## Known weaknesses

- A future live run still requires an unlocked Dashboard exchange and a healthy
  local Dev runtime; sandboxed Codex processes cannot observe host user-service
  activity, so the actual model request must execute through the host boundary.
- This slice does not backfill historical chats, schedule future derivation,
  consolidate conflicts, or project memory into Qdrant/FalkorDB.
- Retrieval proof is content-free at the command boundary, so the human review
  uses the originating harmless qualification fact as its expected result.

## Human review checklist

- [x] Submit the harmless qualification fact through the unlocked Dashboard.
- [x] Review the live local-model derivation and deterministic admission.
- [x] Prove recall in a different Dashboard transmission.
- [x] Compensate the exact transaction and prove direct and cross-chat
  abstention.
- [ ] Review the final code and documentation candidate before merge.
