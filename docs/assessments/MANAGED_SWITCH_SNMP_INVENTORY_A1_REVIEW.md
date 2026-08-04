# Managed-Switch Read-Only SNMP Inventory A1 Review

## Result

Accepted and merged. Lattice and Loom both completed credential-safe live
polling, authenticated Dashboard-card review, and topology review without
gaining switch mutation authority.

## Implementation summary

- Shared fixed-target Net-SNMP adapter for SNMPv2-MIB, IF-MIB, and bounded
  ENTITY-MIB chassis evidence.
- Default-off typed configuration and a stdin-only owner-private `.env`
  installer that never prints the community.
- Inventory-only Lattice and Loom fleet cards, topology relationships, reviewed
  firmware comparisons, private management links, and expandable port evidence.
- Trap ingestion and every form of switch mutation remain out of scope.

## Files changed

The implementation adds `managed_switch_snmp_inventory_adapter.rb`, generic and
device-specific installer/status scripts, and the deterministic A1 verifier. It
updates the fleet service, configuration schema, Dashboard JavaScript/CSS,
public environment example, Makefile, Guided Maintenance guide, A1 brief/review,
and project tracker seed.

## Commands run

```text
make verify-managed-switch-snmp-inventory
make verify-maintenance-fleet-status
make verify-project-timeline
ruby scripts/verify-phase12a-portable-typed-configuration.rb
ruby scripts/verify-noctalia-companion-a0.rb
make loom-snmp-check
ruby scripts/soul-maintenance-fleet-status
git diff --check
```

## Deterministic test results

`make verify-managed-switch-snmp-inventory` proves fixed MIB projections, physical
interface filtering, bounded records, credential exclusion from argv and the
command environment, owner-private ephemeral configuration and cleanup,
private-address validation, firmware comparison, inventory-only Dashboard
semantics, persistence, one-card refresh, and absence of SNMP SET. The full
fleet, project-timeline, typed-configuration, and Noctalia companion regressions
pass. `git diff --check` passes. The Dashboard service restarted active and its
loopback root returned HTTP 200.

## Local LLM evaluation

Not applicable. This adapter is deterministic infrastructure collection and
does not use a model for routing, interpretation, safety, or authorization.

## Failure behavior and known weaknesses

- Missing dependency, credential, private target, timeout, or failed SNMP
  response returns a terminal unavailable/offline card with no retry.
- SNMPv2c provides no transport encryption. Source restriction, a unique
  read-only community, and the trusted private LAN are required compensating
  controls.
- Error counters are cumulative observations, not proof of a current fault.
- Expected firmware is operator-reviewed configuration, not a vendor lookup.
- Trap delivery is configured on both switches but is not ingested by Soul.
- Loom's first live ENTITY-MIB evidence on 2026-08-03 exposed the intermediate
  `1.3.5.58` software image. The Operator subsequently completed and verified
  the bounded firmware procedure: software `1.4.11.5` is active and selected
  in Image 2, bootloader `1.3.5.06` remains installed, and Image 1 retains
  `1.3.5.58` as a fallback. A post-reload A1 poll reports hardware `V02`, ten
  physical ports, three active ports, and zero ports with cumulative errors.
  The A1 integration remains read-only and did not perform the upgrade.

## Memory, lifecycle, and risk

- Shared memory keys added or used: none.
- One foreground collection terminates complete or failed; no adapter-owned
  background work remains.
- Risk: Class 2 read-only infrastructure evidence with owner-private secret
  handling.

## Human review checklist

- [x] Loom live poll proves installed/boot firmware and interface evidence.
- [x] Lattice live poll proves installed firmware and interface evidence.
- [x] Configured Lattice and Loom communities remain absent from argv, output,
  evidence, logs, and Git; `.env` remains ignored and untracked.
- [x] Lattice and Loom cards and topology relationships are readable.
- [x] No Maintain/Reboot/SNMP SET authority is present.
- [x] Final diff, tests, and PR are approved by the Operator.
