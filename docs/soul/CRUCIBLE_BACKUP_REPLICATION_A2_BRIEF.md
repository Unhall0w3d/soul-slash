# Crucible Backup Replication A2 Brief

Status: Operator-approved implementation; human review required before merge

## Objective

Add one bounded manual gate that initializes Crucible's already-qualified
restic target when absent, copies the workstation repository's missing
`soul-state` snapshots, verifies the target, and proves exact snapshot coverage.

## Approved behavior

- Use the configured fixed SFTP repository, SSH alias, absolute path, and owner.
- Require the repository password for one page request and never retain it.
- Verify Crucible's target is a mode `0700` directory owned by the configured
  non-root account.
- Bind preview to the local repository identity and exact source, target, and
  missing snapshot IDs.
- Initialize only an uninitialized target.
- Verify source metadata, run one `restic copy`, verify target metadata, and
  perform one post-copy inventory.
- Share the local backup mutation lock and write one owner-private receipt.

## Excluded

No remote snapshot deletion, forget, prune, retention reconciliation,
scheduler, timer, stored credential, automatic retry, detached work, restore,
or live-tree mutation is authorized. Nightly operation follows only after this
manual path is live-accepted and a separate credential/persistence review.

## Lifecycle

Every call terminates as `complete`, `awaiting_input`,
`blocked_for_human_review`, or `failed`. A timed-out or partial operation may
leave a valid initialized repository or partial copied packs; the next explicit
preview re-inventories both repositories and restic resumes safely.

## Risk

Class 4 encrypted off-device storage mutation. The operation may initialize the
exact prepared Crucible directory and add encrypted repository data. It cannot
delete local or remote backup data.

## Review checklist

- [x] Exact fixed target identity is checked.
- [x] Preview is digest-bound to exact snapshot inventories.
- [x] Password is child-environment-only and never persisted.
- [x] Shared lock prevents overlapping backup administration.
- [x] Post-copy check and coverage proof are required.
- [x] Deletion, scheduling, and automatic retry are absent.
- [ ] Operator live-tests initialization and first copy from the Dashboard.
