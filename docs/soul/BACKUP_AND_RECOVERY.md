# Backup and Recovery

Soul's local recovery repository is an encrypted restic repository on separate
storage. Backups are manual, bounded foreground operations. No timer, daemon,
watcher, automatic retention, or unattended restore is installed.

## Local deployment

The Operator workstation currently uses:

- `/dev/sda1`, ext4, label `SOUL_BACKUP`;
- filesystem UUID `b9713868-7a24-4369-864d-cd67029981fb`;
- mount point `/mnt/soul-backup`;
- repository `/mnt/soul-backup/restic`;
- owner-local source and exclusion manifests under
  `Soul/private/backup/`.

The mount is declared by UUID with `defaults,noatime,nofail` and a bounded
device timeout. Loss of the backup disk therefore does not intentionally block
boot. The restic password is held by the human Operator and is not stored in
the repository, Soul, `.env`, Git, logs, or model context.

The recovered contents of the SanDisk's former NTFS filesystem remain in
`~/Recovered/SanDisk-SSD-2026-07-26/`. They are intentionally absent from the
backup source manifest and must not be added implicitly.

## Manual snapshot

Before starting, confirm that Music and Visual generation jobs are terminal
and that `/mnt/soul-backup` is mounted read-write. Review both manifest files;
the source list is an allow-list, not a whole-home backup.

```sh
findmnt /mnt/soul-backup
restic --repo /mnt/soul-backup/restic backup \
  --files-from Soul/private/backup/sources.txt \
  --exclude-file Soul/private/backup/excludes.txt \
  --tag soul-state \
  --host "$(hostname)"
```

Restic prompts for the repository password. A completed command is not enough
to prove recoverability: run verification and a staged restore.

## Integrity verification

Metadata verification:

```sh
restic --repo /mnt/soul-backup/restic check
```

Full data verification:

```sh
restic --repo /mnt/soul-backup/restic check --read-data
```

The first snapshot was fully read on 2026-07-26: 79 of 79 packs passed and
restic reported no errors.

## Staged restore

Never restore directly over live Soul state. Select a snapshot, restore into a
new staging directory, validate it, compare the proposed destinations, and
require a separate human gate before any live replacement.

Example for one file:

```sh
restic --repo /mnt/soul-backup/restic restore latest \
  --target /tmp/soul-backup-restore-test \
  --include /home/USER/Projects/soul/Soul/private/project_tracker/state.json
```

Validate the staged file before considering promotion:

```sh
jq -e . /tmp/soul-backup-restore-test/home/USER/Projects/soul/Soul/private/project_tracker/state.json
sha256sum \
  /home/USER/Projects/soul/Soul/private/project_tracker/state.json \
  /tmp/soul-backup-restore-test/home/USER/Projects/soul/Soul/private/project_tracker/state.json
```

The 2026-07-26 rehearsal restored the Project Timeline into `/tmp`; the JSON
validated and its SHA-256 matched the live source byte-for-byte.

## Scope and limitations

Routine snapshots include private continuity state, conversations, proposals,
creative project lineage, finished exports, the Knowledge Vault, selected
deployment configuration, and Caddy trust state. They exclude model stores,
download caches, helper environments, transient sessions, approval tokens,
and other reproducible material.

This internal SSD protects against accidental deletion and primary-filesystem
failure. It shares the workstation's chassis, power, administrative boundary,
and physical location. It is not an offline or off-site copy. Retention,
pruning, periodic scheduling, an additional copy, and a full disaster
rehearsal remain separately reviewed work.
