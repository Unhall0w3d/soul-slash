# Memory Observation Derivation A12 Review

Status: candidate-complete; publication, merge, and live synthesis remain
unapproved

## What was implemented

- A foreground-only bridge from immutable conversation observations to
  append-only owner-private memory proposal packets.
- Full source-chain verification followed by a bounded batch of at most 24
  observations / 12 complete exchanges / 48 KiB.
- One injected, explicitly local synthesis call with a closed JSON result
  schema, eight-proposal limit, evidence-ID containment, and content bounds.
- Deterministic protected-material classification that model output cannot
  downgrade.
- Append-only packet chaining, request idempotency, packet-derived cursor,
  content-free receipts, and explicit integrity reporting.
- Valid empty packets advance the cursor. Invalid output and unavailable
  synthesis leave it unchanged.
- No canonical-memory mutation, retrieval admission, background execution,
  Core switch, remote database, or Dashboard action.

## Files changed

- `.gitignore`
- `Makefile`
- `docs/ARCHITECTURE.md`
- `docs/CURRENT_STATE.md`
- `docs/soul/MEMORY_OBSERVATION_DERIVATION_A12_BRIEF.md`
- `docs/assessments/MEMORY_OBSERVATION_DERIVATION_A12_REVIEW.md`
- `lib/soul_core/conversation_observation_store.rb`
- `lib/soul_core/memory_observation_derivation_service.rb`
- `scripts/verify-memory-observation-derivation-a12.rb`

## Deterministic validation

- `make verify-memory-observation-derivation`
  - PASS, 20 checks.
- `make verify-memory-conversation-observation-capture`
  - PASS, 26 checks.
- `make verify-memory-audit-reconstruction`
  - PASS, 38 checks.
- `make verify-memory-retrieval-observatory`
  - PASS, including facade and Dashboard checks.
- Semantic Chat memory, Chat progress, voice latency, private-memory separation,
  Phase 12B application API, responsive Chat, and intent-boundary regressions
  - PASS.
- Ruby syntax and working/staged `git diff --check`
  - PASS.

No local LLM behavioral evaluation was used. The model boundary is tested with
deterministic injected fixtures; no live or private observation was submitted
to any model.

## Known weaknesses

- A12 only produces proposals. The later deterministic lifecycle engine must
  independently reapply protection and admission policy before mutation.
- Keyword protection is intentionally conservative but cannot semantically
  identify every indirect reference to protected authority. Uncertainty must
  remain a candidate or protected review item in the lifecycle slice.
- Source selection verifies the complete observation chain in foreground work.
  Its cost grows with retained history; later independently checkpointed
  projection infrastructure may optimize this without becoming authoritative.
- There is no historical-chat backfill, automatic trigger, Core orchestration,
  Qdrant/FalkorDB projection, or 3D Observatory integration yet.

## Memory and lifecycle impact

- Synthetic temporary roots only; no owner-private observations or canonical
  memories were read or changed during verification.
- Derivation terminates as `complete` or `failed`. It leaves no process alive.
- Proposal packets remain non-authoritative, non-retrieval-active evidence.

## Risk classification

Medium-high. The slice lets a local model read bounded private conversations
and retain derived private proposals, but grants no lifecycle authority and
exports no content.

## Human review checklist

- [ ] Confirm a strict local-model proposal packet is the correct boundary
      before autonomous lifecycle decisions.
- [ ] Confirm empty valid synthesis should advance the observation cursor.
- [ ] Confirm deterministic protection classification must be re-applied by
      every later mutation policy.
- [ ] Confirm no A12 proposal enters retrieval or canonical memory directly.
- [ ] Approve candidate publication; merge remains separate.
- [ ] Run one supervised local-model derivation after merge.
