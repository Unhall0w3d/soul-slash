# Shared Workspace and Artifact Inbox

Phase 11D adds an interface-independent shared workspace projection and append-only artifact inbox over the canonical Phase 11 artifact registry.

## Identity and storage

The artifact ID remains the only canonical identity. Workspace items are projections of artifact, attachment, revision, and inbox metadata; they are not copied files or independently mutable artifacts.

Inbox events are private runtime task state:

```text
Soul/runtime/artifact_inbox/events.jsonl
```

The file is append-only, mode `0600`, and ignored by Git. It contains delivery metadata and state events, not artifact content, chat transcripts, approval tokens, hidden reasoning, or credentials.

## Commands

```text
workspace help
show workspace
show workspace for this chat
show inbox
show workspace artifact <artifact-id>
deliver artifact <artifact-id> to inbox
mark delivery <delivery-id> seen
dismiss delivery <delivery-id>
cancel workspace request
```

Workspace and inbox reads are metadata-only. They do not imply that artifact content was read.

## Projection fields

A workspace projection includes bounded canonical metadata:

```text
artifact ID and title
kind and lifecycle
privacy
project-relative path and media type
size and SHA-256
source and chat provenance
revision relationship
attachment chat IDs
latest inbox delivery ID, reason, state, and timestamps
```

Queries return at most 50 records. Provider-facing conversation context receives at most five delivered workspace records, filtered through the existing artifact privacy matrix before rendering.

## Delivery

Explicit delivery accepts exactly one active artifact attached to the current chat. Delivery is synchronous and idempotent for the tuple:

```text
artifact ID
originating chat ID
recipient chat ID
delivery reason
```

Phase 11C creation and revision synchronously attempt an inbox delivery only after exact-byte verification, registration, and attachment succeed.

If automatic inbox delivery fails:

- the verified registered artifact remains complete;
- the artifact is not removed or falsely reported as failed;
- `delivery_state` is `failed` with a bounded reason;
- the user can retry with `deliver artifact <id> to inbox`.

## Inbox states

```text
new
seen
dismissed
```

State changes append events. They never change artifact lifecycle, attachment, privacy, revision provenance, or file bytes. Repeating the same delivery or state transition is idempotent.

## Provenance and privacy

Workspace detail validates revision references and verifies that inbox snapshots retain the canonical artifact ID, size, digest, and privacy metadata. Inconsistency returns `blocked_for_human_review`; Soul does not silently repair the record.

Workspace metadata does not reread artifact bytes. Exact-byte file integrity remains an explicit Phase 11B inspection operation.

Local deterministic views may display all local metadata. Before workspace metadata enters model context, artifact privacy filters suppress records incompatible with the selected provider class.

## Bounded lifecycle

Every operation returns one of:

```text
complete
failed
awaiting_input
canceled
blocked_for_human_review
```

No listener, watcher, service, scheduler, retry loop, or background continuation is added. A later dashboard will call the same workspace service rather than reading JSONL state directly.
