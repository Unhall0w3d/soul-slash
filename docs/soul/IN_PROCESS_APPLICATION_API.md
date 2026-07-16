# In-Process Application API

Phase 12B defines the transport-independent application contract consumed by the CLI and foreground dashboard.

## Boundary

The facade is an in-process Ruby object. It adds no HTTP server, socket, listener, frontend, service, daemon, watcher, scheduler, polling loop, or automatic startup.

It delegates to existing Soul services for:

```text
conversation runtime
chat persistence
workspace and inbox
typed configuration
bounded host status
skill registry
Skill Studio proposal and Beta lifecycle
Self Improvement assessment and advisory proposals
approval storage
execution activity
```

The facade does not create a second assistant runtime or storage model.

## Envelope

Requests use:

```json
{
  "schema_version": "soul.application.v1",
  "request_id": "dashboard:example-001",
  "operation": "chats.list",
  "parameters": {"limit": 50},
  "context": {"interface": "dashboard"}
}
```

Responses always include:

```text
schema_version
request_id
operation
ok
lifecycle_state
data
errors
warnings
meta.generated_at
meta.mutation
meta.idempotent_replay
meta.limits
```

Terminal lifecycle states are:

```text
complete
failed
awaiting_input
canceled
blocked_for_human_review
```

## Operations

The first registry includes:

```text
application.bootstrap
application.cancel

chats.list
chats.get
chats.messages
chats.create
chats.send
chats.pin
chats.unpin
chats.clear.preview
chats.clear.execute
chats.forget.preview
chats.forget.execute

workspace.list
workspace.chat
workspace.detail
inbox.list
inbox.deliver
inbox.mark_seen
inbox.dismiss

system_status.refresh

configuration.show
configuration.explain
configuration.validate

skills.list

skill_studio.proposals.list
skill_studio.proposals.get
skill_studio.proposals.approval.preview
skill_studio.proposals.approval.execute
skill_studio.proposals.beta_build.preview
skill_studio.proposals.beta_build.execute
skill_studio.proposals.close.preview
skill_studio.proposals.close.execute
skill_studio.betas.list
skill_studio.betas.get
skill_studio.betas.run.preview
skill_studio.betas.run.execute
skill_studio.betas.promotion.preview
skill_studio.betas.promotion.approve
skill_studio.betas.production.preview
skill_studio.betas.production.execute

self_improvement.snapshot
self_improvement.refresh
self_improvement.proposals.preview
self_improvement.proposals.execute

approvals.pending
activities.recent
```

Unknown operations, parameters, context fields, and value types fail closed before a domain call.

Conversation clearing accepts exactly one scope: `mode: title` with a trimmed exact `title`, `mode: selected` with a non-empty array of unique exact `chat_ids`, or `mode: all` with neither selector. Preview returns the exact projected records and a SHA-256 match digest. Execute repeats the same scope and requires that digest plus `CLEAR_CONVERSATIONS`; selected chats that are no longer active cause a human-review block before mutation.

## Bounds

```text
request JSON: 128 KiB
one string: 64 KiB
keys: 64
nesting depth: 8
chats: 50
messages: 200
workspace/inbox: 50
skills: 100
pending approvals: 50
activities: 100
chat message scan: 10,000 records
request receipts: 5,000 events / 2 MiB
```

IDs use explicit canonical patterns. Untrusted strings are never used for dynamic method lookup, constants, or filesystem paths.

## Chat exchange and idempotency

The CLI and application facade share `ApplicationChatService`.

One successful send:

```text
reserve request ID and input digest
→ append one user message
→ call the existing ConversationRuntime
→ append one assistant message
→ complete the receipt
→ return
```

The private append-only receipt file is:

```text
Soul/runtime/application/request_receipts.jsonl
mode: 0600
```

Receipts contain request identity, input digest, chat identity, message IDs, and terminal category. They do not duplicate chat content, credentials, hidden reasoning, or configuration.

Replaying the same request ID, chat, and message returns the existing exchange without another provider call or appended message. Reusing a request ID with changed scope blocks for human review.

If execution is interrupted after reservation, the receipt remains incomplete and reuse blocks rather than risking a duplicate provider call or message pair. Recovery is explicit and foreground-only.

## Read projections

- Chat lists expose canonical chat metadata.
- Message history is explicit and capped.
- Workspace and inbox delegate to Phase 11D and remain metadata-only unless an existing artifact inspection is separately invoked.
- Configuration delegates to Phase 12A and remains redacted and read-only.
- System status is collected by `system_status.refresh`; the dashboard requests it once on page bootstrap and exposes manual refresh.
- Skills are registry summaries and cannot execute.
- Skill Studio preserves exact-revision proposal and Beta gates; no application operation performs automatic implementation or promotion.
- Self Improvement snapshots and refreshes are read-only. Its sole mutation writes advisory proposal packets after preview and exact confirmation.
- Pending approvals use non-authorizing fingerprints and omit token values and sensitive scope values.
- Activities omit original private messages and expose only bounded classifications.

Phase 12E composes `approvals.pending` and `activities.recent` in the dashboard Review Center. The surface is read-only, loads only when opened or manually refreshed, and retains the existing caps and redaction rules. It does not add a fourth product tab or any approval/history mutation operation.

## Safety inheritance

The application facade does not grant new authority. Existing provider privacy, cloud opt-in, artifact approval, destructive-action confirmation, memory promotion, and human-review gates remain authoritative.

No model output can select an application request ID, authorize a replay conflict, approve a token, change configuration, or bypass domain validation.

## Dashboard relationship

The Phase 12C foreground loopback transport translates same-origin HTTP requests into this in-process envelope. Later dashboard slices extend registered operations through the facade; route handlers still must not read domain stores directly or reproduce domain logic.
