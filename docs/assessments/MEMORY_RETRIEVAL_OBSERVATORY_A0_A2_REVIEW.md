# Memory Retrieval and Observatory A0-A2 Review

Status: candidate-complete; awaiting Operator review

## What was implemented

- Added a deterministic synthetic A0 corpus comparing the current lexical
  baseline with explainable hybrid retrieval.
- Added an owner-private, approved-only JSON index with source and payload
  digests, profile/dimension binding, bounded local-loopback embeddings,
  atomic replacement, and lexical fallback.
- Added a read-only retrieval service with explicit score components and honest
  abstention.
- Added an authenticated `memory.observatory.summary` and
  `memory.observatory.query` application surface.
- Added Administration → Memory Observatory with counts, recent lifecycle
  evidence, duplicate/supersession observations, index state, review guidance,
  and one explicit diagnostic query.
- Added foreground CLI and Make targets. No model is downloaded or started and
  no background process is installed.

## Files changed

- `Makefile`
- `README.md`
- `assets/dashboard/dashboard.css`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/index.html`
- `docs/ARCHITECTURE.md`
- `docs/CURRENT_STATE.md`
- `docs/ROADMAP.md`
- `docs/guides/MEMORY_RETRIEVAL_OBSERVATORY.md`
- `docs/soul/MEMORY_RETRIEVAL_OBSERVATORY_A0_A2_BRIEF.md`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `lib/soul_core/conversation_memory_store.rb`
- `lib/soul_core/memory_observatory_service.rb`
- `lib/soul_core/memory_retrieval_evaluator.rb`
- `lib/soul_core/memory_retrieval_index.rb`
- `lib/soul_core/memory_retrieval_service.rb`
- `scripts/memory-retrieval-observatory.rb`
- `scripts/verify-memory-observatory-dashboard-a2.rb`
- `scripts/verify-memory-observatory-facade-a2.rb`
- `scripts/verify-memory-retrieval-observatory-a0-a1.rb`

## Commands run

```text
make memory-retrieval-evaluate
make memory-retrieval-status
make verify-memory-retrieval-observatory
ruby scripts/verify-phase9-memory-reflection-and-export-closeout.rb
make verify-knowledge-vault
make verify-local-search
ruby scripts/verify-dashboard-self-improvement-navigation.rb
node --check assets/dashboard/dashboard.js
git diff --check
```

## Deterministic test results

- Synthetic corpus: 8 queries.
- Hybrid mean recall: `1.0`; lexical baseline: `0.875`.
- Hybrid mean precision: `1.0`; lexical baseline: `0.875`.
- Hybrid mean reciprocal rank: `1.0`; lexical baseline: `0.833333`.
- Correct abstentions: `2/2` deliberately absent queries.
- A0/A1 retrieval verifier: passed.
- A2 facade verifier: 12/12 checks passed.
- A2 Dashboard verifier: 13/13 checks passed.
- Existing Phase 9, Knowledge Vault, Local Search A1/A2, and Dashboard
  navigation regressions passed.

## Local LLM and embedding evaluation

No production model was called. The A0 harness uses deterministic synthetic
vectors only, so it proves ranking, fallback, and authority mechanics without
claiming that a particular local model wins. The optional client now speaks the
Ollama `/api/embed` shape by default and also supports the reviewed neutral Soul
fixture protocol. Live model/profile comparison remains an explicit foreground
qualification step.

## Memory keys

No memory key is added by the implementation. The existing approved ledger is
read; the derived retrieval index is not canonical memory.

## Task lifecycle states touched

- Rebuild: `complete`, `failed`, `canceled`.
- Diagnostic query: `complete`, `awaiting_input`, `failed`.
- Observatory summary: `complete`, `failed`.

## Risk classification

Class 1: owner-private read and rebuildable derived state.

## Known weaknesses

- Semantic results are not yet admitted into ordinary Chat context; this
  candidate adds the diagnostic query path first so the Operator can inspect
  live ranking before changing default recall.
- No local embedding model has been selected or live-qualified.
- Exact-content duplicate detection intentionally does not infer semantic
  conflicts or invented graph relationships.
- JSON is appropriate at the current approved-memory scale but should be
  revisited before raising the 5,000-record or 1,024-dimension bounds.
- The Dashboard is deterministically verified but still needs visual and
  interaction review in the live application.

## Human review checklist

- [ ] Compare lexical and hybrid results for the accepted evaluation corpus.
- [ ] Confirm an absent answer abstains rather than returning a nearby memory.
- [ ] Confirm only approved active records appear in the index and Observatory.
- [ ] Confirm stale or damaged index state falls back to lexical retrieval.
- [ ] Inspect `why recalled` scoring for understandable evidence.
- [ ] Confirm no memory is mutated by rebuild, search, or Observatory refresh.
- [ ] Review Dashboard layout and responsive behavior.
- [ ] Decide whether the selected local embedding profile is worth retaining.
