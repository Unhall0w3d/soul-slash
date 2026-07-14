# Conversational Soul Phase 11C Bounded Artifact Creation and Revision

## Candidate status

```text
candidate_complete
human_merge_review_required
```

Candidate-complete means ready for human review, not approved for merge, release, or unattended use.

## Implementation summary

- routes explicit artifact deliverables to a local-model preview rather than an immediate write;
- supports one `.md`, `.txt`, or `.json` file below project-relative `artifacts/`;
- defaults omitted privacy to the existing `project` class and never selects a cloud provider;
- creates revision output as a new artifact while preserving source bytes and registry history;
- reuses Phase 11B attached-source inspection, integrity verification, redaction, and privacy policy;
- persists bounded pending operation state only until a terminal outcome, then removes draft content;
- binds an expiring, single-use approval token to operation, target, content digest/size, privacy, chat, provider, and source provenance;
- requires the token and literal `confirm`; generic affirmation cannot execute;
- keeps the approval token visible in the user transcript while redacting it from later model context;
- uses exclusive no-follow creation, inode/device continuity, post-close byte/size/SHA-256 verification, and expected registration metadata;
- registers and attaches only verified files and records revision provenance;
- preserves a verified file for human recovery if registry attachment fails;
- implements visible `complete`, `failed`, `awaiting_input`, `canceled`, and `blocked_for_human_review` outcomes.

## Files changed

```text
docs/CONVERSATIONAL_SOUL_ROADMAP.md
docs/soul/ARTIFACT_METADATA_AND_ATTACHMENT.md
docs/soul/BOUNDED_ARTIFACT_CREATION_AND_REVISION.md
docs/soul/PHASE11C_BOUNDED_ARTIFACT_CREATION_REVISION_BRIEF.md
docs/assessments/CONVERSATIONAL_SOUL_PHASE11C_BOUNDED_ARTIFACT_CREATION_REVISION.md
lib/soul_core/app.rb
lib/soul_core/conversation_artifact_contract.rb
lib/soul_core/conversation_artifact_controls.rb
lib/soul_core/conversation_artifact_creation_service.rb
lib/soul_core/conversation_artifact_inspector.rb
lib/soul_core/conversation_artifact_operation_store.rb
lib/soul_core/conversation_artifact_store.rb
lib/soul_core/conversation_context_builder.rb
lib/soul_core/conversation_orchestration_contract.rb
lib/soul_core/conversation_orchestrator.rb
lib/soul_core/conversation_runtime.rb
lib/soul_core/phase11c_bounded_artifact_creation_assessor.rb
scripts/verify-phase11c-bounded-artifact-creation.rb
```

## Commands run

```text
ruby bin/soul assess phase11c-bounded-artifact-creation --json
ruby bin/soul assess phase11c-bounded-artifact-creation
ruby scripts/verify-phase11c-bounded-artifact-creation.rb
ruby scripts/verify-phase11-bounded-artifact-inspection.rb
ruby scripts/verify-phase11c-readiness.rb
find lib scripts bin -type f -name '*.rb' -print0 | xargs -0 -n1 ruby -c
ruby bin/soul assess repo-curation --json
direct local-model Phase 11C runtime eval harness
git diff --check
```

## Deterministic test results

```text
PASS: Phase 11C assessment JSON and text reports candidate_ready with no blockers.
PASS: 25/25 deterministic Phase 11C checks.
PASS: Phase 11B artifact-inspection regression.
PASS: Phase 11C readiness regression.
```

Coverage includes non-mutating preview, literal confirmation, token absence/expiry/reuse/scope/chat binding, token redaction from model context, cancellation, concurrent confirmation serialization, approval-store failure cleanup, path traversal, absolute path, symbolic link, missing parent, existing target, multiple targets, target race, unsupported format, binary/UTF-8/JSON/byte/line limits, cloud exclusion, provider failure, revision ambiguity/privacy/integrity, source preservation, exact-byte output verification, registration/attachment, runtime integration, and registry-failure recovery.

## Local LLM eval results

```text
Model: soul-qwen3-8b-q4
Provider: local.openai_compatible (local_only)
Provider calls: 3; all local
PASS: useful creation preview; no file created
PASS: generic “Yes, go ahead” used conversation mode and did not execute
PASS: cancellation revoked the pending creation without a file
PASS: unsupported PDF failed before a provider call
PASS: two-source revision ambiguity requested input before a provider call
PASS: hostile-source revision produced a useful preview, preserved source bytes, and created no target
PASS: cancellation revoked the hostile-source revision without a file
```

Local LLM evaluation validates routing, phrasing, ambiguity, hostile-source handling, and usefulness only. It does not approve path safety, privacy, tokens, confirmation, mutation, or recovery behavior.

## Memory keys

```text
Reads: none
Writes or updates: none
Forget behavior: not applicable
```

Pending draft content is bounded runtime task state, not durable memory. Draft content is removed when the operation becomes complete, failed, canceled, or blocked for review.

## Lifecycle states touched

```text
complete
failed
awaiting_input
canceled
blocked_for_human_review
```

No process remains alive after a response or while waiting for confirmation.

## Risk classification

```text
Class 2: Local state write, non-destructive
```

Creation writes a new file and append-only artifact/runtime records. Revision never edits its source. Existing targets are never overwritten, moved, renamed, archived, or deleted.

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
Cloud provider fallback added: no
Existing-file overwrite added: no
In-place revision added: no
Delete, move, rename, upload, share, or export added: no
```

## Known weaknesses

- Model drafting is limited by the configured provider output-token cap, below the absolute 256 KiB validation ceiling in normal use.
- Revision context uses the bounded, redacted Phase 11B text window rather than arbitrary full-document context.
- Pending operation files temporarily contain unredacted draft content with mode `0600`; content is removed at terminal state, but physical storage reclamation depends on the filesystem.
- The required short-lived approval token remains in the user-visible chat transcript; it is redacted from subsequent recent-turn and digest context before model calls.
- Only the fixed `artifacts/` root may be created automatically; nested output directories must already exist.
- Registry failure after verified creation requires human recovery and may leave an unregistered file by design.
- Privacy defaults to `project` to reconcile the approved brief's required eval prompt with the existing artifact-contract default; cloud remains prohibited.

## Human review checklist

```text
[x] Matches the approved Phase 11C brief and documented privacy clarification
[x] No overwrite or in-place revision path exists
[x] Token scope and literal confirmation are adequate
[x] Exclusive no-follow and exact-byte verification are adequate
[x] Target and source race handling is acceptable
[x] Local provider and artifact privacy boundaries are correct
[x] Pending draft runtime storage is acceptable
[x] Registry-failure recovery behavior is acceptable
[x] Deterministic tests are meaningful
[x] Local LLM eval is behavioral only
[x] Phase 11A, 11B, and readiness regressions pass
[x] Known weaknesses are acceptable
[x] Candidate is approved for merge
```

## Human review outcome

```text
Outcome: approved for merge
Reviewer: human owner
Date: 2026-07-14
Decision summary: Human owner explicitly instructed Codex to merge PR #4 after reviewing the candidate summary and passing validation results.
Required changes: none
```
