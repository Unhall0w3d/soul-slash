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

## Verification

```text
make verify-maintenance-rehearsal
```

Engineering evidence:

- [`MAINTENANCE_REBOOT_RESTORE_A0_BRIEF.md`](../soul/MAINTENANCE_REBOOT_RESTORE_A0_BRIEF.md)
- [`MAINTENANCE_REBOOT_RESTORE_A1_REVIEW.md`](../assessments/MAINTENANCE_REBOOT_RESTORE_A1_REVIEW.md)
