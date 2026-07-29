# Guided Maintenance

Guided Maintenance is Soul's reviewed host-administration workflow for
Arch/AUR and Flatpak updates and the later, separately gated conditional reboot
and one-shot restoration of safely allowlisted Hyprland applications.

Open it from **Administration → Guided Maintenance**.

## Infrastructure control plane

The page begins with the newest persisted fleet snapshot for the workstation,
the dynamically discovered Proxmox node, the Pi-hole DNS appliance, Crucible
when enrolled, and optional status-only appliances configured by the Operator. Deployment-specific
display names (for example, **Warden**) come from ignored local configuration;
the public repository retains stable functional identities and no private
addresses.
Click **Collect fleet status** to replace it with a fresh bounded collection
and inspect:

- device reachability, platform, and versions;
- native, AUR, and applicable Flatpak update counts;
- running and available kernel evidence;
- reboot indicators;
- Proxmox LXC `100` state;
- a unified maintenance-channel indicator on every card;
- Pi-hole FTL, Unbound, blocking, and DNS-query health; and
- an evidence-driven local network map.

The map follows the host's current kernel route evidence instead of a
deployment-specific address embedded in public source:

**WAN / provider cloud → default gateway → local subnet → known devices**

The detected interface and subnet are shown at the LAN boundary. When the
gateway is already enrolled, that reviewed device supplies its identity and
status; otherwise the map renders an inert route-evidence node and does not
claim reachability. Management, containment, DNS, provider, inventory, and
planned backup relationships remain available beneath the primary route flow
as supplemental operational context. If route evidence is unavailable or
malformed, the map keeps known devices visible and labels the route boundary
unavailable rather than inventing topology.

Every device card also has **Refresh**. It runs only that device's existing
bounded collector, atomically replaces its card in the private snapshot, and
updates the visible **Checked** timestamp. It does not rescan the subnet or
probe any other fleet member. Status-only appliances use compact cards: IP,
assigned display name, semantic status, and **Refresh** remain primary, while a
small evidence row retains checked time, status-probe state, and network
reachability. Firmware, WAN health, client inventory, and vendor-cloud state
remain unasserted unless a separately reviewed adapter provides that evidence.

The card surface is split by actual integration depth. **SSH integrated**
contains rich managed or inventory-only Linux cards. **Status only** contains
compact LAN-presence cards. The two grids are independent, so a short
status-only card never stretches to the height of a managed system beside it.

Card color is evidence-driven: **Healthy** and status-only **Online** are
green, **Updates available** is yellow, and **Offline** or **Reboot required**
is red. Managed hosts and status-only appliances retain different vocabulary;
color does not imply that a status-only appliance has maintenance authority.

### Optional Apple mobile inventory

An enrolled DHCP-tracked iPhone can gain a bounded wired inventory projection
after its first exact match between the private Wi-Fi MAC reviewed during
enrollment and the current-network identity reported by the same unlocked,
trusted phone over USB.

Install `usbmuxd` and `libimobiledevice` through the host distribution. On
Arch-family systems:

```bash
sudo pacman -S usbmuxd libimobiledevice
make apple-mobile-inventory-check
```

Connect the phone with a data-capable cable, accept Apple's **Trust This
Computer** prompt, keep it unlocked, and select **Refresh** on its fleet card.
Soul retains only device name, product type, iOS/build, architecture, and a
small battery/charging projection. UDID, serial, IMEI, phone number, accounts,
applications, files, pairing material, and raw command output are not returned
or persisted.

Once the exact match succeeds, the private registry remembers only that this
record uses the `apple_mobile` inventory adapter. Later refreshes without the
cable preserve truthful LAN status and report wired inventory as unavailable.
The adapter never waits for unlock or trust and never changes phone settings.

`netmuxd` is not required. Network iPhone inventory remains unsupported until a
separate reviewed adapter can prove a reliable paired Wi-Fi session without a
persistent daemon or listener.

An optional Cisco 8851/Webex Calling card is deliberately narrower. It proves
only bounded network reachability and displays the configured device identity,
provider-owned lifecycle, and topology relationship. Reachability does not
assert Webex registration, call readiness, firmware currency, or line state.
The phone never receives Maintenance or Reboot buttons.

Configure it in ignored `.env`:

```text
SOUL_FLEET_CISCO_PHONE_ENABLED=true
SOUL_FLEET_CISCO_PHONE_ADDRESS=<reserved IPv4 address or hostname>
SOUL_FLEET_CISCO_PHONE_LABEL=Cisco 8851
```

Use a DHCP reservation if the phone should retain a stable address. Cisco
documents richer read-only Product Information and Status pages when phone web
access is enabled; Soul does not enable, authenticate to, or retain those pages
in this slice.

## Portable discovery and enrollment

Open **Discover & enroll a device** to extend the local inventory without
editing public source:

1. Enter one explicit RFC1918 IPv4 subnet from `/24` through `/32`.
2. Click **Scan subnet**. Soul runs one 30-second-bounded `nmap` host-discovery
   pass. Already configured or enrolled addresses are counted and excluded;
   only unenrolled addresses appear as candidates. The candidate list remains
   in the current page session and is not persisted. Soul also reads the local
   kernel ARP table once and shows ephemeral MAC, OUI vendor, interface,
   and neighbor-state hints when available. These hints can narrow a device
   family but do not prove device identity.
3. Select one candidate. A reachable address is untrusted until this explicit
   review.
4. Choose **Status only**, or **Fixed SSH inventory** with an existing literal
   OpenSSH `Host` alias whose `HostName` is that exact address. Status-only
   enrollment may keep the address fixed or bind it to the reviewed MAC and
   subnet with **DHCP tracked by MAC**. SSH inventory remains fixed-address.
5. Preview the exact record. SSH inventory reads a bounded hostname, kernel,
   OS projection, and independently tests fixed executable paths for pacman,
   yay, paru, apt, apt-get, dnf, zypper, apk, Flatpak, Snap, and Nix.
6. Click **Enroll reviewed device**. The click authorizes one digest-bound
   write to the owner-private registry. The enrolled address leaves the
   current candidate list while every unacted-on result remains available for
   sequential review. Removing an enrolled record also preserves that current
   list; scan again only when you want fresh discovery evidence or need the
   removed device to reappear as a candidate.

Use **Ignore** when an address should not remain in the candidate queue. The
exact reviewed identity is stored privately, matched by MAC when available and
IP otherwise. Only that candidate leaves the current list; the remaining scan
results stay actionable. The identity remains visible and reversible in
**Ignored devices**. **Restore** removes only that exclusion, preserves the
current candidate list, and lets the restored identity appear in a later
explicit scan.

After a successful scan, Soul remembers only the canonical subnet in an
owner-private `0600` preference file and refills the field on the next page
load. Candidate addresses, MACs, vendors, and scan results remain ephemeral.

Enrolled cards are `inventory_only`. They can display discovered capabilities
and expose a bounded card-level refresh, but do not expose Maintenance or
Reboot. Detecting a package manager never creates update authority. A separate
future adapter must define, test, and receive approval for each mutation
family. Removing a device removes only its local registry record and sends
nothing to the target.

For a DHCP-tracked status-only card, Soul compares the recorded address's ARP
identity with the reviewed MAC. A mismatch or unavailable address triggers one
bounded scan of the reviewed subnet. Exactly one MAC match retargets only the
private status record and appends a bounded address-history event. Zero or
multiple matches do not retarget. One transient user-level oneshot retries ten
minutes later; a second miss terminates recovery until the next manual or
noon/midnight collection. There is no sleeper, daemon, repeating ten-minute
timer, or background polling loop. Devices on the same subnet share one
recovery scan per invocation, and a collection will scan at most four distinct
reviewed subnets.

Public bootstrap and troubleshooting:

```text
make fleet-discovery-check
make fleet-discovery-scan FLEET_SUBNET=192.168.1.0/24
make verify-maintenance-fleet-discovery
make verify-maintenance-fleet-dhcp-identity
make verify-apple-mobile-fleet-inventory
```

`nmap` is the only optional discovery dependency. Install it with the host's
normal package manager if the check reports it missing, then use the
authenticated Dashboard for enrollment. The CLI scan is deliberately
non-persisting and is useful for setup validation. Subnets, addresses, SSH
aliases, discovered candidates, and enrollment records never belong in the
public repository.

Automatic reverse-DNS or mDNS resolution is intentionally omitted: unresolved
LAN names can consume the full resolver timeout for little evidence. A future
explicit per-candidate inspection can add bounded service fingerprinting when
neighbor and vendor hints are insufficient.

The snapshot is private, atomic, and survives Dashboard reloads. The proposed
owner-level oneshot timer collects it at local noon and midnight. The timer
cannot maintain or reboot anything and has no persistent worker or polling
loop. Workstation pacman and remote APT counts use currently cached system
metadata and are labeled as such. An offline device remains visible without
hiding evidence from the other devices.

## Device-scoped flow

```text
choose exactly one mutable workstation, Forge, Pi-hole, or qualified Crucible card
→ choose Maintenance or Reboot
→ inspect the exact device, commands, confirmation, and dependency impact
→ authorize only that digest
→ wait for bounded completion or reconnect verification
→ replace the persisted fleet snapshot
```

There is no fleet-wide maintenance or reboot action.
Status-only appliance cards are inventory and observation surfaces, not action
targets.

The configured workstation delegates to the reviewed A2 visible-terminal maintenance path and A3
conditional reboot/restoration path. Forge and Pi-hole use fixed passwordless
maintenance aliases, fixed command vectors, a global maintenance lock,
device-specific confirmation, one attempt, and redacted receipts. A Forge
reboot explicitly discloses that Pi-hole LXC `100` is interrupted.

Crucible remains inventory-only until its separately reviewed D1 authority
self-check succeeds. Once qualified, its card uses the same digest-bound
device dialog but can call only the root-owned helper's exact `dnf5-upgrade`
or `reboot` operation. The Fedora update never requests a reboot. Crucible
reboot readiness additionally requires SSH, the QEMU guest agent, DNF5,
`/srv/soul-backup`, and the helper self-check. See
[`CRUCIBLE_FEDORA.md`](CRUCIBLE_FEDORA.md).

Remote maintenance never reboots automatically. A remote reboot records the
old boot identity, sends one reboot request, holds off, performs bounded
reconnect checks, requires a changed boot identity, and then recollects fleet
status. It never retries the reboot request.

## Safety engines retained behind the cards

The former A1, A2, and A3 presentation cards are no longer shown. Their
reviewed backend contracts remain authoritative for the workstation: privacy-filtered
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

**Collect fleet status** and the workstation's native evidence serve different
purposes. Fleet collection inventories cached workstation and remote device
state. Selecting **Maintain** or **Reboot** on the workstation now collects a
fresh device-scoped preview and, when native package evidence is stale or
missing, opens one visible read-only evidence handoff automatically. A bounded
Dashboard poll rechecks that evidence for at most two minutes and then presents
the exact reviewed action. The approval phrase is prefilled and read-only:
clicking the final action button is the human authorization.

For **Maintain**, the visible terminal remains the authoritative foreground
transaction. The Dashboard follows only its exact transaction ID for at most
30 minutes. When its retained receipt completes, the fleet card refreshes
automatically. Maintenance never infers, requests, or chains a reboot. If
current evidence reports a reboot requirement, **Reboot** remains a distinct
card action with a new preview, digest, restore journal, and approval click.
Closing the dialog stops its browser-side polling without canceling or
backgrounding the terminal-owned operation.

A2 always stops before reboot. It cannot install or invoke the A3 post-login
restorer. Its package-only approval digest therefore does not bind the current
window/workspace restoration inventory; closing the evidence terminal does not
invalidate the reviewed update plan. A3 captures and binds its own fresh
restore state separately before reboot.

## A4 unattended fixed-operation authority

A4 removes the routine password and package questions without storing a
password and without granting passwordless access to yay, pacman, Flatpak,
systemctl, a shell, or an interpreter. The public default remains:

```text
SOUL_MAINTENANCE_PASSWORDLESS=false
```

The root-owned helper accepts only `arch-update`, `flatpak-system-update`, or
`reboot` plus one opaque maintenance transaction ID. Its sudoers entry binds
the exact helper content by SHA-256 digest. Yay 13.0.1 runs as the qualified
desktop user because AUR packages must not be built as root, and receives a
fixed, target-free policy: no clean rebuild, no diff review, no PKGBUILD edit,
upgrade the reviewed set, retain make dependencies, and proceed
noninteractively. During that exact active operation, yay's pacman calls return
through a helper bridge bound to its recorded PID/start identity. The bridge
permits only a short bounded chain of exact sudo monitor processes before that
recorded yay identity, and rejects removal, database operations, alternate
roots/configuration paths, and non-pacman execution. The public surface still
accepts no executable, package target, path, option, or free-form answer.
Flatpak uses its native `--noninteractive` system update.

The visible terminal remains an audit and cancellation surface. Package-manager
errors stop the transaction; there is no model-driven prompt answering or
automatic retry. A3 reboot still requires its exact pending restore journal,
but it contains no package or Flatpak command and never repeats maintenance.
The package-only A2 path completed supervised live acceptance on 2026-07-29:
Arch/AUR and system Flatpak both completed with zero password prompts and no
reboot request. A3 zero-prompt reboot/restoration acceptance remains separate.
The uniform device-card UX is deterministic-test complete; its separate live
workstation reboot acceptance is intentionally left to the Operator.

Review and deployment commands:

```text
make verify-maintenance-passwordless-authority
make verify-maintenance-fleet-discovery
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
The workstation's reviewed registry includes Webex and Teams for Linux as
`launch_if_absent` entries: they are recorded only when their window or process
exists before reboot, never launched merely because they are installed, and
never duplicated if autologin already restored them.

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
- [`PORTABLE_FLEET_DISCOVERY_A1_BRIEF.md`](../soul/PORTABLE_FLEET_DISCOVERY_A1_BRIEF.md)
- [`PORTABLE_FLEET_DISCOVERY_A1_REVIEW.md`](../assessments/PORTABLE_FLEET_DISCOVERY_A1_REVIEW.md)
