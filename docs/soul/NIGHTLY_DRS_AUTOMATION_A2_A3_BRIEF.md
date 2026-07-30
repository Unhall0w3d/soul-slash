# Nightly DRS Automation A2/A3 Brief

Status: Operator-approved implementation on 2026-07-29; live two-minute
qualification and human review required before permanent 3:00 AM activation

## Objective

Deploy the accepted Nightly DRS A1 transaction as one hardened, bounded
systemd user `oneshot` backed by one user-scoped, host-encrypted credential.
Qualify the deployment with a single timer scheduled two minutes ahead, prove
the resulting local snapshot and exact Crucible lineage, and only then replace
the qualification timer with the permanent 3:00 AM schedule.

## Approved behavior

- Reuse `BackupAdministrationService#drs_preview` and `#drs_execute`.
- Read the Restic password only from a systemd credential made available in
  `$CREDENTIALS_DIRECTORY`.
- Enroll that credential interactively in a local terminal with echo disabled.
- Before encryption, prove the supplied password opens both the current local
  repository and the independently encrypted Crucible repository. A rejected
  password must not create or replace an encrypted credential.
- Encrypt it with `systemd-creds --user --with-key=host`; no plaintext
  credential file may be created.
- Install one exact `soul-nightly-drs.service` and one exact
  `soul-nightly-drs.timer`.
- Permit one qualification schedule between 60 and 300 seconds in the future.
- Require a complete qualification run before permanent activation.
- Set the permanent timer to `03:00:00` in the host's local timezone.
- Use `Persistent=true`; a missed run may execute once after the user manager
  returns, but the existing active-work and nonblocking backup locks still
  fail closed.
- Retain bounded owner-private start and terminal run state, plus the existing
  component and DRS receipts.
- Surface credential, unit, schedule, next-run, last-run, and last-success
  evidence in Administration → Backup & Recovery.

## Authority and safety boundary

- Credential enrollment, qualification installation, permanent activation,
  and removal each require their own exact confirmation.
- Preview digests bind the exact unit text, timer text, mode, and schedule.
- The qualification timer cannot be promoted merely because it fired; its
  latest run must be `complete`, and the referenced parent receipt must
  independently match the local snapshot, local verification, and exact
  Crucible lineage.
- The unit explicitly uses the reviewed owner SSH configuration already
  enforced by Backup Administration.
- Existing checks continue to reject invalid mounts, unavailable sources,
  active creative/model work, concurrent backup operations, invalid local or
  remote repository identity, rejected credentials, and incomplete Crucible
  lineage.
- The service has no restart policy. The transaction performs no retry.
- Restic receives one owner-private, systemd-managed cache directory; the
  remainder of the home directory stays read-only to the service.
- Local and remote `forget`, `prune`, and deletion remain unavailable.
- The encrypted credential is preserved on service/timer removal unless the
  Operator invokes the separate credential-removal confirmation.

## Bounded lifecycle

Each invocation terminates as `complete`, `failed`, `awaiting_input`,
`canceled`, or `blocked_for_human_review`. One run performs at most one local
capture and one Crucible reconciliation attempt.

The systemd service has a four-hour hard deadline, no restart, no queue, no
watcher, and no resident process. The timer is the only approved background
activation.

## Qualification sequence

1. Preview and enroll the encrypted credential locally.
2. Preview an exact run time two minutes ahead.
3. Install and arm the qualification timer.
4. Confirm the timer fired and the service returned to inactive.
5. Confirm a new local snapshot, complete DRS parent receipt, and matching
   Crucible lineage.
6. Preview and activate the permanent 3:00 AM timer.
7. Confirm the next scheduled activation and Dashboard evidence.

Any qualification failure leaves the permanent activation gate blocked.

## Human review

Tests make this candidate-complete only. Live qualification, permanent
activation, repository evidence, unit hardening, credential handling,
documentation, and project-timeline closeout remain subject to Operator review.
