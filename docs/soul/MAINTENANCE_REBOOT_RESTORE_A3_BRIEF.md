# Maintenance Conditional Reboot and Restore A3 Brief

Status: human-approved for implementation and deterministic rehearsal on
2026-07-27; live reboot not authorized

## Outcome

Extend **Administration → Guided Maintenance** with one separately disabled,
digest-bound A3 transaction that can continue the reviewed A2 update sequence,
record a fresh privacy-filtered Hyprland snapshot, request one conditional
reboot, and perform one bounded post-login restoration attempt.

A3 must not weaken or replace A2. The existing A2 live-update path remains a
non-rebooting operation with its own disabled-by-default gate.

## Authority boundary

- The tracked and local default is `SOUL_MAINTENANCE_A3_LIVE=false`.
- Chat and Voice may explain A3 but cannot arm or authorize it.
- One authenticated Dashboard click may authorize only the exact reviewed
  digest.
- The visible desktop terminal remains the only place `sudo -v` may request the
  administrator password.
- Implementing, installing, or rehearsing A3 does not authorize a live reboot.
- The first live reboot requires a later, explicit, human-supervised approval.

## Foreground transaction

The A3 terminal revalidates and executes only the fixed A2 update vectors. It
then:

1. verifies every update command completed;
2. verifies no package lock or declared Soul non-interruptible work remains;
3. captures a fresh allowlisted Hyprland snapshot;
4. verifies the current boot ID and the installed one-shot resume unit;
5. verifies logind reports reboot available;
6. writes one owner-private, digest-bound pending journal;
7. requests reboot once with `/usr/bin/sudo -n /usr/bin/systemctl reboot`; and
8. invalidates the transaction sudo ticket.

Any failed or stale postcondition stops without reboot. There is no automatic
retry.

## One-shot resume unit

The reviewed setup flow may install and enable
`soul-maintenance-resume.service` as an owner-level `Type=oneshot` unit. It:

- exits immediately when no pending journal exists;
- never authenticates, updates packages, or reboots;
- requires the boot ID to differ from the journal's source boot exactly once;
- waits at most 90 seconds for a Hyprland session;
- revalidates the current restore registry and fixed launch vectors;
- launches at most 32 allowlisted records with one retry per record;
- skips an already-running allowlisted background application;
- restores workspace and supported window-state hints with fixed `hyprctl`
  argument vectors;
- restores the previously active workspace last;
- writes a terminal receipt and consumes the pending journal; and
- exits `complete`, `failed`, or `blocked_for_human_review`.

The unit has no restart policy, timer, watcher, socket, or persistent process.

## Durable state

Owner-private A3 state remains below:

```text
Soul/private/host_maintenance/
```

The single `pending_restore.json` journal is mode `0600`, schema-versioned,
digest-protected, owner-bound, boot-bound, and expires after 30 minutes. A
terminal copy moves into the bounded journal archive. Receipts remain capped at
30.

The snapshot stores no window titles, URLs, raw command lines, terminal
contents, environments, passwords, or tokens.

## Lifecycle

```text
planned
→ authorized
→ authenticating
→ updates_running
→ updates_verified
→ snapshot_recorded
→ reboot_requested
→ awaiting_login
→ restoring
→ complete / failed / canceled / blocked_for_human_review
```

No A3 process waits for future human input. A stale or mismatched journal fails
closed and is never retried on a later login.

## Deterministic acceptance

Tests must prove:

- A2 remains incapable of reboot;
- A3 is disabled by default and unavailable without the exact resume unit;
- failed updates, package locks, active work, stale evidence, digest mismatch,
  same-boot journals, stale journals, registry mismatch, and unavailable
  reboot permission cannot request reboot;
- the reboot vector and every restored launch vector are fixed and shell-free;
- only one password prompt is possible;
- pending state is durably written before the reboot request;
- restoration is one-shot, bounded, idempotent, and skips duplicates;
- unsupported applications remain visible and unlaunched;
- terminal state and redacted receipts survive partial restoration; and
- the Dashboard exposes no password field, polling loop, Chat authority, or
  live A3 button unless the local gate and all preconditions are satisfied.

## Explicitly out of scope

- Saving application-internal unsaved work.
- Reconstructing browser tabs, URLs, documents, or terminal commands.
- Restoring games, unknown applications, transient dialogs, or raw process
  command lines.
- Automatically resolving package prompts, `.pacnew` files, conflicts,
  orphans, or failed AUR builds.
- More than one reboot, a reboot retry, or restoration on an unrelated later
  boot.
- Installing the resume unit or performing a live reboot without later exact
  human approval.
