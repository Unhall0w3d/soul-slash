# Noctalia Integrated Inventory — A2 Review

## Candidate

- Name: Noctalia integrated-inventory parity
- Risk class: low read-only desktop projection
- Date: 2026-08-04
- Status: candidate-complete; awaiting Operator visual review

## Implemented

- Replaced the SSH-only status filter with an explicit allowlist for local,
  reviewed SSH, host-local, and read-only SNMP integrated channels.
- Preserved the Dashboard boundary that excludes `status_only` and
  `icmp_status` devices.
- Added a generic connection-boundary detail row.
- Kept non-SSH cards actionless and retained opaque private SSH resolution for
  reviewed connectable devices.
- Corrected firmware-only and unqueried update copy.
- Updated the public plugin copy from **SSH-integrated fleet** to
  **Integrated fleet** and bumped its patch version to 0.3.1.
- Updated the authoritative Project Timeline seed.

## Files changed

Soul repository:

```text
lib/soul_core/noctalia_status_service.rb
scripts/verify-noctalia-companion-a0.rb
docs/soul/NOCTALIA_COMPANION_CONTRACT_A0_BRIEF.md
docs/soul/NOCTALIA_INTEGRATED_INVENTORY_A2_BRIEF.md
docs/assessments/NOCTALIA_INTEGRATED_INVENTORY_A2_REVIEW.md
config/project_tracker_seed.json
```

Public `soul-noctalia` repository:

```text
catalog.toml
overview/plugin.toml
overview/panel.luau
overview/README.md
scripts/verify-public-source.rb
```

## Deterministic and live validation

```text
ruby scripts/verify-noctalia-companion-a0.rb
PASS — 26 checks

bin/soul-noctalia status
PASS — 9/9 healthy integrated systems
Atelier, Forge, Warden, Chancery, Lattice, Loom, Crucible, Foundry, Temper
Only Forge, Warden, Crucible, Foundry, and Temper expose Connect.

ruby scripts/verify-public-source.rb
PASS — public source contains no environment-specific values or resolved targets

git diff --check
PASS — Soul and public plugin repositories
```

## Security and lifecycle

```text
Operation: bounded read-only status projection
New network probe: no
New mutation authority: no
Non-SSH action descriptors: none
Resolved targets exposed: no
Credentials, addresses, or key paths added to public plugin: no
Memory keys added or used: none
Persistent service, timer, watcher, or schedule added: no
Lifecycle states: complete / failed
```

## Known weaknesses

- Nine compact cards require live visual review in the authenticated Noctalia
  panel; the renderer is dynamic and scrollable but Luau has no standalone UI
  harness.
- Lattice and Loom expose bounded summary/detail evidence only. Their private
  management pages, SNMP credentials, trap destinations, and switch mutations
  remain outside this companion contract.

## Human review checklist

```text
[ ] Noctalia shows all nine systems in Integrated fleet
[ ] Atelier, Chancery, Lattice, and Loom fit and flip cleanly
[ ] Read-only cards do nothing on left-click and disclose no hidden target
[ ] Existing five Connect actions still open the correct reviewed targets
[ ] Core control and Voice Presence remain functional
[x] Public plugin source passes its exposure audit
```
