# Artifact Metadata and Conversation Attachment

Phase 11A establishes a common artifact identity and attachment contract without adding automatic file generation or mutation.

## Purpose

Artifacts are durable or reviewable outputs that should not be dumped wholesale into conversation. Examples include reports, code bundles, overlays, spreadsheets, presentations, research notes, and implementation packages.

The first Phase 11 slice gives existing project-local files:

- stable artifact IDs;
- source and chat provenance;
- kind, media type, privacy class, size, path, and SHA-256 metadata;
- append-only registration, attachment, detachment, and archival events;
- metadata-only conversation context;
- deterministic inspection and lifecycle controls.

## Safety boundary

Registration does not read artifact contents into model context and does not modify the registered file. Attachment grants no permission to read, rewrite, move, execute, upload, or delete the file.

The registry rejects:

- files outside the project root;
- symbolic links;
- directories and missing files;
- `.git`, `.env`, `.ssh`, and common private-key paths;
- local memory, identity, runtime, approval, log, and run-state paths.

Archival changes registry metadata only. It never deletes the artifact file.

## Decision policy

A request becomes an explicit artifact request only when it combines a creation or delivery verb with a recognized deliverable, such as “produce a report” or “package an overlay.” Merely mentioning a file, reviewing a path, or asking about a file descriptor remains ordinary conversation.

The policy is advisory in Phase 11A. It does not create files automatically.

## Deterministic controls

```text
artifact help
register artifact: <project-relative path> | <title> | <kind> | <privacy> confirm
list all artifacts
list chat artifacts
show artifact <id>
inspect artifact <id>
summarize artifact <id>
artifact excerpt <id>
compare artifacts <id> and <id>
attach artifact <id>
detach artifact <id>
archive artifact <id> confirm
```

Registration and archival require the literal `confirm` keyword. Attachment and detachment are explicit, reversible metadata operations.

## Phase 11B inspection

Attachment remains metadata-only by default. Explicit inspection requests may read active attached text artifacts through the bounded contract in `docs/soul/BOUNDED_ARTIFACT_INSPECTION.md`.

Every read uses no-follow semantics and verifies the exact bytes against registered size and SHA-256 metadata. Artifact privacy limits eligible provider classes before content enters model context. Ambiguous, failed, and privacy-blocked inspections stop without a provider call. Inspection does not mutate the file or registry.

## Local state

The append-only registry is stored at:

```text
Soul/artifacts/conversation_artifacts.jsonl
```

It is local runtime state and is ignored by Git.

## Deferred work

Phase 11C adds bounded creation and no-overwrite revision through `docs/soul/BOUNDED_ARTIFACT_CREATION_AND_REVISION.md`. Later Phase 11 slices may add inbox delivery, attachment ingestion, provider export, and richer file lifecycle controls. Those features must reuse this metadata and provenance contract rather than inventing parallel artifact identities.
