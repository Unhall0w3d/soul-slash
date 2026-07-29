# Workstation Identity Migration A0 Brief

Status: human-approved implementation; review required before merge

## Human direction

The Operator renamed the owner workstation from Maven to Atelier and approved a
portable canonical internal identity:

```text
canonical device id: workstation
deployment display label: operator-configured (Atelier locally)
legacy read alias: maven
```

The public repository must not make the owner-specific name `atelier` a
portable identity.

## Scope

A0 may:

- emit `workstation` from fresh fleet collection, topology, and refresh output;
- accept `maven` only as a compatibility input for old snapshots and refresh
  requests;
- canonicalize legacy device IDs in persisted snapshot devices, topology
  nodes, topology edges, network node lists, and refresh metadata while reading;
- introduce `SOUL_FLEET_WORKSTATION_ADDRESS` and
  `SOUL_FLEET_WORKSTATION_LABEL`;
- retain `SOUL_FLEET_MAVEN_ADDRESS` and `SOUL_FLEET_MAVEN_LABEL` as bounded
  environment aliases;
- make Dashboard workstation controls and prose deployment-neutral; and
- migrate owner-private current state by performing one explicit fresh fleet
  collection after merge.

## Safety and compatibility boundary

- The stable remote targets `forge`, `pihole`, and enrolled `managed_*` IDs do
  not change.
- The workstation continues to delegate mutation to the existing reviewed
  local A2/A3/A4 services. It does not become a target of the remote device
  control service.
- Historical receipts, archived review evidence, and immutable prior commits
  are not rewritten.
- Compatibility is one-way: legacy input may be read, but all new output uses
  `workstation`.
- No maintenance, reboot, persistence, network, privilege, or confirmation gate
  is broadened.

## Lifecycle

The migration runs only during existing bounded fleet collection, snapshot
read, or one-device refresh calls and terminates as `complete` or `failed`.
There is no watcher, daemon, retry loop, or background continuation.

## Human review checklist

- [x] Approve `workstation` as the canonical portable ID.
- [x] Approve `maven` as a legacy read alias only.
- [x] Verify fresh output contains `workstation` and no emitted `maven` ID.
- [x] Verify an old snapshot and refresh request remain readable.
- [x] Verify the Dashboard displays the configured label rather than an
  internal ID.
- [x] Verify maintenance safety and device-control regressions.
