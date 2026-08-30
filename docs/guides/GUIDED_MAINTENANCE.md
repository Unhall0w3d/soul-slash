# Guided Maintenance

Guided Maintenance is Soul's reviewed host-administration workflow for trusted
pacman repository and Flatpak updates, separately reviewed AUR updates, and the
distinct gated reboot and one-shot restoration of safely allowlisted Hyprland
applications.

Open it from **Administration → Guided Maintenance**.

## Chat and Voice Presence

Soul can invoke the same fixed device controller from Chat or Voice Presence
when the Operator makes an explicit request such as:

```text
Run maintenance on Crucible.
```

Soul resolves one exact managed device from the current fleet snapshot,
previews that device's existing fixed adapter, and repeats the device label,
address, adapter, and no-reboot boundary. Routine package maintenance on a
non-workstation device then accepts one short-lived conversational
confirmation. A plain maintenance discussion, a status question, or an
ambiguous target does not start the workflow.

The retained confirmation is bound to the exact server-authored digest and
expires after ten minutes. A confirming reply runs only that plan. Completion
returns streamed progress, the device receipt, refreshed fleet evidence,
remaining update count, reboot state, and bounded failure evidence. There is
no automatic retry and no background continuation after the request returns.

Reboot remains separate from maintenance and is never inferred or chained.
For a non-workstation managed device, Soul may prepare one fixed reboot plan
and accept a fresh short-lived conversational confirmation bound to its exact
digest. The controller sends one reboot request, waits for a changed boot
identity, and runs bounded reviewed readiness checks without automatic retry.
Workstation maintenance and reboot remain protected actions: the Operator must
use the Dashboard, a reviewed terminal command, or Noctalia for the final
gesture. Permanent deletion, backup-snapshot deletion,
credential or permission changes, and external publication follow the same
protected-action principle in their owning workflows.

## Infrastructure control plane

The page begins with the newest persisted fleet snapshot for the workstation,
the dynamically discovered Proxmox node, the Pi-hole DNS appliance, Crucible
when enrolled, optional host-local inventory, and status-only appliances configured by the Operator. Deployment-specific
display names (for example, **Warden**) come from ignored local configuration;
the public repository retains stable functional identities and no private
addresses.
Click **Collect fleet status** to replace it with a fresh bounded collection
and inspect:

- device reachability, platform, and versions;
- source-labeled update counts only for package channels actually assessed on
  that device;
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

Integrated inventory cards open in a compact identity-and-status view so mixed
platform evidence does not create an uneven wall of permanently expanded
cards. Click the card or its keyboard-accessible **Details** control to reveal
the full platform, package, kernel, service, security, and action surface;
click again or choose **Collapse** to return it to the compact view. Expansion
is presentation state for the current page session and grants no additional
authority.

Every device card also has **Refresh**. It runs only that device's existing
bounded collector, atomically replaces its card in the private snapshot, and
updates the visible **Checked** timestamp. It does not rescan the subnet or
probe any other fleet member. Status-only appliances use compact cards: IP,
assigned display name, semantic status, and **Refresh** remain primary, while a
small evidence row retains checked time, status-probe state, and network
reachability. Firmware, WAN health, client inventory, and vendor-cloud state
remain unasserted unless a separately reviewed adapter provides that evidence.

### Execution and reconciliation evidence

The **Execution & reconciliation** disclosure joins the latest retained
device-operation receipt with the newest persisted observation for that exact
control target. It intentionally presents two independent facts:

- **execution** is the terminal state written by the bounded operation; and
- **reconciliation** reports whether a newer observation verifies the narrow
  goal, still requires attention, or has not arrived yet.

A successful command is not displayed as verified merely because it exited
zero. Maintenance requires newer reachable, assessed package evidence with no
updates remaining. Reboot requires newer reachable evidence with no remaining
reboot indication; the reboot receipt remains authoritative for its own boot
identity and readiness checks. Unassessed package channels remain unknown.

This A0 projection reads existing snapshots and receipts only. It collects
nothing, changes nothing, and adds no action, schedule, polling loop, agent, or
fleet-wide authority. Older receipts remain retained in their existing
owner-private store; the current-state projection shows only the latest
transaction per device so historical successes are not reinterpreted against
today's package state.

### Optional managed-switch inventory

The managed-switch A1 adapter adds the explicitly configured Netgear GS724Tv4
**Lattice** and Cisco SG300-10 **Loom** as read-only integrated inventory. Each
uses its own owner-private, source-restricted SNMPv2c community to collect
system identity, uptime, installed firmware, available ENTITY-MIB chassis and
boot evidence, and a bounded IF-MIB projection of physical link state, speed,
traffic octets, and cumulative error counters. Each card compares installed
firmware with one operator-reviewed expected version and links to its
credential-free private HTTP management page.

The community never reaches the browser, command arguments, evidence, or Git.
It is supplied over stdin to the owner-private installer and consumed through a
short-lived mode-0600 Net-SNMP configuration:

```bash
wl-paste --no-newline | scripts/soul-configure-lattice-snmp \
  <private-ipv4> <reviewed-firmware> http://<private-management-name>
make verify-managed-switch-snmp-inventory
make lattice-snmp-check

wl-paste --no-newline | scripts/soul-configure-loom-snmp \
  <private-ipv4> <reviewed-firmware> http://<private-management-name>
make verify-managed-switch-snmp-inventory
make loom-snmp-check
```

Both switches remain inventory-only: no SNMP SET, firmware upload, reboot, or
configuration control exists. Traps may be configured on the switches, but
Soul A1 has no trap listener and labels both cards as polling-only.

The card surface is split by actual integration depth. **Integrated inventory**
contains rich managed or inventory-only cards, including supported host-local
adapters. **Status only** contains
compact LAN-presence cards. The two grids are independent, so a short
status-only card never stretches to the height of a managed system beside it.

Card color is evidence-driven: **Healthy** and status-only **Online** are
green, **Updates available** is yellow, and **Offline** or **Reboot required**
is red. Managed hosts and status-only appliances retain different vocabulary;
color does not imply that a status-only appliance has maintenance authority.

Update rows name the assessed source rather than using a generic `native`
label: pacman and applicable AUR/Flatpak channels on Atelier, APT on
Debian/Proxmox systems, and DNF5 on Fedora. Unsupported channels are omitted.
Zero means that the named channel was queried successfully and returned no
updates. A failed query is shown as unavailable, while inventory-only systems
whose updates were not queried say so directly. Detected executables such as
`apt` and `apt-get` are canonicalized into one presentation label; detection
alone never creates update evidence or maintenance authority.

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

This legacy optional card is deliberately fixed-address configuration. It does
not participate in MAC-based retargeting. Use a DHCP reservation if the phone
should retain a stable address. To use Soul's reviewed MAC-tracked DHCP
identity instead, disable this legacy card and enroll the phone once through
fleet discovery as a status-only device with reviewed MAC and subnet evidence;
do not keep both representations enabled. Cisco
documents richer read-only Product Information and Status pages when phone web
access is enabled; Soul does not enable, authenticate to, or retain those pages
in the present supported boundary.

### Optional WinBoat Windows inventory

One existing WinBoat Windows 11 guest can appear as a first-class host-local
identity without becoming a LAN endpoint. Its rich inventory-only card shows
the configured private FQDN and guest address, Docker container state, and
bounded RDP/guest-service reachability. It never receives Maintenance or Reboot
buttons.

The adapter reads only fixed-format Docker state, isolated-network address, and
published-port fields. It never requests the container environment, Compose
configuration, credentials, logs, mounts, Windows content, or guest commands.
Every declared binding must remain on `127.0.0.1`; unexpected exposure fails
closed. No DNS, Docker, Windows, DHCP, route, or firewall setting is changed.

Configure the identity in ignored `.env`:

```text
SOUL_FLEET_CHANCERY_ENABLED=true
SOUL_FLEET_CHANCERY_LABEL=Chancery
SOUL_FLEET_CHANCERY_FQDN=<private logical FQDN>
SOUL_FLEET_CHANCERY_GUEST_ADDRESS=<private WinBoat guest address>
SOUL_FLEET_CHANCERY_CONTAINER_NAME=WinBoat
```

Run `make verify-winboat-inventory` to exercise the deterministic security and
presentation boundary.

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
4. Choose **Status only**, or **Fixed SSH inventory** with a literal OpenSSH
   `Host` alias whose `HostName` is that exact address. If the alias is missing,
   provide the remote account and an existing private key under `~/.ssh`,
   preview the exact fixed stanza, and click **Add reviewed SSH alias**. This
   appends only that stanza to the owner config; it does not copy the public
   key, trust a host key, authenticate, or enroll the device. The target must
   already trust the public key and its host key must already be present in
   `known_hosts`. Status-only enrollment may keep the address fixed or bind it
   to the reviewed MAC and subnet with **DHCP tracked by MAC**. SSH inventory
   remains fixed-address.
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

Enrolled cards are `inventory_only` by default. They can display discovered
capabilities and expose a bounded card-level refresh, but do not expose
Maintenance or Reboot. Detecting a package manager never creates update
authority. A separate adapter must define, test, and receive approval for each
mutation family. Removing a device removes only its local registry record and
sends nothing to the target.

An enrolled fixed-SSH host with reviewed `-pve` kernel evidence and a fixed
`pveversion` executable receives a richer read-only Proxmox projection:
version, cached-metadata APT updates, running and selected kernels, reboot
marker, and bounded LXC/QEMU guest summaries. Its card remains
`inventory_only`; platform recognition never creates Maintain, Reboot, or
guest-control authority.

An explicitly reviewed Foundry deployment may opt one exactly matching enrolled
Proxmox SSH alias into the fixed device controller:

```text
SOUL_FLEET_FOUNDRY_CONTROL_ENABLED=true
SOUL_FLEET_FOUNDRY_SSH_ALIAS=foundry
SOUL_FLEET_FOUNDRY_ADDRESS=foundry
SOUL_FLEET_FOUNDRY_LABEL=Foundry
```

The public default is disabled. The alias must be a literal `Host` entry
already configured with its reviewed identity, key, and host-key policy.
Foundry maintenance runs only fixed APT update and distribution-upgrade
vectors. Reboot sends one request and requires a changed boot identity,
`pveversion`, and active `pveproxy`, `pvedaemon`, and `pvestatd` services.
Every action still requires a fresh Dashboard preview and its exact
device-specific gate; there is no guest mutation, automatic reboot, or retry.
See `docs/soul/FOUNDRY_PROXMOX_CONTROL_A6_BRIEF.md`.

### NixOS laboratory target

Temper was the reproducible NixOS maintenance laboratory used to validate this
adapter. It ran as a full VM so system generations, kernel activation,
guest-agent readiness, and reboot semantics were exercised honestly. The local
lab VM was retired after acceptance; its reusable public deployment material
remains in `deploy/nixos/temper/`. A future NixOS endpoint must be separately
enrolled and qualified, with private addresses, SSH keys, host keys, and fleet
records kept local.

The deployment module installs one immutable
`soul-nixos-maintenance` helper and grants the dedicated
`soul-maintenance` account passwordless access to exactly four complete
helper invocations:

- `self-check`;
- `generation-match`;
- `upgrade`; and
- `reboot`.

`upgrade` updates `/etc/nixos/flake.lock` and performs one
`nixos-rebuild switch --flake /etc/nixos#temper`. If the update or rebuild
fails, the reviewed lock file is restored before the operation terminates.
NixOS still retains its prior system generations for ordinary rollback.
There is no arbitrary command forwarding, unattended timer, automatic
garbage collection, automatic upgrade, or automatic reboot.

After enrolling one exact literal SSH alias, a local deployment may enable the
adapter with ignored environment settings. The historical Temper names below
are examples, not evidence that the retired lab still exists:

```text
SOUL_FLEET_TEMPER_CONTROL_ENABLED=true
SOUL_FLEET_TEMPER_SSH_ALIAS=temper
SOUL_FLEET_TEMPER_ADDRESS=192.168.1.80
SOUL_FLEET_TEMPER_LABEL=Temper
```

The card compares the pinned `nixpkgs` revision with the live
`nixos-26.05` branch and reports one native **Nix** source update when they
differ. This is intentionally not a fabricated package count: NixOS applies
one declarative system generation. A reboot is recommended only when
`/run/current-system` differs from `/run/booted-system`. Exact authority
self-check evidence is required before Maintain or Reboot becomes available.
See `docs/soul/NIXOS_TEMPER_MAINTENANCE_A1_BRIEF.md`.

### Witness Raspberry Pi target

Witness is a Raspberry Pi OS / Debian security telemetry endpoint. Enrollment
alone remains inventory-only. After installing the separately reviewed
root-owned authority, local deployment may enable the adapter with ignored
settings:

```text
SOUL_FLEET_WITNESS_CONTROL_ENABLED=true
SOUL_FLEET_WITNESS_SSH_ALIAS=witness
SOUL_FLEET_WITNESS_ADDRESS=192.168.1.13
SOUL_FLEET_WITNESS_LABEL=Witness
```

The address and literal SSH alias must both match the enrolled record. The card
reports an APT simulation, running kernel, reboot marker, SSH, Wazuh agent, and
authority state. Fixed authority exposes only `self-check`, `apt-upgrade`, and
`reboot`; the helper does not forward request arguments. Its self-check also
proves the image-generated broad cloud-init sudo rule is absent. Maintenance
and reboot still require a fresh preview and exact device-specific gate. Reboot
is separate, never automatic, and must restore SSH, Wazuh, APT, and authority
readiness before the card refreshes. See
`docs/soul/WITNESS_RASPBERRY_PI_MAINTENANCE_A1_BRIEF.md`.

An unsubscribed, non-production Proxmox VE node must use Proxmox's
`pve-no-subscription` repository rather than the authenticated enterprise PVE
or Ceph repositories. For Proxmox VE 9 on Debian 13, the reviewed deb822 source
is:

```text
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
```

Repository selection remains an installation responsibility and is never
changed automatically during enrollment or maintenance. A repository repair
must preserve the prior files, use a separately reviewed host-specific plan,
and stop before package installation. Foundry's initial repair followed that
boundary: the enterprise sources were backed up and disabled, metadata refresh
and a simulated upgrade succeeded, and the real upgrade remained behind a new
Dashboard gate.

If a previously enrolled SSH device suddenly appears offline while still
answering ping, test its literal alias directly. A changed host key is treated
as an identity failure, not ordinary downtime. Verify the new fingerprint
against an independent management path before replacing a dedicated
`known_hosts` entry.

The SSH prerequisite has its own digest-bound gate. It accepts only a portable
literal alias, one account name, the reviewed candidate address, and an
existing mode-`0600` private-key path confined beneath the owner SSH directory.
It cannot accept passwords, key contents, ports, commands, or arbitrary SSH
options. A second, unchanged enrollment preview is always required afterward.

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

The snapshot is private, atomic, and survives Dashboard reloads. When separately
installed, the owner-level oneshot timer collects it at local noon and
midnight. The timer cannot maintain or reboot anything and has no persistent
worker or polling loop. Atelier refreshes official pacman metadata into an
isolated temporary database, queries that database, and deletes it before
returning. The fixed adapter uses `fakeroot`, an alternate `--dbpath`, and
pacman's documented `--disable-sandbox` option because Soul already supplies a
stricter outer systemd sandbox. It never synchronizes pacman's live database or
requires sudo. `yay -Qua` supplies a separate AUR-only count; Flatpak remains a
third independently assessed channel. If the isolated-sync tooling is missing,
Atelier falls back to explicitly cached `pacman -Qu` evidence. Remote APT
counts remain cached because refreshing APT metadata is a privileged
maintenance mutation; DNF5 retains its existing on-demand query. The Dashboard
labels fresh and cached evidence. An offline device remains visible without
hiding evidence from the other devices.

## Device-scoped flow

```text
choose exactly one mutable workstation, Forge, Pi-hole, qualified Crucible, qualified Foundry, or qualified NixOS card
→ choose Maintenance or Reboot
→ inspect the exact device, platform adapter, commands, confirmation, and dependency impact
→ authorize only that digest
→ wait for bounded completion or reconnect verification
→ replace the persisted fleet snapshot
```

There is no fleet-wide maintenance or reboot action.
Status-only appliance cards are inventory and observation surfaces, not action
targets.

The Dashboard presents one `device_scoped_v1` lifecycle across the supported
families. The platform adapter supplies only fixed commands, readiness checks,
and impact evidence:

- `arch_pacman` for the configured workstation;
- `proxmox_apt` for Forge and qualified Foundry nodes;
- `debian_apt_pihole` for the Pi-hole appliance;
- `fedora_dnf5` for qualified Crucible hosts; and
- `nixos_flake` for a separately qualified NixOS host.

Adapter recognition never grants authority. Enrollment and monitoring remain
read-only until the adapter's separately reviewed mutation prerequisites are
satisfied. Once qualified, every family uses the same card, exact preview,
prefilled click authorization, global operation lock, bounded lifecycle,
owner-private receipt, and post-success status recollection. New operating
systems extend this adapter layer rather than creating a new approval flow.

The configured workstation delegates to the reviewed A2 visible-terminal
maintenance path and A3 conditional reboot/restoration path. Forge, qualified
Foundry, and Pi-hole use fixed passwordless maintenance aliases, fixed command
vectors, a global maintenance lock, device-specific confirmation, one attempt,
and redacted receipts. A Forge reboot explicitly discloses that Pi-hole LXC
`100` is interrupted.

Crucible remains inventory-only until its separately reviewed D1 authority
self-check succeeds. Once qualified, its card uses the same digest-bound
device dialog but can call only the root-owned helper's exact `dnf5-upgrade`
or `reboot` operation. The Fedora update never requests a reboot. Crucible
reboot readiness additionally requires SSH, the QEMU guest agent, DNF5,
`/srv/soul-backup`, and the helper self-check. See
[`CRUCIBLE_FEDORA.md`](CRUCIBLE_FEDORA.md).

A NixOS target likewise remains inventory-only until its declarative authority
self-check succeeds. Its update is one fixed flake-and-switch transaction.
Reboot readiness requires SSH, the QEMU guest agent, the exact helper
self-check, and matching active/booted generations. The validated Temper lab
was retired after completing this qualification; it is not a current fleet
member.

Remote maintenance never reboots automatically. A remote reboot records the
old boot identity, sends one reboot request, holds off, performs bounded
reconnect checks, requires a changed boot identity, and then recollects fleet
status. It never retries the reboot request.

If a fixed command fails, the same receipt format records a stable diagnostic
class, a short explanation, and at most 480 bytes of sanitized command output.
The shared classifier covers repository authorization, package-manager locks,
name resolution, storage exhaustion, interrupted package state, network
failure, timeout, and an unclassified nonzero exit. Terminal controls, URL
credentials, and common secret query values are removed before the
owner-private receipt is written. The Dashboard shows this bounded evidence in
the same device dialog; it does not retry, repair, or reinterpret the command.

## Maintenance, Reboot, and Session Restore A1

The former A1, A2, and A3 presentation cards are no longer shown. Their
reviewed backend contracts remain authoritative for the workstation: privacy-filtered
workspace capture, the native desktop handoff, exact package vectors, receipt
bounds, reboot preconditions, and one-shot restoration are unchanged. Native
mode retains one sudo prompt. The separately installed A4 authority may replace
that prompt only with a digest-bound root-owned fixed-operation helper.

## Maintenance Foreground Execution A2

The human-approved A2 contract is documented in
[`MAINTENANCE_FOREGROUND_EXECUTION_A2_BRIEF.md`](../soul/MAINTENANCE_FOREGROUND_EXECUTION_A2_BRIEF.md).
The reviewed implementation provides:

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

## Maintenance Passwordless Authority A4 + AUR Review A11

A4 removes routine trusted-repository and Flatpak questions without storing a
password and without granting passwordless access to pacman, Flatpak,
systemctl, a shell, or an interpreter. A11 removes AUR execution from this
authority entirely. The public default remains:

```text
SOUL_MAINTENANCE_PASSWORDLESS=false
```

The root-owned helper accepts only `repository-update`,
`flatpak-system-update`, or `reboot` plus one opaque maintenance transaction
ID. Its sudoers entry binds the exact helper content by SHA-256 digest. The
repository operation runs target-free `pacman -Syu` (or explicitly selected
`pacman -Syyu`) with `--noconfirm`; Flatpak uses its native `--noninteractive`
system update. The helper contains no yay, makepkg, AUR, package target, caller
path, arbitrary argument, shell, or interpreter surface.

Pending AUR updates remain visible in the A2 plan. **Review pending AUR** opens
a separate native terminal, authenticates at most once, confirms that the
fresh package set still matches the reviewed digest, and runs AUR-only
`yay -Sua`. Clean-build, diff, and PKGBUILD edit menus are forced on while all
saved predetermined answers are unset. The Operator reviews build files,
install scripts, sources, and checksums and may decline, cancel, or close the
terminal. Every outcome invalidates the sudo ticket; there is no retry or
background continuation.

The visible terminal remains an audit and cancellation surface. Package-manager
errors stop the transaction; there is no model-driven prompt answering or
automatic retry. A3 reboot still requires its exact pending restore journal,
but it contains no package or Flatpak command and never repeats maintenance.
The historical combined A2 path completed supervised live acceptance on
2026-07-29. A11 retires its unattended AUR portion; its exact replacement
helper was reviewed, installed, and natively self-checked on 2026-08-02. No AUR
updates were pending, so the first organic interactive review remains an
operational observation rather than a manufactured package test. The distinct
A3 reboot-only path then completed supervised live
acceptance with zero password prompts, empty package-command vectors, and no
package replay. The uniform device-card UX remains human-reviewed at each
transaction.

Review and deployment commands:

```text
make verify-maintenance-passwordless-authority
make verify-maintenance-aur-review-gate
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

## Maintenance Conditional Reboot and Restore A3

A3 is a separate disabled-by-default reboot-only gate. It requires the package
transaction to have ended, rejects any non-empty package, AUR, or Flatpak
command vectors, captures a fresh privacy-filtered restore map, and writes one
boot-bound journal before requesting exactly one reboot. It cannot replay A2
maintenance. The tracked and local default is:

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
places supported windows through Hyprland's typed Lua dispatchers, waits once
for two seconds, reasserts the reviewed placements against the final window
identities, restores the previously active workspace last, writes a terminal
receipt, and consumes the journal. The unit and native handoff use the stable
`/usr/bin/ruby` runtime. Native ChatGPT, Obsidian, and WinBoat use their current
reviewed local classes and fixed launch vectors. Teams for Linux and Steam are
`launch_if_absent` entries: they are recorded only when their window or process
exists before reboot, never launched merely because they are installed, and
never duplicated if autologin already restored them. Steam uses the same
fixed `NO_AT_BRIDGE=1` client launcher as the Operator's desktop entry and does
not include a game URI, so restoring the client cannot implicitly launch a
game. Webex is retained as a `manual_after_login` snapshot record: the restorer
reports it as skipped when absent and never treats its reviewed manual launch as
an orchestration failure.

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

The zero-prompt reboot-only path completed supervised live acceptance again on
2026-08-15 with no package replay or password prompt. All three displays and the
active workspace restored. Steam, Opera GX, Vesktop, and Teams returned; Teams
remained tray-only by design. The native ChatGPT client was reopened manually
after that reboot because its old Codex identity was stale, while Obsidian and
WinBoat exposed previously unsupported contracts. Those exact identities and
launch vectors are now reviewed. Webex remains the accepted manual post-login
exception. Receipts preserve the transaction authority mode and report `0`
password prompts for root-owned passwordless A3 instead of a historical fixed
count.

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
