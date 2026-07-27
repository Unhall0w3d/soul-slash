# Guided Maintenance

Guided Maintenance is Soul's reviewed host-administration workflow for a future
Arch/AUR and Flatpak update, conditional reboot, and one-shot restoration of
safely allowlisted Hyprland applications.

Open it from **Administration → Guided Maintenance**.

## Current reviewed flow

```text
collect fresh Self Assessment evidence
→ choose normal or forced database refresh
→ preview exact inert update commands
→ inspect visible and tray-only application restore decisions
→ simulate the complete lifecycle
→ stop without changing the host
```

Normal mode plans `yay -Syu`. The explicit forced-refresh option plans
`yay -Syyu`. System Flatpak updates are shown as reusing the future
transaction's existing authorization; user installations are planned
separately.

The window map uses structured Hyprland data. A second privacy-filtered process
view accounts for approved tray-only applications such as qBittorrent.
Windowless entries use `launch_if_absent`, meaning a future restorer must first
honor ordinary desktop autostart and never create a duplicate.

## Privacy boundary

The rehearsal stores or displays only the application identity and placement
information needed to explain restoration. It excludes:

- window titles and document names;
- browser URLs and tabs;
- terminal contents;
- raw process arguments and environments;
- unmatched background processes; and
- passwords, tokens, or other credentials.

## What A1 cannot do

A1 cannot:

- request or retain a sudo password;
- run `yay`, `pacman`, or a Flatpak update;
- launch, close, or move an application;
- write an operational maintenance journal;
- request a reboot; or
- install a post-login restoration unit.

A2 foreground execution and A3 reboot/restoration remain distinct
human-review gates.

## A2 foreground candidate

The human-approved A2 contract is documented in
[`MAINTENANCE_FOREGROUND_EXECUTION_A2_BRIEF.md`](../soul/MAINTENANCE_FOREGROUND_EXECUTION_A2_BRIEF.md).
The candidate implementation adds:

- a fresh digest-bound package, disk, active-work, and restore preflight;
- `yay --sudoflags=-n -Syu` or the explicitly selected `-Syyu` variant;
- user Flatpak update as the desktop owner and system Flatpak update through the
  existing non-interactive sudo ticket;
- a visible foreground kitty transaction with a four-hour hard bound;
- one native `sudo -v` prompt, a parent-bound ticket keeper, and guaranteed
  `sudo -k` invalidation;
- redacted owner-private receipts capped at 30; and
- a visible no-mutation terminal rehearsal.

### Native desktop handoff

The installed Dashboard is deliberately confined with `NoNewPrivileges=true`.
It therefore cannot create a child process that authenticates with `sudo`, and
its sandbox cannot refresh pacman metadata reliably. A2B resolves those two
testability blockers without weakening the Dashboard service:

1. **Refresh native evidence** reserves a single-use, ten-minute
   `soul-maintenance://` URL.
2. The desktop opens a visible kitty owned by the logged-in operator.
3. That bounded process performs read-only package checks and records
   owner-private evidence that expires after 15 minutes.
4. Refresh the A2 preview to bind the exact update plan to that evidence.
5. A future enabled live click similarly reserves one single-use URL; package
   commands still begin only after the visible terminal obtains one native
   `sudo -v` authorization.

The URI contains only a typed operation, opaque ID, and SHA-256 digest. It
contains no command, path, password, or shell text. The handler is an XDG
desktop association, not a service, daemon, socket, timer, watcher, or
listener. It is installed through an exact plan:

```text
make maintenance-handoff-plan
make maintenance-handoff-install EXPECTED_DIGEST=<reviewed digest> CONFIRM=INSTALL_SOUL_MAINTENANCE_HANDOFF
make maintenance-handoff-check
```

The public and local default remains `SOUL_MAINTENANCE_A2_LIVE=false`. The live
button stays unavailable until the completed candidate and one supervised run
receive separate authorization. Passwords never enter the Dashboard, `.env`,
receipts, arguments, or model context.

The Dashboard distinguishes fixture-rehearsal blockers from live-only
blockers. A failed package-metadata fetch cannot weaken or enable the live path,
but it does not prevent the zero-command fixture rehearsal from exercising the
visible terminal and receipt lifecycle. The desktop handoff supplies native
evidence while preserving the service sandbox.

A2 always stops before reboot. It cannot install or invoke the A3 post-login
restorer.

## Verification

```text
make verify-maintenance-rehearsal
make verify-maintenance-foreground-execution
make verify-maintenance-desktop-handoff
```

Engineering evidence:

- [`MAINTENANCE_REBOOT_RESTORE_A0_BRIEF.md`](../soul/MAINTENANCE_REBOOT_RESTORE_A0_BRIEF.md)
- [`MAINTENANCE_REBOOT_RESTORE_A1_REVIEW.md`](../assessments/MAINTENANCE_REBOOT_RESTORE_A1_REVIEW.md)
- [`MAINTENANCE_FOREGROUND_EXECUTION_A2_REVIEW.md`](../assessments/MAINTENANCE_FOREGROUND_EXECUTION_A2_REVIEW.md)
- [`MAINTENANCE_DESKTOP_HANDOFF_A2B_BRIEF.md`](../soul/MAINTENANCE_DESKTOP_HANDOFF_A2B_BRIEF.md)
- [`MAINTENANCE_DESKTOP_HANDOFF_A2B_REVIEW.md`](../assessments/MAINTENANCE_DESKTOP_HANDOFF_A2B_REVIEW.md)
