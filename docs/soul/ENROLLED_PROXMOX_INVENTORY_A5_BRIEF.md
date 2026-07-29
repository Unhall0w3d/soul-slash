# Enrolled Proxmox Inventory A5 Brief

## Human direction

After enrolling the new Foundry Proxmox host, the Operator observed that its
card remained generic inventory-only and approved the changes required to make
the Dashboard accurately represent the host while retaining the existing
review boundaries.

## Approved scope

A5 may:

- classify one enrolled fixed-SSH record as Proxmox only when its reviewed
  kernel evidence ends in `-pve` and fixed `/usr/bin/pveversion` exists;
- collect bounded PVE version, running and boot-selected kernels, cached APT
  update simulation, reboot marker, and PVE guest inventory;
- show that evidence on the existing device card and preserve the enrolled
  identity during one-card refresh; and
- distinguish a read-only Proxmox adapter from generic SSH inventory.

## Prohibited scope

A5 must not:

- infer maintenance authority from platform detection;
- install packages, update repositories, start or stop guests, reboot a host,
  alter Proxmox configuration, or create credentials;
- replace one enrolled Proxmox identity with Forge during refresh;
- execute request-supplied commands or SSH options; or
- add a service, timer, watcher, listener, or background process.

## Execution contract

- Classification uses only fixed SSH commands and the enrolled literal alias.
- Every command remains shell-free, output-bounded, and timeout-bounded.
- APT evidence uses cached metadata only.
- Guest output is reduced to VMID, type, name, state, tags, memory, and uptime.
- The resulting card remains `control: inventory_only` with
  `mutation_supported: false`.
- Lifecycle terminates as `complete` or `failed`.

## Public/local boundary

The adapter and deterministic fixtures are public. Addresses, aliases, keys,
host keys, enrolled records, snapshots, and live guest inventory remain local.

## Risk classification

Class 2 authenticated read-only host inventory. No device mutation authority.
