# Guided Maintenance

Guided Maintenance is Soul's reviewed host-administration workflow for a future
Arch/AUR and Flatpak update, conditional reboot, and one-shot restoration of
safely allowlisted Hyprland applications.

Open it from **Administration → Guided Maintenance**.

## Current A1 flow

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

The public and local default is `SOUL_MAINTENANCE_A2_LIVE=false`. The live
button stays unavailable until the completed candidate and one supervised run
receive separate authorization. Passwords never enter the Dashboard, `.env`,
receipts, arguments, or model context.

The Dashboard distinguishes fixture-rehearsal blockers from live-only
blockers. A failed package-metadata fetch or a service sandbox that sets
`NoNewPrivileges` cannot weaken or enable the live path, but they do not prevent
the zero-command fixture rehearsal from exercising the visible terminal and
receipt lifecycle. On the current reference host, both conditions remain
visible live blockers pending a separately reviewed deployment decision.

A2 always stops before reboot. It cannot install or invoke the A3 post-login
restorer.

## Verification

```text
make verify-maintenance-rehearsal
make verify-maintenance-foreground-execution
```

Engineering evidence:

- [`MAINTENANCE_REBOOT_RESTORE_A0_BRIEF.md`](../soul/MAINTENANCE_REBOOT_RESTORE_A0_BRIEF.md)
- [`MAINTENANCE_REBOOT_RESTORE_A1_REVIEW.md`](../assessments/MAINTENANCE_REBOOT_RESTORE_A1_REVIEW.md)
- [`MAINTENANCE_FOREGROUND_EXECUTION_A2_REVIEW.md`](../assessments/MAINTENANCE_FOREGROUND_EXECUTION_A2_REVIEW.md)
