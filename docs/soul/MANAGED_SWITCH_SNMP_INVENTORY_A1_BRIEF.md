# Managed-Switch Read-Only SNMP Inventory A1 Brief

```text
date: 2026-08-03
human_authorization: approved in the active development conversation
implementation_authorized: yes
live read-only polling authorized: yes
switch mutation authorized: no
trap listener authorized: no
risk: Class 2 read-only infrastructure evidence with an owner-private credential
```

## Objective

Add the Operator's Netgear GS724Tv4 (**Lattice**) and Cisco SG300-10 (**Loom**)
to Guided Maintenance and Operations Topology through one shared bounded
SNMPv2c read-only adapter. Report identity, installed and boot firmware where
the standard entity table supplies it, reviewed firmware comparison, uptime,
and a bounded physical-interface projection without creating SSH, SNMP SET,
firmware upload, reboot, or configuration authority.

## Trust and credential boundary

- Each switch community is unique, read-only, and restricted on its switch to
  the exact Atelier management address.
- Public configuration is default-off and contains no private address or
  community.
- The community is read from ignored mode-0600 `.env`, written to a fresh
  mode-0600 Net-SNMP configuration inside a mode-0700 temporary directory, and
  never placed in process arguments, Dashboard data, fleet evidence, or logs.
- The temporary configuration is removed when the foreground adapter returns,
  including failure paths.
- The target must be one exact private IPv4 address. Request data and model
  output cannot replace it.

## Collection contract

A1 uses only standard MIBs the devices explicitly advertise:

- SNMPv2-MIB system identity and uptime;
- RFC1213/IF-MIB physical interface state, negotiated speed, traffic octets,
  and cumulative error counters; and
- ENTITY-MIB chassis model, hardware revision, boot firmware, and software
  revision when implemented by the device.

One fixed `snmpget` and three fixed `snmpbulkwalk` processes use SNMPv2c, a
two-second protocol timeout, zero retries, a six-second process timeout, and
bounded output. Only Ethernet interfaces enter the normalized projection, with
a maximum of 64 records. Raw SNMP output is never returned to the Dashboard.

## Dashboard behavior

Lattice and Loom appear as integrated inventory with installed firmware and
reviewed target comparison, available hardware/boot evidence, active and
inventoried physical-port counts, cumulative error-port count, expandable
per-port link/speed/error evidence, and a credential-free private HTTP
management link. Each card says `inventory only`, `polling`, and `traps not
ingested`; no Maintain or Reboot button is rendered.
The topology relationship from Atelier is labeled `read-only SNMP inventory`.

## Trap boundary

Both switches are operator-configured to send bounded SNMPv2 traps to Atelier.
Lattice sends link up/down, spanning-tree, and ACL traps with authentication
traps disabled. A1 installs no UDP/162
listener and does not claim those events are observed. Durable trap ingestion
requires a separate approved persistent-service brief, event privacy contract,
retention policy, and notification design.

## Explicit exclusions

- SNMP SET, write communities, SNMPv3 admin credentials, or switch mutation.
- Automatic firmware discovery, download, upload, activation, or reboot.
- Vendor-private MIB traversal, configuration export, MAC/FDB inventory,
  client identity, VLAN inspection, LLDP neighbors, RMON alarms, and traps.
- Background polling beyond the existing separately accepted fleet snapshot
  schedule.

## Acceptance

1. Deterministic adapter and existing fleet regressions pass.
2. Live polling returns Loom identity, firmware/boot evidence, and bounded
   interface evidence without revealing the community; Lattice receives the
   same proof after its private credential is handed off.
3. Both authenticated Dashboard cards and topology relationships are reviewed.
4. Neither switch exposes mutation controls or leaves a process after polling.
