# Cisco Phone Fleet Status D1 Review

Status: candidate-complete; awaiting human dashboard review.

## What was implemented

- Added an optional Cisco 8851/Webex Calling inventory card to Guided
  Maintenance.
- Added one shell-free, five-second-bounded ICMP probe per fleet collection.
- Added explicit `status_only` capability and removed all Maintenance/Reboot
  controls from that card.
- Added a Webex Calling topology node whose link explicitly does not assert
  registration.
- Moved all fleet display addresses out of public Ruby constants and into
  portable environment configuration.
- Enabled the phone locally through ignored `.env`.
- Preserved private atomic fleet snapshots and the existing status-only
  collection schedule without adding a service, timer, watcher, or loop.

## Files changed

- `.env.example`
- `assets/dashboard/dashboard.css`
- `assets/dashboard/index.html`
- `assets/dashboard/dashboard.js`
- `config/project_tracker_seed.json`
- `docs/assessments/CISCO_PHONE_FLEET_STATUS_D1_REVIEW.md`
- `docs/guides/GUIDED_MAINTENANCE.md`
- `docs/soul/CISCO_PHONE_FLEET_STATUS_D1_BRIEF.md`
- `docs/soul/MAINTENANCE_DEVICE_CONTROL_C1_BRIEF.md`
- `lib/soul_core/application_facade.rb`
- `lib/soul_core/configuration_schema.rb`
- `lib/soul_core/maintenance_device_control_service.rb`
- `lib/soul_core/maintenance_fleet_status_service.rb`
- `scripts/verify-maintenance-device-control-c1.rb`
- `scripts/verify-maintenance-fleet-status-b1.rb`

Ignored local files updated:

- `.env`
- `Soul/private/host_maintenance/fleet_status.json`
- `Soul/private/project_tracker/state.json`

## Commands run

```text
ping -c 1 -W 2 <phone>
curl --max-time 5 http://<phone>/
curl --insecure --max-time 5 https://<phone>/
ruby scripts/verify-maintenance-fleet-status-b1.rb
ruby bin/soul config validate
ruby -c lib/soul_core/maintenance_fleet_status_service.rb
ruby -c lib/soul_core/application_facade.rb
node --check assets/dashboard/dashboard.js
git diff --check
ruby scripts/soul-maintenance-fleet-status
systemctl --user restart soul-dashboard.service
systemctl --user is-active soul-dashboard.service
```

## Deterministic results

The focused verifier passes and proves:

- disabled-by-default behavior;
- portable public defaults with no Operator RFC1918 addresses;
- exactly one bounded phone probe;
- reachable and offline terminal states;
- no raw probe output, credentials, unique device identity, directory number, or
  call history in returned evidence;
- no registration or firmware assertion;
- an external Webex Calling topology relationship; and
- no dashboard mutation controls for a status-only device.

Configuration, Ruby syntax, JavaScript syntax, and whitespace validation pass.

## Live result

The Operator-configured Cisco 8851 answered the bounded ICMP probe. The live
snapshot completed with four of four managed local devices reachable. HTTP and
HTTPS were closed, so no web status was queried and no registration, line,
firmware, or call-readiness claim is made.

Authenticated browser inspection confirmed that the card says **Reachable**,
uses **Status probe**, contains no action buttons, and links to an external
Webex Calling node whose status is explicitly not asserted. Maven, Forge, and
Pi-hole retained their existing controls.

## Local LLM evaluation

Not applicable. Collection and rendering are deterministic; no model decides
the target, status, or authority.

## Known weaknesses

- ICMP reachability proves only network presence.
- A DHCP address can move; a reservation or stable hostname is recommended.
- Webex registration, call quality, line state, firmware currency, uptime, and
  provider incidents are not currently visible.
- Cisco's richer read-only web information requires phone/provider web access,
  which was closed during the live probe.
- Final human visual review of the four-card desktop and responsive topology is
  still required.

## Memory keys

None. Fleet evidence is operational status, not conversational memory.

## Lifecycle states touched

- operation: `complete`, `failed`
- device: `reachable`, `offline`

Every probe ends with its fleet collection. No process waits for the phone.

## Risk classification

Class 1 read-only local status, plus the pre-existing owner-private snapshot
cache mutation.

## Human review checklist

- [ ] Cisco 8851 appears after **Collect fleet status**.
- [ ] Card says **Reachable**, not Healthy or Registered.
- [ ] Card says **Status only** and has no Maintenance/Reboot buttons.
- [ ] Webex topology link says its status is not asserted.
- [ ] Maven, Forge, and Pi-hole actions remain unchanged.
- [ ] Narrow/mobile layout remains usable.
