# Conversational Soul Phase 12B In-Process Application API

## Candidate status

```text
candidate_complete
human_merge_review_required
```

Candidate-complete means ready for human review, not approved for merge, release, deployment, or unattended use.

## Implementation summary

- adds a versioned `soul.application.v1` request/response contract with 23 exact operations;
- validates request IDs, operation names, parameter names/types, canonical identities, size, key count, nesting, and UTF-8 before domain calls;
- adds bounded Chat, workspace, inbox, configuration, manual status, skills, approvals, and activity projections;
- shares one Chat exchange service between the CLI and application facade;
- adds private append-only duplicate-send receipts without duplicating chat content;
- replays identical Chat sends without another provider call or message append;
- blocks request-ID scope conflicts and incomplete receipts rather than risking duplicate actions;
- keeps configuration redacted, status manual, approvals non-authorizing, and activities free of private original messages;
- adds no HTTP server, listener, frontend, daemon, service, watcher, scheduler, polling loop, or new memory store.

## Files changed

```text
docs/CONVERSATIONAL_SOUL_ROADMAP.md
docs/assessments/CONVERSATIONAL_SOUL_PHASE12B_IN_PROCESS_APPLICATION_API.md
docs/soul/IN_PROCESS_APPLICATION_API.md
docs/soul/PHASE12B_IN_PROCESS_APPLICATION_API_BRIEF.md
lib/soul_core/app.rb
lib/soul_core/application_chat_service.rb
lib/soul_core/application_contract.rb
lib/soul_core/application_facade.rb
lib/soul_core/application_request_receipt_store.rb
lib/soul_core/chat_command.rb
lib/soul_core/chat_store.rb
lib/soul_core/phase12b_in_process_application_api_assessor.rb
scripts/verify-multiturn-conversation-runtime-phase3.rb
scripts/verify-phase12b-in-process-application-api.rb
```

## Commands run

```text
ruby bin/soul assess phase12b-in-process-application-api --json
ruby bin/soul assess phase12b-in-process-application-api
ruby scripts/verify-phase12b-in-process-application-api.rb
ruby scripts/verify-multiturn-conversation-runtime-phase3.rb
find lib scripts bin -type f -name '*.rb' -print0 | xargs -0 -n1 ruby -c
ruby bin/soul assess repo-curation --json
direct local-model Phase 12B application-facade eval harness
git diff --check
```

## Deterministic test results

```text
PASS: 20/20 Phase 12B checks.
PASS: Phase 3 shared-Chat-path regression.
PASS: Phase 11A–11D and Phase 12A regressions.
```

Coverage includes bootstrap purity, request validation, input bounds, empty state, canonical Chat creation, exact message pairing, replay, conflict blocking, receipt privacy, lifecycle behavior, result caps, Phase 11D delegation, manual status, configuration redaction, approval safety, activity privacy, bounded exceptions, CLI sharing, and absence of transport/background primitives.

## Local LLM eval results

```text
Model: soul-qwen3-8b-q4
Provider: local.openai_compatible (local_only)
Provider calls: 2; local only
PASS: application facade created one canonical Chat
PASS: two Chat sends returned useful responses
PASS: the second response retained the supplied project codename across turns
PASS: exactly two user/assistant pairs were persisted
PASS: identical replay made no provider call and appended no message
PASS: changed-content request-ID reuse blocked before provider invocation
```

The eval is behavioral only. Deterministic tests approve request validation, idempotency, privacy, persistence, and authorization boundaries.

## Memory keys

```text
New durable memory keys: none
Existing conversation memory behavior: unchanged
Forget behavior: unchanged
```

Request receipts are operational idempotency state, not conversational memory.

## Lifecycle states touched

```text
complete
failed
awaiting_input
canceled
blocked_for_human_review
```

No operation remains running after return.

## Risk classification

```text
Class 2: Local state write, non-destructive
```

Chat exchanges, pins, and inbox states use existing local state. No user artifact bytes are modified.

## Safety and persistence check

```text
Persistent service added: no
Daemon added: no
HTTP/TCP listener added: no
Frontend added: no
Watcher added: no
Scheduled task added: no
Cron job added: no
systemd unit added: no
Long-running background loop added: no
Background polling added: no
Configuration writer added: no
Approval authority added: no
Skill execution authority added: no
Confirmation gate weakened: no
Cloud opt-in weakened: no
Skill-private memory store added: no
```

## Known weaknesses

- The first facade is synchronous and does not stream model tokens.
- ChatStore remains file-backed; application operations cap output and scan 10,000 messages but do not add database indexing.
- Chat create and pin/unpin are not request-receipt idempotent; duplicate-send protection applies to the higher-risk provider-backed Chat exchange.
- A crash after request reservation blocks reuse for human recovery rather than automatically repairing or retrying.
- A receipt completion failure after messages append reports a blocked state; the stored exchange remains truthful and request reuse remains blocked.
- Pending approval fingerprints are display-only and cannot be used to approve or execute.
- Activity projection is intentionally sparse and excludes original messages.
- HTTP transport and dashboard visuals remain Phase 12C.

## Human review checklist

```text
[ ] Matches the approved Phase 12B brief
[ ] Request validation fails closed
[ ] Terminal envelope is stable and useful
[ ] Chat CLI and facade share one exchange path
[ ] Duplicate-send receipts are private and appropriately bounded
[ ] Replay and conflict behavior are correct
[ ] Workspace/inbox retain Phase 11D boundaries
[ ] Configuration remains redacted and read-only
[ ] Status refresh remains explicit and manual
[ ] Approval summaries are non-authorizing
[ ] Activities omit private original messages
[ ] No listener, frontend, service, watcher, or polling exists
[ ] Deterministic tests are meaningful
[ ] Local LLM eval is behavioral only
[ ] Regressions pass
[ ] Known weaknesses are acceptable
[ ] Candidate is approved for merge
```

## Human review outcome

```text
Outcome: pending
Reviewer: human owner
Date:
Decision summary:
Required changes:
```
