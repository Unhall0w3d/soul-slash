# Phase 12D.5 Approved Brief: Gated Beta Build and Production Promotion

```text
brief_status: approved by human owner instruction
implementation_authorized: yes
automatic_model_code_application: no
automatic_production_promotion: no
human_visual_review_required: yes
human_merge_review_required: yes
```

The human owner approved this checkpoint on 2026-07-15 after Phase 12E closeout. It completes the safe portions of the Skill Studio lifecycle without treating model output or a passing test as authorization.

## Purpose

Connect Human Gate 1 to a bounded proposal-local Beta implementation workspace, and connect Human Gate 2 to an explicit preview-gated production copy and registry update.

## Gate 1: prepare Beta implementation

- Preview one exact approved proposal revision and one explicit canonical `skill_id`.
- Require the exact confirmation `PREPARE_BETA_BUILD <skill_id>` and unchanged digest.
- Create only a new proposal-local `beta/` workspace containing an incomplete manifest, implementation task pack, candidate entrypoint placeholder, test requirements, rollback notes, and human review artifact.
- Mark the candidate `implementation_complete: false`; it must not be runnable or described as implemented.
- Do not invoke Codex, Mistral, another model, a shell implementation agent, or a background process.
- A human or Codex may later implement the candidate under the repository's existing review rules.

## Gate 2: promote an exact tested Beta

- Require Gate 1 approval, an implemented self-contained Ruby Beta entrypoint, current passing required-test evidence, and Gate 2 approval bound to the exact Beta digest.
- Preview the production directory, registry definition, copied files, source/target hashes, and rollback instructions.
- Require `PROMOTE_BETA_SKILL <skill_id>` and an unchanged promotion digest.
- Copy only the reviewed entrypoint and manifest into `Soul/skills/generated/<skill-id>/`.
- Atomically add exactly one new entry to `Soul/skills/registry.yaml`; never replace an existing registry ID or production directory.
- Write a production-local promotion receipt containing hashes and rollback evidence.
- If registry publication fails after creating the target directory, remove only that newly created direct-child directory and return a failed terminal result.

## Bounds

- Foreground, synchronous operations only; no polling, retries, services, or continuation.
- One Beta workspace or one production skill per invocation.
- Canonical IDs: `[a-z][a-z0-9_]*(.[a-z][a-z0-9_]*)+`, maximum 120 characters.
- One self-contained Ruby entrypoint, maximum 64 KiB; no symlinks.
- Registry and generated-skill paths are fixed below the repository root.
- Production definitions preserve the Beta description, risk, approval requirement, confirmation phrase, file-write declaration, output type, and verifier declaration.

## Explicitly out of scope

- Automatic Codex/Mistral invocation or direct application of model-written code.
- Multi-file or dependency-bearing production packages.
- Package installation, network credential setup, service changes, workflow registration, merge, release, or proposal closeout.
- Replacing, upgrading, or deleting an existing production skill.
- Automatic rollback execution.
- Treating tests, model output, Gate 1, or Gate 2 alone as permission to promote.

## Required lifecycle

Every operation terminates as `complete`, `failed`, `awaiting_input`, `canceled`, or `blocked_for_human_review`. Preview is read-only. Execution is bounded and returns exact evidence of every created or preserved path.

## Required deterministic tests

- Gate 1 build preparation rejects unapproved, stale, malformed-ID, and existing-Beta requests.
- Build preparation creates only the proposal-local incomplete workspace and never invokes a model or production write.
- Production preview rejects incomplete, untested, stale-tested, unapproved, legacy, already-registered, multi-file, symlinked, and oversized candidates.
- Wrong confirmation or stale promotion digest performs no production mutation.
- Successful promotion copies exact bytes, writes a hash receipt, and atomically adds one registry definition.
- A simulated registry failure removes only the newly created target directory.
- Existing production entries and unrelated files remain byte-identical.
- Dashboard exposes both operations as explicit preview/confirmation flows.
- Phase 12 and runtime privacy regressions pass.

## Human approval

```text
Outcome: approved
Reviewer: human owner
Date: 2026-07-15
Decision: proceed with the recommended gated lifecycle checkpoint
```
