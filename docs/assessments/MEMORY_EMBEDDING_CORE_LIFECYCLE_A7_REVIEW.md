# Memory Embedding Core Lifecycle A7 Review

## Candidate outcome

A7 is candidate-complete for installation review. It fixes the qualified
`qwen3-embedding:0.6b-q8_0` endpoint at a 1024-token ceiling, reuses the existing
Core controller, and preserves lexical retrieval when the endpoint fails.

## Files changed

- `lib/soul_core/memory_embedding_runtime_coordinator.rb`
- `lib/soul_core/ollama_model_runtime_deployment.rb`
- `lib/soul_core/core_orchestration_service.rb`
- `lib/soul_core/application_facade.rb`
- `scripts/soul-memory-embedding-runtime`
- `scripts/soul-model-runtime-start-selected`
- `scripts/verify-memory-embedding-core-lifecycle-a7.rb`
- `Makefile`
- A7 brief and current documentation

## Deterministic evidence

`make verify-memory-embedding-core-lifecycle` passed 15 checks. Existing Core
orchestration passed 27 checks. Retrieval Observatory, semantic Chat context,
private runtime review, and reviewed-ledger bootstrap suites all passed.
`git diff --check` passed.

## Live qualification evidence

The 1024-token pilot processed 1,023 embedding tokens. The embedding runner used
1,324 MiB of NVIDIA VRAM alongside the 5,296 MiB Qwen chat process, leaving
1,475 MiB free. Simultaneous embedding and Chat completed successfully. Ten
warm short embeddings averaged 56.7 ms. Teardown closed port 11434 and returned
GPU usage to the exact 5,306 MiB baseline.

## Lifecycle and risk

The lifecycle states are `complete`, `failed`, and
`blocked_for_human_review`. Installation and removal require literal
confirmations. The unit is loopback-only, inactive, unenabled, and cannot select
a Core or mutate memory. Free Core teardown fails closed before the Core change;
non-Free startup failure degrades semantic retrieval to the established lexical
path rather than blocking Chat.

## Known weaknesses

- The 1,475 MiB Soul-Lite margin is viable but tighter than the 512-token pilot.
- Only Soul-Lite coexistence has direct live load evidence; other non-Free Cores
  still require observation after installation.
- Index rebuilding remains an explicit foreground operation.

## Human review checklist

- [x] Accept the 1024-token ceiling.
- [x] Accept Core-owned endpoint lifecycle and Free Core exclusion.
- [x] Review the exact unit plan and Ollama binary digest.
- [x] Install the inactive, unenabled unit.
- [x] Observe Soul-Lite startup and live hybrid retrieval.
- [ ] Observe one transition for each remaining applicable Core.
- [ ] Approve merge after live review.
