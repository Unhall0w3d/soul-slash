# Bounded Artifact Creation and Revision

Phase 11C adds one-file, local-model-assisted creation for Markdown, plain-text, and JSON artifacts. Revision creates a new version and never changes the source file.

## Authority boundary

An explicit deliverable request produces a preview, not a file. The preview shows the target, privacy, provider, byte and line counts, SHA-256, source provenance when applicable, and a bounded redacted excerpt.

Execution requires the preview's unexpired, single-use approval token and the literal `confirm` keyword:

```text
create artifact <token> confirm
```

A generic “yes” or “go ahead” never executes a write. Pending work may be canceled synchronously:

```text
cancel artifact operation <token>
```

Every invocation exits as `complete`, `failed`, `awaiting_input`, `canceled`, or `blocked_for_human_review`. No process remains alive waiting for approval.

## Output boundary

- one output file per operation;
- target must remain below project-relative `artifacts/`;
- supported extensions are `.md`, `.txt`, and `.json`;
- maximum final size is 256 KiB;
- maximum final line count is 4,000;
- content must be valid UTF-8 and non-binary;
- JSON must parse before preview and again before execution;
- only the fixed `artifacts/` root may be created automatically;
- existing targets, symbolic links, traversal, absolute paths, and missing nested parents are rejected.

The file is opened with exclusive-create and no-follow flags. Soul verifies the exact bytes, size, and SHA-256 after close before registering or attaching the artifact.

## Revision boundary

A revision names exactly one active artifact attached to the current chat and a new target filename. The source passes the Phase 11B no-follow, exact-byte integrity check before preview and again before execution.

Revision privacy must be at least as restrictive as source privacy. Source instructions remain untrusted data. The source bytes and original registry record are unchanged, and the new artifact records `revision_of_artifact_id` provenance.

## Provider boundary

Phase 11C uses only configured `local_only` or `local_network` providers and never falls back to cloud. The Phase 11 privacy matrix is enforced before source content reaches the provider. Omitted output privacy defaults to `project`, matching the existing artifact contract; `project` content is barred from cloud providers.

One bounded provider request drafts the preview content. Provider output is untrusted and cannot choose the target, privacy, approval scope, or execution behavior.

## Approval scope and races

The approval token binds:

```text
operation ID and type
target path
content SHA-256 and size
privacy class
chat ID
provider ID
source artifact ID and SHA-256, when revising
```

Execution recomputes and revalidates the bound scope. Target appearance, token expiry or reuse, scope changes, source drift, and output validation failures stop without overwriting or deleting foreign files.

## Recovery behavior

If writing or byte verification fails, Soul removes only the partial new file created by that invocation. If the file verifies but registry attachment fails, Soul preserves the verified file and returns `blocked_for_human_review` with its path and digest for recovery.

## Deferred work

Phase 11C does not add in-place edits, overwrite, delete, move, rename, archive, inbox delivery, upload, sharing, export, rich documents, code, executables, media, or multi-file packages.
