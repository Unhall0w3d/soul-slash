# Operator Codex recovery coverage

## Scope and authority

The current operator authorized routine coverage of missing sessions/state and
dependency lockfiles, then fresh backup and replication. The approved extension
is in [Operator Backup A0](../soul/OPERATOR_BACKUP_A0_BRIEF.md). No model work,
new timer, credential enrollment, pruning, restore promotion or disk operation
is introduced. Detailed live receipts remain private, not in public Git.

## Implementation and impact

- Add the stable `.codex` parent and actual case-sensitive `.config/Codex`.
  Preserve old child roots, so the retention ledger still sees a root superset.
  Versioned DBs, WAL/SHM companions, sessions, attachments, automation definitions,
  plugins, local worktrees and registry state are directory contents. External
  linked targets still need their own source coverage.
- Exclude Codex package/cache/IPC payloads and known runtime locks. Replace
  global `*.lock` with Git runtime-lock exclusion; preserve dependency locks.
- Explicitly report `live_file_copy_not_atomic`. This does not implement SQLite
  snapshotting, cross-database consistency or browser profile quiescence.
  The migration still needs a separate capture with Codex writers closed.
- Existing generic manifest reconciliation remains **add-only**. Deployment
  must explicitly remove the two obsolete exclusion lines, retaining originals,
  exact digest binding and the shared operation lock. Merely adding source roots
  while retaining the session exclusion would leave the central defect unfixed.

Consumers are configuration generation, status policy projection and manifest
reconciliation. Capture, credentials, snapshot verification, retention and
replication interfaces are unchanged. Primary review checked these callers and
the ledger's configured-root inventory contract. Native Restic confirms nested
legacy roots remain represented when their parent is also selected.

## Deterministic evidence

- `verify-operator-backup-a0.rb`: policy, configuration, shared lock, facade,
  distinct credentials/profile, schedule and runner checks pass.
- `verify-operator-codex-coverage.rb`: actual temporary Restic capture selects
  21 required synthetic files, excludes 14 transient paths, preserves overlapping
  legacy roots and passes repository metadata check. No live credentials/data.
- Existing manifest-reconciliation, nightly-transaction, nightly-automation and
  Crucible-replication checks pass, including stale digest, wrong confirmation,
  concurrent-lock, partial-failure and no-deletion behavior.
- `verify-operator-drs-stream-reconciliation-a0.rb`: all 30 reconciliation and
  post-capture failure-evidence checks pass. Git whitespace checks pass.

These checks prove selection and unchanged operational contracts, not successful
live replication or restoration of a running desktop profile. Fresh live receipt
acceptance and the separate cold migration capture remain distinct.

## Rollback and limits

Retain owner-only manifest originals before applying the exact reviewed change.
Restore those originals under the same shared lock only if rollback is required;
never remove snapshots created during qualification. No memory keys, model
configuration or persistent service is changed. Recent accepted restore tests
are reused at the operator's request; no new full restore rehearsal is claimed.
