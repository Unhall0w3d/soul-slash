# Fundamental Skill Cohort A1 — Workspace Artifact Compose

## Purpose

Deliver the fourth Fundamental Skill Cohort A1 candidate by packaging the
existing Phase 11C/11D artifact workflow as the modern
`workspace.artifact.compose` skill. This slice must not add a second writer,
registry, approval store, attachment model, inbox store, or application path.

## Existing implementation authority

`ConversationArtifactCreationService` remains the only writer. An explicit
Chat or Voice deliverable request passes through the existing artifact decision
policy and conversation runtime. `chats.send` is the application API entry.

Preview performs one local-provider draft and persists a private bounded
operation record. It returns a redacted excerpt, target, privacy, provider,
size, line count, SHA-256, provenance, and expiring approval token without
creating the artifact file. Execution remains the exact command
`create artifact <token> confirm`; cancellation remains
`cancel artifact operation <token>`.

For pending-operation compatibility, approval tokens remain internally bound
to historical skill identity `artifact.create_revision`. The modern public
registry name does not create or replace an execution identity.

## Output boundary

- exactly one new project-relative file below `artifacts/`;
- `.md`, `.txt`, or `.json` only;
- at most 256 KiB and 4,000 lines;
- valid UTF-8, non-binary content, and parsed JSON when applicable;
- no overwrite, traversal, absolute path, symlink, unsupported parent, or
  unsupported format;
- exclusive no-follow creation and exact byte/size/digest verification; and
- canonical artifact registration, chat attachment, revision lineage, and
  synchronous inbox delivery through existing stores.

Revision requires one active artifact attached to the current chat and creates
a new target without changing the source. Privacy cannot become less
restrictive.

## Provider and authority boundary

Only configured `local_only` or `local_network` providers may draft. Source
content, research grounding, and provider output are untrusted and cannot
choose the path, privacy, approval scope, or operation. No cloud fallback,
direct edit, overwrite, code/executable output, rich document, media, archive,
multi-file package, publication, memory promotion, retry loop, service,
schedule, watcher, or background continuation is added.

## Lifecycle

Every invocation terminates as `complete`, `failed`, `awaiting_input`,
`canceled`, or `blocked_for_human_review`. A preview awaiting approval is
durable state for a future invocation, not a running process.

## Acceptance

- the modern skill package points only to the existing handler;
- explicit creation and revision route to preview while ordinary artifact
  discussion remains conversation;
- preview is non-mutating and execution requires the original exact gate;
- original Phase 11C/11D deterministic verification remains green;
- registry, invocation, capability, documentation, and tracker projections
  agree; and
- the separate human gate remains required before acceptance.
