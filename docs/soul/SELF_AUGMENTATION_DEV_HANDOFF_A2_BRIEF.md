# Self Augmentation Dev Handoff A2 Brief

Status: implementation authorized by the human-approved Dev Core GPT-OSS integration sequence

## Objective

Add one explicit, bounded Dev Core action after Self Augmentation Gate A1. The
action turns the exact approved proposal, experiment record, allowed-file scope,
and deterministic `CODEX_HANDOFF.md` into an advisory implementation handoff
for human/Codex review. It does not implement the experiment.

## Approved vertical slice

1. The Operator selects one existing `soul.self_augmentation.experiment.v1`
   record that was created by Gate A1.
2. Preview re-reads the exact experiment, source proposal, and original handoff;
   binds their canonical projection and SHA-256 digests; and prepares one Dev
   Worker request.
3. Execute requires the unchanged evidence, reviewed request digest, and the
   existing exact Dev Worker confirmation phrase.
4. GPT-OSS receives only the bounded evidence packet and a closed advisory
   schema. It receives no repository excerpts, worktree contents, shell,
   network, Git, credentials, memory, Vault context, or approval authority.
5. A valid result is written once below the experiment's owner-local
   `dev_handoffs/` directory and displayed beside the experiment lifecycle.

## Allowed output

- one concise implementation summary;
- up to eight ordered implementation objectives;
- guidance for only the exact Gate A1 allowed files, with bounded
  responsibilities and verification expectations;
- up to ten compatibility checks;
- up to eight rollback considerations; and
- up to ten explicit unknowns for the implementer or Operator.

The handoff may describe sequencing, responsibilities, compatibility concerns,
and verification goals. It must not contain source code, patches, command
lines, or instructions to expand the approved file scope.

## Prohibited behavior

The model and handoff action must not:

- modify `CODEX_HANDOFF.md`, the experiment record, proposal, or allowed files;
- inspect or write the detached worktree;
- produce source code, a patch, shell commands, Git commands, or executable
  snippets;
- create a branch, commit, dossier, Gate A2 record, or integration handoff;
- classify safety, approve either gate, invoke Codex, or start implementation;
- change the repository, host, shared memory, or Knowledge Vault; or
- invoke any follow-on action.

## Storage and lifecycle

Handoffs are immutable owner-local review evidence stored beneath
`Soul/augmentation/experiments/<experiment-id>/dev_handoffs/<handoff-id>/`.
They are covered by the existing augmentation backup source and ignored by Git.
No routine content is copied to a new memory system.

Every invocation terminates as `complete`, `failed`, `awaiting_input`,
`canceled`, or `blocked_for_human_review`. It uses the existing five-minute Dev
Worker ceiling and adds no polling, watcher, daemon, scheduler, listener, or
background continuation.

## Acceptance criteria

- Missing, changed, or unsafe experiment evidence blocks before model
  invocation.
- The generated handoff names only exact Gate A1 allowed files.
- Invalid schemas, paths, code fences, or command-like content write no packet.
- A valid result creates one owner-private immutable packet and exposes the
  exact source digests and allowed-file scope.
- The original handoff, worktree, experiment record, proposal, Gate A1, dossier,
  Gate A2, cleanup, and model qualification behavior remain unchanged.
- The Dashboard pre-fills click authority and visibly reports foreground
  progress without polling.
