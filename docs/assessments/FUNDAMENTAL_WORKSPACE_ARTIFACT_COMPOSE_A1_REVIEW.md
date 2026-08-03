# Fundamental Skill Cohort A1 — Workspace Artifact Compose Review

Date: 2026-08-02

Branch: `codex/fundamental-artifact-compose-a1`

Status: candidate-complete; human review required

## Implementation

This slice gives the mature Phase 11C/11D conversational artifact workflow the
modern public identity `workspace.artifact.compose`. It intentionally adds no
second implementation path. `ConversationArtifactCreationService` remains the
only writer, and `chats.send` remains the Chat and Voice application entry.

An explicit deliverable request selects one new target below `artifacts/` and
uses one configured local provider to draft bounded content. Preview creates no
artifact file and returns a redacted excerpt plus provider, provenance, size,
line count, digest, token, and expiry. The exact command
`create artifact <token> confirm` consumes one scope-bound token and invokes
exclusive no-follow creation, exact byte and digest verification, canonical
registration, active-chat attachment, and workspace delivery. Cancellation is
synchronous. Revision requires one attached active source, preserves it, uses a
new target, records lineage, and cannot reduce privacy.

The historical internal approval identity `artifact.create_revision` is
preserved. The new public skill ID is registry and instruction metadata, not a
new application operation or token namespace.

## Authority and privacy

Only `local_only` and `local_network` provider classes may draft. Conversation
selects requirements, a supported target, privacy, and an attached source for a
revision; it cannot authorize cloud fallback, overwrite, arbitrary paths,
direct edit, unsupported formats, multi-file output, publication, memory
promotion, retries, or background continuation.

Source content, retained research evidence, and model output are untrusted.
They cannot choose path, privacy, approval scope, provider class, or execution.

## Deterministic evidence

The focused verifier checks the modern package, registry, invocation catalog,
operator capability catalog, unchanged internal token identity, absence of a
second application operation, exact creation/revision/control routing, and
ordinary-conversation restraint. It also runs the original Phase 11C assessor,
which uses temporary roots and injected local providers to cover preview,
execution, cancellation, concurrency, token reuse, source drift, privacy,
structured JSON, limits, provider failure, registry recovery, and the Phase 11D
delivery handoff.

## Results

```text
make verify-fundamental-workspace-artifact-compose
10 checks passed

quick_validate.py Soul/skills/workspace/compose-artifact
Skill is valid

ruby scripts/verify-phase11c-bounded-artifact-creation.rb
candidate-ready

ruby scripts/verify-phase11d-shared-workspace-inbox.rb
candidate-ready
```

The final candidate also runs the invocation, capability, Chat boundary,
application API, project tracker, Skill Studio, generated-documentation, skill
catalog, and full `make test-soul` regressions before publication.

## Local LLM eval

Not used. This slice changes packaging and catalogs, not generative behavior.
Deterministic fixtures cover routing and authority. LLM output remains untrusted
content and does not approve a write.

## Known weaknesses

- exact conversational request shapes are conservative;
- output is limited to one Markdown, text, or JSON artifact;
- non-root nested target directories must already exist;
- local-model draft quality still needs human review; and
- the documented public/internal identity distinction remains necessary for
  pending-operation compatibility.

## Memory and lifecycle

No memory key, private memory format, cache, or index was added. Requests
terminate as `complete`, `failed`, `awaiting_input`, `canceled`, or
`blocked_for_human_review`. A durable preview awaiting a later exact command is
not a resident process.

## Risk classification

`write_local_state`, Class 2 non-destructive local creation. Preview is
non-mutating; execution is single-use, expiring, digest-bound, scope-bound,
exclusive, verified, and non-overwriting. Human review is still required.

## Human review

Review the single-writer mapping, preview and token scope, local-provider
restriction, creation verification, revision privacy and lineage, Chat/Voice
restraint, recovery semantics, and absence of cloud, memory, retry,
persistence, or background behavior. Passing tests does not authorize merge or
production acceptance.
