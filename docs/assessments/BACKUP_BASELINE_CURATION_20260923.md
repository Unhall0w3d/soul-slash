# Backup source baseline curation — 2026-09-23

Status: source candidate complete for human merge review. This curation did not
access a repository credential, run Restic against a live repository, change a
manifest, start a backup, or delete a snapshot.

## Source scope

- Explicit project source roots were added to the portable manifest policy;
  the entire project or home directory is not selected implicitly.
- Read-only Restic calls use `--no-lock` for recovery from a read-only carrier.
  Mutating backup calls retain normal repository locking.
- The approved inventory ceilings are one million paths, 256 MiB of projected
  path output and 512 MiB of persisted ledger or manifest JSON. Parsing can use
  more memory; bounds and overflow refusal remain in place.
- The bounded command runner reaps its owned child on cancellation and caps
  decoded UTF-8 output by bytes.
- No `forget` or `prune` execution path was added.

## Verification

Ruby 4.0.7 with Prism: backup administration, manifest reconciliation,
retention ledger, large inventory capacity, bounded command runner and
cancellation, Crucible replication, nightly DRS transaction, and Operator DRS
stream reconciliation verifiers all passed in the isolated source worktree.
`git diff --check` passed after curation.

The original host-specific recovery receipts and snapshot identifiers remain
in the owner worktree for private review. This public packet does not reproduce
them or claim that today's live repository was freshly requalified.

## Human review

Review the source-root additions and capacity ceilings against the approved
backup policy. Verify a current snapshot and replica when qualifying the next
live deployment. Source checks alone do not authorize merge, release, retention
execution, or restore promotion.
