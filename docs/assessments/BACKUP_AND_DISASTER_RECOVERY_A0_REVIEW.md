# Backup and Disaster Recovery A0 Review

Status: review in progress; design candidate only

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
- drafted backup, restore, verification, exclusion, retention, and secret
  boundaries without installing or executing a backup tool.

## Files changed

- `config/project_tracker_seed.json`
- `docs/ROADMAP.md`
- `docs/soul/BACKUP_AND_DISASTER_RECOVERY_A0_BRIEF.md`
- `docs/assessments/BACKUP_AND_DISASTER_RECOVERY_A0_REVIEW.md`

The ignored owner-local Project Timeline was updated through
ProjectTrackerService and is not part of the Git diff.

## Commands and evidence

- path and size inventory with `du`, `find`, and `stat`;
- filesystem inspection with `findmnt` and `stat -f`;
- installed-tool inspection with `command -v` and `pacman -Q`;
- private and public tracker JSON parsing;
- `ruby scripts/verify-project-timeline-a1.rb`;
- `ruby scripts/verify-runtime-privacy-hygiene-phase44.rb`;
- `ruby scripts/verify-docs-cleanup.rb`;
- `git diff --check`.

## Result

The normal protected set is approximately 2.5 GiB plus small continuity and
configuration files. Approximately 130 GiB of models, caches, helper
environments, pilots, and evaluations is reconstructable and should be
excluded from routine snapshots.

Restic is the leading A1 candidate, but no destination, key custody, package
installation, service, timer, prune policy, or backup execution is approved.

## Local LLM evaluation

None. Storage classification and recovery policy require deterministic
inventory and human review, not model judgment.

## Known weaknesses

- current measurements describe one workstation at one point in time;
- no external backup destination has been selected or measured;
- no recovery snapshot exists yet;
- no restore rehearsal has been run;
- exact cross-file quiescence needs an A1 implementation decision;
- the current public setup documentation does not yet provide a single
  machine-readable dependency lock or recovery manifest.

## Memory keys added or used

None.

## Lifecycle states touched

- tracker item: `planned` → `in_progress`;
- proposed future backup: terminal `complete`, `failed`, `canceled`, or
  `blocked_for_human_review`;
- proposed future restore: always staged and `blocked_for_human_review` before
  live replacement.

## Risk

Low. This is a read-only inventory and design slice plus explicit tracker and
documentation changes. No private data is copied, deleted, uploaded, or
published.

## Human review checklist

- [ ] Confirm the recovery classes and default exclusions.
- [ ] Select a first backup destination.
- [ ] Confirm restic as the A1 tool candidate.
- [ ] Select a key-custody approach.
- [ ] Decide whether preserving Caddy trust material is worthwhile.
- [ ] Choose portable quiescent capture or authorize investigation of an
  optional Btrfs source-snapshot adapter.
- [ ] Confirm or revise the candidate retention policy.
