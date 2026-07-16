# Self Augmentation A4–A5 Review

Status: candidate-complete; human review required
Date: 2026-07-16

## What was implemented

- Gate A1 previews and approves one exact proposal, base commit, and list of
  repository-relative files.
- Immediately before mutation it requires a clean primary worktree, exact
  proposal HEAD, no submodules, no forbidden path, and no Class 5 subject.
- Exact confirmation creates one detached linked worktree under the ignored
  augmentation root and writes an implementation handoff plus candidate-results
  template. It does not invoke Codex or edit source.
- Candidate review requires a clean committed candidate descended from the
  exact base, inventories the complete diff, validates every path and Git mode,
  and collects dependency/configuration impact categories.
- Changed Ruby/JavaScript syntax and at most ten changed Ruby verifier scripts
  run sequentially in foreground Bubblewrap sessions with no network, a
  read-only candidate worktree, writable temporary storage, capped output, and
  per-command plus aggregate timeouts.
- Model-facing candidates require digest-bound, human-attested evidence from a
  separately run local-model qualification. That evidence authorizes nothing.
- Gate A2 re-runs the dossier and exact-candidate validation, then writes only an
  external integration handoff. It creates no branch, commit, merge, push,
  deployment, migration, host action, or persistent process.
- Cleanup has its own preview/digest/confirmation gate, refuses dirty
  worktrees, uses non-forced `git worktree remove`, and retains review records.
- The authenticated API and Self Augmentation tab expose Experiment and Review
  as real lifecycle stages with explicit gates and truthful terminal states.

## Files changed

- `lib/soul_core/self_augmentation_experiment_service.rb`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `assets/dashboard/index.html`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/dashboard.css`
- `scripts/verify-self-augmentation-a4-a5.rb`
- `docs/soul/SELF_AUGMENTATION_A4_A5_IMPLEMENTATION_BRIEF.md`
- Architecture, milestone, changelog, ignore rules, and generated-root
  sentinels.

## Commands run

```text
ruby -c lib/soul_core/self_augmentation_experiment_service.rb
ruby -c lib/soul_core/application_contract.rb
ruby -c lib/soul_core/application_facade.rb
node --check assets/dashboard/dashboard.js
ruby scripts/verify-self-augmentation-a4-a5.rb
ruby scripts/verify-self-augmentation-host-improvement-a1-a3.rb
ruby scripts/verify-phase12d3-self-improvement-dashboard.rb
ruby scripts/verify-phase12e-unified-review-center.rb
git diff --check
```

## Deterministic test results

All focused commands passed. The A4–A5 verifier creates a temporary Git
repository and proves:

- preview and wrong-confirmation paths create no worktree;
- Gate A1 creates exactly one detached worktree and no Codex task;
- external model evidence is digest-gated and non-authorizing;
- a committed allowed-file candidate produces a clear dossier with passing
  no-network sandboxed syntax and Git-aware verifier checks;
- wrong Gate A2 confirmation writes no approval;
- exact Gate A2 writes a handoff while the primary HEAD remains unchanged;
- dirty cleanup is refused and clean cleanup is non-forced;
- the API and dashboard expose both explicit gates without polling or automatic
  implementation/integration operations.

## Local LLM eval results

Not run for this implementation candidate. A4–A5 includes a typed route for
recording separately executed capability-specific local-model evidence when a
future candidate changes model-facing paths. LLM output cannot validate Git
paths, sandboxing, safety, approval, or integration readiness.

## Known weaknesses

- Bubblewrap is currently required for candidate execution. On systems without
  it, Gate A2 remains blocked; there is no unsafe fallback.
- The sandbox exposes the candidate read-only plus the repository's Git metadata
  read-only so Git-aware verifiers work; private runtime and ignored user data
  remain unmounted.
- The sandboxed checks are intentionally narrow and cannot prove semantic
  correctness or absence of malicious behavior.
- Model qualification evidence is externally run and human-attested. Soul
  validates its schema, candidate binding, and digest, not the truth of the
  evaluator itself.
- Allowed files are exact paths rather than globs. Large architectural changes
  may require a longer human-reviewed list.
- The candidate must be clean and committed in detached HEAD by the external
  human/Codex operator before review.
- Post-integration verification remains external because Soul performs no
  integration action.

## Memory keys added or used

None. Experiment packets are review artifacts, not durable user context, and no
private skill memory was introduced.

## Task lifecycle states touched

- `complete`: inventories, previews, dossier generation without blockers, and
  model-evidence recording.
- `awaiting_input`: missing/invalid IDs, paths, digests, or evidence fields.
- `failed`: bounded Git, sandbox, or filesystem dependency failures.
- `blocked_for_human_review`: both approved handoffs and every safety blocker.
- `canceled`: explicit clean-worktree cleanup.

Every operation terminates in the foreground. No task silently continues.

## Risk classification

- Read-only Git inspection: Class 1.
- Review packet/model evidence writes: Class 2.
- Detached worktree creation and non-forced clean removal: Class 3 bounded local
  mutation.
- External candidate implementation/integration: Class 4 or Class 5 depending
  on proposal; not executed or authorized by Soul.

## Human review checklist

- [ ] Confirm Gate A1 blocks a dirty primary worktree and stale proposal base.
- [ ] Inspect the detached worktree path and generated Codex handoff.
- [ ] Confirm no Codex invocation, branch, commit, merge, push, or deployment is
      performed by Soul.
- [ ] Confirm changed paths outside the exact allowlist block Gate A2.
- [ ] Confirm Bubblewrap has no network and mounts candidate source read-only.
- [ ] Confirm model evidence authorizes nothing and is required only for detected
      model-facing changes.
- [ ] Confirm Gate A2 produces only an external integration handoff.
- [ ] Confirm dirty cleanup is refused and no `--force` path exists.
- [ ] Visually inspect Experiment and Review at desktop and phone widths.
- [ ] Approve, request changes, or reject before merge/release.
