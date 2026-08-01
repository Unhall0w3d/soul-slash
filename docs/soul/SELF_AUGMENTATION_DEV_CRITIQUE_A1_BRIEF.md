# Self Augmentation Dev Critique A1 Brief

Status: implementation authorized by the human-approved Dev Core GPT-OSS integration sequence

## Objective

Add one explicit, bounded Dev Core critique action for an existing immutable
Self Augmentation proposal. The action helps the Operator revise a proposal
before Gate A1 without delegating the Gate A1 decision or any implementation
authority to the model.

## Approved vertical slice

1. The Operator selects one existing `soul.self_augmentation.proposal.v1`
   packet from the proposal queue.
2. Preview re-reads the exact packet and binds its complete projected JSON to a
   SHA-256 and one Dev Worker request digest.
3. Execute requires the unchanged proposal, reviewed digest, and existing exact
   Dev Worker confirmation phrase.
4. GPT-OSS receives only the proposal packet, eligible scalar references, and a
   closed critique schema. It receives no repository excerpts, shell, network,
   Git, worktree, approval, memory, or host authority.
5. A valid result is written once below that proposal's owner-local
   `dev_critiques/` directory and displayed beside the proposal lifecycle.

## Allowed output

- one concise summary;
- up to eight strengths, each citing one exact proposal scalar;
- up to twelve concerns across a fixed review-dimension allowlist, each citing
  one exact proposal scalar;
- up to twelve explicit unknowns;
- up to eight questions the human author may answer in a later proposal
  revision.

The fixed concern dimensions are scope, compatibility, migration, rollback,
verification, privacy, and authority boundary.

## Prohibited behavior

The model and critique action must not:

- classify safety or risk;
- approve or reject Gate A1;
- select allowed files;
- produce code, a patch, commands, or implementation steps;
- create an experiment, worktree, branch, commit, dossier, or handoff;
- change the proposal, repository, host, shared memory, or Knowledge Vault;
- invoke any follow-on action.

## Storage and lifecycle

Critiques are immutable owner-local review evidence stored beneath
`Soul/augmentation/proposals/<proposal-id>/dev_critiques/<critique-id>/`.
They are covered by the existing augmentation backup source and ignored by Git.
No routine proposal content is copied to a new memory system.

Every invocation terminates as `complete`, `failed`, `awaiting_input`,
`canceled`, or `blocked_for_human_review`. It uses the existing five-minute Dev
Worker ceiling and adds no polling, watcher, daemon, scheduler, listener, or
background continuation.

## Acceptance criteria

- Missing or changed proposals block before model invocation.
- Invalid schema or citations write no critique packet.
- A valid result creates one owner-private immutable packet and exposes exact
  cited values beside model prose.
- Gate A1, worktree creation, dossier generation, Gate A2, cleanup, and model
  qualification remain behaviorally unchanged.
- The Dashboard pre-fills click authority for one critique and visibly reports
  foreground progress without polling.
