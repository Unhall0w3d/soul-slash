# Conversational Soul Phase 11D Shared Workspace and Artifact Inbox

## Candidate status

```text
candidate_complete
human_merge_review_required
```

Candidate-complete means ready for human review, not approved for merge, release, deployment, or unattended use.

## Implementation summary

- adds an append-only private artifact-inbox event store with `new`, `seen`, and `dismissed` state;
- keeps the Phase 11 artifact ID canonical and projects workspace records from existing artifact metadata;
- provides bounded workspace, chat-workspace, inbox, and detail queries capped at 50 records;
- supports synchronous idempotent delivery of one active artifact attached to the current chat;
- integrates automatic inbox delivery after successful Phase 11C verification, registration, and attachment;
- preserves truthful artifact completion when the later inbox append fails;
- validates revision and delivery provenance without silently repairing inconsistencies;
- filters provider-facing workspace context through the existing artifact privacy matrix;
- supplies deterministic chat controls and explicit lifecycle outcomes;
- adds no listener, dashboard, service, watcher, scheduler, polling loop, file mutation, or new memory store.

## Files changed

```text
docs/CONVERSATIONAL_SOUL_ROADMAP.md
docs/assessments/CONVERSATIONAL_SOUL_PHASE11D_SHARED_WORKSPACE_INBOX.md
docs/soul/ARTIFACT_METADATA_AND_ATTACHMENT.md
docs/soul/BOUNDED_ARTIFACT_CREATION_AND_REVISION.md
docs/soul/SHARED_WORKSPACE_AND_ARTIFACT_INBOX.md
lib/soul_core/app.rb
lib/soul_core/chat_responder.rb
lib/soul_core/conversation_artifact_creation_service.rb
lib/soul_core/conversation_artifact_inbox_store.rb
lib/soul_core/conversation_context_builder.rb
lib/soul_core/conversation_orchestrator.rb
lib/soul_core/conversation_runtime.rb
lib/soul_core/conversation_workspace_controls.rb
lib/soul_core/conversation_workspace_service.rb
lib/soul_core/phase11d_shared_workspace_inbox_assessor.rb
scripts/verify-phase11d-shared-workspace-inbox.rb
```

## Commands run

```text
ruby bin/soul assess phase11d-shared-workspace-inbox --json
ruby bin/soul assess phase11d-shared-workspace-inbox
ruby scripts/verify-phase11d-shared-workspace-inbox.rb
ruby scripts/verify-phase11c-bounded-artifact-creation.rb
find lib scripts bin -type f -name '*.rb' -print0 | xargs -0 -n1 ruby -c
ruby bin/soul assess repo-curation --json
direct local-model Phase 11D runtime eval harness
git diff --check
```

## Deterministic test results

```text
PASS: Phase 11D assessment JSON and text report candidate_ready with no blockers.
PASS: 17/17 deterministic Phase 11D checks.
PASS: Phase 11C, 11B, and 11A artifact regressions.
```

Coverage includes empty state, canonical identity, revision provenance, append-only delivery, idempotency, state transitions, cross-chat rejection, active/attached requirements, provider privacy filtering, corrupt provenance, query bounds, deterministic routing, context labeling, Phase 11C automatic delivery, post-creation inbox failure, explicit append failure, file preservation, and private runtime permissions.

## Local LLM eval results

```text
Model: soul-qwen3-8b-q4
Provider: local.openai_compatible (local_only)
Provider calls: 1; local only
PASS: workspace summary stayed deterministic and useful
PASS: current-chat workspace summary stayed deterministic and relevant
PASS: ambiguous delivery requested one artifact ID without mutation
PASS: ambiguous dismissal requested one delivery ID without mutation
PASS: background watching was refused with a foreground-refresh alternative
PASS: local-model metadata synthesis was useful, included the artifact ID and content-read boundary, and excluded sentinel file content
PASS: inbox delivery state remained unchanged during evaluation
```

Local LLM evaluation validates routing, phrasing, ambiguity, foreground-refresh behavior, and usefulness only. It does not approve artifact eligibility, provenance, privacy, delivery, state mutation, or file safety.

## Memory keys

```text
Reads: none
Writes or updates: none
Forget behavior: not applicable
```

Inbox events are shared artifact/task operational state, not durable conversational memory.

## Lifecycle states touched

```text
complete
failed
awaiting_input
canceled
blocked_for_human_review
```

No process remains alive after a response or while awaiting input.

## Risk classification

```text
Class 2: Local state write, non-destructive
```

Delivery and state changes append local metadata. They do not alter artifact file bytes, lifecycle, privacy, attachment, or canonical identity.

## Safety and persistence check

```text
Persistent service added: no
Daemon added: no
Network listener added: no
Watcher added: no
Scheduled task added: no
Cron job added: no
systemd unit added: no
launch agent added: no
Windows service added: no
Long-running background loop added: no
Background polling added: no
Confirmation gate weakened: no
Skill-private memory store added: no
Cloud provider fallback added: no
Parallel artifact identity added: no
Artifact file mutation added: no
Cross-chat implicit attachment added: no
```

## Known weaknesses

- Workspace views validate metadata provenance but do not reread artifact bytes; exact-byte integrity remains an explicit Phase 11B inspection.
- The JSONL stores replay their bounded local histories and do not yet provide SQLite indexing or full-text search.
- The workspace projection exposes only the latest delivery state per artifact; the inbox event store retains complete event history.
- Automatic inbox append failure requires an explicit foreground retry; no background recovery is attempted.
- Cross-chat delivery is intentionally unsupported even when an artifact is attached to multiple chats.
- Workspace context includes only delivered items and remains capped at five records.
- The dashboard and visual review gate remain future Phase 12 work.

## Human review checklist

```text
[ ] Matches the approved Phase 11D brief
[ ] Canonical artifact identity is preserved
[ ] Inbox event storage is bounded and appropriate
[ ] Delivery idempotency is adequate
[ ] Cross-chat and active/attached boundaries are correct
[ ] Seen/dismissed state cannot mutate artifacts
[ ] Provenance mismatch behavior is acceptable
[ ] Provider privacy filtering is correct
[ ] Phase 11C completion remains truthful on delivery failure
[ ] No listener, watcher, service, or background behavior exists
[ ] Deterministic tests are meaningful
[ ] Local LLM eval is behavioral only
[ ] Phase 11A, 11B, and 11C regressions pass
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
