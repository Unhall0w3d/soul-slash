# Operator DRS Stream Reconciliation A0 Brief

Status: human-approved repair scope on 2026-08-29; candidate review required

## Objective

Repair the Operator nightly DRS evidence path after Restic successfully created
local snapshots whose newline-delimited JSON output exceeded the bounded command
capture. Reconcile the resulting unrecorded local snapshot evidence and resume
the existing exact Crucible lineage copy without deleting or replacing backup
data.

## Approved implementation

- Add an explicit bounded complete-line tail capture mode to the existing
  foreground command runner. The default prefix mode remains unchanged.
- Use complete-line tail capture only for Restic backup JSON. Earlier progress
  records may be discarded; the terminal summary must remain a complete JSON
  record within the existing two MiB memory bound.
- If a successful Restic process still lacks one valid terminal snapshot ID,
  classify the result as indeterminate and require repository reconciliation.
  Never report that no mutation occurred merely because receipt parsing failed.
- Add one bounded, explicit, digest-bound reconciliation operation for existing
  snapshots that belong to the selected profile but have no finalized local
  manifest. It may verify repository metadata, reconstruct exact manifests,
  advance the existing deletion-aware ledger in chronological order, and write
  one owner-private audit receipt.
- Reconciliation may add evidence only. It cannot create a snapshot, change the
  source or exclusion manifests, forget or prune snapshots, delete local or
  remote data, restore files, or alter credentials.
- A later ordinary DRS run may copy all missing verified local lineage to
  Crucible through the existing replica transaction. No new copy mechanism is
  introduced.
- Surface degraded automation status when the most recent successful run is
  older than 36 hours while keeping timer readiness and run health distinct.

## Bounds and failure behavior

- At most 100 profile snapshots may be inspected and reconciled.
- Every candidate snapshot must have a valid full ID, exact profile tag, valid
  configured source roots, and no existing manifest path or symlink conflict.
- Preview binds repository identity, ordered missing snapshot IDs, current
  source and exclusion digests, and current ledger digest.
- Wrong confirmation, stale digest, repository drift, source drift, an active
  backup lock, invalid snapshot inventory, or any unsafe path blocks mutation.
- One invocation terminates as `complete`, `failed`, `awaiting_input`, or
  `blocked_for_human_review`. There is no retry, polling loop, deletion, or
  detached continuation.
- If reconciliation fails after recording a bounded prefix, the receipt must
  identify the recorded IDs and remaining IDs. Existing valid evidence is not
  rolled back or deleted.

## Credential and deployment boundary

- Repository passwords remain inside the existing Dashboard request or
  systemd credential boundary and bounded Restic child environments.
- The repair adds no credential file, service, timer, listener, scheduler, or
  resident process.
- Live reconciliation may use one transient foreground invocation carrying the
  already enrolled host-encrypted Operator credential. It must terminate and
  leave no installed unit.
- Existing permanent Operator and Soul timers remain unchanged.

## Deterministic acceptance

- A stream larger than two MiB retains complete terminal JSON records without
  retaining a partial line; default command capture remains unchanged.
- Backup execution accepts a complete retained Restic summary even when earlier
  progress records were discarded.
- A successful process without a trustworthy summary reports an indeterminate
  snapshot mutation requiring reconciliation.
- Reconciliation preview is read-only and deterministic.
- Exact execution records missing manifests and ledger observations in
  chronological order; replay is idempotent.
- Confirmation, digest, path, lock, and inventory failures mutate nothing.
- No password, source content, command output, or private path inventory enters
  tracked review artifacts.
- Existing Backup Administration, Operator Backup, Nightly DRS transaction,
  automation, retention, and Crucible replication verifiers remain passing.

## Human review boundary

Passing tests makes the repair candidate-complete only. The Operator reviews
the code and receipt semantics before merge. Live reconciliation and one
supervised Operator DRS recovery run remain separately evidenced operational
steps under this approved repair scope.
