# Self Augmentation A4–A5 Implementation Brief

Status: human-authorized implementation brief
Authorization date: 2026-07-16
Source decision: “let's work on the next two gates”

## Outcome

Implement the two remaining Self Augmentation gates defined by the approved
architecture:

1. **Gate A1 / A4:** approve one exact proposal and file scope, verify a clean
   primary worktree at the proposal base commit, create one detached linked
   worktree, and write a bounded implementation handoff without invoking Codex.
2. **Gate A2 / A5:** inspect one clean committed candidate in that worktree,
   produce a deterministic review dossier, approve that exact candidate for
   external integration consideration, and write a handoff without integrating.

## Authorized effects

- Run bounded Git inspection commands with argument arrays and fixed timeouts.
- Create one detached linked Git worktree per approved proposal beneath
  `Soul/augmentation/worktrees/<experiment-id>`.
- Write experiment, dossier, approval, and handoff records beneath
  `Soul/augmentation/experiments/<experiment-id>`.
- Run allowlisted syntax and changed-verifier commands only inside Bubblewrap
  with no network, a read-only candidate worktree, writable `/tmp`, bounded
  output, sequential execution, and a per-command timeout.
- Expose explicit preview/digest/confirmation operations through the existing
  authenticated local application facade and Self Augmentation tab.
- Remove a clean experiment worktree only through a separately previewed exact
  cleanup gate. Dirty worktrees are never removed by Soul.

## Explicitly prohibited

- Invoking Codex, a local LLM, cloud model, or another implementation agent.
- Editing the primary worktree or applying candidate patches to it.
- Creating a named branch, commit, tag, PR, merge, push, release, or deployment.
- Force-removing a worktree or deleting a dirty candidate.
- Running arbitrary operator-, model-, proposal-, or candidate-supplied shell
  text.
- Executing candidate code outside the declared Bubblewrap sandbox.
- Network access from candidate verification.
- Installing dependencies or changing lockfiles outside an approved candidate.
- Reading `.env`, credentials, private memory, runtime data, models, ignored
  files, or untracked primary-worktree content.
- Host mutation, privilege escalation, persistent services, schedulers,
  watchers, daemons, or background continuation.
- Treating tests, model output, or a dossier as merge/release authorization.

## Proposal eligibility

- Proposal packet must use `soul.self_augmentation.proposal.v1` and exist in the
  approved local proposal root.
- Gate A1 accepts an explicit list of 1–100 exact repository-relative paths.
  No globs, absolute paths, traversal, `.git`, private/generated roots, or
  symlink paths are allowed.
- Class 5 subjects—authentication, privilege, persistence, destructive
  behavior, security boundaries, memory policy, provider privacy, or unattended
  execution—remain blocked without a proposal-specific human brief.
- The primary worktree must be clean, have no submodules, and have HEAD exactly
  equal to the proposal base commit immediately before worktree creation.

## Gate A1 lifecycle

```text
preview exact proposal + allowed paths
→ digest + APPROVE_AUGMENTATION_EXPERIMENT
→ revalidate clean base and absence of existing target
→ git worktree add --detach <bounded-target> <exact-base>
→ write record + CODEX_HANDOFF.md + CANDIDATE_RESULTS template
→ blocked_for_human_review
```

The terminal state means the experiment awaits explicit human/Codex work. No
process remains alive.

## Candidate review

- Candidate worktree must be clean and HEAD must differ from the base.
- HEAD must identify a commit descended from the exact base.
- Complete `git diff --name-status`, `--numstat`, and bounded patch statistics
  are collected for `base..candidate`.
- Every changed path must be in the Gate A1 allowlist. Symlinks, submodules,
  forbidden paths, and unexpected dependency/configuration/migration changes
  block the dossier.
- Ruby and JavaScript syntax checks run for changed applicable files.
- At most ten changed `scripts/verify-*.rb` files may run. Bubblewrap is
  mandatory; absence or failure blocks Gate A2.
- Model-facing changes are detected from explicit path categories. They require
  a separately recorded capability-specific local-model result before Gate A2;
  the model result cannot decide safety or approval.

## Gate A2 lifecycle

```text
generate current dossier
→ all deterministic blockers clear
→ preview exact candidate/dossier digest
→ APPROVE_AUGMENTATION_FOR_INTEGRATION_REVIEW
→ revalidate candidate commit, clean state, paths, and dossier
→ write approval + INTEGRATION_HANDOFF.md
→ blocked_for_human_review
```

The handoff instructs the human/Codex operator to create any branch/commit/PR or
perform integration externally. Soul does not execute those actions.

## Cleanup lifecycle

Cleanup preview requires a known experiment and clean worktree. Exact
confirmation `REMOVE_CLEAN_AUGMENTATION_WORKTREE` revalidates cleanliness and
runs `git worktree remove` without `--force`. Review records are retained and
the experiment becomes `canceled` or `complete`, never silently deleted.

## Bounds

- One worktree per proposal; at most 100 experiment records.
- At most 100 allowed or changed paths.
- Git command timeout: 20 seconds; sandbox command timeout: 30 seconds.
- At most ten changed verifier commands; output capped at 256 KiB per stream.
- Dossier and record files capped at 1 MiB each.
- All operations are synchronous foreground operations with terminal lifecycle.

## Required review artifact

The candidate review must record files changed, commands, deterministic results,
model qualification status, known weaknesses, memory keys, lifecycle states,
risk classification, and a human checklist. Passing verification means
candidate-complete only.
