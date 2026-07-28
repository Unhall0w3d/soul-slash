# Crucible Fedora Backup and Maintenance Laboratory A0 Brief

Status: human-approved implementation and deployment scope; live review required

## Human direction

On 2026-07-28 the Operator approved deployment of one Fedora guest on the
existing Forge Proxmox host. The guest may serve both as Soul's off-device
backup target and as the controlled live target for a future DNF5 maintenance
adapter. A separate Debian backup guest is intentionally out of scope.

The approved device identity is:

```text
device_id: crucible
display_name: Crucible
hostname: crucible
role: Fedora backup target and DNF5 maintenance laboratory
```

## Approved A0 deployment

A0 may:

- download the official Fedora Cloud Base 44 x86_64 Generic image from Fedora
  infrastructure;
- verify its exact published byte size and SHA-256 digest before import;
- create one KVM guest with VMID `200` on Forge;
- allocate two vCPUs, 4 GiB RAM, one 40 GiB system disk, and one 100 GiB backup
  data disk from `local-lvm`;
- connect one VirtIO network interface to `vmbr0` with the Proxmox firewall
  flag enabled;
- configure DHCP through cloud-init;
- create one non-root `souladmin` account with one dedicated Maven-held SSH
  public key and no password authentication;
- enable guest autostart and the QEMU guest agent;
- boot the guest and collect bounded identity, DNF5, storage, SSH, and service
  evidence;
- add neutral public configuration and a private deployment record needed to
  represent Crucible in Guided Maintenance; and
- prepare, but not silently authorize, later backup or package mutation gates.

## Persistent components explicitly approved

This brief explicitly approves:

- one persistent Proxmox KVM guest named `crucible`;
- its Proxmox autostart setting;
- Fedora's ordinary SSH service for key-only administration;
- the QEMU guest agent; and
- later installation of an NFSv4 export only after its exact storage and
  network scope is separately previewed and reviewed.

No Soul daemon, watcher, polling loop, automatic package update, automatic
backup, automatic retention, or automatic reboot is approved by A0.

## Image identity

```text
url: https://download.fedoraproject.org/pub/fedora/linux/releases/44/Cloud/x86_64/images/Fedora-Cloud-Base-Generic-44-1.7.x86_64.qcow2
filename: Fedora-Cloud-Base-Generic-44-1.7.x86_64.qcow2
bytes: 583729152
sha256: 28680fe5b371a5a82ebf43a31926e086a168e59949d03969c5093e7071f90b7f
```

The digest is taken from Fedora's signed
`Fedora-Cloud-44-1.7-x86_64-CHECKSUM` publication.

The Server Guest Generic image was downloaded and verified first, but bounded
pre-qualification found that it does not contain cloud-init and therefore
cannot receive the approved non-root account or SSH key through Proxmox. It was
rejected before any in-guest package or configuration mutation. The Cloud Base
Generic image replaces only that unusable system disk; the independently
allocated backup data disk is preserved.

## Storage boundary

The 100 GiB backup disk is independent from the Fedora system disk. A0 does not
format, mount, export, initialize a restic repository on, or write backup data
to that disk until the exact device identity and mount plan are reviewed after
the guest is online.

The existing Maven-local restic repository remains unchanged and authoritative
throughout A0.

## Maintenance boundary

A0 proves only:

- Fedora identity and version;
- DNF5 executable and read-only package evidence;
- kernel and boot identity;
- SSH and QEMU agent availability; and
- the absence of package mutation authority.

DNF5 upgrade, privilege delegation, reboot, readiness verification, Proxmox
snapshot/rollback, and Dashboard mutation controls require later exact briefs.
A detected DNF5 executable is evidence, not authorization.

## Network and credential boundary

- DHCP is permitted for initial boot.
- A stable reservation may be configured by the Operator after the guest MAC
  and assigned address are known.
- The public repository contains no address, MAC, private key, password,
  Proxmox token, or owner-specific SSH configuration.
- The dedicated private key remains outside Git with mode `0600`.
- Root SSH login and password authentication are not required.
- No credential enters model context, Dashboard state, command arguments,
  receipts, or tracked source.

## Lifecycle and failure behavior

Deployment terminates as one of:

- `complete`
- `failed`
- `awaiting_input`
- `blocked_for_human_review`

Download, import, cloud-init, boot, and readiness checks are individually
bounded. There is no automatic destructive retry. If creation fails after VMID
`200` exists, the guest remains stopped for inspection; it is not automatically
destroyed.

## Risk classification

Class 5 infrastructure mutation.

The deployment creates persistent compute and storage resources on Forge. It
does not modify the existing Pi-hole container, Maven backup repository, Forge
network bridge, router, DHCP service, or public firewall.

## Human review checklist

- [x] Approve Fedora rather than Debian.
- [x] Approve the combined backup/laboratory role.
- [x] Approve the device name `Crucible`.
- [x] Verify the Fedora image byte size and SHA-256.
- [x] Review VMID, CPU, memory, disk, bridge, cloud-init, and autostart plan.
- [x] Confirm the guest boots and accepts only the dedicated SSH key.
- [ ] Review the assigned address and optionally create a DHCP reservation.
- [x] Confirm DNF5 evidence is read-only and no mutation controls exist.
- [x] Separately review the 100 GiB data-disk format and SSH/SFTP transport plan.
- [ ] Separately review second-copy and DNF5 mutation adapters.
