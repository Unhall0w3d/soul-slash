# Guided Maintenance

Guided Maintenance is Soul's reviewed host-administration workflow for
Arch/AUR and Flatpak updates and the later, separately gated conditional reboot
and one-shot restoration of safely allowlisted Hyprland applications.

Open it from **Administration → Guided Maintenance**.

## Infrastructure control plane

The page begins with the newest persisted fleet snapshot for the Maven
workstation, the dynamically discovered Proxmox node, and the Pi-hole LXC.
Click **Collect fleet status** to replace it with a fresh bounded collection
and inspect:

- device reachability, platform, and versions;
- native, AUR, and applicable Flatpak update counts;
- running and available kernel evidence;
- reboot indicators;
- Proxmox LXC `100` state;
- a unified maintenance-channel indicator on every card;
- Pi-hole FTL, Unbound, blocking, and DNS-query health; and
- an evidence-driven architecture map.

The snapshot is private, atomic, and survives Dashboard reloads. The proposed
owner-level oneshot timer collects it at local noon and midnight. The timer
cannot maintain or reboot anything and has no persistent worker or polling
loop. Workstation pacman and remote APT counts use currently cached system
metadata and are labeled as such. An offline device remains visible without
hiding evidence from the other devices.

## Device-scoped flow

```text
choose exactly one Maven, Forge, or Pi-hole card
→ choose Maintenance or Reboot
→ inspect the exact device, commands, confirmation, and dependency impact
→ authorize only that digest
→ wait for bounded completion or reconnect verification
→ replace the persisted fleet snapshot
```

There is no fleet-wide maintenance or reboot action.

Maven delegates to the reviewed A2 visible-terminal maintenance path and A3
conditional reboot/restoration path. Forge and Pi-hole use fixed passwordless
maintenance aliases, fixed command vectors, a global maintenance lock,
device-specific confirmation, one attempt, and redacted receipts. A Forge
reboot explicitly discloses that Pi-hole LXC `100` is interrupted.

Remote maintenance never reboots automatically. A remote reboot records the
old boot identity, sends one reboot request, holds off, performs bounded
reconnect checks, requires a changed boot identity, and then recollects fleet
status. It never retries the reboot request.

## Safety engines retained behind the cards

The former A1, A2, and A3 presentation cards are no longer shown. Their
reviewed backend contracts remain authoritative for Maven: privacy-filtered
workspace capture, the native desktop handoff, exact package vectors, receipt
bounds, reboot preconditions, and one-shot restoration are unchanged. Native
mode retains one sudo prompt. The separately installed A4 authority may replace
that prompt only with a digest-bound root-owned fixed-operation helper.

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
5. An explicitly enabled live click similarly reserves one single-use URL;
   package commands begin only after the visible terminal obtains one native
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

The public and local default remains `SOUL_MAINTENANCE_A2_LIVE=false`. The first
separately authorized supervised live transaction completed on 2026-07-27 and
the local gate was immediately returned to disabled. Future live runs still
require deliberate local arming and an exact Dashboard review. Passwords never
enter the Dashboard, `.env`, receipts, arguments, or model context.

The Dashboard distinguishes fixture-rehearsal blockers from live-only
blockers. A failed package-metadata fetch cannot weaken or enable the live path,
but it does not prevent the zero-command fixture rehearsal from exercising the
visible terminal and receipt lifecycle. The desktop handoff supplies native
evidence while preserving the service sandbox.

A2 always stops before reboot. It cannot install or invoke the A3 post-login
restorer.

## A4 unattended fixed-operation authority candidate

A4 removes the routine password and package questions without storing a
password and without granting passwordless access to yay, pacman, Flatpak,
systemctl, a shell, or an interpreter. The public default remains:

```text
SOUL_MAINTENANCE_PASSWORDLESS=false
```

The root-owned helper accepts only `arch-update`, `flatpak-system-update`, or
`reboot` plus one opaque maintenance transaction ID. It accepts no executable,
package target, path, option, or free-form answer. Its sudoers entry binds the
exact helper content by SHA-256 digest. Yay 13.0.1 receives a fixed,
target-free policy: no clean rebuild, no diff review, no PKGBUILD edit, upgrade
the reviewed set, retain make dependencies, and proceed noninteractively.
Flatpak uses its native `--noninteractive` system update.

The visible terminal remains an audit and cancellation surface. Package-manager
errors stop the transaction; there is no model-driven prompt answering or
automatic retry. A3 reboot still requires its exact pending restore journal.

Review and deployment commands:

```text
make verify-maintenance-passwordless-authority
make maintenance-authority-plan
make maintenance-authority-install EXPECTED_DIGEST=<reviewed digest> CONFIRM=INSTALL_SOUL_MAINTENANCE_AUTHORITY
make maintenance-authority-status
```

Installation itself requests privilege once. After exact installation, the
ignored local `.env` may opt in with
`SOUL_MAINTENANCE_PASSWORDLESS=true`. Any process already running as the
desktop owner can then request the same fixed full-maintenance operation; it
still cannot turn that authority into an arbitrary root command. Remove the
authority with the exact `REMOVE_SOUL_MAINTENANCE_AUTHORITY` Make target gate.

## A3 conditional reboot candidate

A3 is a separate disabled-by-default gate. It reuses the fixed A2 update
vectors, then captures a fresh privacy-filtered restore map and writes one
boot-bound journal before requesting a reboot. The tracked and local default is:

```text
SOUL_MAINTENANCE_A3_LIVE=false
```

The one-shot resume unit is also installed through a separate exact plan:

```text
make maintenance-resume-plan
make maintenance-resume-install CONFIRM=INSTALL_SOUL_MAINTENANCE_RESUME
make maintenance-resume-status
```

Installing the unit does not run it. It exits immediately when no pending
journal exists, has no restart policy or timer, and cannot authenticate, update
packages, or reboot. A valid post-reboot run waits at most 90 seconds for
Hyprland, discovers the owner-controlled compositor socket without relying on
inherited shell variables, revalidates the restore registry, launches only
fixed allowlisted applications, skips already-running background entries,
places supported windows through Hyprland's typed Lua dispatchers, restores the
previously active workspace last, writes a terminal receipt, and consumes the
journal. The unit and native handoff use the stable `/usr/bin/ruby` runtime.

Hosts that require a physical display-link retrain after autologin may provide
one owner-controlled executable:

```text
SOUL_MAINTENANCE_DISPLAY_RECOVERY_SCRIPT=/absolute/path/under/the/operators/home
```

The public default is empty. When configured, the restorer first requests DPMS
on, then runs that exact regular, owner-owned, non-group/world-writable
executable with the discovered Hyprland environment and a 30-second bound.
Failure is recorded for human review; it never broadens the application
restore registry or gains reboot authority.

Chat and Voice may explain the plan but cannot arm or authorize A3. Each live
A3 reboot remains a separate supervised human gate even after deterministic
verification and resume-unit installation.

## Verification

```text
make verify-maintenance-rehearsal
make verify-maintenance-foreground-execution
make verify-maintenance-desktop-handoff
make verify-maintenance-reboot-restore
make verify-maintenance-passwordless-authority
```

Engineering evidence:

- [`MAINTENANCE_REBOOT_RESTORE_A0_BRIEF.md`](../soul/MAINTENANCE_REBOOT_RESTORE_A0_BRIEF.md)
- [`MAINTENANCE_REBOOT_RESTORE_A1_REVIEW.md`](../assessments/MAINTENANCE_REBOOT_RESTORE_A1_REVIEW.md)
- [`MAINTENANCE_FOREGROUND_EXECUTION_A2_REVIEW.md`](../assessments/MAINTENANCE_FOREGROUND_EXECUTION_A2_REVIEW.md)
- [`MAINTENANCE_DESKTOP_HANDOFF_A2B_BRIEF.md`](../soul/MAINTENANCE_DESKTOP_HANDOFF_A2B_BRIEF.md)
- [`MAINTENANCE_DESKTOP_HANDOFF_A2B_REVIEW.md`](../assessments/MAINTENANCE_DESKTOP_HANDOFF_A2B_REVIEW.md)
- [`MAINTENANCE_REBOOT_RESTORE_A3_BRIEF.md`](../soul/MAINTENANCE_REBOOT_RESTORE_A3_BRIEF.md)
- [`MAINTENANCE_REBOOT_RESTORE_A3_REVIEW.md`](../assessments/MAINTENANCE_REBOOT_RESTORE_A3_REVIEW.md)
- [`MAINTENANCE_PASSWORDLESS_AUTHORITY_A4_BRIEF.md`](../soul/MAINTENANCE_PASSWORDLESS_AUTHORITY_A4_BRIEF.md)
- [`MAINTENANCE_PASSWORDLESS_AUTHORITY_A4_REVIEW.md`](../assessments/MAINTENANCE_PASSWORDLESS_AUTHORITY_A4_REVIEW.md)
