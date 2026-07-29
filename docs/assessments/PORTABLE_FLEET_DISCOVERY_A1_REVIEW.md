# Portable Fleet Discovery and Enrollment A1 Review

Status: candidate-complete; live acceptance passed; merge pre-approved by the
Operator. Guided missing-alias extension is candidate-complete and awaiting
live acceptance.

## What was implemented

- Added one explicit, private-IPv4-only, `/24` through `/32` subnet discovery
  operation with a 30-second bound and no persisted candidate scan.
- Added review-gated status-only and fixed-SSH inventory enrollment.
- Required an existing literal SSH alias whose resolved `HostName` equals the
  selected candidate address.
- Added independent package executable detection for pacman, yay, paru, apt,
  apt-get, dnf/dnf5, zypper, apk, Flatpak, Snap, and Nix.
- Added a 64-record, owner-private `0600` atomic registry under ignored local
  state.
- Added enrolled devices to fleet status as `inventory_only` cards without
  Maintenance or Reboot controls.
- Added exact reviewed registry removal that never contacts the device.
- Added Administration UI, CLI prerequisite/scan helpers, Makefile targets,
  documentation, and deterministic verification.
- Corrected post-enrollment candidate semantics: configured and enrolled
  addresses are counted as represented but excluded from the actionable
  candidate list, and registry mutations invalidate stale page-session scans.
- Added one bounded local `/proc/net/arp` read plus Nmap's local OUI data to
  provide ephemeral candidate MAC/vendor/interface/state hints.
- Added one owner-private preference containing only the last successfully
  scanned canonical subnet so the Dashboard can refill the discovery field.
- Added a reversible owner-private ignored-device list with MAC-first identity
  matching and IP fallback.
- Added reviewed MAC/subnet DHCP tracking for status-only inventory, one
  bounded recovery scan, and exactly one transient ten-minute retry.
- Added compact status-only cards and semantic green/yellow/red fleet states.
- Added a separately gated missing-alias prerequisite that requests one
  portable account and one existing owner-private key path, derives HostName
  from the selected candidate, previews a fixed non-interactive stanza, and
  atomically appends it only after digest-bound approval.

## Files changed

- `Makefile`
- `assets/dashboard/dashboard.css`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/index.html`
- `config/project_tracker_seed.json`
- `docs/assessments/PORTABLE_FLEET_DISCOVERY_A1_REVIEW.md`
- `docs/guides/GUIDED_MAINTENANCE.md`
- `docs/soul/PORTABLE_FLEET_DISCOVERY_A1_BRIEF.md`
- `docs/soul/FLEET_DHCP_IDENTITY_A3_BRIEF.md`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `lib/soul_core/maintenance_fleet_discovery_service.rb`
- `lib/soul_core/maintenance_fleet_status_service.rb`
- `scripts/soul-maintenance-fleet-discovery`
- `scripts/verify-maintenance-device-control-c1.rb`
- `scripts/verify-maintenance-fleet-discovery-a1.rb`
- `scripts/verify-maintenance-fleet-status-b1.rb`
- `scripts/soul-maintenance-fleet-dhcp-recheck`
- `scripts/verify-maintenance-fleet-dhcp-identity-a3.rb`

Ignored runtime state, if enrolled through the Dashboard:

- `Soul/private/host_maintenance/discovered_devices.json`
- `Soul/private/host_maintenance/fleet_status.json`

## Commands run

```text
ruby -c lib/soul_core/maintenance_fleet_discovery_service.rb
ruby -c lib/soul_core/maintenance_fleet_status_service.rb
node --check assets/dashboard/dashboard.js
ruby scripts/verify-maintenance-fleet-discovery-a1.rb
ruby scripts/verify-maintenance-fleet-status-b1.rb
ruby scripts/verify-maintenance-fleet-dhcp-identity-a3.rb
ruby scripts/verify-maintenance-device-control-c1.rb
make verify-project-timeline
make fleet-discovery-check
make fleet-discovery-scan FLEET_SUBNET=<private /24>
ruby bin/soul config validate
git diff --check
```

Guided alias extension verification also ran:

```text
ruby -c lib/soul_core/maintenance_fleet_discovery_service.rb
ruby -c lib/soul_core/application_facade.rb
node --check assets/dashboard/dashboard.js
ruby scripts/verify-maintenance-fleet-discovery-a1.rb
git diff --check
```

## Deterministic results

The focused verifier proves:

- public, loopback, oversized, and shell-shaped scan scopes fail before command
  execution;
- discovery uses one fixed shell-free `nmap` vector, timeout, and result bound;
- candidates remain untrusted and non-persisted;
- configured and enrolled addresses never remain actionable candidates;
- candidate identity hints require one bounded local neighbor read and are
  never written to the registry or public source;
- the remembered subnet preference contains no candidate or device identity;
- status-only enrollment performs one bounded reachability probe;
- SSH inventory binds the alias to the selected address and uses only fixed
  BatchMode commands;
- missing-alias setup rejects key paths outside the owner SSH directory,
  previews one fixed stanza, blocks changed evidence and duplicate aliases,
  and preserves mode `0600` on atomic append;
- every supported package-manager family can be detected concurrently without
  consulting the distro identifier;
- changed preview evidence fails closed;
- enrollment and removal write only one exact owner-private registry revision;
- registered devices surface as inventory-only with zero invented updates; and
- the Dashboard never offers mutation controls for an inventory-only device.

## Live result

The authenticated Dashboard ran one explicit private `/24` scan in under three
seconds and returned 22 reachable addresses. Maven, Forge, Pi-hole, and the
Cisco phone were correctly identified as already represented. No candidate
scan was written to disk.

A live Forge SSH preview verified the configured alias-to-address binding,
identified Debian 13, and detected `apt` plus `apt-get`; it was not enrolled.
A temporary status-only record was then previewed and enrolled through the
Dashboard. Its fleet card showed `inventory_only`, zero invented updates, and
no Maintenance or Reboot controls. The reviewed removal deleted that one
registry record, removed its card, and did not contact or modify the device.
The registry returned to zero records. A 390-pixel responsive check found no
horizontal overflow and stacked all discovery controls into one column.

The candidate-filter and identity-hint follow-up was exercised live on Maven.
One `/24` scan detected 22 reachable addresses, excluded five configured or
enrolled addresses, and returned 17 actionable candidates. All 17 received
ephemeral neighbor-table MAC, vendor/address-type, and interface hints; none
were persisted.

No Proxmox guest was created for A1. Deterministic capability fixtures prove
discovery semantics without introducing a disposable machine. A real NixOS or
Alpine guest becomes useful only when a later separately approved mutation
adapter must prove package-manager execution and postconditions.

## Local LLM evaluation

Not applicable. Discovery, validation, fingerprinting, persistence, and
rendering are deterministic. No model selects a subnet, trusts a candidate, or
grants authority.

## Known weaknesses

- Host discovery reports network presence, not identity or trust.
- A status-only DHCP address can move; stable addressing is recommended.
- SSH enrollment intentionally does not support wildcard-only aliases, included
  SSH config fragments, DNS `HostName` values, or interactive authentication.
  Guided alias setup does not copy a public key or enroll a host key; those
  trust prerequisites remain explicit operator actions.
- Package-manager detection proves executable presence only; it does not prove
  repository health, privilege, update semantics, reboot behavior, or adapter
  safety.
- A1 does not install `nmap`; the Makefile checks the dependency and documents
  the host-package-manager prerequisite.
- Cancellation is enforced by the HTTP/client timeout and bounded process
  lifetime; no long-lived cancellation worker exists.

## Memory keys

None. Inventory belongs to owner-private operational state, not conversational
memory.

## Lifecycle states touched

- discovery/status/registry: `complete`, `failed`
- alias setup/enrollment/removal: `complete`, `awaiting_input`,
  `blocked_for_human_review`, `failed`
- device: `reachable`, `offline`

Every command terminates before returning. No scanner, watcher, polling loop,
service, or timer was added.

## Risk classification

Class 2 local-network reads and Class 2 owner-private inventory registry
mutations. The guided prerequisite adds one Class 2 owner SSH-config append.
No device mutation authority.

## Human review checklist

- [x] Open Administration → Guided Maintenance → Discover & enroll a device.
- [x] Confirm no scan happens merely by opening the page.
- [x] Scan one explicit private subnet and inspect ephemeral candidates.
- [x] Confirm existing configured devices are labeled already represented.
- [x] Preview one status-only or configured SSH inventory candidate.
- [x] Confirm the preview contains capabilities but no credentials or raw
      command output.
- [x] Enroll one suitable test record and confirm its card has no Maintenance or
      Reboot controls.
- [x] Remove the test record and confirm the device itself is untouched.
- [x] Confirm Maven, Forge, Pi-hole, and Cisco phone behavior is unchanged.
- [x] Confirm narrow/mobile layout remains usable.
- [ ] With a reviewed test host, preview and add one missing literal SSH alias.
- [ ] Confirm the stanza contains only the reviewed address, user, key path,
      and fixed non-interactive options.
- [ ] Confirm the alias gate alone does not enroll or mutate the device.
