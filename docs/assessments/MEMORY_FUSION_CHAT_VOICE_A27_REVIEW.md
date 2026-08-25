# Memory Fusion Chat and Voice A27 Review

Status: candidate-complete; production-facade retrieval is qualified, while
human Voice experience review remains required.

## Implemented

- Policy-controlled projection gate with local ordering.
- Exact A23 identity and canonical-local-join validation.
- Safe local hybrid or lexical fallback.
- Shared Chat and Voice context path with canonical re-read.
- Retrieval mode, profile, projection, and generation diagnostics.

## Deterministic validation

Run `ruby scripts/verify-memory-fusion-chat-voice-a27.rb` plus the existing A3,
A23, A24, A25, and A26 verifiers.

## Human review

- [x] Activate the exact production-qualified A29 policy through A26.
- [x] Qualify representative known-memory and negative-abstention cases through
  the public `ApplicationFacade` Observatory query route.
- [x] Confirm canonical local content is re-read and remote projection content
  does not enter prompts.
- [x] Confirm typed Chat and Voice share the same ConversationRuntime context
  implementation deterministically.
- [ ] Complete human spoken recall, latency, and usefulness review.
