# Dev Review Bounded Jobs A3 Brief

Status: implementation authorized by the approved Dev Core GPT-OSS integration brief

## Objective

Move the three long-running, review-only GPT-OSS Dashboard actions onto the
existing persisted bounded-job channel so navigation, refresh, disconnect, and
Dashboard restart behavior match Skill Studio Dev builds and creative work.

## Approved operations

- `self_improvement.dev_synthesis.execute`
- `self_augmentation.dev_critique.execute`
- `self_augmentation.dev_handoff.execute`

Preview operations remain ordinary read-only application calls. Only an exact
confirmed execute request may enter the bounded-job channel.

## Required behavior

1. Add a neutral authenticated endpoint for supported bounded jobs while
   retaining the existing music endpoint as a compatibility alias.
2. Persist operation-specific subject identity, progress, terminal lifecycle,
   and the exact application envelope using owner-private files.
3. Allow one active bounded creative or development job at a time, preserving
   the current AMD generation lease boundary.
4. On Dashboard restart, mark an accepted/running job failed; never resume it
   silently or leave a model lease intentionally alive.
5. Pass bounded progress callbacks through each Dev review service into the
   existing scoped Dev runtime coordinator.
6. Update the Dashboard to reconnect to the persisted stream and render one
   terminal result without polling.

## Prohibited behavior

- no new service, listener, scheduler, watcher, or background process;
- no automatic retry or model-generated follow-on action;
- no weakening of preview digests, click authority, Core or lease checks;
- no change to Self Assessment evidence or either Self Augmentation gate;
- no Git, worktree, host, memory, Vault, or production-skill mutation.

## Acceptance criteria

- Each approved operation validates its exact subject before accepting a job.
- Duplicate active requests return the same job; a distinct concurrent request
  fails safely.
- Refresh/reconnect receives current progress or the retained terminal result.
- Restart recovery records failure and does not execute the request again.
- Scoped Soul Core and Soul-Lite execution restores the prior Core intent;
  selected Dev Core retains GPT-OSS residency.
- Existing music, creative chat, and Skill Studio Dev build continuity tests
  remain unchanged and pass.
