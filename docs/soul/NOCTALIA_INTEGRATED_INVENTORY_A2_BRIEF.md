# Noctalia Integrated Inventory — A2 Brief

## Human-approved objective

Make Soul's Noctalia companion pick up new systems added to the Dashboard's
**Integrated inventory** instead of silently limiting the panel to SSH-channel
devices.

## Required behavior

- Project the same rich integrated classes used by Guided Maintenance:
  Atelier's local channel, reviewed SSH maintenance/inventory, host-local
  inventory, and read-only managed-switch SNMP inventory.
- Continue excluding compact ICMP/status-only presence devices.
- Preserve stable opaque device IDs, bounded text, and the 128-device limit.
- Add no action to a device merely because it appears in inventory.
- Keep **Connect** limited to IDs already resolved by Soul's reviewed private
  SSH action registry.
- Describe firmware-only and unqueried package evidence truthfully.
- Keep the public plugin dynamic, scrollable, and free of private topology,
  addresses, aliases, credentials, or key paths.

## Explicit exclusions

- SNMP SET, switch configuration, firmware installation, or reboot;
- actions for Atelier, Chancery, Lattice, or Loom;
- compact network-presence devices;
- new services, timers, watchers, probes, or schedules;
- a status-schema version change or a new private registry.

## Lifecycle

`status` remains one bounded foreground projection and terminates `complete` or
`failed`. The Noctalia collector continues to invoke it on the plugin's existing
bounded refresh interval; this slice adds no persistence mechanism.
