# Maintenance Conditional Reboot and Restore A3 Brief

Status: human-approved for implementation and deterministic rehearsal on
2026-07-27; amended by the Operator's separate Maintain/Reboot authority
decision on 2026-07-29 and the accepted natural-reboot refinement on 2026-08-15

## Outcome

Extend **Administration → Guided Maintenance** with one separately disabled,
digest-bound A3 transaction that records a fresh privacy-filtered Hyprland
snapshot, requests one conditional reboot, and performs one bounded post-login
restoration attempt.

A3 must not weaken or replace A2. The existing A2 live-update path remains a
non-rebooting operation with its own disabled-by-default gate. The 2026-07-29
Operator decision further separates these actions: A3 must not replay A2
package or Flatpak commands. **Maintain** updates; **Reboot** captures,
reboots, and restores.

## Authority boundary

- The tracked and local default is `SOUL_MAINTENANCE_A3_LIVE=false`.
- Chat and Voice may explain A3 but cannot arm or authorize it.
- One authenticated Dashboard click may authorize only the exact reviewed
  digest.
- Native-prompt mode may request the administrator password only through the
  visible desktop terminal. The separately reviewed root-owned passwordless
  authority records zero password prompts and exposes no credential surface.
- Implementing, installing, or rehearsing A3 does not authorize a live reboot.
- The first live reboot requires a later, explicit, human-supervised approval.

## Foreground transaction

The A3 terminal binds current A2-derived host, disk, lock, active-work, and
native evidence as conservative preflight input, but executes no package
command. It:

1. verifies no package lock or declared Soul non-interruptible work remains;
2. captures a fresh allowlisted Hyprland snapshot;
3. verifies the current boot ID and the installed one-shot resume unit;
4. verifies logind reports reboot available;
5. writes one owner-private, digest-bound pending journal;
6. requests reboot once with `/usr/bin/sudo -n /usr/bin/systemctl reboot`; and
7. invalidates the transaction sudo ticket.

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
- performs one bounded two-second settle and final placement reassertion to
  resolve known application/compositor startup races;
- records reviewed manual-after-login applications as skipped rather than
  launching them or failing the complete orchestration;
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
- native-prompt mode permits at most one password prompt, while reviewed
  root-owned passwordless mode truthfully records zero;
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
