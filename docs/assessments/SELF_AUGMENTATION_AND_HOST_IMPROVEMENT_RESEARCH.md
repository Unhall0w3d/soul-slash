# Self Augmentation and Host Improvement Research Review

## Candidate

```text
date: 2026-07-16
status: candidate_complete
risk class: Class 0 — read-only research and architecture design
implementation authorized: no
host mutation performed: no
human review required: yes
```

## Repository findings

### Strong foundations

- `SelfImprovementService` already enforces foreground assessment, advisory-only
  proposals, preview digests, exact confirmation, and explicit mutation limits.
- `BoundedCommandRunner` supplies argv execution, timeout, output caps, and
  process-group cleanup.
- the application facade has explicit operation allowlisting, request IDs,
  lifecycle envelopes, activity records, and authenticated dashboard transport.
- Skill Studio demonstrates proposal revision binding, isolated candidate state,
  deterministic tests, two human gates, and production linkage.
- Codex contracts already express allowed/forbidden files, acceptance criteria,
  verifier expectations, rollback, and no-direct-commit policy.
- model runtime controls demonstrate shared locks, active-work checks, exact
  profile targeting, and manual-only persistent operations.

### Gaps requiring design changes

- `PackageManagerAssessor` currently runs `pacman -Qu`, which can reflect the
  installed sync database rather than safely refreshing an isolated current
  update view. `checkupdates` is installed and is the correct Arch inventory
  primitive.
- `safe_update_check_supported` is reported as true for every detected package
  manager without adapter-specific proof.
- assessment command failures collapse into empty lists, making “none found” and
  “check failed” indistinguishable.
- improvement proposals are fixed capability-gap templates. They are not typed
  host transaction plans and have no before/after, interruption, privilege, or
  receipt contract.
- current Codex flows prepare contracts and review response JSON but do not
  create or manage an isolated linked worktree.
- current approval-token storage was not designed as the sole authority for a
  Class 5 host transaction; high-risk operations need stronger atomic,
  revision-bound operation records and receipts.
- there is no architectural distinction in the application API between host
  change plans and repository augmentation proposals.

## External research findings

### Arch package operations

`checkupdates` uses a separate database in a temporary/state location and
reports old/new versions without changing the system sync database. Its exit
code 2 means no updates, not failure. Pacman exposes `--print` for transaction
targets, warns that `--noconfirm` is inappropriate for casual scripting, and
documents dependency, removal, configuration-file, and full-upgrade semantics.
Arch supports full system upgrades and warns against partial-upgrade sequences.

Sources:

- [checkupdates(8)](https://man.archlinux.org/man/checkupdates.8.en)
- [pacman(8)](https://man.archlinux.org/man/pacman.8.en)
- [Arch package management FAQs](https://wiki.archlinux.org/index.php/Package_Management_FAQs)

Design consequence: the first Arch adapter is a full-upgrade plan, not a
general command composer. Package removal and AUR rebuilds are separate adapters.

### Isolated source experiments

Git linked worktrees have separate working-tree state, `HEAD`, and index while
sharing repository history. Git provides explicit list, lock, remove, repair,
and prune operations and recommends `git worktree remove` rather than deleting
the directory manually.

Source:

- [git-worktree documentation](https://git-scm.com/docs/git-worktree.html)

Design consequence: approved augmentation experiments belong in a linked
worktree at an exact base commit, never in Soul's primary working tree.

### Foreground process containment

`systemd-run` can create transient services/scopes. `--wait` propagates the
finished command's result and `--collect` removes failed transient unit state.
Without a wait/pipe/pty option, transient services are asynchronous.

Source:

- [systemd-run(1)](https://man7.org/linux/man-pages/man1/systemd-run.1.html)

Design consequence: a later unprivileged executor may use a waited/collected
transient unit for accounting and containment, but detached/timer execution is
incompatible with Soul's bounded foreground rule.

### Privileged authorization

Polkit uses declared actions and can require administrator authentication. Its
documentation warns that mechanisms must validate arguments, and that retained
authorization is unsafe when decisions depend on varying action details.

Sources:

- [polkit reference](https://polkit.pages.freedesktop.org/polkit/polkit.8.html)
- [pkexec security notes](https://polkit.pages.freedesktop.org/polkit/pkexec.1.html)

Design consequence: polkit could authenticate a future narrow root-owned
mechanism, but cannot make arbitrary dashboard-supplied commands safe. A
privileged broker is deferred behind its own Class 5 brief.

## Architecture recommendation

Adopt the three-authority model in
`docs/soul/SELF_AUGMENTATION_AND_HOST_IMPROVEMENT_ARCHITECTURE.md`:

```text
Self Assessment → evidence and plans
Host Improvement → terminal handoff and verification first
Self Augmentation → tracked-code proposals and isolated experiments
```

Keep Skill Studio separate. Reuse its visible lifecycle language and review
quality, but do not reuse its storage root or production-promotion operation.

## Rejected alternatives

### One universal “self improvement” executor

Rejected because it creates a confused-deputy boundary between package
transactions, model/service changes, skills, and repository architecture.

### Dashboard sudo-password form

Rejected because Soul should not receive or retain administrator credentials,
and authenticated dashboard access is not equivalent to transaction authority.

### Automatically invoking Codex after a model proposal

Rejected because model output is candidate material, not repository mutation
authority, and the proposal may contain an incorrect risk or file scope.

### Editing the primary checkout

Rejected because user changes, dirty state, and an experimental patch would
share one index and rollback boundary.

### Automatic pacman rollback

Rejected because package downgrade and partial-upgrade recovery are contextual
system administration, not safely inferable from a failed transaction.

### Background update or code watchers

Rejected because they violate Soul's foreground lifecycle and create ambient
authority without a current user request.

## Recommended next block

Implement A1–A3:

1. correct update assessment and evidence-status semantics;
2. define host transaction-plan and augmentation-proposal schemas;
3. add review-only host plan and tracked-code census dashboard surfaces;
4. add the Arch terminal handoff and postcondition receipt path;
5. stop before worktree creation or automatic coding-agent invocation.

This is a clean review point before A4–A5 introduce isolated repository
experiments.

## Commands run

```text
repository searches and source inspection with rg/sed
command -v checkupdates
command -v systemd-run
git --version
systemd-run --version
pacman --version
ruby scripts/verify-self-augmentation-host-improvement-design.rb
git diff --check
```

## Memory and lifecycle

```text
durable memory read: none
durable memory write: none
host mutation: none
repository source mutation: documentation and verifier only
network use: public primary-source research only
lifecycle: complete → blocked_for_human_review
```

## Human review checklist

```text
[x] Approve the three-authority separation
[x] Approve Self Assessment and Host Improvement sharing one tab
[x] Approve Self Augmentation as a separate fourth tab
[x] Approve terminal handoff as the first privileged-operation boundary
[x] Approve two augmentation gates plus external integration authority
[x] Approve A1–A3 as the next implementation block
[x] Confirm privileged broker and automatic Codex invocation remain deferred
```

## Human review outcome

```text
Outcome: approved
Reviewer: repository owner
Date: 2026-07-16
Decision summary: Approved the proposed architecture and A1-A3 as the next bounded implementation block.
Required changes: none
```
