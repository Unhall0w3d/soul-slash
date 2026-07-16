# Self Augmentation and Host Improvement A1–A3 Brief

Status: human-authorized implementation brief
Authorization date: 2026-07-16

## Outcome

Implement three bounded foreground slices:

1. **A1 — trustworthy assessment:** typed assessment results distinguish complete,
   no-update, unavailable, and failed checks. Arch update discovery uses
   `checkupdates`, not the potentially stale local database exposed by
   `pacman -Qu`.
2. **A2 — terminal handoff:** Self Assessment may prepare an exact Arch full
   upgrade plan and a terminal handoff packet. Soul never executes the upgrade.
   A later foreground verification may compare the plan with current package
   state and bounded pacman-log evidence.
3. **A3 — self-augmentation observation:** a separate dashboard tab may inspect
   bounded, Git-tracked project code and prepare a proposal packet for human
   review. It does not edit project code.

## Authorized effects

- Run bounded read-only inventory and assessment commands.
- Read bounded Git-tracked regular files under the repository root.
- Write generated review packets only beneath:
  - `Soul/host_improvement/plans/`
  - `Soul/augmentation/proposals/`
- Expose the new operations through the local authenticated dashboard API.
- Add the fourth **Self Augmentation** dashboard tab.

## Explicitly prohibited in this slice

- Running `sudo`, `pacman -Syu`, package removal, or any host mutation.
- Starting, stopping, enabling, or installing services.
- Creating a worktree or branch.
- Invoking Codex or another implementation agent.
- Applying generated text or patches to tracked project files.
- Merging, committing, releasing, or promoting an augmentation automatically.
- Watchers, polling, schedulers, daemons, or background continuation.
- Reading `.env`, credentials, private memory, runtime state, untracked files,
  model data, or generated proposal/plan roots during the code census.

## Gates and lifecycle

- Assessment and census operations are read-only and terminate `complete` or
  `failed`.
- A host handoff requires a current preview digest and exact confirmation
  `CREATE_ARCH_FULL_UPGRADE_HANDOFF`; it terminates
  `blocked_for_human_review` because the terminal action remains external.
- An augmentation proposal requires a current census-bound preview digest and
  exact confirmation `CREATE_SELF_AUGMENTATION_PROPOSAL`; packet creation
  terminates `blocked_for_human_review`.
- Stale evidence, wrong confirmation, invalid paths, symlinks, or exceeded
  limits terminate without a write.

## Bounds

- Command timeout: 30 seconds or less per operation.
- Census: at most 5,000 tracked paths, 256 KiB per text file, and 4 MiB total
  text content.
- Generated inventories: at most 100 packets per surface.
- No user-supplied filesystem paths or shell fragments are accepted.

## Acceptance contract

- Deterministic tests prove the status distinction and that no mutation command
  is executed.
- Preview is write-free; execute re-derives and compares the digest.
- Generated paths are direct children of their approved roots and reject
  symbolic links.
- Dashboard interactions are explicit and foreground-only; there are no timers
  or polling loops.
- A human review artifact records commands, results, weaknesses, lifecycle,
  memory use, and risk.
