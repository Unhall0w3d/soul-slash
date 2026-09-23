# Maintenance Platform Adapter Registry A12 Brief

```text
date: 2026-09-02
human_authorization: approved in the active Omarchy recovery conversation
implementation_authorized: yes
live_execution_authorized: no; adapter candidate and deterministic review first
risk: Class 5 architecture supporting read-only fleet status and separately gated mutation
```

## Objective

Preserve Soul's generic CachyOS and Arch maintenance behavior while adding an
Omarchy-specific workstation adapter and normalizing fleet devices onto shared
platform adapters. Hosts must not receive bespoke mutation vectors merely
because they have different names.

The first candidate slice is read-only. It introduces one registry, routes the
local workstation through it, and exposes enough evidence to review later
mutation and reboot work without enabling any gate.

## Adapter families

| Adapter | Platforms | Status contract | Future mutation contract |
| --- | --- | --- | --- |
| `omarchy` | Omarchy on Arch | Arch package managers plus Omarchy version, pending migrations, and Omarchy restart/reboot state | reviewed Omarchy update stages; AUR remains a separate visible review |
| `arch` | Arch Linux, CachyOS, and compatible derivatives | discovered pacman, AUR helper, Flatpak, kernel, and reboot evidence | generic package-manager transaction with no distro-specific assumptions |
| `proxmox_apt` | Debian with Proxmox VE | APT plus Proxmox kernel, guest, and service evidence | fixed Proxmox APT maintenance and separate reboot |
| `debian_apt` | Debian-family hosts | APT, kernel, reboot marker, and service evidence | fixed Debian APT authority and separate reboot |
| `fedora_dnf5` | Fedora hosts | DNF5, kernel, and reboot evidence | fixed DNF5 authority and separate reboot |
| `nixos_flake` | NixOS hosts | flake revision, generation, service, and reboot evidence | fixed declarative flake authority and separate reboot |
| read-only appliance adapters | Windows/WinBoat, ASUSWRT-Merlin, managed switches, phones, mobile and network appliances | platform-specific bounded inventory | none unless a later human brief grants it |

Forge and Foundry therefore share `proxmox_apt`. Warden, Observatory, Vigil,
and ordinary Debian guests share `debian_apt` unless a more specific reviewed
role adapter is required. Host labels and readiness checks may add bounded
role-specific evidence without changing the underlying package adapter.

## Local Omarchy status

Omarchy is identified from bounded `/etc/os-release` fields. The adapter may
reuse Arch package evidence because Omarchy is Arch-based, but must additionally
collect:

- `omarchy version`;
- `omarchy migrate --pending` with its documented zero/pending exit contract;
- owner-local Omarchy reboot and restart marker names, never their contents;
- presence and executable status of the documented `omarchy` entrypoint.

The status path is foreground, bounded, read-only, and has no background
polling. It must not run `omarchy update`, refresh package metadata through a
mutating package database, start a service, or clear an Omarchy state marker.

## Future Omarchy mutation boundary

The later mutation slice must use documented Omarchy command surfaces and
retain Soul's existing preview digest, authenticated confirmation, visible
terminal, cancellation, receipt, and lifecycle gates. It must not simply call
full `omarchy update -y`, because the current Omarchy AUR stage invokes
`yay -Sua --noconfirm`, while Soul A11 requires separate visible review of AUR
build instructions.

The reviewed adapter will compose bounded Omarchy stages without the automatic
AUR stage, leave AUR updates visible for the existing A11 review flow, and use
`omarchy system reboot` only through the separately confirmed A3 journal and
one-shot restoration path. Changed Omarchy command contracts must fail closed
for review rather than fall back to direct pacman mutation.

## Safety and lifecycle

- Adapter selection grants no mutation authority.
- Package-manager discovery is evidence, not authorization.
- Unknown and ambiguous platforms remain inventory-only.
- Existing Arch, Debian, Proxmox, Fedora, NixOS, and appliance behavior remains
  available.
- This slice adds no service, timer, watcher, listener, daemon, or background
  loop.
- Read-only collection terminates `complete` or `failed`.
- Later mutation remains separately gated and terminates in the existing
  maintenance lifecycle states.

## Deterministic acceptance

- Omarchy resolves to the Omarchy adapter and retains the Arch base family.
- CachyOS and Arch resolve to the generic Arch adapter.
- Debian with Proxmox resolves to `proxmox_apt`; ordinary Debian resolves to
  `debian_apt`.
- Fedora and NixOS resolve to their existing adapters.
- Unknown platforms resolve to inventory-only.
- Workstation status exposes adapter identity and Omarchy evidence without
  mutation.
- Existing maintenance and fleet regression suites remain green.
- No test or implementation path invokes a live update or reboot.
