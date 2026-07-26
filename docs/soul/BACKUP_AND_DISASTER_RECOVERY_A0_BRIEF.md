# Backup and Disaster Recovery A0 Brief

Status: review in progress; no backup implementation or destination approved

## Objective

Define what makes this Soul instance recoverable without copying every
reproducible model, cache, virtual environment, and experiment. The design must
cover backup, restore, verification, exclusions, secret handling, retention,
and recovery rehearsal before any scheduled or unattended behavior is
considered.

This slice is read-only except for documentation and the explicit Project
Timeline status update. It installs nothing, creates no backup repository, and
adds no service, timer, watcher, or scheduled task.

## Current inventory snapshot

Measured on the Operator workstation on 2026-07-26:

| Class | Approximate size | Character |
| --- | ---: | --- |
| Repository-local Music projects | 1.3 GiB | Irreplaceable briefs, lineage, candidates, reviews, and bound previews |
| Finished `~/Music/soul-music` exports | 1.1 GiB | Irreplaceable delivered FLAC, MP3, lyrics, metadata, and video packages |
| Repository-local Visual projects | 39 MiB | Irreplaceable briefs, lineage, candidates, reviews, and motion artifacts |
| Private/runtime/proposal/reflection state | under 2 MiB | Small but identity- and continuity-critical |
| Knowledge Vault | 276 KiB | Durable reviewed knowledge; optionally protected by its own private Git remote |
| Repository-local Music tooling | 803 MiB | Reproducible helper environments and analysis models |
| `~/.local/share/soul` | 77 GiB | Primarily reproducible Music, Visual, Voice runtimes, models, pilots, and evaluations |
| Ollama store | 20 GiB | Re-downloadable model data |
| GGUF model directory | 21 GiB | Re-downloadable configured models, including obsolete compatibility candidates |
| Hugging Face cache | 12 GiB | Re-downloadable cache |

The immediate high-value backup surface is therefore only a few GiB. Copying
the roughly 130 GiB reproducible surface into every normal snapshot would make
backup slower, costlier, and harder to verify without materially improving
recovery.

Sizes are observations, not manifest rules. The implementation must classify
paths by purpose rather than by current size.

## Proposed recovery classes

### Class P0 — identity, continuity, and authority

Encrypted backup required:

- `.env` and owner-local model/provider configuration;
- `Soul/private/`, including approved memory and Project Timeline state;
- conversation history, evidence, state, artifact inbox, and execution
  receipts under `Soul/runtime/`;
- Skill Studio proposals, reflection state, augmentation proposals, host
  improvement plans, identity, and conversation artifact records;
- Dashboard administrator credential state;
- the external Knowledge Vault.

Default exclusions within this class:

- active dashboard sessions;
- unexpired approval tokens;
- lock files and transient request files;
- caches and temporary files.

Credential recovery must not silently restore a live session or reusable
approval. Restoring the administrator credential is useful; restoring session
and approval capability is not.

### Class P1 — creative source and finished work

Encrypted backup required:

- `Soul/music/projects/`;
- `Soul/visual/projects/`;
- retained reference profiles that are legal and intended to persist;
- `~/Music/soul-music/` finished exports and upload packages.

Temporary downloaded reference audio, disposable pilot runs, rejected
intermediate scratch files, and regenerable analysis environments are excluded.
Existing project deletion and retention contracts remain authoritative.

### Class P2 — deployment identity and convenience

Encrypted backup recommended:

- `~/.config/soul/`;
- the installed Soul-related systemd user unit files;
- Caddy local CA and certificate state if preserving already trusted LAN
  certificates is desired.

Caddy private keys and dashboard environment files are secrets. They must never
enter Git or an unencrypted archive. These files can be regenerated, but doing
so changes trust material and increases recovery work.

### Class R — reproducible material

Do not include in routine owner-state snapshots:

- Git-tracked source, because the Git remote is its primary recovery source;
- `~/.local/share/soul` model/runtime builds and evaluation sandboxes;
- `~/.ollama`;
- the configured GGUF model directory;
- Hugging Face and other download caches;
- repository-local `.venv` trees and Music tooling environments;
- native build trees, pilot runs, logs without durable review value, and
  temporary generation files.

Recovery documentation must record exact setup commands, model identities, and
checks so Class R can be reconstructed. A separate optional cold model mirror
may be considered later if avoiding large downloads becomes worth the storage.

## Tool assessment

The workstation currently has `rsync`, `tar`, `zstd`, GnuPG, and Btrfs tools,
but no snapshot backup application. Btrfs is the current home filesystem and
could provide an optional point-in-time source snapshot; it must not become a
public-repository requirement.

The recommended A1 candidate is **restic**:

- client-side encrypted repositories;
- deduplicated snapshots with compression;
- local, SFTP, object-storage, and other supported backends without changing
  Soul's source manifest;
- selective restore, dry-run restore, integrity checking, and machine-readable
  output;
- a current signed package in Arch Linux Extra.

Borg is also technically sound, particularly for local or SSH-hosted
repositories. Restic is preferred while the destination remains undecided
because its backend range and JSON-oriented scripting surface better fit a
portable public project.

No package is approved for installation by this brief.

Upstream references reviewed:

- [restic 0.19.1 documentation](https://restic.readthedocs.io/en/stable/)
- [restic repository and key setup](https://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html)
- [restic restore behavior](https://restic.readthedocs.io/en/stable/050_restore.html)
- [restic retention and prune behavior](https://restic.readthedocs.io/en/stable/060_forget.html)
- [Arch Linux restic package](https://archlinux.org/packages/extra/x86_64/restic/)
- [BorgBackup 1.4 documentation](https://borgbackup.readthedocs.io/en/stable/)
- [Arch Linux Borg package](https://archlinux.org/packages/extra/x86_64/borg/)

## Proposed backup transaction

An eventual Soul backup capability should remain a bounded foreground
operation:

1. inventory the selected recovery classes;
2. fail if paths escape approved roots, contain unsafe symlinks, or exceed
   configured limits unexpectedly;
3. report active creative/model work and require it to finish or be canceled;
4. render the exact sources, exclusions, destination identity, estimated byte
   count, retention policy, and snapshot tags;
5. require a digest-bound preview and exact human confirmation;
6. create one encrypted snapshot with bounded runtime and terminal status;
7. run repository metadata verification;
8. emit a local receipt that contains no password, key, or secret value;
9. return `complete`, `failed`, `canceled`, or
   `blocked_for_human_review`.

No model output can select sources, exclusions, retention, destination, or
authorization. A future scheduler would require a separate explicit brief.

## Consistency boundary

The most reliable portable default is to require zero active creative work and
take the snapshot as one foreground transaction. Existing atomic JSON writes
and immutable candidate artifacts reduce risk, but they do not make a
multi-path backup globally atomic.

Two A1 options require human selection:

1. **Portable quiescent capture:** verify no active jobs, briefly hold a
   dedicated maintenance write lock, and back up the approved paths. This is
   portable but may keep write operations unavailable during the snapshot.
2. **Optional Btrfs source snapshot:** create a read-only filesystem snapshot,
   release the application quickly, and back up from that stable view. This is
   faster operationally but filesystem-specific and may require narrowly
   reviewed privilege.

The A0 recommendation is to implement portable quiescent preview and
verification first, then assess whether the measured pause justifies an
optional Btrfs adapter.

## Restore contract

Restore must never target the live tree first.

1. select one exact snapshot;
2. restore into a new staging directory;
3. verify repository integrity and a generated SHA-256 manifest;
4. validate JSON, JSONL, YAML, project lineage, media existence, and
   owner/permission expectations;
5. render the proposed live destinations and conflicts;
6. stop or gate writers only after staging validation passes;
7. require a second digest-bound human confirmation;
8. preserve the displaced live state until post-restore validation succeeds;
9. revoke restored sessions and approval tokens;
10. run the applicable deterministic Soul verifiers before reopening writes.

Single-file or single-project recovery should use the same staging rule.
In-place restore and deletion flags are prohibited in the first implementation.

## Retention proposal

Candidate policy for review, not approval:

- retain the latest 7 daily snapshots;
- retain 5 weekly snapshots;
- retain 12 monthly snapshots;
- protect manually tagged pre-migration and release snapshots from ordinary
  retention;
- dry-run retention before any destructive prune;
- run a metadata check after prune;
- perform a full data-read verification periodically rather than on every
  foreground backup.

The first implementation should support manual snapshots and verification
only. Scheduling, pruning, and off-site replication are separate gates.

## Destination and key custody

A backup on the same NVMe protects against accidental deletion but not device
loss. The intended mature posture is:

- one encrypted repository on separate local storage;
- one additional offline or off-site copy;
- the repository password/recovery material stored outside both the source
  workstation and the backup repository.

The backup password must not be stored in `.env`, the Soul repository, the
backup itself, logs, receipts, or model context.

### Local SanDisk candidate

The Operator workstation contains a separate SanDisk SSD Plus 120 GB device
with 111.8 GiB usable capacity. At review time it held one read-only mounted
NTFS partition with 5.7 GiB used and 106.1 GiB free.

The three personal data trees on the device were copied into an owner-only
recovery directory on the primary home filesystem. A checksum-mode rsync
comparison reported no differences across 2,569 files and 4,099,426,963 bytes.
An owner-only relative SHA-256 manifest was then generated and all 2,569
entries verified successfully.
The Windows recycle bin, empty recovery directory, and volume metadata were
intentionally not migrated. The source SSD remains unchanged pending health
review and a separate destructive confirmation.

If SMART health is acceptable, the recommended local-target layout is:

- GPT partition table;
- one ext4 partition labeled `SOUL_BACKUP`;
- a stable UUID-based mount at `/mnt/soul-backup`;
- an owner-only restic repository below that mount;
- `nofail` mount behavior so loss of the backup disk cannot block boot;
- a capacity warning before the repository consumes 80% of the filesystem.

Ext4 is preferred here for a simple portable filesystem boundary; restic
provides repository encryption, deduplication, and integrity verification.
Using Btrfs for the backup target would not make the source capture globally
atomic and is unnecessary for the first implementation.

This internal SSD is only the first local recovery copy. It shares the
workstation's power, chassis, and administrative boundary and therefore does
not satisfy the additional offline/off-site copy requirement.

## Human decisions required before A1 implementation

- first repository destination and available capacity;
- acceptable SMART health for the local SanDisk candidate;
- restic versus Borg if the destination strongly favors Borg/SSH;
- key-custody method;
- whether finished exports and the Knowledge Vault share the same repository;
- whether to preserve Caddy trust material;
- portable quiescent capture versus an optional Btrfs snapshot adapter;
- acceptable manual-backup pause;
- retention values;
- whether any future scheduled execution is desirable.

## A0 acceptance

- recovery classes reflect actual current storage;
- secrets and ephemeral authority are treated differently;
- reproducible models and helper environments are excluded by default;
- restore stages and verifies before touching live data;
- tool and destination choices remain human decisions;
- no persistence, privilege, backup repository, or destructive retention is
  introduced.
