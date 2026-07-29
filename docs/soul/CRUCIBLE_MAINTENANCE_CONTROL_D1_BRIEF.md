# Crucible Maintenance Control D1 Brief

```text
date: 2026-07-29
human_authorization: approved in the active development conversation
implementation_authorized: yes
live_authority_install_authorized: yes
live_package_transaction_authorized: deferred until Operator review
live_reboot_authorized: deferred until Operator review
risk: Class 5 privileged remote package mutation and reboot candidate
```

## Outcome

Promote the exactly enrolled Fedora guest named `Crucible` from read-only DNF5
inventory to the existing device-scoped Guided Maintenance controller. Keep
maintenance and reboot as separate digest-bound actions. Separate managed and
SSH-integrated cards from compact status-only devices in the Dashboard.

## Fixed target and authority

The runtime target remains the literal owner-local SSH alias:

```text
crucible-maintenance
```

The remote `souladmin` account must not retain cloud-init's broad
`NOPASSWD: ALL`. Installation replaces that rule with one root-owned helper:

```text
/usr/local/libexec/soul-crucible-maintenance
```

The helper accepts exactly:

- `self-check`
- `dnf5-upgrade`
- `reboot`

Its sudoers rule is bound to the helper SHA-256 and those exact argument
vectors. The helper accepts no additional arguments, executable, package,
repository, path, host, or shell expression.

## Maintenance

The fixed maintenance vector is:

```text
/usr/bin/sudo -n /usr/local/libexec/soul-crucible-maintenance dnf5-upgrade
```

The helper executes only:

```text
/usr/bin/dnf5 -y upgrade --refresh
```

It performs one foreground attempt with the existing device-operation lock and
45-minute deadline. It does not autoremove, clean caches, select packages,
change repositories, resolve prompts through an LLM, or reboot automatically.
Completion writes a redacted receipt and recollects fleet evidence.

## Reboot

Reboot remains a fresh second action:

```text
/usr/bin/sudo -n /usr/local/libexec/soul-crucible-maintenance reboot
```

The existing bounded coordinator records the prior boot ID, sends one request,
and requires a changed boot ID plus all of:

- `sshd` active;
- `qemu-guest-agent` active;
- DNF5 available;
- `/srv/soul-backup` mounted; and
- the root-owned authority self-check returning its exact version.

There is no reboot retry. Failure retains the prior snapshot and terminates for
human review.

## Dashboard presentation

Guided Maintenance contains two independent surfaces:

1. **Managed & integrated** — maintenance-capable hosts plus SSH inventory.
2. **Network presence** — compact status-only LAN devices.

The groups do not share grid rows. Status-only card heights therefore cannot be
stretched by a managed or SSH-integrated card.

## Explicitly prohibited

- Fleet-wide update or reboot.
- Request-supplied SSH target or command arguments.
- Direct root SSH or stored password.
- Broad `NOPASSWD`, general shell, package-selection, or arbitrary sudo.
- Automatic package retry, reboot, rollback, snapshot, or restore.
- Backup deletion or mutation outside normal package-manager effects.
- Background worker, daemon, watcher, or scheduled mutation.

## Acceptance

- [x] Human approves implementation and exact live authority installation.
- [x] Deterministic authority, fleet, controller, and UI regressions pass.
- [x] Live self-check proves the broad cloud-init sudo rule is absent.
- [x] Live Crucible card exposes separate Maintenance and Reboot previews.
- [ ] Operator reviews and starts the 173-package maintenance action.
- [ ] Operator reviews its receipt and refreshed DNF5 evidence.
- [ ] Operator separately authorizes reboot if the refreshed card recommends it.
