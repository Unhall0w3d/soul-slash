# Operations Topology Network Map E1 Brief

```text
date: 2026-07-28
human_authorization: approved in the active development conversation
risk: Class 1 read-only local route evidence and Dashboard presentation
```

## Objective

Replace the flat Operations Topology sequence with a network-oriented map:

```text
WAN and provider cloud
          ↓
detected default gateway
          ↓
local IPv4 subnet
          ↓
known fleet and inventory devices
```

Management, DNS, containment, provider, inventory, and planned-backup
relationships remain available as secondary informational records beneath the
network flow.

## Evidence and portability

- Read `/proc/net/route` once as bounded, read-only local evidence.
- Select the active IPv4 default route and its lowest metric.
- Decode the gateway, interface, directly connected subnet, and prefix without
  invoking a shell or network command.
- Match the gateway address to an existing fleet device when one is enrolled.
- Otherwise render an inert `Default gateway` topology node.
- Never commit or configure the Operator's subnet or gateway address as a
  public default.

## Boundaries

- No network discovery, DNS lookup, port probing, route mutation, or device
  mutation is added.
- Route evidence affects the map only; it grants no trust or authority.
- An absent or malformed route file degrades to an evidence-unavailable network
  boundary without hiding known devices.
- Operations Topology remains derived from the same fleet snapshot as the
  device cards.

## Acceptance

- The live map shows the WAN/cloud tier above the default gateway.
- The gateway is the enrolled device at the detected gateway address when
  available.
- The detected subnet contains all known local device nodes beneath it.
- Operational relationships remain legible below the primary map.
- Desktop and narrow layouts preserve the hierarchy without horizontal
  overflow.
- Deterministic tests prove little-endian route decoding and public-source
  neutrality.
