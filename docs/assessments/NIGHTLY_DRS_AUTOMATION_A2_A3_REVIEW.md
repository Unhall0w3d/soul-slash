# Nightly DRS Automation A2/A3 Review

## Candidate

Name: Nightly DRS Automation A2/A3

Risk class: host-bound encrypted credential, persistent user service and timer,
encrypted local and off-device backup addition; no deletion

Branch: `codex/nightly-drs-automation-a2-a3`

Date: 2026-07-29

Status: `live_qualified_human_approved`

## What was implemented

- One interactive, echo-disabled credential enrollment gate.
- Read-only password verification against both accepted Restic repositories
  before encryption. A rejected password creates or replaces nothing.
- User-scoped, host-bound encryption through `systemd-creds`.
- One hardened, no-restart `soul-nightly-drs.service` systemd user oneshot.
- One owner-private systemd-managed Restic cache while the remainder of the
  home directory stays read-only.
- One `soul-nightly-drs.timer` with a digest-bound 60–300 second
  qualification mode and a separately gated permanent 3:00 AM mode.
- One owner-private run-state record with start, terminal, partial,
  interruption, and last-success evidence.
- Backup & Recovery status for credential, timer, next run, local/Crucible
  result, and last success.
- Qualification evidence is required before the permanent timer can be
  rendered or activated.

The scheduled runner invokes the accepted A1 preview and execution methods. It
does not implement a second backup path.

## Files changed

```text
Makefile
assets/dashboard/dashboard.js
assets/dashboard/index.html
config/project_tracker_seed.json
docs/CURRENT_STATE.md
docs/ROADMAP.md
docs/soul/BACKUP_AND_RECOVERY.md
docs/soul/NIGHTLY_DRS_AUTOMATION_A2_A3_BRIEF.md
docs/assessments/NIGHTLY_DRS_AUTOMATION_A2_A3_REVIEW.md
lib/soul_core/application_facade.rb
lib/soul_core/nightly_drs_deployment.rb
lib/soul_core/nightly_drs_runner.rb
scripts/soul-nightly-drs-run
scripts/soul-nightly-drs-schedule
scripts/verify-nightly-drs-automation-a2-a3.rb
```

## Deterministic validation

```text
make verify-nightly-drs-automation
make verify-nightly-drs-transaction
make verify-backup-administration
make verify-crucible-backup-replication
make verify-project-timeline
ruby scripts/verify-phase12b-in-process-application-api.rb
ruby -c lib/soul_core/nightly_drs_deployment.rb
ruby -c lib/soul_core/nightly_drs_runner.rb
node --check assets/dashboard/dashboard.js
systemd-analyze --user verify <rendered service> <rendered timer>
git diff --check
```

Fixtures prove wrong confirmation and stale digest cause no installation,
qualification schedules are bounded, permanent activation is unavailable
before complete timed evidence, the encrypted credential never becomes a
plaintext file, rejected repository passwords cannot be enrolled, a complete
run records exact local and remote evidence, and a remote failure terminates
partial without retry.

## Local LLM evaluation

Not applicable. Credential transport, unit rendering, time bounds, repository
lineage, and lifecycle behavior are deterministic.

## Memory keys

Reads: none.

Writes: none.

## Lifecycle states

```text
complete
failed
awaiting_input
blocked_for_human_review
canceled
```

## Persistence and risk review

```text
Encrypted credential: yes, user-scoped and host-bound
Plaintext credential file: no
Persistent process: no
User service: yes, Type=oneshot
User timer: yes, qualification then fixed 3:00 AM
Automatic retry: no
Automatic retention/prune: no
Remote deletion: no
Live restore: no
Overlap waiting or queue: no
```

## Live qualification evidence

- A deliberately rejected old password created or replaced no encrypted
  credential. A second accidental old-password attempt was likewise rejected.
- The accepted password opened both repositories before host encryption.
- Qualification was armed for `2026-07-29 23:45:10 EDT` and systemd triggered
  it at that exact second without an open Dashboard.
- The service returned inactive/success after 26.208 seconds, with no retry.
- Local snapshot:
  `7b5c625e4b1d7347136df17265a8c2d22fa1a5c2605a769e117caca182c54ba1`.
- DRS parent receipt:
  `drs_20260730T034536Z_44222028b106d27c`.
- The parent receipt reports local `complete`/verification `passed` and replica
  `complete`; Crucible's six-entry original-lineage set contains the new local
  snapshot ID exactly.
- Permanent installation replaced the qualification unit and is enabled,
  active/waiting, with next activation `2026-07-30 03:00:00 EDT`.
- Credential, state, and component receipts retain no password.

## Known weaknesses

- A missed persistent timer activation runs once when the user manager returns;
  active work fails it closed and there is no retry.
- A stale shared model lease blocks the run until separately reconciled.
- The credential is bound to this user and host installation. Host replacement
  requires fresh enrollment from the recovery password.
- Remote retention and full isolated disaster-recovery rehearsal remain
  separate work.
- Failure notification currently relies on Dashboard/systemd evidence; a
  separate notification integration may improve visibility without changing
  backup authority.

## Human review checklist

```text
[x] Old/rejected password creates no encrypted credential
[x] Current password verifies both repositories before encryption
[x] Qualification timer is approximately two minutes ahead and within the exact 60–300 second bound
[x] Timer fires without an open Dashboard
[x] Service returns to inactive with success
[x] New local snapshot is verified
[x] Exact snapshot lineage exists on Crucible
[x] Parent/component receipts contain no password
[x] No retry, forget, prune, or remote deletion occurs
[x] Permanent timer is exactly 3:00 AM local time
[x] Dashboard shows credential, next run, and last success
[x] Project Timeline closeout is accurate
[x] Merge approval is independent from test success
```

## Human review outcome

```text
Outcome: approved
Reviewer: Operator
Date: 2026-07-29
Decision summary: Live qualification, permanent 3:00 AM activation, documentation, and merge approved.
Required changes: None.
```
