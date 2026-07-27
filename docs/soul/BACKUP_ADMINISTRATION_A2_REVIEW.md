# Backup Administration A2 Review

## Candidate

Name: Backup & Recovery Administration A2

Risk class: High — encrypted capture plus destructive snapshot retention

Branch: `agent/backup-administration-a2`

Date: 2026-07-26

Status: `candidate_complete`

## Implementation summary

Soul now exposes a bounded **Administration → Backup & Recovery** surface for
repository inspection, verified capture, deletion-aware exact retention, and
isolated staged restore. Repository passwords are accepted only for the
current page operation and passed only through the bounded restic child
environment. Mutating operations share one nonblocking owner-private lock,
stream progress only while the request remains open, record private receipts,
and terminate explicitly.

Capture validates that the configured repository is on the exact expected
writable mount, validates every source, refuses active creative/model work,
runs backup and metadata verification, inventories the resulting snapshot,
and atomically advances the existing 30-day deletion-hold ledger.

Retention accepts explicit full snapshot IDs only. It blocks the newest
snapshot, unknown IDs, deletion holds, and any plan leaving fewer than two
snapshots. Preview includes restic dry-run. Execution performs bounded
forget/prune and post-operation verification.

Restore uses one exact snapshot and optional exact included paths, invokes
restic restore with verification into a fresh owner-private staging directory,
records a hashed inventory, and ends `blocked_for_human_review`. No live state
is replaced.

## Files changed

```text
.env.example
Makefile
assets/dashboard/dashboard.css
assets/dashboard/dashboard.js
assets/dashboard/index.html
config/project_tracker_seed.json
docs/soul/BACKUP_ADMINISTRATION_A2_BRIEF.md
docs/soul/BACKUP_ADMINISTRATION_A2_REVIEW.md
docs/soul/BACKUP_AND_RECOVERY.md
docs/soul/LOCAL_SYSTEMD_HTTPS_DEPLOYMENT.md
lib/soul_core/application_contract.rb
lib/soul_core/application_facade.rb
lib/soul_core/backup_administration_service.rb
lib/soul_core/dashboard_authentication_assessor.rb
lib/soul_core/dashboard_deployment.rb
lib/soul_core/dashboard_deployment_assessor.rb
lib/soul_core/dashboard_http_application.rb
lib/soul_core/phase12b_in_process_application_api_assessor.rb
scripts/soul-backup-config
scripts/verify-dashboard-authentication-phase12c1.rb
scripts/verify-backup-administration-a2.rb
scripts/verify-dashboard-self-improvement-navigation.rb
scripts/verify-phase12d3-self-improvement-dashboard.rb
scripts/verify-protected-lan-systemd-deployment.rb
```

Owner-local, ignored state also receives the staged-restore exclusion and an
updated Project Timeline entry.

## Commands run

```text
ruby scripts/verify-backup-administration-a2.rb
node --check assets/dashboard/dashboard.js
ruby -c lib/soul_core/backup_administration_service.rb
ruby -c lib/soul_core/application_facade.rb
ruby -c lib/soul_core/dashboard_http_application.rb
ruby bin/soul assess dashboard-deployment --json
ruby scripts/verify-dashboard-authentication-phase12c1.rb
ruby scripts/verify-dashboard-self-improvement-navigation.rb
ruby scripts/verify-protected-lan-systemd-deployment.rb
make test-fast
git diff --check
```

## Deterministic results

`ruby scripts/verify-backup-administration-a2.rb`: passed.

The fixture proves locked inspection, exact mount identity, capture preview and
authority, restic capture/check/inventory, private manifests and ledger,
newest/minimum retention protection, dry-run and exact prune, staged verified
restore, operation concurrency rejection, application/dashboard contracts,
and password absence from argv and persisted evidence.

Broader repository regression commands and live dashboard inspection are
recorded at final handoff. Live inspection at 1280px and 390px confirmed no
horizontal overflow, a usable Administration menu, correct responsive stacking,
and accurate writable recovery-target status after service sandbox deployment.

## Local LLM evaluation

Not applicable. Repository operations, authority, retention, and restore are
deterministic safety behavior and must not be validated by an LLM.

## Memory

Reads: none.

Writes/updates: none.

Forget behavior: none.

Backup manifests, snapshot inventories, deletion holds, receipts, and restore
staging are operational recovery evidence under `Soul/private/backup/`; they
are not conversational memory or skill-private memory.

## Lifecycle states touched

```text
complete
awaiting_input
failed
blocked_for_human_review
```

No operation remains silently active after response completion or client
disconnect.

## Safety and persistence check

```text
Persistent service added: no
Daemon added: no
Watcher added: no
Scheduled task added: no
Cron job added: no
systemd unit added: no
launch agent added: no
Windows service added: no
Long-running background loop added: no
Background polling added: no
Confirmation gate weakened: no
Skill-private memory store added: no
Repository password persisted: no
Live-tree restore added: no
Automatic retention added: no
```

## Known weaknesses

- Password-authenticated capture, retention, and restore were not triggered
  during Codex's live UI check. Their command semantics are covered by the
  deterministic fake-restic transaction fixture and remain human review gates.
- Metadata verification is automatic after capture and retention. Full
  `--read-data` verification remains a slower manual maintenance procedure.
- Request-bound operations stop being observable if the browser connection is
  lost. They do not detach into a background job; restic termination follows
  the bounded process/request lifecycle.
- Same-user local processes may observe transient child-process environment
  values through operating-system inspection. Soul itself does not persist,
  log, or send the password to a model.
- Staged restore promotion and service/session recovery remain a documented
  external human disaster-recovery procedure.
- The internal SSD is neither offline nor off-site.

## Human review checklist

```text
[ ] Dashboard unlock works without browser/password persistence
[ ] Read-only and wrong-mount states are clearly blocked
[ ] Capture preview lists the intended owner allow-list
[ ] One approved live capture produces a verified snapshot and receipt
[ ] Snapshot ordering and newest protection are clear
[ ] Exact retention preview does not select protected snapshots
[ ] Restore creates only isolated staging and stops for review
[ ] Responsive Administration menu/page is usable on desktop and mobile
[ ] No unapproved persistence or background behavior exists
[ ] Public setup and .env guidance are reproducible
[ ] Risk classification and known weaknesses are accepted
```

## Human review outcome

```text
Outcome: pending
Reviewer: Operator
Date:
Decision summary:
Required changes:
```
