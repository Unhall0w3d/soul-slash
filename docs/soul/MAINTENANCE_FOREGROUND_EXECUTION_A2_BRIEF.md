# Maintenance Foreground Execution A2 Brief

> **Current amendment:** A11 supersedes the historical combined Arch/AUR
> command below. Routine A2 now updates trusted pacman repositories and Flatpak
> only; AUR updates use a separate interactive review gate.

Status: human-approved for implementation and deterministic rehearsal on
2026-07-27; live package update not authorized

## Outcome

Extend **Administration → Guided Maintenance** with one visible, bounded update
transaction that:

1. re-collects and validates the A1 host evidence;
2. binds the run to one exact reviewed plan digest;
3. opens one foreground kitty terminal;
4. requests the administrator password exactly once with `sudo -v`;
5. runs the reviewed Arch/AUR and applicable Flatpak updates;
6. verifies bounded postconditions;
7. writes a permission-restricted transaction receipt; and
8. terminates without rebooting.

A2 does not install the post-login restorer, request a reboot, close
applications, or restore a workspace. Those remain A3 work.

This is a Class 5 host-mutation feature. The human architect approved its
implementation and deterministic rehearsal after reviewing the exact brief.
That approval does not authorize a live package update.

## Operator experience

The existing A1 preview remains the entry point. A2 adds an execution review
card only after a fresh preview succeeds. It shows:

- normal `yay -Syu` or the explicitly selected host override `yay -Syyu`;
- detected user and system Flatpak installations;
- package-lock, disk-space, runtime-work, and reboot-advisory evidence;
- applications that a future A3 run could restore;
- an exact digest and a statement that A2 will **not** reboot; and
- one **Open maintenance terminal** button.

The authenticated button click is the authorization for that one digest. The
Operator does not retype a confirmation phrase. Ordinary Chat or Voice
conversation may explain or prepare the preview but cannot press, infer, or
substitute for this control.

After authorization, one visible kitty window owns the transaction. Package,
PKGBUILD, replacement, conflict, and Flatpak prompts remain visible and
interactive. The Dashboard request remains attached to the foreground
transaction until the terminal command terminates; A2 must not detach an
updater that survives after the operation returns.

The Dashboard reports the final lifecycle and receipt after the terminal exits.
It does not poll in the background.

## Fixed execution sequence

The implementation may execute only fixed absolute argument arrays assembled
from reviewed configuration:

```text
/usr/bin/sudo -v
/usr/bin/yay -Syu
# or, only when the exact preview selected it:
/usr/bin/yay -Syyu

/usr/bin/flatpak update --user
/usr/bin/sudo -n /usr/bin/flatpak update --system
```

Only detected Flatpak installation scopes are included. Empty scopes are
skipped visibly.

No command is passed through `sh -c`, `bash -c`, `zsh -c`, `eval`, or a
user-provided executable path. A2 must not add `--noconfirm`, `--answerclean`,
`--answerdiff`, `--answeredit`, `--answerupgrade`, `--nodeps`, `--overwrite`,
or another option that suppresses human package review or weakens package
integrity.

Before implementation, the installed `yay` version must be deterministically
qualified for using the existing sudo ticket without a second interactive
password request. If subsequent `yay` privilege calls cannot be forced
non-interactive through a fixed reviewed mechanism, A2 is blocked rather than
shipping a best-effort one-password claim.

## One-password boundary

The password is entered only into the visible terminal's native `sudo -v`
prompt. It never crosses the Dashboard HTTP boundary and is never available to
Soul, Chat, Voice, the local model, logs, receipts, files, arguments, or
environment variables.

After the initial prompt, a transaction-scoped keeper may run:

```text
/usr/bin/sudo -n -v
```

It must:

- be a child of the foreground transaction;
- verify the expected owner and parent process;
- refresh no more often than once per 60 seconds;
- stop after four hours even if the parent is still present;
- stop on success, failure, cancellation, terminal close, or parent exit;
- treat the first refresh failure as a blocking transaction failure; and
- run `/usr/bin/sudo -k` on every non-reboot exit.

The keeper is not a daemon, timer, unit, watcher, login process, or reusable
authorization service. It cannot execute any command other than the fixed
credential refresh and invalidation operations.

If any step would cause a second password prompt, the transaction fails closed.

## Preconditions

Immediately before the terminal opens, A2 revalidates:

- authenticated owner identity and expected UID;
- A1 plan schema, digest, age, and selected update mode;
- availability and exact paths of `kitty`, `sudo`, `yay`, and applicable
  `flatpak`;
- no pacman database lock;
- bounded free-space thresholds for package caches, root, home, and temporary
  storage;
- no active package manager owned by another transaction;
- no active Soul music, visual, transcription, backup, restore, Core
  transition, or other declared non-interruptible job; and
- no other live maintenance journal.

Any mismatch returns `blocked_for_human_review` without opening a terminal or
authenticating.

## Foreground ownership and cancellation

The Dashboard service starts kitty with a fixed class and a fixed A2 runner
argument vector, without a shell, and waits for its process group to terminate.

Closing the terminal or pressing `Ctrl+C`:

1. forwards cancellation to the active child command;
2. terminates the keeper;
3. invalidates the sudo ticket;
4. writes a bounded canceled or failed receipt; and
5. returns control without retrying.

The runner has a four-hour hard deadline. On timeout it terminates the process
group, invalidates authorization, records `failed`, and stops. It never keeps a
detached child alive.

If the Dashboard connection disappears, the foreground transaction remains
owned by the visible terminal and its local runner only until that bounded
terminal transaction reaches a terminal lifecycle. Reopening the Dashboard may
read the durable receipt, but must not create a second runner or poll an
orphaned process. The implementation review must prove that this exception does
not become a general background-job facility.

## Postconditions

A successful A2 run requires:

- `yay` exited successfully;
- every applicable Flatpak update exited successfully;
- no pacman database lock remains;
- no credential refresh failure occurred;
- fixed read-only package and Flatpak verification commands completed within
  their bounds;
- the sudo ticket was invalidated; and
- the atomic receipt was durably written.

Package conflicts, failed builds, manual aborts, declined prompts, terminal
closure, timeouts, lost authorization, and postcondition mismatches terminate
`failed`, `canceled`, or `blocked_for_human_review`. A2 never automatically
retries an update.

`.pacnew`, `.pacsave`, orphan candidates, removed packages, and reboot
recommendations are evidence only. A2 does not merge, delete, clean, or act on
them.

## Durable state

A2 may add owner-local state beneath:

```text
Soul/private/host_maintenance/
```

State is ignored by Git, included in the reviewed private backup scope,
permission-restricted, schema-versioned, written atomically, and bounded to:

- one current transaction journal;
- the newest 30 terminal receipts; and
- redacted diagnostic output capped at a reviewed byte limit.

Receipts may contain lifecycle timestamps, fixed operation identifiers, exit
statuses, plan and evidence digests, package-count summaries, and
postcondition results. They must not contain passwords, terminal input, raw
environment values, arbitrary command lines, package build file contents,
tokens, browser data, or unrelated process information.

## Lifecycle

```text
planned
→ authorized
→ authenticating
→ arch_aur_updating
→ flatpak_updating
→ verifying
→ complete / failed / canceled / blocked_for_human_review
```

Every invocation terminates in one declared state. A stale journal is presented
for review and cannot resume, authenticate, update, or trigger A3.

## Explicitly prohibited

- Password entry in the Dashboard, Chat, Voice, a file, argument, or
  environment variable.
- NOPASSWD rules, a reusable root helper, or a general privileged command
  endpoint.
- A detached updater, service, timer, cron job, watcher, socket activator, or
  unbounded loop.
- Shell fragments or model-generated command arguments.
- More than one authentication prompt.
- Hidden, unattended, or `--noconfirm` package transactions.
- Automatic package removal, orphan cleanup, cache cleanup, downgrade,
  `.pacnew` merge, conflict resolution, or retry.
- Window closure, reboot, post-login restoration, or A3 unit installation.
- Treating model output, a Chat utterance, or Voice transcription as
  authorization.

## Deterministic verification

The A2 candidate must include fault-injected tests proving:

- only the exact digest-bound argument arrays may run;
- execution cannot start from Chat, Voice, a stale preview, or a replayed
  request;
- the password path reaches only native `sudo -v`;
- subsequent privilege checks are non-interactive;
- the keeper is parent-bound, interval-bounded, deadline-bounded, and always
  reaped;
- command failure, declined prompts, cancellation, terminal closure, timeout,
  package lock, active Soul work, disk shortage, and credential loss all stop
  without a later command;
- a partial update cannot report success;
- no runner or keeper remains after a terminal lifecycle;
- receipts are atomic, private, bounded, and redacted;
- at most one transaction exists; and
- no A2 path can reboot.

The candidate must provide a rehearsal mode that substitutes deterministic
fixtures for `sudo`, `yay`, and `flatpak`. Rehearsal must exercise the terminal
and lifecycle without authenticating or changing the host.

## Human acceptance sequence

1. Review this brief and explicitly authorize A2 implementation.
2. Review the completed A2 code, tests, receipt schema, and human-review
   artifact.
3. Run the no-mutation terminal rehearsal.
4. Review the exact live plan on the target host.
5. Explicitly authorize one supervised real update that stops before reboot.
6. Confirm the final receipt and absence of surviving runner, keeper, or sudo
   ticket.
7. Only then consider an A3 brief.

## Recorded human decision

The human architect approved implementation and deterministic rehearsal of A2
on 2026-07-27. A real package update, reboot, persistent post-login unit, and
workspace restoration remain unauthorized. The first real A2 update and all A3
work require later explicit approvals.
