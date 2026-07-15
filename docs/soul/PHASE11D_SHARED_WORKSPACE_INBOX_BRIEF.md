# Phase 11D Candidate Brief: Shared Workspace and Artifact Inbox

```text
brief_status: candidate
implementation_authorized: no
human_review_required: yes
```

This brief must be reviewed and approved by the human owner before implementation begins.

## Purpose

Complete the artifact-aware conversation milestone with a bounded, interface-independent workspace projection and artifact inbox. Phase 11D makes existing artifact, revision, chat, and task provenance queryable as shared workspace items without adding a dashboard, arbitrary filesystem browsing, background delivery process, or parallel artifact identity.

Delivery is synchronous local state recorded during the foreground operation that creates it. No process remains alive to watch for new files or await user input.

## Risk class

```text
Class 2: Local state write, non-destructive
```

The phase may append inbox and workspace-lifecycle records. It must not modify artifact file bytes or delete, overwrite, move, rename, upload, or export user data.

## Approved scope

Phase 11D may:

- expose a bounded workspace read model derived from the existing artifact registry, chat attachment state, revision provenance, and task lifecycle records;
- list and filter workspace items by chat ID, artifact kind, lifecycle, privacy, delivery state, and bounded time ordering;
- return one workspace item's metadata and provenance by stable artifact ID;
- append an idempotent inbox-delivery record for a registered active artifact;
- synchronously deliver a Phase 11C artifact to the originating chat inbox after verified creation and attachment;
- support explicit deterministic delivery of one active artifact already attached to the current chat;
- mark an inbox delivery `seen` or `dismissed` through append-only events without changing or archiving the artifact;
- render concise deterministic creation, revision, delivery, failure, and blocked-for-review summaries;
- preserve artifact privacy metadata and suppress incompatible records before any provider context;
- supply interface-independent result contracts suitable for later CLI and dashboard clients;
- reuse existing shared task, artifact, approval, and conversation infrastructure;
- add deterministic tests, behavioral local-LLM evals, documentation, and a human review artifact.

## Explicitly out of scope

Phase 11D must not:

- add a web server, HTTP listener, dashboard, frontend framework, daemon, watcher, scheduler, or background delivery process;
- crawl, index, or display arbitrary filesystem paths;
- create a second artifact registry or duplicate artifact identity;
- read artifact content unless the existing Phase 11B inspection contract explicitly authorizes the read;
- silently attach an existing artifact to a different chat;
- deliver an inactive, unknown, unattached, or integrity-failed artifact;
- change artifact privacy classification;
- overwrite, edit in place, delete, move, rename, archive, upload, share, export, or execute artifact files;
- add rich-document parsing, OCR, binary artifacts, media handling, provider export, or multi-file packages;
- add voice input/output behavior;
- add SQLite, PostgreSQL, ChromaDB, a vector store, or a storage migration;
- add automatic memory promotion or skill-private durable memory;
- broaden Phase 11C creation formats or output roots;
- treat an LLM response as authorization for delivery, mutation, privacy changes, or lifecycle transitions.

## Canonical identity and projection

The Phase 11 artifact ID remains canonical. A workspace item is a projection, not a new independently mutable object.

An inbox delivery record must retain:

```text
delivery_id
artifact_id
originating_chat_id
recipient_chat_id
delivery_reason
artifact_lifecycle_at_delivery
privacy
size_bytes
sha256
created_at
latest_delivery_state
latest_state_at
```

The record must not duplicate full artifact content, approval tokens, private chat text, hidden reasoning, or secrets.

## Inputs

Workspace listing:

```text
Optional:
- chat ID
- artifact kind
- artifact lifecycle
- privacy class
- delivery state
- result limit, capped at 50
```

Workspace detail:

```text
Required:
- one stable artifact ID
```

Explicit inbox delivery:

```text
Required:
- current chat ID
- exactly one active artifact ID attached to that chat
```

Inbox state change:

```text
Required:
- current chat ID
- exactly one delivery ID belonging to that chat
- target state: seen or dismissed
```

Missing or ambiguous required inputs terminate as `awaiting_input` without provider invocation or file mutation.

## Outputs

User-facing:

- bounded workspace list with title, kind, lifecycle, privacy, revision relationship, delivery state, and updated time;
- artifact detail with canonical path, size, digest, source, provider, chat, attachment, revision, and inbox provenance;
- concise delivery, state-change, failure, and blocked-for-review summaries;
- explicit statement that workspace metadata does not imply content read or mutation authority.

Structured/logged:

- operation and delivery IDs;
- artifact and chat IDs;
- filters and bounded result counts;
- lifecycle transition;
- privacy and digest metadata;
- terminal state and bounded failure reason.

Never log artifact content, approval token values, hidden reasoning, credentials, or private chat transcripts.

## Memory behavior

```text
Reads: none
Writes: none
Updates: none
Forget behavior: not applicable
```

Workspace and inbox records are task/artifact operational state, not durable conversational memory.

The inbox implementation should use a shared append-only artifact-inbox event store. It must not store artifact content or create a second mutable copy of artifact metadata.

## Task lifecycle

Every operation terminates as one of:

```text
complete
failed
awaiting_input
canceled
blocked_for_human_review
```

Expected flow:

```text
invoked
→ context_check
→ awaiting_input, if a reference is missing or ambiguous
→ executing, only for a bounded append-only delivery or inbox-state event
→ complete / failed / canceled / blocked_for_human_review
→ exit
```

No operation remains silently running after it returns.

## First-use behavior

If no artifact has been delivered, return a useful empty workspace/inbox response and exit `complete`. Do not generate sample data, call a provider, scan the filesystem, or create a background watcher.

If an explicit delivery request lacks one unambiguous active artifact attached to the current chat, return `awaiting_input` and exit without mutation.

## Follow-up behavior

Supported deterministic follow-ups may include:

```text
show workspace
show workspace for this chat
show inbox
show artifact <artifact-id>
deliver artifact <artifact-id> to inbox
mark delivery <delivery-id> seen
dismiss delivery <delivery-id>
cancel workspace request
```

Generic affirmation must not infer a delivery target or inbox state change.
An explicit cancellation returns `canceled`, appends no inbox event, and exits.

## Provider and dependency behavior

Workspace queries, delivery, and state changes are deterministic and require no model provider.

A local model may be used only to validate conversational routing and phrasing in evals. It must not decide artifact eligibility, privacy, delivery, lifecycle, or mutation. Provider failure during an optional conversational rendering path must leave deterministic workspace behavior available.

## Safety and confirmation gates

- A delivery event never grants permission to read, revise, execute, upload, move, or delete an artifact.
- Existing-artifact delivery requires one explicit artifact ID active and attached to the current chat.
- Automatic delivery is allowed only as the synchronous completion step of an already approved Phase 11C creation/revision operation and must be idempotent.
- Successful artifact creation is not rolled back or reported as failed when the later inbox append fails. The artifact operation remains `complete`; the response must separately expose `delivery_state: failed` with a bounded reason and a safe explicit retry path.
- `seen` and `dismissed` mutate only append-only inbox state and do not alter artifact lifecycle or attachment.
- No operation accepts a path as a substitute for a registered artifact ID.
- Privacy filtering occurs before any workspace metadata is supplied to a provider-facing context.
- Integrity failure or inconsistent provenance returns `blocked_for_human_review` without repairing or rewriting records automatically.

## Bounded execution

- Workspace queries return at most 50 records.
- Detail returns exactly one artifact projection.
- Delivery and state-change operations append at most one logical event per invocation.
- Automatic delivery is idempotent for the same artifact, originating chat, recipient chat, and delivery reason.
- File content is not read during normal workspace or inbox operations.
- No retries, polling, loops over unbounded histories, or background continuation are allowed.

## Deterministic tests required

- empty workspace and inbox complete without mutation or provider call;
- projection reuses canonical artifact IDs and does not create a parallel registry;
- filters and ordering are stable and capped at 50;
- workspace detail exposes bounded provenance without content reads;
- Phase 11C completion produces one synchronous idempotent inbox delivery;
- explicit delivery requires one active artifact attached to the current chat;
- unknown, inactive, detached, cross-chat, or ambiguous artifacts do not deliver;
- `seen` and `dismissed` append state without changing artifact bytes, lifecycle, privacy, or attachment;
- duplicate delivery is idempotent;
- privacy-incompatible records are absent from provider-facing context;
- integrity/provenance inconsistency blocks for human review;
- no artifact file is created, changed, moved, renamed, or deleted;
- no background process, listener, watcher, scheduler, or polling loop is added;
- explicit cancellation terminates as `canceled` without mutation;
- complete, failed, awaiting-input, canceled, and blocked-for-review outcomes are represented;
- Phase 11A, 11B, and 11C regressions pass.

## Local LLM evals required

Local LLM evals validate routing and usefulness only, never delivery safety or mutation authorization.

- Prompt: "What is in my workspace?"
  Expected: useful bounded workspace summary; no filesystem claim or content-read claim.
- Prompt: "Show me what Soul created in this chat."
  Expected: relevant delivered artifact metadata and revision relationship; no unrelated artifacts.
- Prompt: "Send that to the inbox."
  Expected: focused clarification when more than one artifact is plausible; no inferred mutation.
- Prompt: "Dismiss it" after one delivery is explicitly in focus.
  Expected: correct bounded continuation or focused clarification; no artifact archival or deletion claim.
- Prompt: "Keep watching the workspace and tell me when something changes."
  Expected: explain that background watching is unavailable; offer a foreground refresh.

## Failure behavior

- Unknown or detached artifact: `awaiting_input`; no event.
- Inactive artifact or inconsistent provenance: `blocked_for_human_review`; no event.
- Provider privacy mismatch while rendering optional conversational context: omit the incompatible record before the provider call; the local inbox record remains available through deterministic views.
- Invalid delivery ID or cross-chat state request: `failed`; no event.
- Corrupt registry or inconsistent provenance: `blocked_for_human_review`; preserve existing state.
- Explicit-delivery or inbox-state append failure: `failed`; report no successful delivery or state change.
- Automatic inbox append failure after Phase 11C creation: preserve the verified registered artifact, keep artifact creation `complete`, expose `delivery_state: failed`, and provide a safe explicit retry command.
- Provider unavailable during conversational eval/rendering: deterministic workspace operations remain available.

## Logging and review artifact

Use shared artifact/task history infrastructure. Do not create a skill-private memory store.

Implementation must create:

```text
docs/assessments/CONVERSATIONAL_SOUL_PHASE11D_SHARED_WORKSPACE_INBOX.md
```

The review artifact must document implementation, files changed, commands, deterministic results, local-LLM eval results, weaknesses, memory behavior, lifecycle states, risk, and the human review checklist required by `AGENTS.md`.

## Done criteria

Phase 11D is candidate-complete when:

- the approved scope is implemented without out-of-scope behavior;
- canonical artifact identity is preserved;
- workspace and inbox operations are bounded, synchronous, and foreground-only;
- deterministic tests and Phase 11 regressions pass;
- required local-model behavioral evals pass or failures are documented;
- memory behavior and operational storage are documented;
- the review artifact is complete;
- all operations exit in an explicit terminal state;
- human merge review remains pending.

## Human brief review

```text
Outcome: pending
Reviewer: human owner
Date:
Decision summary:
Required changes:
```
