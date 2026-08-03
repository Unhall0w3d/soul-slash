# Human review — workspace.artifact.compose

Candidate: Fundamental Skill Cohort A1, slice 4

Status: candidate-complete; human review required

## Implemented

- A modern public skill package over the existing Phase 11C/11D artifact flow.
- One explicit substantial `.md`, `.txt`, or `.json` deliverable per operation.
- Existing local-provider preview, redaction, digest, expiry, and approval token.
- Existing exclusive no-follow creation, exact verification, canonical registry,
  active-chat attachment, revision lineage, and workspace inbox delivery.
- Existing deterministic Chat and Voice path through `chats.send`.
- Registry, invocation, capability, public documentation, and tracker records.

No new artifact writer, application operation, token identity, approval store,
registry, attachment model, inbox store, or background execution path was added.
The internal token identity remains `artifact.create_revision` so pending
operations retain their original authority and compatibility.

## Files changed

- `Soul/skills/workspace/compose-artifact/`
- skill, invocation, and operator-capability registries
- cohort tracker and current-state documentation
- `docs/skills/WORKSPACE_ARTIFACT_COMPOSE.md`
- `docs/soul/FUNDAMENTAL_WORKSPACE_ARTIFACT_COMPOSE_A1_BRIEF.md`
- `docs/assessments/FUNDAMENTAL_WORKSPACE_ARTIFACT_COMPOSE_A1_REVIEW.md`
- `scripts/verify-fundamental-workspace-artifact-compose-a1.rb` and Make target

The existing implementation under `lib/soul_core/conversation_artifact_*` was
not changed.

## Commands and deterministic results

See `docs/assessments/FUNDAMENTAL_WORKSPACE_ARTIFACT_COMPOSE_A1_REVIEW.md` for
the complete validation inventory.

The focused verifier includes the original Phase 11C end-to-end temporary-root
assessment and proves the modern package maps to that single writer.

## Local LLM eval

Not used. Routing, approval, file constraints, verification, registry state,
and lifecycle behavior are deterministic. Provider output is untrusted content
and cannot validate authority or safety.

## Memory keys

None added or used. No skill-private memory exists.

## Lifecycle states

```text
complete
failed
awaiting_input
canceled
blocked_for_human_review
```

A preview awaiting a future invocation is persisted state, not a running
process.

## Risk classification

`write_local_state`, non-destructive. Preview is non-mutating. Execution needs
the preview's unexpired, single-use, digest- and scope-bound token plus literal
`confirm`. Creation cannot overwrite an artifact.

## Persistence and safety

```text
Persistent service added: no
Daemon or watcher added: no
Scheduled task added: no
Background continuation added: no
Automatic retry added: no
Cloud provider path added: no
Second writer or registry added: no
Skill-private durable memory added: no
```

## Known weaknesses

- Exact conversational wording is deliberately conservative.
- Only Markdown, plain text, and JSON are supported.
- Nested target parents must already exist; only the fixed `artifacts/` root may
  be created automatically.
- Draft quality remains bounded by the selected local model and requires human
  review before reliance or publication.
- The public skill ID differs from the retained historical token identity; this
  compatibility distinction must remain documented until a separately reviewed
  migration is justified.

## Human review checklist

- [ ] Confirm the public skill maps only to the existing artifact service.
- [ ] Confirm preview creates no artifact file.
- [ ] Confirm the token binds the exact target, digest, scope, source, and chat.
- [ ] Confirm execution remains exclusive, verified, and non-overwriting.
- [ ] Confirm only local provider classes may draft.
- [ ] Confirm revision lineage and privacy restrictions remain intact.
- [ ] Confirm ordinary artifact discussion does not invoke composition.
- [ ] Confirm no service, watcher, schedule, retry, cloud path, or memory was
      added.
- [ ] Accept, request revision, or reject this candidate independently of tests.
