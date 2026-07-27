# Backup Administration A2 Brief

Status: approved implementation scope; candidate review required

## Objective

Turn the approved encrypted backup foundation and deletion-hold ledger into one
bounded Administration workflow available through the authenticated Dashboard.

## Approved surfaces

The Backup & Recovery surface may:

- inspect the configured repository, mount, source manifests, ledger, receipts,
  and snapshots;
- accept the restic password for one request without retaining it;
- preview and execute one foreground snapshot;
- verify that snapshot, derive its exact path inventory, write its private
  manifest, and update the deletion-hold ledger as one transaction;
- preview and execute deletion of explicitly selected, hold-clear snapshots;
- run bounded prune as part of that exact retention transaction and verify the
  repository afterward;
- preview and restore one exact snapshot, optionally narrowed to explicit
  paths, into a new owner-private staging directory;
- report staged restore evidence without overwriting the live tree.

## Authority and credential boundary

- Every mutating operation uses a fresh preview digest and exact confirmation.
- Dashboard buttons may prefill the exact confirmation phrase; clicking the
  final button is the human authorization event.
- The repository password exists only in the current browser field, HTTPS or
  loopback request body, Ruby string, and environment of the bounded restic
  child process.
- The password is never written to `.env`, browser storage, logs, receipts,
  manifests, activity records, or model context.
- Wrong-password output is reduced to a generic authentication failure.
- No LLM selects sources, snapshots, restore paths, retention candidates, or
  authority values.

## Bounded execution

- one operation per request;
- backup timeout: 60 minutes;
- metadata verification timeout: 20 minutes;
- retention/prune timeout: 60 minutes;
- staged restore timeout: 60 minutes;
- at most 100 snapshots, 50 retention selections, 20 restore includes, and
  100,000 inventoried paths;
- no automatic retry;
- no scheduler, timer, watcher, daemon, or unattended execution;
- progress is request-bound and reaches one terminal lifecycle state.

## Retention

The Operator selects exact full snapshot IDs. The newest snapshot, an actively
held snapshot, an unknown snapshot, or a selection that would leave fewer than
two snapshots is blocked. Execution revalidates the repository and ledger,
runs the exact forget/prune transaction with bounded repacking, and then runs
repository metadata verification.

`hold-clear` remains necessary but not sufficient: the human must still select,
preview, and approve each snapshot.

## Restore

Restore always targets a newly created directory under
`Soul/private/backup/restores/`. It uses `--verify`, inventories the staged
result, records evidence, and stops at `blocked_for_human_review`. No Dashboard
operation replaces live files, deletes live files, restores sessions or
approval tokens, or restarts Soul.

## Navigation

Add a primary **Administration** menu using the existing top-bar visual
language. Its first surface is **Backup & Recovery**. Future administrative
surfaces may be added only through separately approved briefs.
