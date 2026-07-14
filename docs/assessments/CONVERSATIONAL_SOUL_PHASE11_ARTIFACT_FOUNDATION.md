# Conversational Soul Phase 11 Artifact Foundation

## Outcome

Phase 11A begins artifact-aware conversation with a metadata and attachment foundation.

Soul can register an existing project-local file as an artifact, attach or detach it from a chat, inspect its provenance and lifecycle metadata, and archive the metadata without deleting the file.

## Boundaries

- File contents are not injected into model context.
- Attachment is not permission to read or mutate a file.
- Registration and archival require explicit confirmation.
- Paths remain project-local and exclude sensitive runtime state.
- Artifact events are append-only.
- The model cannot register or approve artifacts by improvisation.
- Explicit deliverable requests are recognized without hijacking ordinary uses of the word `file`.

## Next slice

Phase 11B can add bounded artifact creation and delivery on top of this shared identity, provenance, and attachment contract.

## Candidate status

```text
candidate_complete
```

This status records implementation readiness for human review. It is not merge or release approval.

## Files changed

```text
.gitignore
CHANGELOG.md
docs/ARCHITECTURE.md
docs/CONVERSATIONAL_SOUL_ROADMAP.md
docs/INTERACTION_ARCHITECTURE.md
docs/REPOSITORY_HYGIENE.md
docs/assessments/CONVERSATIONAL_SOUL_PHASE11_ARTIFACT_FOUNDATION.md
docs/soul/ARTIFACT_METADATA_AND_ATTACHMENT.md
lib/soul_core/app.rb
lib/soul_core/chat_responder.rb
lib/soul_core/conversation_artifact_contract.rb
lib/soul_core/conversation_artifact_controls.rb
lib/soul_core/conversation_artifact_decision_policy.rb
lib/soul_core/conversation_artifact_store.rb
lib/soul_core/conversation_context_builder.rb
lib/soul_core/conversation_orchestrator.rb
lib/soul_core/phase11_artifact_metadata_attachment_assessor.rb
scripts/verify-phase11-artifact-metadata-attachment.rb
```

## Commands run

```text
ruby scripts/verify-phase11-artifact-metadata-attachment.rb
ruby -c <each repository Ruby file>
git diff --check
git diff --cached --check
```

## Deterministic test results

```text
Phase 11A verifier: passed
Phase 10 closeout regression: passed
Ruby syntax checks: passed for 241 discovered Ruby files
Working-tree whitespace check: passed
Staged whitespace check: passed
```

The Phase 11A verifier exercises project-root and reserved-path rejection, symlink rejection, registration confirmation, append-only events, attachment and archival behavior, metadata-only context, decision-policy anti-hijacking, and Phase 10 regression coverage.

## Local LLM eval results

```text
Not run for Phase 11A.
```

Phase 11A adds deterministic metadata and attachment controls and does not inject artifact contents into model context. Model-backed behavioral evaluation is deferred to the first slice that supplies artifact contents for conversational synthesis. No model result is used as safety approval.

## Known weaknesses

- Phase 11A registers existing project-local files but does not create, revise, ingest, or deliver artifacts.
- The artifact registry is replayed from an append-only JSONL file and has no compaction strategy yet.
- Attachment supplies metadata only; it does not prove that a later consumer is authorized to read or disclose content.
- Artifact privacy classes are recorded but require explicit provider-routing enforcement before any future content inspection.
- Artifact lifecycle currently supports only `active` and `archived`.

## Memory keys

Reads:

```text
none
```

Writes or updates:

```text
none
```

Artifact state uses the shared artifact registry at `Soul/artifacts/conversation_artifacts.jsonl`; it does not create a skill-private memory store.

## Lifecycle states touched

```text
active
archived
attached
detached
```

Each control returns synchronously as complete, failed, awaiting confirmation, or blocked. No process remains running after control returns.

## Risk classification

```text
local_metadata_write
```

Registration and archival mutate only the append-only local artifact registry and require literal confirmation. Attachment and detachment are explicit reversible registry events. Phase 11A does not read artifact contents into model context and does not modify, execute, upload, move, or delete registered files.

## Safety and persistence check

```text
Persistent service added: no
Daemon added: no
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
```

## Human review checklist

```text
[x] Matches the approved Phase 11A scope
[x] No unapproved scope expansion
[x] No persistent or background behavior
[x] Risk classification is correct
[x] Memory behavior is appropriate
[x] Registration and archival confirmation gates are intact
[x] Path and sensitive-state exclusions are adequate
[x] Deterministic tests are meaningful
[x] Failure behavior is predictable
[x] Local artifact registry hygiene is appropriate
[x] Candidate is approved for merge
```

## Human review outcome

```text
Outcome: approved
Reviewer: human owner
Date: 2026-07-14
Decision summary: The human owner explicitly authorized Codex to push and merge the candidate after the documented checks passed.
Required changes: none
```
