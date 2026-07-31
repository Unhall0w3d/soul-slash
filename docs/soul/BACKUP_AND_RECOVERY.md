# Backup and Recovery

Soul exposes encrypted local recovery under **Administration → Backup &
Recovery**. Dashboard mutations are bounded, foreground, manually initiated,
and end in a visible lifecycle state. An optional separately reviewed
deployment may invoke the exact accepted DRS transaction nightly through one
hardened systemd `oneshot`. There is no watcher, resident backup process,
automatic retry, automatic pruning, remote deletion, or unattended restore.

The page has two explicitly separated profiles. **Soul continuity** preserves
Soul's private runtime and retains the separately approved nightly DRS option.
**Operator continuity** preserves the human-owned workstation data, dotfiles,
selected application state, and host-rebuild evidence described below. The
Operator profile is manual foreground only. The profiles use distinct Restic
tags, manifests, ledgers, receipts, and restore staging; by default they share
the same encrypted local repository and Crucible destination.

## What the dashboard does

The page has five exact-gated operations:

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
5. **Run a supervised DRS transaction** performs one fresh verified local
   capture and one exact Crucible reconciliation under a single reviewed
   parent gate. The local snapshot remains valid and is reported as a partial
   result if Crucible becomes unavailable. It never retries, forgets, prunes,
   or deletes remote data.

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

Generate the separate Operator manifests after reviewing the machine-local
inventory:

```sh
make operator-backup-config-plan
make operator-backup-configure \
  EXPECTED_DIGEST=DIGEST_FROM_PLAN \
  CONFIRM=CONFIGURE_OPERATOR_BACKUP_MANIFESTS
```

Operator manifests live under `Soul/private/operator_backup/`. Select
**Operator continuity** in the Dashboard before previewing capture, replica,
retention, or staged restore operations. A shared operation lock prevents Soul
and Operator mutations from running concurrently.

### Operator continuity scope

The portable Operator policy includes existing readable personal-data folders
such as Documents, Music, Pictures, Videos, Servers, Tools, Projects, and the
other named home folders; selected application configuration under
`~/.config`; shell, Git, terminal, SSH, GnuPG, keyring, Codex, Noctalia,
desktop/theming, gaming-overlay, and WinBoat state needed to recreate this
workstation; selected local game-save/userdata and qBittorrent resume state;
and readable host-rebuild evidence such as package inventory, boot
configuration, systemd units, udev rules, and the LACT fan curve. Large
reproducible build trees, caches, virtual environments, `node_modules`, Rust
`target` trees, Steam game installations, Soul's separately protected
project/private state, and WinBoat container disks are excluded.

`~/ai_models` raw GGUF weights are deliberately excluded. The tracked
`config/operator_recovery_assets.json` records the exact filename, byte count,
SHA-256 digest, upstream repository, and revision needed to reacquire each
model. This avoids spending roughly 21 GiB in every local and Crucible lineage
on reproducible artifacts while retaining integrity evidence. If an upstream
artifact disappears, the reviewed policy may be changed later to protect that
specific model as irreplaceable data.

The encrypted profile may include private keys and credential stores because
those are essential recovery material, but encryption does not make every
credential portable. In particular, systemd-creds material encrypted to the
current host is useful for same-host disk recovery and cannot by itself restore
an unattended credential on replacement hardware. A bare-metal recovery still
requires separately held repository credentials, password-vault recovery, and
re-enrollment or rotation of host-bound secrets.

The following remain explicit manual-review gaps rather than silent coverage:
browser profiles/session stores, Downloads and recovered-file holding areas,
WinBoat disk images, root-only NetworkManager profiles, and cloud-synchronized
password-vault contents. The plan lists only paths that exist, are readable,
and are not symlinks; review it before configuration.

The source file is an allow-list, not a whole-home backup. The default
exclusions omit session state, approval tokens, temporary files, and staged
restores. Models, caches, helper environments, and other reproducible large
material are not included by default.

### Durable coverage contract

The portable source defaults include the durable owner state that is intentionally
absent from the public repository:

- Chat transcripts, conversation evidence, shared memory, and owner-private
  configuration/state;
- Music and Visual Studio projects, references, candidates, and retained
  workflow state;
- Skill Studio, Self Assessment, Self Augmentation, proposals, experiments,
  reflections, and reviewed artifacts;
- finished Music exports under `~/Music/soul-music`;
- the configured local Knowledge Vault, normally
  `~/Knowledge/soul-vault`;
- durable application receipts, artifact inbox state, executions, exports,
  creative-flow continuity, and YouTube authorization/description-sync state.

The Knowledge Vault's private Git repository is supplementary version history.
It does not replace inclusion of the local Vault in encrypted Restic snapshots.
Conversely, reproducible model weights and helper environments, active leases,
browser sessions, approval tokens, request-private screen/creative-inspection
staging, maintenance package caches, partial files, and restore staging are
excluded from the default snapshot scope.

**Self Assessment → Storage & Retention** compares the owner source/exclusion
manifests with the latest retained path manifest. Its read-only census reports
each artifact class's owner, retention boundary, deletion behavior, and backup
state as latest-snapshot verified, configured but not yet verified, deliberately
excluded, reproducible/manual-review material, or uncovered. It reads metadata
and path inventories only; it does not accept a Restic password, inspect private
content, change manifests, create a backup, or remove anything.

Portable setup never overwrites an existing owner manifest. When the census
finds a new durable path or missing exclusion, review and edit the owner
manifests first, then create and verify a fresh snapshot through the normal
Dashboard gate. Coverage is not considered proven merely because a parent
directory exists locally.

### Reconciling an existing installation

Initial Makefile setup and the Dashboard reconciliation gate derive from the
same tracked portable policy. When Soul gains a new durable continuity path or
an explicit disposable/cache exclusion:

1. Open **Administration → Backup & Recovery**.
2. Select **Preview manifest additions**.
3. Review every exact source and exclusion line. The preview must show zero
   removals, no replacement, no password, and no Restic operation.
4. Select **Add reviewed entries**.
5. Unlock the repository separately and create a fresh verified backup.
6. Return to **Self Assessment → Storage & Retention** and confirm required
   coverage is latest-snapshot verified.

Reconciliation preserves existing sources, exclusions, comments, and blank
lines. It binds both manifest hashes and the current policy into one digest,
shares the Backup Administration operation lock, writes owner-only files, and
records only counts/hashes in a private receipt. Drift or concurrent backup
work blocks it. Adding a source to the allow-list is not itself evidence that
the source has been captured.

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

The supervised DRS gate is also the transaction foundation for reviewed
nightly execution. The manual A1 gate continues to use the page-session
password. The optional A2/A3 deployment uses a host-encrypted systemd
credential and invokes that same preview-bound implementation. Both paths
record a terminal parent receipt showing local and Crucible state, while the
component capture and replica receipts retain their exact evidence.

If the target is read-only, on the wrong filesystem, missing, or if configured
sources are unavailable, backup creation fails before restic capture.

## Optional nightly DRS deployment

Nightly deployment is intentionally separate from portable setup. It requires
systemd 256 or newer with user-scoped encrypted credentials, a functioning
user manager, the configured recovery mount, Restic, and the already reviewed
key-only Crucible SSH alias.

First preview and enroll the repository password in a local terminal:

```sh
make drs-credential-plan
make drs-credential-enroll CONFIRM=ENROLL_SOUL_DRS_CREDENTIAL
```

The enrollment prompt disables terminal echo and confirms the password
locally. Soul first proves that it opens both the local and Crucible
repositories; a rejected password creates or replaces nothing. The verified
value then passes directly to
`systemd-creds encrypt --user --with-key=host`. Plaintext is never written to
disk. The resulting ignored credential is bound to the current user and host
installation.

Qualification requires one exact run scheduled 60 to 300 seconds ahead:

```sh
make drs-test-plan RUN_AT=ISO8601_TIME
make drs-test-install \
  RUN_AT=THE_SAME_ISO8601_TIME \
  EXPECTED_DIGEST=DIGEST_FROM_PLAN \
  CONFIRM=INSTALL_SOUL_DRS_QUALIFICATION_TIMER
make drs-automation-status
```

Permanent activation remains blocked until the timed run records a complete
DRS parent receipt with verified local and Crucible state:

```sh
make drs-permanent-plan
make drs-permanent-install \
  EXPECTED_DIGEST=DIGEST_FROM_PLAN \
  CONFIRM=ACTIVATE_SOUL_DRS_3AM_TIMER
```

The permanent calendar is fixed at **3:00 AM in the host's local timezone**.
`Persistent=true` permits one missed activation after the user manager
returns. Existing active-work and backup locks still fail closed, and there is
no retry. The Dashboard reports the encrypted credential state, timer mode,
next activation, last run, and last successful complete transaction.
Restic receives one owner-private systemd-managed cache directory while the
rest of the home directory remains read-only to the service.

The service and timer can be removed without deleting the encrypted
credential. Credential removal is a separate exact confirmation so an
accidental service rollback cannot also destroy recovery access.

The current Operator deployment was qualified live on 2026-07-29. Its timed
run completed in 26 seconds, created and verified local snapshot
`7b5c625e…c54ba1`, proved that lineage on Crucible, and then unlocked the
permanent 3:00 AM timer. This machine-local evidence is not a portable setup
default; another installation must perform its own credential enrollment and
qualification.

## Deletion-aware retention

Deleted source files remain recoverable for **30 full days after Soul first
detects their deletion in a newly captured and verified snapshot**. This is
intentionally different from `restic forget --keep-within 30d`: a long gap
between captures could otherwise remove the immediately preceding snapshot
that still contains a recently deleted file.

For every verified snapshot, Soul records:

- repository identity;
- source roots, allowing only a strict verified superset of the preceding set;
- the sorted path inventory;
- snapshot ID and verification time;
- holds created for paths present in the preceding snapshot but absent now.

Each hold protects the preceding snapshot until 30 full days after detection.
Later captures do not reset the clock. A verified reappearance resolves the
hold. An additive source-root expansion is disclosed by count and path digest
and bound into the exact observation approval. Removing or replacing any prior
root remains blocked because that could otherwise be misread as mass deletion.
Retention also fails closed when the ledger is absent/corrupt, repository
identity changes, verification fails, or a selected snapshot is protected. A
hold expiring permits review; it does not itself delete anything.

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
and location. Crucible provides an independently hosted encrypted second copy.
The manual initialize/copy/check path and exact
cross-repository lineage reconciliation were live-accepted on 2026-07-29. The
supervised DRS A1 transaction composes capture and replication without storing
its page-session password. A2/A3 adds the separately reviewed host-encrypted
credential and qualification-before-permanent systemd timer. Neither path
deletes remote snapshots. Remote retention policy and a complete disaster
rehearsal remain separate work.

### Rotating both repository passwords

Repository password rotation is intentionally excluded from the Dashboard so
browser inspection cannot observe the credential field. Preview the fixed
scope, then run the bounded interactive terminal operation:

```sh
make backup-credential-rotation-plan
make backup-credential-rotate
```

The rotation requires exact `ROTATE_BACKUP_CREDENTIALS` confirmation, reads
both passwords with terminal echo disabled, and supplies them to restic only
through inherited anonymous file descriptors. It requires one access key per
repository, preserves repository identity and snapshot inventory, verifies the
new password, rejects the old password, and attempts rollback if the second
repository cannot complete. It writes no credential or rotation receipt.

The first live dual-repository rotation was accepted on 2026-07-29. Both
repositories preserved three tagged snapshots, accepted the replacement
password, and rejected the previous password without requiring rollback.

## Verification

Run the deterministic fixture:

```sh
make verify-backup-administration
make verify-backup-manifest-reconciliation
make verify-storage-retention-census
make verify-nightly-drs-transaction
make verify-nightly-drs-automation
```

It exercises locked status, exact capture authority, repository verification,
manifest/ledger evidence, newest/minimum retention protection, dry-run and
exact prune, staged restore, operation concurrency, application/dashboard
contracts, password non-persistence, and the metadata-only artifact coverage
census. See
`docs/soul/BACKUP_ADMINISTRATION_A2_REVIEW.md` for the human review checklist.
