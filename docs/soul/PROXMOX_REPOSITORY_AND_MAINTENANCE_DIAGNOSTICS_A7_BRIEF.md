# Proxmox Repository and Maintenance Diagnostics A7 Brief

```text
date: 2026-07-29
human_authorization: approved in the active development conversation
implementation_authorized: yes
foundry_repository_repair_authorized: yes
live_metadata_refresh_authorized: yes
live_package_upgrade_authorized: deferred to a fresh Dashboard maintenance gate
live_reboot_authorized: deferred to a fresh Dashboard reboot gate
risk: Class 5 remote repository configuration; Class 1 private diagnostic reporting
```

## Outcome

Repair Foundry's fresh-install Proxmox repository configuration for its
non-production, unsubscribed role, then improve the shared device maintenance
lifecycle so a failed fixed command reports a bounded, redacted diagnostic
classification across supported platform adapters.

## Unified lifecycle

All supported devices continue to use one human experience:

1. enroll or configure an exact reviewed identity;
2. collect normalized package, kernel, reboot, service, and adapter evidence;
3. preview one exact device-scoped maintenance or reboot plan;
4. authorize that reviewed digest through the Dashboard;
5. execute fixed adapter-owned command vectors under one global lock;
6. terminate with one receipt; and
7. recollect normalized status after success.

Platform adapters may define only fixed package commands, readiness checks,
impact disclosures, and diagnostic classifications. They do not define a
different authorization experience and cannot accept request-supplied hosts,
commands, packages, repositories, or retries.

## Foundry repository repair

Foundry is an unsubscribed, non-production Proxmox VE 9 node. The current
enterprise PVE and enterprise Ceph sources require a subscription and cause
the fixed `apt-get update` step to exit 100.

The one-time repair must:

- reconfirm the exact `foundry` SSH identity and no-subscription state;
- preserve the two existing source files in a root-private timestamped backup;
- disable the enterprise PVE and Ceph source files reversibly;
- install the official Proxmox VE 9 `pve-no-subscription` deb822 source;
- run one bounded `apt-get update`; and
- run only a simulated distribution upgrade afterward.

It must not install, upgrade, remove, autoremove, reboot, or mutate guests.
The actual package upgrade remains a new Dashboard action.

## Shared failure diagnostics

Failed maintenance command evidence may add:

- one stable diagnostic code;
- one short operator-facing summary; and
- one bounded sanitized excerpt when safe.

Classification covers at least repository authorization, package-manager lock,
DNS resolution, storage exhaustion, interrupted package state, and a generic
nonzero exit. Excerpts must strip terminal control characters, redact URL
userinfo and sensitive query values, and remain owner-private in receipts.

## Explicitly prohibited

- Automatic repository changes during enrollment or package maintenance.
- Treating platform detection as mutation authority.
- Retrying package maintenance automatically after repository repair.
- Running a package upgrade or reboot as part of this repair.
- Request-supplied repository URLs or arbitrary remote file paths.
- Separate per-platform approval flows.
- Persistent workers, watchers, daemons, or scheduled mutation.

## Acceptance

- [x] Foundry enterprise sources are backed up and disabled.
- [x] Official PVE 9 no-subscription source is installed.
- [x] Bounded metadata refresh and simulated upgrade succeed.
- [x] Foundry status recollects through the same fleet card.
- [x] Failed receipts expose bounded diagnostic classification.
- [x] Existing Arch, Proxmox/APT, Pi-hole/APT, and Fedora/DNF controls do not regress.
- [x] No package upgrade or reboot occurs during the slice.
