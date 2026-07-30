# Foundry Proxmox Control A6 Brief

```text
date: 2026-07-29
human_authorization: approved in the active development conversation
implementation_authorized: yes
live_control_enablement_authorized: yes
live_package_transaction_authorized: deferred until Operator review
live_reboot_authorized: deferred until Operator review
risk: Class 5 privileged remote package mutation and reboot candidate
```

## Outcome

Promote the enrolled Proxmox VE host named `Foundry` from rich read-only
inventory to the existing device-scoped Guided Maintenance controller.
Maintenance and reboot remain independent, digest-bound foreground actions.

## Authority boundary

Platform detection does not grant mutation authority. Foundry control requires
all of:

- the public-default-off `SOUL_FLEET_FOUNDRY_CONTROL_ENABLED` setting;
- one configured literal SSH alias;
- an enrolled SSH record whose alias exactly matches that configured alias; and
- the existing global `SOUL_MAINTENANCE_REMOTE_LIVE` execution gate.

The local deployment uses the reviewed owner-local `foundry` SSH alias and its
dedicated Proxmox maintenance key. Requests cannot supply a host, executable,
argument, package, repository, or readiness check.

## Fixed maintenance transaction

The exact remote command vectors are:

```text
/usr/bin/apt-get update
/usr/bin/apt-get -y -o Dpkg::Options::=--force-confold dist-upgrade
```

The transaction has the existing 45-minute bound, no automatic retry, no
automatic reboot, one global maintenance lock, and a terminal receipt.

## Fixed reboot transaction

Reboot sends exactly one:

```text
/usr/bin/systemctl reboot
```

The coordinator records the prior boot ID, requires a changed boot ID, and then
requires:

- `pveversion` to identify Proxmox VE; and
- `pveproxy`, `pvedaemon`, and `pvestatd` to be active.

Reconnect attempts and readiness checks use the existing fixed bounds. Failure
terminates for human review without retrying the reboot.

## Explicitly prohibited

- Authority inferred from operating-system or Proxmox detection.
- Fleet-wide update or reboot.
- Request-supplied SSH aliases, commands, flags, packages, or checks.
- Automatic package retry, reboot, rollback, or guest mutation.
- Persistent background workers or polling loops.

## Acceptance

- [x] Human approves implementation and local control enablement.
- [x] Deterministic status, controller, configuration, and UI regressions pass.
- [x] Foundry card exposes separate Maintenance and Reboot previews.
- [ ] Operator reviews and starts any package transaction separately.
- [ ] Operator reviews and starts any reboot separately.
