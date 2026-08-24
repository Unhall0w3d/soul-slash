# Memory Conversation Observation Capture A11 Review

Status: candidate-complete and approved for merge; live acceptance remains
pending

## What was implemented

- A shared owner-private, append-only segmented conversation observation
  ledger with no lifetime event or byte ceiling.
- Automatic foreground capture of the exact persisted user and assistant
  messages after each successful application chat turn.
- Ordered two-message batch capture with SHA-256 content and event chaining.
- Deterministic observation identities and idempotent application-request
  replay.
- Content-free capture and integrity receipts.
- Bounded 32-MiB / 25,000-event segments, cross-segment digest continuity,
  UTF-8 and timestamp validation, path and symlink protection,
  duplicate/conflict rejection, flush, and `fsync`.
- A content-free sharded identity index used for bounded historical
  idempotency lookup, plus explicit foreground full-history verification and
  index reconstruction.
- Safe degradation: an observation dependency failure is reported without
  erasing or hiding the already-persisted chat response. Replaying the same
  completed application request retries the missing capture idempotently.

## Files changed

- `Makefile`
- `docs/ARCHITECTURE.md`
- `docs/CURRENT_STATE.md`
- `docs/soul/MEMORY_POLICY.md`
- `docs/soul/MEMORY_CONVERSATION_OBSERVATION_CAPTURE_A11_BRIEF.md`
- `docs/assessments/MEMORY_CONVERSATION_OBSERVATION_CAPTURE_A11_REVIEW.md`
- `lib/soul_core/application_chat_service.rb`
- `lib/soul_core/conversation_observation_store.rb`
- `scripts/verify-memory-conversation-observation-capture-a11.rb`

## Validation

- `make verify-memory-conversation-observation-capture`
  - PASS, 26 checks.
- `ruby scripts/verify-chat-progress-summaries-a1.rb`
  - PASS.
- `ruby scripts/verify-voice-presence-a4-local-latency.rb`
  - PASS, 39 deterministic checks.
- `ruby scripts/verify-semantic-memory-chat-context-a3.rb`
  - PASS, 11 checks.
- `ruby scripts/verify-private-memory-separation.rb`
  - PASS, 12 checks.
- `make verify-memory-audit-reconstruction`
  - PASS, 38 checks.
- `ruby scripts/verify-phase12b-in-process-application-api.rb`
  - PASS, including shared Chat-path and staged-diff regressions.
- `ruby scripts/verify-responsive-chat-and-web-research.rb`
  - PASS, 44 checks.
- `ruby scripts/verify-chat-intent-and-interaction-boundary.rb`
  - PASS, 35 checks.
- `ruby scripts/verify-structured-capability-gap-signal.rb`
  - PASS.
- `ruby scripts/verify-local-search-a2.rb`
  - PASS.
- Ruby syntax checks and `git diff --check`
  - PASS.

No local LLM evaluation was used because this slice tests deterministic source
capture, integrity, idempotency, and privacy boundaries rather than model
behavior.

## Known limitations

- Only newly completed application chat turns are captured. Historical chat
  backfill belongs to a later bounded projection/backfill slice.
- Failed or interrupted turns without an assistant message remain only in the
  operational chat store.
- Segments are retained indefinitely by default. Physical retention limits,
  archival tiers, or purge remain later protected policy decisions.
- Full-history integrity verification and index rebuilding become
  progressively more expensive as retained history grows, but are explicit
  foreground maintenance rather than part of normal chat capture.
- This slice does not classify, summarize, embed, promote, retrieve, export, or
  physically purge observations.

## Memory and lifecycle impact

- Tests used synthetic temporary roots only. No live conversation or private
  memory content was inspected, captured, imported, changed, or deleted.
- Capture terminates as `complete` or `failed`; there is no background
  continuation.
- Observations are source evidence, not candidates or approved memories.

## Risk classification

Medium-high. The change automatically duplicates completed conversations into
durable private evidence, but remains local, ignored by Git, foreground,
bounded, content-isolated from receipts, and excluded from retrieval.

## Human review checklist

- [x] Confirm exact successful-turn capture is the desired source boundary.
- [x] Confirm observations must not enter retrieval automatically.
- [x] Confirm physical purge remains a separate protected operation.
- [x] Confirm a failed capture should preserve the completed chat response and
      be repairable by exact request replay.
- [x] Accept bounded 32-MiB segments with indefinite default retention and no
      lifetime ledger ceiling.
- [x] Approve candidate publication and merge.
- [ ] Perform one live chat turn after merge and verify the content-free capture
      receipt and private ledger integrity.
