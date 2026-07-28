# Operations Topology Network Map E1 Review

```text
date: 2026-07-28
candidate_state: candidate-complete
risk: Class 1 read-only local route evidence and Dashboard presentation
human_review: required before merge
```

## What was implemented

- Replaced the flat topology chain with a primary network flow:
  `WAN/provider cloud → default gateway → local subnet → known devices`.
- Added one bounded read of `/proc/net/route` to derive the default gateway,
  interface, directly connected IPv4 subnet, and prefix.
- Reused the enrolled gateway device when its reviewed address matches the
  route; otherwise rendered an inert evidence-only gateway node.
- Kept management, containment, DNS, provider, inventory, and planned backup
  relationships in a separate informational section beneath the network map.
- Added desktop and narrow responsive layouts without committing the
  Operator's private subnet or gateway as defaults.

## Files changed

- `lib/soul_core/maintenance_fleet_status_service.rb`
- `assets/dashboard/index.html`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/dashboard.css`
- `scripts/verify-maintenance-fleet-status-b1.rb`
- `docs/soul/OPERATIONS_TOPOLOGY_NETWORK_MAP_E1_BRIEF.md`
- `docs/guides/GUIDED_MAINTENANCE.md`
- `config/project_tracker_seed.json`
- `docs/assessments/OPERATIONS_TOPOLOGY_NETWORK_MAP_E1_REVIEW.md`

## Commands run

```text
ruby -c lib/soul_core/maintenance_fleet_status_service.rb
node --check assets/dashboard/dashboard.js
ruby -rjson -e 'JSON.parse(File.read("config/project_tracker_seed.json"))'
git diff --check
make verify-maintenance-fleet-status
make verify-maintenance-fleet-discovery
make verify-maintenance-fleet-dhcp-identity
ruby scripts/soul-maintenance-fleet-status
systemctl --user restart soul-dashboard.service
```

## Deterministic results

- Fleet-status verification passed, including little-endian route decoding,
  gateway and subnet projection, WAN/LAN edge construction, missing-route
  degradation, and the public-source RFC1918 guard.
- Portable discovery and DHCP-identity regression suites passed.
- Ruby, JavaScript, tracker JSON, and whitespace checks passed.

## Live results

- Maven resolved `eno1`, its current `/24` LAN, and its current default gateway
  from kernel route evidence.
- The gateway matched the already enrolled Amplifi Router HD instead of
  producing a duplicate synthetic node.
- The refreshed Dashboard displayed WAN/cloud above the gateway, the local
  subnet below it, five remaining LAN devices, and secondary operational
  relationships at the bottom.
- At the default viewport, the map stayed within its 1068-pixel container.
- At a temporary 390-by-844 viewport, the map collapsed to one column and
  remained within the page without horizontal overflow. The viewport override
  was then reset.

## Local LLM evals

None. This slice is deterministic route projection and presentation; local LLM
behavior is not involved.

## Known weaknesses

- Linux `/proc/net/route` is IPv4-only. IPv6 default-route presentation remains
  outside this slice.
- Route configuration proves configured topology, not gateway reachability.
  An unmatched gateway therefore remains `unknown`.
- Known devices are grouped under the detected LAN because the fleet snapshot
  does not yet retain a per-device interface or routed-subnet association.

## Memory and lifecycle

- Shared memory keys added or used: none.
- Task lifecycle: one bounded `complete` or `failed` fleet collection.
- No watcher, daemon, timer, scheduled task, or background continuation was
  added.

## Human review checklist

- [ ] Confirm the WAN → gateway → subnet → device hierarchy reads as a network
      map.
- [ ] Confirm the enrolled gateway identity is correct.
- [ ] Confirm the secondary operational relationships remain useful.
- [ ] Confirm the desktop spacing and mobile one-column layout.
- [ ] Approve merge or request changes.
