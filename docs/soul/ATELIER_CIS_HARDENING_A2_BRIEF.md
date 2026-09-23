# Atelier CIS Hardening A2 Brief

## Objective

Resolve the Operator-approved subset of Atelier's refreshed Wazuh findings
without applying server-oriented controls that conflict with its Omarchy
workstation role.

## Approved controls

- Disable IPv4 redirect sending and secure-redirect acceptance for `all` and
  `default` interfaces while preserving IPv4 forwarding for Docker and WinBoat.
- Record user-originated filesystem mount syscalls for both 64-bit and 32-bit
  ABIs through the existing audit service.
- Require membership in `wheel` for `su` by enabling Arch's existing
  `pam_wheel.so use_uid` rule without enabling passwordless trust.

The dedicated rotated sudo log requested by the refreshed finding is already
installed through A1 and must not be duplicated.

## Reviewed exceptions

- Periodic password expiration, minimum age, and warning rules remain disabled.
- Atelier retains its existing Omarchy Btrfs `/var/tmp` layout; this transaction
  does not create a partition, subvolume mount, bind mount, or restrictive mount
  flags.

## Exact mutation boundary

The transaction creates only:

- `/etc/sysctl.d/70-soul-workstation-network.conf`;
- `/etc/audit/rules.d/71-soul-mount-events.rules`.

It performs one exact transition in `/etc/pam.d/su`: uncomment the existing
`auth required pam_wheel.so use_uid` line only when the whole file matches the
reviewed Arch baseline hash. Drift, symlinks, missing files, or a package update
fail closed. Installation is atomic, digest-qualified, foreground-only, and
rollback-backed. It adds no service, timer, listener, credential, passwordless
authority, or generic privileged command surface.

## Acceptance

The live gate must verify exact root-owned files and modes, all four redirect
values at zero, IPv4 forwarding still at one, both mount rules loaded with the
`mounts` key, the exact PAM transition, the existing A1 sudo log, Docker and
WinBoat health, and a subsequent Wazuh rescan before posture rebinding.

```bash
make verify-atelier-cis-hardening-a2
make atelier-cis-hardening-a2-plan
```
