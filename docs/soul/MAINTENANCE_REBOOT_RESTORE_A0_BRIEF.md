# Maintenance, Reboot, and Session Restore A0 Brief

Status: candidate human-authorization brief

## Outcome

Add one bounded, operator-started maintenance transaction that can:

1. assess and preview repository, AUR, and Flatpak updates;
2. open one visible interactive terminal and request the administrator password
   exactly once;
3. run the approved Arch/AUR and Flatpak update sequence;
4. verify that both update legs completed successfully;
5. snapshot restorable Hyprland windows and their workspaces;
6. reboot only when every required postcondition passes; and
7. after SDDM auto-login and Hyprland startup, perform one bounded restoration
   attempt and close the transaction.

This is a Class 5 host-mutation and reboot feature. This brief does not become
authorization until the human architect explicitly approves it.

## Operator experience

Administration exposes **Guided Maintenance**, using fresh Self Assessment
evidence, with:

- a fresh package and reboot assessment;
- the exact update mode and commands;
- expected downloads, foreign/AUR packages, available Flatpak updates, package
  database lock state, free space, `.pacnew`/`.pacsave` guidance, and known
  blockers;
- a restorable-window preview with unsupported or intentionally excluded
  windows called out;
- a clear statement that a successful run will reboot the host automatically;
- one approval control for the exact, digest-bound transaction; and
- live stage, completion, failure, cancellation, and post-login restoration
  status.

Chat and Voice may prepare or explain the same plan. They must not infer
approval from ordinary conversation. Starting it requires the same explicit
dashboard confirmation as Self Assessment.

## Update semantics

### Arch and AUR

The portable default is one coherent full upgrade:

```text
yay -Syu
```

On hosts whose owner-local configuration explicitly enables forced database
refresh, the exact plan may instead use:

```text
yay -Syyu
```

The latter matches the Operator's requested workflow on this machine. `-yy` is
not silently applied as a universal default because it forces database refresh
even when the local databases are current.

Soul must not split the repository and AUR upgrade into invented partial
transactions. It must not add `--noconfirm`, `--nodeps`, `--dbonly`,
`--noscriptlet`, or `--overwrite`. `yay` remains visible and interactive so the
Operator can review package and PKGBUILD prompts.

### Flatpak

Soul detects user and system installations independently:

- user installations run as the desktop owner;
- system installations run through the already-authorized sudo ticket; and
- no second polkit or sudo password prompt is permitted.

Flatpak failure stops the transaction before snapshot and reboot.

## One-authentication contract

Each transaction requests the administrator password exactly once in the
visible maintenance terminal using `sudo -v`.

A transaction-scoped credential keeper may refresh only that existing ticket
with non-interactive `sudo -n -v` calls while the foreground update transaction
is alive. It must:

- be tied to the parent transaction PID;
- run no more often than once per minute;
- have a hard four-hour lifetime;
- never read, store, proxy, log, or replay the password;
- terminate on success, failure, cancellation, terminal close, or parent exit;
- invalidate the transaction ticket on every non-reboot exit; and
- treat any refresh failure as a blocking failure before reboot.

This bounded helper is explicitly authorized only as part of the foreground
maintenance transaction. It is not a daemon, timer, watcher, login service, or
general sudo session.

If a second password would be required for any reason, the transaction fails
closed and does not reboot.

## Window snapshot

After both update legs verify successfully, Soul obtains fresh structured
Hyprland data from `hyprctl` for clients, monitors, workspaces, and the active
workspace. It also inspects process names for the desktop owner so allowlisted
tray-only or otherwise windowless applications are not lost.

The snapshot stores only:

- stable application identity (`initialClass`, `class`, and Flatpak application
  ID where available);
- workspace ID or name and monitor identity;
- floating, fullscreen, pinned, and focus-order hints;
- a display-safe title only when the application restore policy allows it; and
- the matched restore-registry entry and fixed launch argument vector.
- allowlisted background application process identity and
  `launch_if_absent` policy when no Hyprland window represents it.

Soul must not persist arbitrary `/proc/<pid>/cmdline` values, environment
variables, browser URLs, document contents, terminal commands, passwords,
tokens, unmatched process inventories, or other inferred launch arguments.

Restoration uses an owner-local allowlist mapping stable application identities
and approved background process names to fixed argument arrays. A windowless
background application is checked again after login and launched only if it did
not auto-start; Soul must not create a duplicate. Unknown applications, games, transient dialogs,
authentication agents, launchers, and windows without a safe mapping are shown
as **not restorable** and skipped. Browser session recovery remains the
browser's responsibility; Soul launches at most the approved browser instances
and does not reconstruct private tabs or URLs.

The transaction has a maximum of 32 restorable application entries. Duplicate
windows are collapsed according to the per-application policy unless the
Operator explicitly configures a bounded multi-instance rule.

## Reboot gate

The exact dashboard approval authorizes one conditional reboot as part of the
same transaction. Reboot occurs automatically only if:

- the plan digest and owner identity still match;
- `yay` and every applicable Flatpak update returned success;
- package and Flatpak postcondition checks complete;
- no package database lock remains;
- the credential keeper is healthy;
- no Soul creative generation, transcription, backup, restore, Core transition,
  or other declared non-interruptible task is active;
- the final window snapshot is valid and durably written;
- the transaction journal is durably written and bound to the current boot ID;
  and
- logind reports that reboot is permitted.

Failure of any condition terminates `failed` or `blocked_for_human_review`
without rebooting. Soul never retries a reboot automatically.

## One-shot post-login restoration

This brief authorizes one dedicated user-level oneshot resume unit installed by
the normal reviewed setup process. It may run only when a pending,
digest-validated maintenance journal exists.

After SDDM auto-login it:

1. verifies that the boot ID changed exactly once;
2. waits a bounded maximum of 90 seconds for the expected Hyprland session;
3. verifies that the snapshot owner and compositor instance match;
4. launches only fixed restore-registry argument arrays;
5. uses Hyprland workspace/window operations to place matched windows;
6. waits at most 20 seconds and retries at most once per application;
7. restores the previously active workspace last; and
8. closes the journal as `complete`, `failed`, or
   `blocked_for_human_review`.

It never reruns updates, requests privilege, reboots, loops indefinitely, or
keeps a process alive after restoration terminates. Failed and skipped entries
remain visible for manual recovery.

## Durable state and lifecycle

Owner-local state lives beneath:

```text
Soul/private/host_maintenance/
```

It is ignored by Git, included in approved private backup scope, written
atomically, permission-restricted, schema-versioned, and bounded to the most
recent 30 transaction receipts plus the single current journal.

Lifecycle:

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

No lifecycle may remain silently running. A stale `awaiting_login` or
`restoring` journal becomes `blocked_for_human_review`; it never triggers a
later surprise reboot or restoration.

## Explicitly prohibited

- A general-purpose root shell, root-running dashboard, or reusable privileged
  command endpoint.
- Password storage, password forwarding through Chat, Voice, HTTP, files, or
  environment variables.
- NOPASSWD sudo rules.
- Unattended `yay` or PKGBUILD approval.
- More than one authentication prompt per transaction.
- Update or reboot execution from conversational inference.
- Automatic package removal, orphan cleanup, downgrade, `.pacnew` merge, or
  conflict resolution.
- Restoring raw process commands, games, transient dialogs, unknown windows, or
  URLs.
- A daemon, watcher, timer, socket activator, unbounded poller, or repeated
  post-login restoration.
- Continuing to reboot or restore after digest, owner, boot, session, deadline,
  or retry validation fails.

## Implementation slices

### A1 — Plan, registry, and rehearsal

- Add typed schemas for maintenance plans, journals, window snapshots, and the
  restore registry.
- Add fresh read-only preflight and Hyprland snapshot preview.
- Add a dry-run rehearsal that exercises lifecycle and restoration planning
  without sudo, updates, launching applications, or rebooting.
- Add deterministic tests and a review artifact.

### A2 — Visible foreground update transaction

- Add the visible kitty transaction runner and one-authentication keeper.
- Execute only digest-bound, fixed update operations.
- Capture bounded receipts and verify postconditions.
- Stop before reboot in test/rehearsal mode.
- Add fault-injection tests for command, credential, cancellation, timeout, and
  lock failures.

### A3 — Conditional reboot and one-shot restoration

- Add the exact reboot postconditions and single conditional reboot.
- Add the reviewed oneshot user unit and bounded Hyprland restoration.
- Add boot-ID, stale-journal, duplicate-window, unsupported-application, and
  partial-restore tests.
- Perform a human-supervised live acceptance run only after A1 and A2 are
  separately reviewed.

## Acceptance contract

- Deterministic tests prove that no failed, stale, mismatched, or partially
  authorized transaction can reboot.
- Tests prove there is at most one password request and no password persistence.
- Tests prove update commands contain no shell fragments or user-supplied
  executable paths.
- Tests prove snapshots exclude raw command lines, URLs, and environment data.
- Tests prove restoration is allowlisted, bounded, one-shot, and idempotent.
- The dashboard and Chat explain unsupported windows before authorization.
- A non-destructive rehearsal passes on the target Hyprland host.
- A human reviews the exact A3 live transaction before the first real update and
  reboot.

## Human decision required

Approval of this brief authorizes implementation of A1 only. A2 and A3 remain
separate review gates so the read-only rehearsal, privilege boundary, and reboot
restoration can each be inspected before the next risk is introduced.
