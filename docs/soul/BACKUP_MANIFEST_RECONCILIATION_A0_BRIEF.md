# Backup Manifest Reconciliation A0 Brief

Status: human-approved for implementation on 2026-07-29

## Outcome

Allow an existing Soul installation to reconcile its owner-managed Restic
source and exclusion manifests with the current portable backup policy through
one bounded, add-only, human-reviewed Dashboard gate.

The operation must preserve every existing source, exclusion, comment, and
blank line. It may add only currently missing entries from the tracked portable
policy. It must never start Restic, request a repository password, remove or
replace an owner entry, or claim backup coverage until a later verified
snapshot inventories the durable additions.

## Included

- One shared portable manifest policy used by initial Makefile setup and
  existing-install reconciliation.
- A metadata-only preview listing exact source and exclusion additions.
- SHA-256 binding to both existing owner manifests and the complete proposed
  add-only scope.
- Exact click authorization through Backup & Recovery.
- Atomic owner-only manifest writes with post-write verification.
- One private receipt containing hashes and generic counts, never credentials
  or file contents.
- Read-only status showing whether reconciliation is current.
- Deterministic service, application, Dashboard, documentation, and regression
  coverage.

## Fixed safety boundaries

- Existing manifests must be regular owner-local files inside
  `Soul/private/backup`; symlinks and oversized/invalid manifests fail closed.
- New sources must exist, be readable, normalized absolute paths, and not be
  symlinks.
- Only entries produced by the tracked portable policy may be appended.
- No existing non-comment entry may disappear or change.
- No generic home-directory or project-root source may be introduced.
- No exclusion may broaden beyond the tracked exact path/glob set.
- Preview drift, changed manifest bytes, changed policy, wrong confirmation,
  or another active backup-administration operation blocks execution.
- The operation has no retry, scheduler, timer, watcher, daemon, or background
  continuation.
- Restic capture, verification, replication, retention, and restore remain
  separate existing gates.

## Lifecycle

- `complete`: preview produced, reconciliation applied and verified, or no
  additions remain.
- `awaiting_input`: manifests are missing/invalid or exact confirmation is
  absent.
- `blocked_for_human_review`: preview digest is stale, scope changed, unsafe
  state is detected, or another backup operation is active.
- `failed`: an atomic write or post-write verification fails safely.

No operation remains active after returning.

## Deterministic acceptance

- Initial setup and reconciliation derive from one portable policy.
- A fixture with older manifests previews only the expected missing entries.
- Wrong confirmation, stale digest, source drift, symlink state, and concurrent
  administration change no manifest.
- Exact execution preserves all prior bytes logically, appends only policy
  entries, applies owner-only modes, and records a private receipt.
- A second preview reports no remaining additions.
- No Restic command or password path is touched.
- Dashboard clearly requires reconciliation before a fresh backup and does not
  imply that manifest inclusion equals snapshot verification.
- Existing Backup Administration and Storage & Retention regressions pass.

## Human review boundary

Passing tests makes this candidate-complete only. The Operator separately
approves merge, performs the live manifest reconciliation, unlocks Restic,
creates a fresh verified snapshot, and confirms the census reaches expected
coverage.
