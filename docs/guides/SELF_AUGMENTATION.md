# Self Augmentation

Self Augmentation is the architecture-change lane. It lets Soul inspect its tracked construction and prepare a tightly bounded experiment when a limitation cannot honestly be solved by adding one skill.

Open it from **Self Improvement → Self Augmentation**.

## When to use it

Use Self Augmentation for changes to shared orchestration, contracts, memory infrastructure, provider behavior, capability discovery, or another cross-cutting part of Soul itself.

Do not use it when:

- a bounded skill can perform the task;
- the problem is a host package or configuration change;
- the request is simply to inspect the environment;
- the desired result is a music or visual artifact.

## Intended flow

```text
Observe tracked code
→ propose a core change
→ Gate A1: authorize one isolated experiment
→ external implementation in an exact worktree/file scope
→ deterministic dossier and optional model qualification
→ Gate A2: approve one exact candidate for integration review
→ external merge/release decision
→ bounded clean-worktree removal
```

## 1. Observe

**Survey tracked code** reads bounded Git-tracked regular files. It excludes credentials, private memory, runtime state, model weights, generated packets, and untracked files. The census changes nothing.

## 2. Propose

Describe the architectural objective and explain why it cannot be a bounded skill. The preview binds the proposal fields before **Create review packet** writes a candidate proposal.

This is intentionally a human-authored gate. Soul may help analyze the architecture, but the objective and the reason for crossing the skill boundary must remain reviewable.

## 3. Gate A1: isolated experiment

Select a proposal and list the exact files the experiment may change. Gate A1 may create one detached worktree plus an implementation handoff. It does not invoke Codex, create a production branch, merge, push, deploy, or modify the main worktree.

Implementation happens externally against that allowed-file boundary.

## 4. Candidate dossier

After an implementation is committed in the experiment worktree, **Generate dossier** records the base and candidate commits, changed files, deterministic verification, and blockers. Passing checks make the candidate reviewable; they do not approve it.

Where model behavior is relevant, an external bounded local-model run can be recorded with its suite ID, model profile, result, and evidence digest.

## 5. Gate A2: integration review

Gate A2 revalidates the exact committed candidate and dossier. Approval creates an external integration handoff only. Branch creation, merge, push, deployment, and release remain explicit development decisions outside Soul.

## Cleanup

A separate cleanup gate may remove only a clean experiment worktree. Soul refuses to force-remove a dirty worktree, preserving unreviewed work rather than hiding it.

## Relationship to other surfaces

- [Self Assessment](SELF_ASSESSMENT.md) asks, “What is true about the environment now?”
- [Skill Studio](SKILL_STUDIO.md) asks, “Can one bounded capability solve this?”
- Self Augmentation asks, “Does Soul's shared architecture itself need to change?”

## Related engineering references

- [`docs/soul/SELF_AUGMENTATION_AND_HOST_IMPROVEMENT_ARCHITECTURE.md`](../soul/SELF_AUGMENTATION_AND_HOST_IMPROVEMENT_ARCHITECTURE.md)
- [`docs/assessments/SELF_AUGMENTATION_HOST_IMPROVEMENT_A1_A3_REVIEW.md`](../assessments/SELF_AUGMENTATION_HOST_IMPROVEMENT_A1_A3_REVIEW.md)
- [`docs/assessments/SELF_AUGMENTATION_A4_A5_REVIEW.md`](../assessments/SELF_AUGMENTATION_A4_A5_REVIEW.md)
