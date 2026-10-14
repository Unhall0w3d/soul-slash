# Backup retention capacity and failure-evidence repair

Current user authorized the scoped repair and evidence-only reconciliation on
October 14, 2026. This is not authorization for new captures, snapshot deletion,
source-scope changes, credential changes, schedules or general deployment.
Detailed host execution evidence remains private, separate from this source review.

## Change and invariants

- Retention holds now use the existing one-million-path inventory ceiling.
  The independent 512 MiB serialized-ledger bound is unchanged. This supports
  deletion of a large valid inventory without discarding protection history.
- Reappearance membership uses a lookup table rather than a repeated linear
  search, avoiding quadratic work when many held paths reappear.
- Failures after capture begins expose a known snapshot or an indeterminate
  mutation, failing stage, repository-verification state and reconciliation
  requirement. A failed receipt write cannot erase those facts from the result.
- Parent DRS component records retain the selected evidence fields. A nonzero
  Restic exit with a valid summary is still a failure, with its snapshot retained.
- Exact confirmation/digest binding, locks, source-root checks, byte bounds,
  30-day clocks and protective lineage remain. No deletion or automatic retry
  was added; retirement of a project does not waive its existing deletion holds.

## Deterministic evidence

Passed with the pinned Ruby runtime:

- `scripts/verify-backup-inventory-capacity.rb`: 170,000-path inventory and
  complete deletion, persisted holds, 30-day clocks/lineage, replay, count
  overflow refusal, 5,000-path reappearance, both inventory readers.
- `scripts/verify-operator-drs-stream-reconciliation-a0.rb`: 30 checks,
  including verification, invalid manifest, ledger rejection, receipt-storage,
  unknown capture and partial capture failures; parent evidence and credentials.
- Existing retention, administration, Operator backup, nightly transaction,
  nightly automation, Crucible replication, storage census and manifest
  reconciliation verifiers all passed.
- Source syntax and Git whitespace checks passed.

These are fixtures, not proof of a new backup/replication or restored machine.
The existing bounded reconciliation workflow is responsible for live metadata
checks and chronological recording of exact existing snapshot IDs. Its
completion must be evidenced separately; no successful nightly run is invented.

## Review outcome

Primary review checked capture/verify/manifest/ledger/receipt ordering, callers,
and unchanged deletion gates. The change retains existing data rather than
waiving protection to make capacity available. No shared-memory keys, model
evaluation, new service or background worker is involved.

Known bound: a sufficiently large accumulated history or very long paths can
still hit the count/byte ceiling. Such a failure remains explicit and requires
reconciliation; this repair does not introduce an unbounded ledger.
