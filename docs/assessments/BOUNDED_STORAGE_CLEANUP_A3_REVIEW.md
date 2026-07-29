# Bounded Storage Cleanup A3 Review

## Skill

Name: Bounded Storage Cleanup A3

Risk class: permanent owner-local deletion; exact human-reviewed scope

Branch/checkpoint: `codex/bounded-storage-cleanup-a3`

Date: 2026-07-29

## Candidate status

`candidate_complete`

## Implementation summary

Storage & Retention now has one executable cleanup gate for exactly three
previously accepted categories:

- allowlisted Soul review residue in the configured temporary root after
  24 hours;
- regular non-dot project log files after 30 days;
- failed `.candidate_*.partial` Music quarantine directories after 24 hours
  when no Music lease is active.

Preview recursively inventories metadata for every candidate and binds the
path, type, owner, age, byte count, device/inode-backed tree identity, category,
and complete entry list. Execute repeats discovery and requires the exact
digest before mutation.

Candidates are renamed to unique same-parent staging names, immediately
reverified by device, inode, and recursive identity, and then removed without a
shell command. A failure restores every entry that still exists in staging and
discloses anything already removed. One owner-only receipt is written under the
existing age-reviewable project-log class using path/identity digests rather
than raw paths.

The Dashboard keeps preview and destructive authorization separate. The button
supplies the exact confirmation only after a non-empty preview; refreshes and
Storage assessments never execute cleanup.

## Files changed

```text
- lib/soul_core/storage_retention_assessor.rb
- lib/soul_core/self_improvement_service.rb
- lib/soul_core/application_contract.rb
- lib/soul_core/application_facade.rb
- assets/dashboard/index.html
- assets/dashboard/dashboard.js
- scripts/verify-bounded-storage-cleanup-a3.rb
- scripts/verify-storage-retention-a1.rb
- scripts/verify-storage-retention-backup-census-a2.rb
- Makefile
- config/project_tracker_seed.json
- docs/soul/BOUNDED_STORAGE_CLEANUP_A3_BRIEF.md
- docs/guides/SELF_ASSESSMENT.md
- docs/CURRENT_STATE.md
- docs/ROADMAP.md
- this review artifact
```

## Commands run

```text
make verify-storage-cleanup
ruby scripts/verify-storage-retention-a1.rb
ruby scripts/verify-storage-retention-backup-census-a2.rb
ruby scripts/verify-phase12b-in-process-application-api.rb
ruby -c lib/soul_core/storage_retention_assessor.rb
ruby -c lib/soul_core/self_improvement_service.rb
ruby -c lib/soul_core/application_facade.rb
ruby -c lib/soul_core/application_contract.rb
ruby -c scripts/verify-bounded-storage-cleanup-a3.rb
node --check assets/dashboard/dashboard.js
ruby -rjson -e 'JSON.parse(File.read("config/project_tracker_seed.json"))'
git diff --check
```

## Deterministic test results

The dedicated A3 fixture passes:

- one exact allowlisted old temporary tree;
- wrong-confirmation immutability;
- preview-digest invalidation after candidate drift;
- exact removal with adjacent unknown and recent paths preserved;
- owner-only, hash-only cleanup receipt;
- terminal empty second preview;
- old regular log removal with current logs and `.keep` preserved;
- active Music lease rejection after preview;
- failed partial quarantine removal with accepted candidate preservation;
- non-waiting concurrent-operation rejection;
- application preview and execute routing;
- symlink-tree rejection;
- oversized-scope rejection rather than truncation;
- simulated partial failure with restoration of still-staged entries;
- separate Dashboard preview and destructive controls;
- absence of shell deletion and persistence primitives.

Historical Storage A1 and artifact-census/backup A2 regressions pass after
recognizing A3 as their separately approved execute layer. Ruby and JavaScript
syntax checks pass. The application API regression is expected to pass after
the intentional new verifier is staged; its repository-curation check correctly
reports the current untracked review artifact before staging.

No local LLM evaluation applies; eligibility, scope binding, and mutation are
entirely deterministic.

## Memory keys

Reads: none.

Writes/updates: none.

Forget behavior: not applicable.

## Task lifecycle states touched

```text
- complete
- awaiting_input
- blocked_for_human_review
- failed
```

Every preview and execution is bounded and terminal.

## Safety and persistence check

```text
Persistent service added: no
Daemon added: no
Watcher added: no
Scheduled task added: no
Cron job added: no
systemd unit added: no
Long-running background loop added: no
Background polling added: no
Privilege escalation added: no
Shell deletion added: no
Arbitrary client path accepted: no
Symlink followed: no
Protected artifact class made executable: no
Automatic cleanup added: no
Backup or Restic mutation added: no
```

## Known weaknesses

- Permanent removal is intentional for these disposable/age-review classes;
  there is no restore operation. Restic may retain eligible project logs or
  quarantine data if they were present in a prior verified snapshot.
- Metadata identity does not hash private file content. A local actor able to
  replace content while restoring the same inode, size, mode, and nanosecond
  timestamp could evade content-change detection; Soul does not read private
  content merely to authorize cleanup.
- A process may hold an old temporary or log file open without a detectable
  lease. Age, ownership, exact metadata drift, and same-parent staging bound
  the risk, but no `lsof`-style process scan is introduced.
- Cleanup receipts are ordinary age-reviewable project logs and may themselves
  become eligible after 30 days through a later explicit cleanup.
- The live workstation currently reports zero candidates in all three
  categories, so human review can validate empty-state presentation but not a
  real deletion without waiting for or deliberately creating eligible residue.
- Broader lifecycle-owned, capacity-bounded, model, cache, project, chat,
  memory, Vault, credential, export, backup, and maintenance cleanup remains
  unavailable.

## Human review checklist

```text
[ ] Storage refresh remains read-only
[ ] Only the three approved categories appear
[ ] Empty preview exposes no destructive button
[ ] Non-empty preview lists every exact path and identity digest
[ ] Protected projects, candidates, exports, memory, Vault, and backups never appear
[ ] Destructive button is separate from preview and supplies one exact authorization
[ ] Changed scope requires a fresh preview
[ ] Active Music work blocks partial-quarantine cleanup
[ ] Success refreshes the point-in-time census
[ ] Owner-only receipt contains no raw path
[ ] No automatic cleanup or persistence behavior exists
[ ] Merge readiness is approved independently from tests
```

## Human review outcome

```text
Outcome: pending
Reviewer: Operator
Date:
Decision summary:
Required changes:
```
