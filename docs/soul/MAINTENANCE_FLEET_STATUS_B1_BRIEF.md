# Maintenance Fleet Status B1 Brief

```text
date: 2026-07-27
human_authorization: approved in the active development conversation
implementation_authorized: yes
live device mutation authorized: no
background monitoring authorized: no
risk: Class 2 read-only infrastructure evidence
```

## Objective

Extend **Administration → Guided Maintenance** with one bounded, on-demand
status collection for:

- the `maven` CachyOS/Hyprland workstation;
- the standalone Proxmox VE hypervisor, whose node identity is discovered at
  collection time; and
- the `pihole` Debian LXC with Pi-hole FTL and Unbound.

The same normalized evidence drives both the device status cards and the
connected-architecture view. B1 does not authorize package metadata mutation,
updates, service restarts, guest operations, reboot, backup execution, or
scheduled monitoring.

## Operator experience

The Guided Maintenance page starts with an infrastructure control plane. The
operator explicitly clicks **Collect fleet status**. The foreground request:

1. checks cached local pacman metadata, live AUR and Flatpak listings, and
   kernel evidence;
2. connects through the preconfigured `proxmox-maintenance` and
   `pihole-maintenance` SSH aliases;
3. collects cached remote APT upgrade counts, kernel/reboot evidence,
   Proxmox LXC state, Pi-hole versions, service state, blocking state, and a
   bounded DNS query;
4. normalizes partial and unavailable evidence without hiding another healthy
   device;
5. renders device indicators and an architecture map; and
6. terminates.

There is no automatic refresh, client polling, server polling, detached
process, retry loop, timer, watcher, daemon, or persistent status cache.

## Access and credential boundary

- SSH uses fixed aliases and existing owner-readable configuration.
- Both remote aliases use dedicated passwordless maintenance keys installed
  outside Soul.
- No private key, public key, password, token, environment dump, SSH
  configuration content, or raw command output is returned to the Dashboard.
- The service records only bounded adapter status, exit status, and truncation
  evidence.
- The fixed remote targets accept no request parameters or model-generated
  command arguments.

## Data model

Each device reports:

- stable role and current address;
- discovered hostname where applicable;
- reachability and normalized health state;
- platform/version;
- running and available kernel evidence;
- native, AUR, and applicable Flatpak update counts;
- reboot evidence;
- bounded service checks; and
- role-specific facts, including Proxmox LXC `100` and Pi-hole DNS health.

Workstation pacman and remote APT counts are explicitly labeled as using
current cached metadata. Refreshing system package metadata belongs to a later
exact maintenance transaction.

## Lifecycle and bounds

```text
requested
→ collecting_local
→ collecting_proxmox
→ collecting_pihole
→ normalizing
→ complete / failed
```

- Every command has a fixed argument vector.
- Connection attempts and command runtimes are bounded.
- One unreachable device is returned as `offline`; it is not retried and does
  not erase evidence from other devices.
- The entire Dashboard request has a foreground time limit.
- No state is written by the collector.

## Explicitly prohibited

- Package metadata refresh or package installation.
- Service, guest, storage, network, DNS, backup, or reboot mutation.
- Dashboard password or SSH-passphrase entry.
- Arbitrary hostname, address, command, path, or argument parameters.
- Shell command construction from returned hostnames or request data.
- Background monitoring, polling, retry, persistence, or notification.
- Treating a green status result as authority to run maintenance.

## Deterministic verification

The B1 candidate must prove:

- exact operation and parameter contract;
- fixed SSH aliases, batch authentication, and connection bounds;
- no shell interpreter command vectors;
- normalization of local, Proxmox, Pi-hole, kernel, update, service, DNS, and
  LXC evidence;
- topology derives from the same normalized records;
- dynamic Proxmox node naming;
- offline-device partial success with no retry;
- no credential or raw output reaches the response;
- no mutation or persistent/background behavior; and
- the existing A1, A2, A2B, and A3 maintenance verifiers continue to pass.

## Human acceptance

1. Review the B1 candidate, test output, and review artifact.
2. Open Guided Maintenance and explicitly collect fleet status.
3. Confirm the status cards match the three live devices.
4. Confirm the topology shows Maven, Forge, Pi-hole, and the upstream edge.
5. Confirm no process remains after collection.
6. Separately authorize any future multi-device update executor.
