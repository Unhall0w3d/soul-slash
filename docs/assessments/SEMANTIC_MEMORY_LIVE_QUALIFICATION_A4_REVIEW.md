# Semantic Memory Live Qualification A4 Review

Status: candidate-complete; awaiting Operator review

## Outcome

The optional `qwen3-embedding:0.6b-q8_0` profile now produces measurable
semantic gain on an expanded public corpus while preserving deterministic
lexical fallback. Ollama remains temporary and is not started by Chat.

## What changed

- Added `hybrid-a4-v1`: `0.20` lexical, `0.65` semantic, `0.10` confidence,
  and `0.05` layer.
- Preserved `lexical-a1-v1` for missing, stale, incompatible, or failed vector
  paths.
- Added `SOUL_MEMORY_EMBEDDING_QUERY_INSTRUCTION`, bounded to one line and 500
  characters and applied only to query embeddings.
- Expanded the public corpus from 8 to 11 queries with two additional semantic
  paraphrases and one additional hard negative.
- Exposed the ranking profile and instruction presence in read-only diagnostics.

## Live evidence

Temporary runtime: Ollama `0.32.15` on `127.0.0.1:11434`; model
`qwen3-embedding:0.6b-q8_0`, 1,024 dimensions.

- mean recall: `1.0` (lexical `0.909091`);
- mean precision: `0.954545` (lexical `0.677273`);
- mean reciprocal rank: `1.0` (lexical `0.78125`);
- correct abstentions: `3/3`;
- mean latency: `35.293818 ms`; maximum: `44.108 ms`.

The first baseline returned recall and precision `0.875`, identical to lexical,
and missed the old `spacecraft flight` fixture. Adding only the official query
instruction did not improve it. Component inspection showed that the fixture
was ambiguous and the shared lexical-heavy weights blocked useful
semantic-only admission. Those failed candidates are retained as rationale.

## Files changed

- `lib/soul_core/memory_retrieval_service.rb`
- `lib/soul_core/memory_retrieval_evaluator.rb`
- `lib/soul_core/application_facade.rb`
- `lib/soul_core/configuration_schema.rb`
- `scripts/memory-retrieval-observatory.rb`
- `scripts/verify-memory-retrieval-observatory-a0-a1.rb`
- `docs/guides/MEMORY_RETRIEVAL_OBSERVATORY.md`
- `docs/ARCHITECTURE.md`
- `docs/ROADMAP.md`
- `docs/soul/SEMANTIC_MEMORY_LIVE_QUALIFICATION_A4_BRIEF.md`
- `docs/assessments/SEMANTIC_MEMORY_LIVE_QUALIFICATION_A4_REVIEW.md`

## Commands and checks

```text
make memory-retrieval-evaluate-live
make verify-memory-retrieval-observatory
make verify-semantic-memory-chat-context
ruby -c (changed Ruby files)
git diff --check
```

## Known weaknesses

- The public corpus is small and does not prove every private-memory phrasing.
- One terrain paraphrase also admitted a related vehicle-flight memory, which
  accounts for precision below `1.0`.
- Runtime lifecycle is manual and separately gated. An absent endpoint falls
  safely back to lexical retrieval.
- The downloaded model remains on local disk until explicitly removed.

## Lifecycle, memory, and risk

- Existing query states only: `complete`, `awaiting_input`, and `failed`.
- No memory keys added; the derived index remains non-canonical.
- Risk: Class 1 owner-private read plus rebuildable derived state.

## Human review checklist

- [ ] Accept the selected local model and query instruction.
- [ ] Accept separate hybrid and lexical ranking profiles.
- [ ] Accept the measured non-perfect precision disclosure.
- [ ] Confirm no persistent embedding runtime was installed or enabled.
- [ ] Decide whether runtime lifecycle qualification should be next.
