# ASUSWRT-Merlin Gateway Inventory A2 Brief

```text
date: 2026-09-01
human_authorization: approved in the active development conversation
implementation_authorized: yes
live read-only qualification authorized: yes
router mutation authorized: no
risk: Class 2 read-only private-infrastructure evidence
```

## Objective

Promote the existing generic ASUSWRT-Merlin inventory adapter into a useful
gateway projection for Guided Maintenance and Local Topology. Preserve the
router as inventory-only while reporting bounded firmware-state signals,
Entware posture, swap, attached storage aggregates, and a small reviewed
diagnostic-tool inventory.

## Collection boundary

One fixed, literal remote shell script may collect:

- the existing identity, firmware, kernel, uptime, load, memory, JFFS,
  temperature, QoS, acceleration, and custom-script aggregates;
- Entware presence, `opkg` version, installed-package count, and the count from
  the locally cached `opkg list-upgradable` result;
- aggregate swap device count, capacity, and usage without device names;
- aggregate `/tmp/mnt/` filesystem count and capacity without paths, labels,
  UUIDs, serials, filenames, or directory contents;
- raw allowlisted `webs_state_*` firmware-check values without claiming that an
  undocumented value means an update is available; and
- presence booleans for `jq`, `dig`, `tcpdump`, `htop`, `iperf3`, `bash`, and
  `tmux` under `/opt/bin`.

The adapter may derive attention only from explicit local thresholds: cached
Entware upgrades greater than zero, JFFS use at least 90 percent, available
memory at or below 10 percent, swap use at least 90 percent, a reported
temperature at least 85 C, or a nonzero vendor firmware error code. Every
finding identifies the deterministic rule that produced it.

## Dashboard and topology

- The gateway remains an integrated, collapsible inventory-only card.
- The card shows firmware check evidence, Entware counts, swap, USB storage,
  diagnostic health, and the reviewed toolbox without mutation controls.
- Local Topology continues to derive the gateway position from the live route
  and enrolled device address. The management relationship remains fixed SSH
  inventory, not maintenance authority.
- Entware cached-upgrade evidence may contribute to the fleet update count, but
  the Dashboard must not offer package installation.

## Bounds and exclusions

- One foreground SSH process; eight-second timeout; 32 KiB output ceiling.
- No retries, listener, watcher, timer, daemon, or new persistent process.
- No NVRAM dump, configuration export, client inventory, traffic history,
  wireless keys, credentials, public IP, filesystem paths, package names, or
  raw command output reaches the Dashboard.
- No `opkg update`, firmware download/check request, package mutation, service
  mutation, configuration change, reboot, or router maintenance authority.
- Private address, SSH alias, hostname, and collected snapshot remain ignored
  owner state; only generic adapter code, fixtures, and documentation are
  tracked.

## Acceptance

1. Deterministic fixtures prove parsing, thresholds, privacy, bounds, and
   fail-closed behavior.
2. A live read-only probe returns the approved aggregates without secrets or
   filenames and leaves no process running.
3. Guided Maintenance renders the expanded evidence without Maintain or Reboot
   controls; Local Topology uses the same truthful snapshot.
4. Existing fleet, topology, and Dashboard security regressions pass.
