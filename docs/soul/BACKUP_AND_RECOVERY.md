# Backup and Recovery

Soul exposes encrypted local recovery under **Administration → Backup &
Recovery**. Every operation is bounded, foreground, manually initiated, and
ends in a visible lifecycle state. Soul installs no backup timer, scheduler,
watcher, daemon, automatic retry, or unattended restore.

## What the dashboard does

The page has four exact-gated operations:

1. **Create a backup** validates the recovery mount and allow-listed sources,
   refuses active creative/model work, captures one tagged restic snapshot,
   runs metadata verification, derives its exact path inventory, updates the
   deletion-hold ledger, and records an owner-private receipt.
2. **Forget selected snapshots** accepts only exact full snapshot IDs. It
   rejects the newest snapshot, unknown snapshots, active deletion holds, and
   any selection that would leave fewer than two snapshots. Preview runs
   restic's dry-run; execution performs one bounded forget/prune and verifies
   repository metadata again.
3. **Stage a restore** restores one full snapshot or up to 20 exact absolute
   paths into a new owner-private staging directory with restic verification.
   It inventories and hashes the result, then stops as
   `blocked_for_human_review`. It never overwrites live state.
4. **Copy to Crucible** verifies the fixed SSH/SFTP target, initializes its
   encrypted repository when absent, copies missing `soul-state` snapshots,
   verifies target metadata, and proves exact source-snapshot coverage through
   restic's preserved original-snapshot lineage. Destination storage IDs differ
   because the repositories are independently encrypted.

The repository password is entered per dashboard page session. It is sent only
in the environment of the bounded restic child process. Soul does not place it
in `.env`, browser storage, command arguments, receipts, logs, Git, model
context, or the repository itself. **Forget password** clears it from the page.

## Portable configuration

Install `restic`, prepare and mount separate storage, and initialize an
encrypted repository yourself. Configure only non-secret locations in `.env`:

```dotenv
SOUL_BACKUP_MOUNT=/mnt/soul-backup
SOUL_BACKUP_REPOSITORY=/mnt/soul-backup/restic
SOUL_BACKUP_MAX_REPACK_SIZE=4G
SOUL_BACKUP_REPLICA_REPOSITORY=sftp:crucible-maintenance:/srv/soul-backup/restic
SOUL_BACKUP_REPLICA_SSH_ALIAS=crucible-maintenance
SOUL_BACKUP_REPLICA_TARGET_PATH=/srv/soul-backup/restic
SOUL_BACKUP_REPLICA_OWNER=souladmin
SOUL_BACKUP_REPLICA_SSH_CONFIG=~/.ssh/config
```

`SOUL_BACKUP_MAX_REPACK_SIZE` accepts a bounded value such as `512M`, `1G`, or
`4G`. The configured mount must be the exact filesystem containing the
repository and must be writable. This prevents an absent recovery disk from
silently redirecting a backup onto the primary filesystem.

When the persistent dashboard is installed or refreshed through
`dashboard-service-install`, its `ProtectSystem=strict` sandbox grants write
access only to the project and this configured recovery mount. Re-run that
exact-gated installer after changing `SOUL_BACKUP_MOUNT`.

Generate portable owner manifests only after Soul has been initialized:

```sh
make backup-config-plan
make backup-configure \
  EXPECTED_DIGEST=DIGEST_FROM_PLAN \
  CONFIRM=CONFIGURE_SOUL_BACKUP_MANIFESTS
```

The plan includes only existing readable default continuity paths. Review every
line. The execute command will create missing owner-only manifests, but will
not replace manifests whose scope differs. Machine-specific additions belong
in:

```text
Soul/private/backup/sources.txt
Soul/private/backup/excludes.txt
```

The source file is an allow-list, not a whole-home backup. The default
exclusions omit session state, approval tokens, temporary files, and staged
restores. Models, caches, helper environments, and other reproducible large
material are not included by default.

## Dashboard flow

1. Confirm no Music/Visual generation or model transition is active.
2. Open **Administration → Backup & Recovery**.
3. Inspect the mount, repository, manifest, ledger, and evidence state.
4. Enter the restic password and select **Unlock & refresh**.
5. Use one preview button and inspect its exact scope.
6. Click the corresponding gold/destructive gate. The click supplies the
   displayed confirmation; there is no redundant phrase field.
7. Keep the page open while its request-bound progress stream runs. The
   operation does not detach into a background process.

If the target is read-only, on the wrong filesystem, missing, or if configured
sources are unavailable, backup creation fails before restic capture.

## Deletion-aware retention

Deleted source files remain recoverable for **30 full days after Soul first
detects their deletion in a newly captured and verified snapshot**. This is
intentionally different from `restic forget --keep-within 30d`: a long gap
between captures could otherwise remove the immediately preceding snapshot
that still contains a recently deleted file.

For every verified snapshot, Soul records:

- repository identity;
- unchanged source roots;
- the sorted path inventory;
- snapshot ID and verification time;
- holds created for paths present in the preceding snapshot but absent now.

Each hold protects the preceding snapshot until 30 full days after detection.
Later captures do not reset the clock. A verified reappearance resolves the
hold. Retention fails closed when the ledger is absent/corrupt, repository or
source identity changes, verification fails, or a selected snapshot is
protected. A hold expiring permits review; it does not itself delete anything.

The ledger, manifests, and receipts are owner-private:

```text
Soul/private/backup/retention-ledger.json
Soul/private/backup/manifests/
Soul/private/backup/receipts/
```

The lower-level A1 ledger tool remains available for audit and compatibility;
routine use should go through the integrated dashboard so capture, verification,
observation, and receipts remain one transaction.

## Restore and disaster recovery

Dashboard restores land under:

```text
Soul/private/backup/restores/restore_<id>/
```

This directory is excluded from future snapshots. Inspect file type, size,
hashes, content, ownership, permissions, and destination mapping before any
live recovery. Promotion is deliberately external because replacing current
credentials, conversations, creative projects, or runtime state may require
stopping services and invalidating active sessions.

A full disaster rehearsal should separately document:

1. restoring into an empty staging location;
2. validating critical JSON/YAML and creative artifacts;
3. comparing hashes and permissions;
4. stopping affected local services;
5. copying only reviewed paths;
6. revoking stale dashboard sessions and restarting services;
7. confirming Chat, projects, memory, and model/runtime configuration.

## Current Operator deployment

The present workstation uses an ext4 filesystem labeled `SOUL_BACKUP`, mounted
at `/mnt/soul-backup`, with the repository at `/mnt/soul-backup/restic`. Its
`nofail` mount avoids intentionally blocking boot when the disk is absent.
Former SanDisk data already copied to `~/Recovered/` is not part of Soul's
backup scope.

This internal SSD protects against accidental deletion and primary-filesystem
failure. It shares the workstation's chassis, power, administrative boundary,
and location. The manual Crucible gate provides an independently hosted
encrypted second copy. It intentionally does not yet delete remote snapshots
or run nightly; live acceptance, exact reconciliation, noninteractive
credential handling, and a complete disaster rehearsal remain later work.

## Verification

Run the deterministic fixture:

```sh
make verify-backup-administration
```

It exercises locked status, exact capture authority, repository verification,
manifest/ledger evidence, newest/minimum retention protection, dry-run and
exact prune, staged restore, operation concurrency, application/dashboard
contracts, and password non-persistence. See
`docs/soul/BACKUP_ADMINISTRATION_A2_REVIEW.md` for the human review checklist.
