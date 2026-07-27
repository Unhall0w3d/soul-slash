# Maintenance Desktop Handoff A2B Brief

```text
date: 2026-07-27
human_authorization: approved in the active development conversation
implementation_authorized: yes
desktop-handler installation authorized: only through the reviewed exact gate
live package update authorized: no
reboot authorized: no
risk: Class 5
```

## Objective

Make the merged A2 foreground maintenance transaction testable from the
persistent Dashboard without weakening `soul-dashboard.service`.

The installed Dashboard intentionally uses `NoNewPrivileges=true` and
`PrivateTmp=true`. A child kitty process inherits those restrictions and cannot
perform native `sudo -v`; its private temporary directory also cannot share
fresh `checkupdates` metadata with an ordinary desktop terminal.

A2B therefore adds one user-local `soul-maintenance://` desktop handler. The
authenticated Dashboard reserves an exact short-lived operation. The browser's
Operator click asks the desktop session to launch the registered handler, which
opens one visible kitty window outside the Dashboard service sandbox.

## Authorized vertical slice

- One exact-gated user-local desktop entry for
  `x-scheme-handler/soul-maintenance`.
- One fixed Ruby URI handler and one fixed kitty argument vector.
- No service, daemon, socket, timer, scheduler, watcher, login process, or
  reusable privilege helper.
- One read-only native package-evidence reservation.
- One live A2 transaction reservation, available only when
  `SOUL_MAINTENANCE_A2_LIVE=true`.
- Owner-private reservations, native package evidence, and existing redacted
  A2 receipts under `Soul/private/host_maintenance/`.
- Manual Dashboard receipt refresh after the terminal reaches a terminal
  lifecycle. No client or server polling.
- A portable check/plan/install flow and Makefile targets.

Installing the handler does not enable live A2. The tracked and local default
remain disabled. This brief does not authorize a real package update.

## Read-only evidence flow

```text
Operator clicks Refresh native package evidence
→ Dashboard writes one random opaque reservation with a ten-minute deadline
→ browser opens soul-maintenance://evidence/<id>/<digest>
→ desktop handler atomically claims the exact reservation
→ visible kitty runs bounded checkupdates, yay -Qua, and Flatpak evidence
→ handler writes one owner-private, schema-versioned evidence record
→ terminal exits
→ Operator explicitly reviews A2 again
```

The URI contains only an opaque reservation ID and SHA-256 digest. It contains
no path, command, package name, password, token, environment value, or user
input.

Evidence is accepted only when:

- the reservation and evidence files are regular owner-only files beneath the
  fixed private root;
- schema, owner UID, operation kind, digest, and deadline match;
- the package assessor completed without truncated pacman or AUR evidence;
- the evidence is no older than fifteen minutes; and
- the desktop handler installation exactly matches the reviewed desktop entry.

Stale, missing, malformed, symlinked, replayed, or incomplete evidence blocks
live A2. It never falls back to cached data silently.

## Live transaction handoff

```text
Operator reviews the fresh exact A2 digest
→ Operator clicks Open maintenance terminal
→ Dashboard revalidates and atomically reserves one live transaction
→ browser opens soul-maintenance://transaction/<id>/<digest>
→ desktop handler atomically claims the exact transaction
→ visible kitty runs the merged A2 transaction runner
→ runner writes the existing bounded redacted receipt and exits
→ Operator explicitly clicks Refresh receipt
```

The external-protocol click is the only handoff authority. Chat, Voice, model
output, copied URLs, stale plans, and direct script invocation cannot create a
reservation or authorize execution.

The handler accepts only the exact URI grammar and fixed operation kinds. It
derives all paths from the compiled project root, opens no shell, and passes no
URI text to sudo, yay, Flatpak, or the transaction runner.

## Lifecycle and bounds

Reservations:

```text
reserved → claimed → complete / failed / canceled / expired
```

- Reservation lifetime: ten minutes.
- Native evidence lifetime: fifteen minutes.
- Maximum reservations retained: 16.
- Maximum reservation/evidence file: 512 KiB.
- Only one maintenance operation lock may be held.
- A live reservation must be claimed within ten minutes; after claim, the
  foreground runner retains its independent A2 four-hour execution bound.
- Replays are rejected before kitty or authentication.
- A terminal result never causes automatic reboot, restoration, retry, or a
  second operation.

## Installation boundary

The installer may write only:

```text
~/.local/share/applications/soul-maintenance.desktop
~/.config/mimeapps.list
```

through the standard `update-desktop-database` and `xdg-mime default`
registration flow after exact digest and
`INSTALL_SOUL_MAINTENANCE_HANDOFF` confirmation.

The desktop entry uses:

```text
Exec=<project>/scripts/soul-maintenance-uri %u
MimeType=x-scheme-handler/soul-maintenance;
NoDisplay=true
Terminal=false
```

The handler itself opens kitty with fixed argv. The desktop entry grants no
root authority and survives no process after the visible terminal exits.

## Explicitly prohibited

- Disabling or weakening `NoNewPrivileges`, `ProtectSystem`, authentication,
  CSRF, digest, replay, or active-work gates.
- Putting a password in the Dashboard, URI, file, argv, environment, receipt,
  Chat, Voice, or model context.
- A NOPASSWD rule, polkit rule, setuid helper, transient systemd unit, helper
  service, IPC listener, or detached updater.
- A URI containing a file path, command, package selection, or arbitrary
  argument.
- Automatic browser launch from Chat or Voice.
- Client/server polling for completion.
- Automatic update retry, reboot, workspace restoration, package cleanup, or
  `.pacnew` handling.

## Deterministic verification

The candidate must prove:

- exact desktop entry, MIME handler, URI grammar, and fixed kitty argv;
- wrong, stale, missing, symlinked, malformed, or replayed reservations launch
  no terminal and no package command;
- evidence and live transaction reservations are distinct;
- native evidence is bounded, fresh, owner-private, and content-safe;
- live reservation remains impossible while the typed live flag is false;
- no URI field reaches a command vector;
- no shell, listener, service, watcher, timer, or polling primitive is added;
- fixture handoffs complete with zero sudo calls and zero host mutation;
- the existing A2 command allowlist, one-password, cancellation, receipt, and
  no-reboot regressions continue to pass; and
- the existing protected Dashboard unit remains unchanged.

## Human acceptance

1. Review the A2B candidate and installer plan.
2. Install the exact user-local handler.
3. Run a fixture evidence and fixture transaction handoff.
4. Confirm the handler process and kitty terminate.
5. Confirm live A2 remains disabled.
6. Separately decide whether to arm one supervised live A2 run.
7. Do not begin A3 or authorize reboot from A2B acceptance.
