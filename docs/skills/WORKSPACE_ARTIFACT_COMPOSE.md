# Bounded Workspace Artifact Composition

`workspace.artifact.compose` is the modern public name for Soul's established
Phase 11C/11D conversational artifact workflow. It does not add a new writer.
`ConversationArtifactCreationService` remains the sole implementation for
drafting, approval, creation, registration, attachment, revision lineage, and
shared-workspace delivery.

## Chat and Voice examples

```text
Create a project report at artifacts/status.md covering the reviewed findings.
Can you revise artifact art_example into artifacts/status-v2.md with project privacy?
```

Creation requires one explicit substantial text deliverable and exactly one
new project-relative target below `artifacts/`. Revision additionally requires
one active source artifact attached to the current conversation and a different
new target. Ordinary artifact discussion remains conversation.

## Preview and approval

Soul uses only a configured `local_only` or `local_network` provider. Preview
creates no artifact file. It reports the target, privacy, provider, size, line
count, SHA-256 digest, provenance, redacted excerpt, expiring approval token,
and exact next actions.

```text
create artifact <approval-token> confirm
cancel artifact operation <approval-token>
```

The first form is the only creation authority. Generic agreement, a repeated
request, or an example from this guide does not authorize a write. The token is
single-use and bound to the operation, target, content digest and size, privacy,
conversation, provider, source identity and digest, and any grounding evidence.

## Output and limits

- exactly one new UTF-8 `.md`, `.txt`, or `.json` file;
- fixed `artifacts/` root, 256 KiB maximum, and 4,000-line maximum;
- parsed JSON validation for `.json` output;
- exclusive no-follow creation with exact byte, size, digest, and identity
  verification;
- canonical artifact registration, active-chat attachment, and synchronous
  inbox delivery; and
- revision creates a new artifact and cannot reduce source privacy.

Absolute paths, traversal, symlinks, missing nested parents, overwrite, cloud
drafting, code or executables, rich documents, media, archives, multi-file
packages, publication, automatic retries, watchers, services, schedules, and
background continuation are outside this skill.

The historical internal approval identity `artifact.create_revision` remains
unchanged so existing pending operations do not silently lose or change their
authority. The public skill name is catalog metadata, not a second execution
token or application operation.
