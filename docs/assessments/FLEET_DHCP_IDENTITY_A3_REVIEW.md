# Fleet DHCP Identity and Recovery A3 Review

Status: validated; live Operator acceptance complete.

## What was implemented

- Added fixed or reviewed-MAC DHCP address policy to status-only enrollment.
- Kept SSH inventory and every mutation-capable device on fixed addressing.
- Added current-address MAC verification and one bounded reviewed-subnet
  recovery scan when a DHCP-tracked identity is absent or mismatched.
- Shared recovery results by subnet and capped one invocation at four distinct
  subnet scans.
- Allowed exactly one MAC match to retarget one owner-private status record and
  retain eight bounded address-history events.
- Added one hardened transient user oneshot for a single ten-minute recheck.
  The delayed invocation terminates and cannot schedule itself again.
- Added a reversible ignored-candidate list with MAC-first matching and IP
  fallback.
- Retained only the last successful canonical discovery subnet between page
  loads.
- Added compact status-only cards showing IP, assigned name, Online/Offline,
  Refresh, checked time, status probe, and network reachability.
- Added semantic fleet colors: green for Healthy/Online, yellow for Updates
  available, and red for Offline/Reboot required.

## Files changed

- `Makefile`
- `assets/dashboard/dashboard.css`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/index.html`
- `config/project_tracker_seed.json`
- `docs/assessments/FLEET_DHCP_IDENTITY_A3_REVIEW.md`
- `docs/assessments/PORTABLE_FLEET_DISCOVERY_A1_REVIEW.md`
- `docs/guides/GUIDED_MAINTENANCE.md`
- `docs/soul/FLEET_DHCP_IDENTITY_A3_BRIEF.md`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `lib/soul_core/maintenance_fleet_discovery_service.rb`
- `lib/soul_core/maintenance_fleet_status_service.rb`
- `scripts/soul-maintenance-fleet-dhcp-recheck`
- `scripts/verify-maintenance-fleet-dhcp-identity-a3.rb`
- `scripts/verify-maintenance-fleet-discovery-a1.rb`

Owner-private runtime state may include:

- `Soul/private/host_maintenance/discovered_devices.json`
- `Soul/private/host_maintenance/ignored_devices.json`
- `Soul/private/host_maintenance/fleet_discovery_preferences.json`
- `Soul/private/host_maintenance/dhcp_recovery.json`
- `Soul/private/host_maintenance/fleet_status.json`

None of those files belongs in the public repository.

## Commands run

```text
ruby -c lib/soul_core/maintenance_fleet_discovery_service.rb
ruby -c lib/soul_core/maintenance_fleet_status_service.rb
ruby -c scripts/verify-maintenance-fleet-dhcp-identity-a3.rb
node --check assets/dashboard/dashboard.js
make verify-maintenance-fleet-discovery
make verify-maintenance-fleet-dhcp-identity
make verify-maintenance-fleet-status
make verify-maintenance-device-control
make verify-project-timeline
git diff --check
```

## Deterministic results

- Public, loopback, oversized, and shell-shaped discovery scopes fail closed.
- Unreviewed candidates and neighbor tables are not persisted.
- Ignoring and restoring bind the exact reviewed identity and digest.
- DHCP tracking requires a reviewed MAC and subnet and is rejected for SSH.
- A missing tracked device retains its old address, becomes Offline, and
  schedules exactly one delayed retry.
- Recovery uses a fixed shell-free Nmap vector.
- Multiple missing devices on one subnet share one bounded recovery scan.
- One exact reviewed-MAC match retargets only the private status-only record.
- The delayed retry clears pending state and cannot become a repeating poll.
- Existing fleet status, device-control, and discovery regression suites pass.

## Live result

One explicit live `/24` scan completed in approximately two seconds, detected
21 online addresses, excluded all seven configured or enrolled identities, and
returned 14 actionable candidates with local MAC/vendor/interface hints. It
persisted only `192.168.124.0/24` in the owner-private preference file.

After the Dashboard restart, live DOM inspection found four compact
status-only cards (Cisco phone, router, and two extenders). Each exposed only
IP, assigned name, Online, Refresh, checked time, status probe, and network
reachability. The three managed cards retained their full operational evidence.
Computed Online and Healthy badge/rail colors were the intended green values.
The live ignored list was initially empty and the three pre-A3 Amplifi records
remained fixed-address; no existing private identity was silently migrated.

Subsequent normal Dashboard use completed the remaining live gate. The
owner-private ignored list now retains ten reviewed MAC-first identities, and
the DHCP-tracked Operator iPhone record contains one bounded address-history
event from its prior address to its current address with reason
`exact_reviewed_mac_match`. No unrelated registry record changed and no pending
DHCP recovery state remains. The Operator accepted this evidence on 2026-08-08
without requiring a redundant live restore/re-ignore mutation.

## Local LLM evaluation

Not applicable. Identity validation, recovery, persistence, and UI state are
deterministic. No model may select an identity, approve a retarget, ignore a
device, or grant maintenance authority.

## Known weaknesses

- ARP and MAC evidence is local-link IPv4 evidence; it is not cryptographic
  identity and does not cross routed networks.
- Locally administered or duplicated MAC addresses can be unstable or
  ambiguous. Ambiguity never retargets automatically.
- A status-only probe establishes Online/Offline only. It does not establish
  firmware, application, WAN, provider, or service health.
- Existing fixed status-only records require removal and reviewed re-enrollment
  to opt into MAC tracking; A3 does not silently rewrite them.
- The ten-minute recheck depends on a functioning user systemd manager.
  Scheduling failure leaves the device Offline until the next manual or
  noon/midnight collection.

## Memory keys

None. Fleet identity is owner-private operational state, not conversational
memory.

## Lifecycle states touched

- discovery/status/registry/ignored: `complete`, `failed`
- enrollment/ignore/restore: `complete`, `awaiting_input`,
  `blocked_for_human_review`, `failed`
- DHCP identity: `verified_current`, `verified_after_scan`, `retargeted`,
  `offline`, `mac_mismatch`, `ambiguous_mac`, `address_conflict`
- device state: `healthy`, `reachable`, `updates_available`, `attention`,
  `offline`

All foreground invocations terminate. The only delayed work is the
human-approved, fixed, one-attempt transient oneshot.

## Risk classification

Class 2 local-network identity reads and Class 2 owner-private inventory
mutations. No device mutation, authentication, package, service, reboot, or
root authority is introduced.

## Human review checklist

- [x] Reload Guided Maintenance and confirm the last subnet is retained.
- [x] Confirm status-only cards are compact and display Online/Offline,
      Refresh, Checked, Status probe, and Network reachability.
- [x] Confirm managed cards remain rich and show green/yellow/red semantics.
- [x] Ignore candidates and confirm they remain excluded by reviewed identity.
- [x] Review deterministic restore coverage; no redundant live registry
      mutation is required for acceptance.
- [x] Enroll suitable status-only DHCP devices with reviewed MAC evidence.
- [x] Confirm the cards have no Maintenance or Reboot authority.
- [x] Let one address change and confirm one exact MAC match
      updates only that card and private registry history.
- [x] Confirm bounded missing-device behavior and absence of indefinite polling
      through the accepted deterministic recovery suite.
- [x] Confirm narrow/mobile layout remains usable.
