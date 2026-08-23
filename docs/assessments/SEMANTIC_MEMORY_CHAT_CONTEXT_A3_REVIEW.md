# Semantic Memory Chat Context A3 Review

Status: candidate-complete; awaiting Operator review

## What was implemented

- Added a narrow Chat memory adapter that combines protected legacy context
  with fresh hybrid semantic matches.
- Re-reads every semantic result from the canonical approved-memory ledger.
- Preserves the exact legacy context for all non-hybrid and failed paths.
- Exposes retrieval mode and admitted semantic IDs in bounded context metadata.
- Wired the adapter into the ordinary `ApplicationFacade` conversation runtime.

## Files changed

- `.env.example`
- `Makefile`
- `docs/ARCHITECTURE.md`
- `docs/CURRENT_STATE.md`
- `docs/ROADMAP.md`
- `docs/assessments/SEMANTIC_MEMORY_CHAT_CONTEXT_A3_REVIEW.md`
- `docs/guides/MEMORY_RETRIEVAL_OBSERVATORY.md`
- `docs/soul/SEMANTIC_MEMORY_CHAT_CONTEXT_A3_BRIEF.md`
- `lib/soul_core/application_facade.rb`
- `lib/soul_core/configuration_schema.rb`
- `lib/soul_core/conversation_context_builder.rb`
- `lib/soul_core/conversation_runtime.rb`
- `lib/soul_core/semantic_conversation_memory_context.rb`
- `scripts/verify-semantic-memory-chat-context-a3.rb`

## Deterministic tests

- A3 Chat-context verifier: 11/11 checks passed.
- Existing Memory Retrieval and Observatory suite: passed.
- Existing Phase 9 memory closeout and layered-context regressions: passed.
- Portable typed configuration and Noctalia configuration projection: passed.
- Ruby syntax and `git diff --check`: passed.

## Commands run

```text
make verify-semantic-memory-chat-context
make verify-memory-retrieval-observatory
ruby scripts/verify-phase9-memory-reflection-and-export-closeout.rb
ruby scripts/verify-phase9-reviewed-memory-controls.rb
ruby scripts/verify-phase9-layered-memory-foundation.rb
ruby scripts/verify-conversational-soul-acceptance.rb
ruby scripts/verify-phase12a-portable-typed-configuration.rb
ruby scripts/verify-noctalia-companion-a0.rb
git diff --check
```

## Local LLM evaluation

No LLM or embedding model was called. The adapter behavior is deterministic.
A live semantic result still requires an explicitly configured loopback model,
a foreground index rebuild, and Operator comparison of real retrieval quality.

## Memory and lifecycle

No memory key or event is added. Retrieval is foreground and terminates as
`complete`, `awaiting_input`, or `failed`; Chat falls back safely in every
non-complete or non-hybrid case.

## Risk and known boundary

Class 1 owner-private read. Semantic Chat admission is implemented but remains
dormant on installations without a configured embedding endpoint and fresh
compatible index. There is no automatic index freshness maintenance.

## Human review checklist

- [ ] Configure and foreground-start one reviewed loopback embedding runtime.
- [ ] Explicitly rebuild the approved-memory index.
- [ ] Confirm paraphrased real queries recall useful approved memories.
- [ ] Confirm absent-answer queries abstain.
- [ ] Confirm normal Chat remains responsive when the endpoint is stopped.
- [ ] Decide whether this profile is worth operating before any persistence
  proposal is considered.
