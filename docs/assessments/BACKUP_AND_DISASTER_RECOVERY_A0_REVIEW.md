# Backup and Disaster Recovery A0 Review

Status: candidate-complete; human review required

## Work performed

- selected Backup and Disaster Recovery from the Project Timeline backlog;
- moved its owner-local and public tracker representation to `now /
  in_progress / high`;
- inventoried repository-local private state, creative projects, finished
  exports, external Knowledge Vault data, deployment configuration, model
  stores, helper runtimes, and caches;
- separated irreplaceable owner state from reconstructable dependencies;
- inspected installed filesystem and backup tooling;
- compared current upstream restic and Borg capabilities;
- identified and inventoried the separate 120 GB-class SanDisk SSD proposed as
  the first local repository;
- copied its personal Documents, Pictures, and Janempa trees to an owner-only
  home-directory recovery location and checksum-compared every copied file;
- verified SMART health and completed a fresh short device self-test;
- reformatted the explicitly approved device as GPT/ext4 and mounted it by
  UUID at `/mnt/soul-backup`;
- installed signed Arch restic 0.19.1 and initialized an encrypted owner-only
  repository;
- created the first 1.4 GiB manual Soul-state snapshot while explicitly
  excluding the recovered SanDisk data;
- read and verified all 79 repository data packs;
- restored the private Project Timeline into `/tmp`, validated its JSON, and
  matched it byte-for-byte to the live source;
- documented the bounded manual backup and staged-restore procedure.

## Files changed

- `config/project_tracker_seed.json`
- `README.md`
- `docs/ROADMAP.md`
- `docs/soul/BACKUP_AND_DISASTER_RECOVERY_A0_BRIEF.md`
- `docs/soul/BACKUP_AND_RECOVERY.md`
- `docs/assessments/BACKUP_AND_DISASTER_RECOVERY_A0_REVIEW.md`

The ignored owner-local Project Timeline was updated through
ProjectTrackerService and is not part of the Git diff.

## Commands and evidence

- path and size inventory with `du`, `find`, and `stat`;
- filesystem inspection with `findmnt` and `stat -f`;
- installed-tool inspection with `command -v` and `pacman -Q`;
- private and public tracker JSON parsing;
- `smartctl` health, attributes, and short self-test inspection;
- ext4 host write, fsync, read, clean unmount, and UUID-based remount checks;
- `restic check --read-data` (79/79 packs; no errors);
- staged `restic restore latest` of Project Timeline state;
- `jq`, `sha256sum`, and `cmp` against the staged restored file;
- `ruby scripts/verify-project-timeline-a1.rb`;
- `ruby scripts/verify-runtime-privacy-hygiene-phase44.rb`;
- `ruby scripts/verify-docs-cleanup.rb`;
- `git diff --check`.

## Result

The normal protected set is approximately 2.5 GiB plus small continuity and
configuration files. Approximately 130 GiB of models, caches, helper
environments, pilots, and evaluations is reconstructable and should be
excluded from routine snapshots.

The SanDisk now provides an owner-only ext4 recovery target and encrypted
restic repository. Its former personal data was checksum-recovered into the
home directory before reformatting, but is intentionally excluded from the
Soul source allow-list at the Operator's direction.

Snapshot `20ae7e63` occupies approximately 1.4 GiB. Full pack verification
reported no errors. The staged Project Timeline restore has SHA-256
`de79aecf2e0743a61f08e466485d0451ecafc017b4222916313ce49e5ff56218`
for both restored and live copies.

## Local LLM evaluation

None. Storage classification and recovery policy require deterministic
inventory and human review, not model judgment.

## Known weaknesses

- current measurements describe one workstation at one point in time;
- the local SanDisk candidate shares the workstation failure boundary and is
  not an offline/off-site backup;
- exact cross-file quiescence needs an A1 implementation decision;
- the first snapshot used a manually reviewed source allow-list rather than a
  productized preview/receipt workflow;
- only a representative single-file restore was rehearsed, not complete
  host-loss recovery;
- the repository remains inside the same workstation and is not an offline or
  off-site copy;
- retention and prune behavior are documented candidates but not implemented;
- the current public setup documentation does not yet provide a single
  machine-readable dependency lock or recovery manifest.

## Memory keys added or used

None.

## Lifecycle states touched

- tracker item: `planned` → `in_progress` → `needs_review`;
- proposed future backup: terminal `complete`, `failed`, `canceled`, or
  `blocked_for_human_review`;
- proposed future restore: always staged and `blocked_for_human_review` before
  live replacement.

## Risk

High during the explicitly authorized device reformat; medium for secret-bearing
encrypted backup and restore verification. The destructive storage operation
is complete. No private data was uploaded or published, no live Soul data was
overwritten, and no unattended process was introduced.

## Human review checklist

- [ ] Confirm the final recovery classes and source allow-list.
- [x] Select the first local backup destination.
- [x] Confirm restic as the local snapshot tool.
- [x] Keep the password under human custody and outside Soul/Git.
- [x] Preserve Caddy trust material in the encrypted repository.
- [ ] Choose portable quiescent capture or authorize investigation of an
  optional Btrfs source-snapshot adapter.
- [ ] Confirm or revise the candidate retention policy.
- [ ] Select an additional offline or off-site recovery copy.
- [ ] Schedule a separately gated complete recovery rehearsal.
