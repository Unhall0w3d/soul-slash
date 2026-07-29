# Crucible: Fedora Backup and DNF5 Laboratory

Crucible is the optional Fedora KVM guest used for two bounded purposes:

1. an off-device target for a manually authorized encrypted restic second copy; and
2. a live Fedora/DNF5 target for Guided Maintenance qualification.

It does not run Soul, perform automatic updates, schedule backups, or replace
the workstation-local recovery repository.

## Reference deployment

The reviewed reference guest uses:

- Fedora Cloud Base 44 Generic x86_64;
- two virtual CPUs;
- 4 GiB RAM with a 2 GiB balloon floor;
- one 40 GiB system disk;
- one independent 100 GiB backup disk;
- VirtIO networking on the existing LAN bridge;
- DHCP for initial address assignment;
- Proxmox autostart;
- cloud-init with a non-root `souladmin` account;
- key-only SSH; and
- the QEMU guest agent.

Pin the exact Fedora image byte size and SHA-256 from Fedora's published
checksum document before importing it. Disable Proxmox cloud-init's automatic
package-upgrade option before first boot; package mutation belongs to Guided
Maintenance, not provisioning.

## Owner-local configuration

Keep addresses and keys outside Git. Add one literal SSH alias to the owner's
`~/.ssh/config`:

```sshconfig
Host crucible-maintenance
    HostName <reserved-private-address>
    User souladmin
    IdentityFile ~/.ssh/id_ed25519_crucible_maintenance
    IdentitiesOnly yes
    BatchMode yes
    PasswordAuthentication no
    StrictHostKeyChecking yes
    UserKnownHostsFile ~/.ssh/known_hosts_crucible
    HostKeyAlgorithms ssh-ed25519
    UpdateHostKeys no
```

Reserve the guest's address in local DHCP before treating the fixed SSH alias
as stable.

Enroll the reviewed address through **Administration → Guided Maintenance →
Discover & enroll a device** using SSH mode and the exact
`crucible-maintenance` alias. The registry record and fleet snapshots remain
under ignored `Soul/private/host_maintenance/` state.

## Backup storage

The independent backup disk is XFS-mounted by UUID at:

```text
/srv/soul-backup
```

The encrypted repository target is:

```text
sftp:crucible-maintenance:/srv/soul-backup/restic
```

The mount uses `nodev,nosuid,noexec`. The `restic` directory is owned by
`souladmin` with mode `0700`. SSH/SFTP is the only transport; the reference
deployment does not add NFS or SMB.

Preparing the directory does not initialize a repository. **Administration →
Backup & Recovery → Copy to Crucible** previews and executes the bounded
initialization/copy/check transaction with a fresh password supplied for one
page request. The password must never be stored in Git, `.env`, receipts,
logs, or Dashboard persistence.

The live gate initialized Crucible's independently encrypted repository,
copied all three local snapshots, passed repository checks, and proved exact
source coverage through restic's preserved original-snapshot lineage. A
subsequent local terminal gate rotated both repository passwords after a
browser-inspection incident; both repositories accepted the replacement,
rejected the previous password, and preserved all snapshots.

The accepted manual path never deletes target snapshots and has no timer.
Remote retention, nightly reconciliation, and full recovery rehearsal remain
later, separately reviewed gates.

## Guided Maintenance state

Crucible always begins as a read-only SSH inventory card. It collects:

- live DNF5 available-update counts;
- running and available kernel evidence;
- DNF5 reboot evidence;
- SSH and QEMU guest-agent state.

Maintenance and Reboot appear only after installing the separately reviewed
D1 authority. This authority stores no password and does not grant direct
passwordless access to DNF5, systemctl, a shell, or an interpreter. It installs
one root-owned, SHA-256-bound helper that accepts exactly:

- `self-check`;
- `dnf5-upgrade`, which runs `/usr/bin/dnf5 -y upgrade --refresh`; or
- `reboot`, which runs `/usr/bin/systemctl reboot`.

Review and install it from the owner workstation:

```bash
make verify-crucible-maintenance-control
make crucible-maintenance-authority-plan
make crucible-maintenance-authority-install \
  EXPECTED_DIGEST=<reviewed digest> \
  CONFIRM=INSTALL_CRUCIBLE_MAINTENANCE_AUTHORITY
make crucible-maintenance-authority-status
```

The one-time bootstrap replaces Fedora cloud-init's broad
`souladmin NOPASSWD:ALL` rule with the exact helper operations. The Dashboard
will continue to show Crucible as inventory-only if the helper self-check is
missing or invalid.

Maintenance is one foreground, device-scoped DNF5 transaction with a terminal
receipt and no automatic reboot. Reboot remains a separate digest-bound gate.
After one reboot request, Soul requires a changed boot identity plus active
SSH and QEMU guest agent, working DNF5, the `/srv/soul-backup` mount, and the
exact authority self-check. It never retries the reboot request.

## Live acceptance

Crucible is validated for both reviewed roles:

- D1 installed the exact fixed-operation authority and removed broad
  cloud-init sudo access;
- a 173-package DNF5 update completed, followed by a separate reboot;
- the guest returned on its newer kernel and passed SSH/QEMU guest-agent,
  DNF5, backup-mount, and authority readiness;
- the XFS target remained mounted with the reviewed hardening options; and
- the encrypted second-copy repository now contains all three accepted local
  snapshots.

## Verification

```bash
make verify-crucible-fedora-status
make verify-crucible-maintenance-control
make verify-maintenance-fleet-status
make verify-maintenance-device-control
```

For the live guest, confirm cloud-init completion, a changed boot ID after a
controlled reboot, both required services active, and `/srv/soul-backup`
mounted from the independent disk with the reviewed options.
