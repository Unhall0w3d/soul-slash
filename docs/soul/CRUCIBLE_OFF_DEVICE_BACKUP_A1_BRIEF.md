# Crucible Off-Device Backup Target A1 Brief

Status: implementation scope derived from the Operator's direct deployment
authorization; candidate review required

## Objective

Prepare Crucible's independently allocated 100 GiB disk as Soul's dedicated
off-device encrypted-restic target without changing the existing Maven-local
repository or creating an unattended backup service.

## Approved storage transaction

The bounded deployment may:

- verify that the stable VirtIO/SCSI identity
  `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1` resolves to one
  unformatted, unmounted 100 GiB disk;
- create one XFS filesystem on that exact disk;
- mount it persistently at `/srv/soul-backup` by its resulting UUID with
  `nodev,nosuid,noexec` options;
- create `/srv/soul-backup/restic` owned by the existing non-root
  `souladmin` account with mode `0700`;
- expose the directory only through Crucible's existing key-only SSH/SFTP
  channel; and
- collect mount, ownership, capacity, and reboot-persistence evidence.

No other block device may be formatted or mounted.

## Transport choice

Use restic's SSH/SFTP backend through the fixed `crucible-maintenance` alias.
Do not install or expose NFS, SMB, a new listener, or a new backup account in
this slice. Crucible's existing SSH service remains the only network transport.

The owner-specific address, host key, and private key remain outside Git.

## Repository boundary

This slice prepares an empty target directory. It does not:

- initialize a restic repository without a fresh Operator-supplied password;
- copy, capture, forget, prune, or restore any snapshot;
- persist a repository password;
- replace or alter the existing local repository;
- schedule backups; or
- retry in the background.

A later exact Dashboard gate may initialize and copy to the off-device
repository. It must accept the password for one request, retain no secret, bind
execution to fresh source and target identities, and terminate visibly.

## Lifecycle

The deployment terminates as `complete`, `failed`, `awaiting_input`, or
`blocked_for_human_review`. Device qualification, formatting, mount
installation, and verification are individually bounded. There is no automatic
destructive retry.

## Risk classification

Class 5 storage mutation. The exact empty 100 GiB Crucible data disk is
formatted once. Maven's local backup repository and Crucible's system disk are
outside the mutation scope.

## Human review checklist

- [x] Approve Crucible as the dedicated off-device backup target.
- [x] Approve one combined Fedora backup and DNF5 laboratory guest.
- [x] Confirm the stable disk identity is the empty 100 GiB `scsi1` disk.
- [x] Confirm XFS UUID-based mounting at `/srv/soul-backup`.
- [x] Confirm SSH/SFTP is the only backup transport.
- [x] Confirm no restic repository or password exists yet.
- [ ] Review the later repository initialization and copy gate separately.
